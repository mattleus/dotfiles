{ user, pkgs, lib, ... }:

let
  # homebrew-core's terraform formula is frozen at 1.5.7 (deprecated after
  # HashiCorp's BUSL relicense), hashicorp/homebrew-tap only tracks latest, and
  # nixpkgs-26.05-darwin has 1.15.3 - so an exact 1.14.0 pin means fetching the
  # official binary from releases.hashicorp.com. Bump: change the url + replace
  # the hash from `nix store prefetch-file --unpack <url>` (fetchzip hashes the
  # unpacked contents, NOT the zip, so the hashes in HashiCorp's SHA256SUMS file
  # do not work here).
  terraform_1_14_0 = pkgs.stdenvNoCC.mkDerivation {
    pname = "terraform";
    version = "1.14.0";
    src = pkgs.fetchzip {
      url = "https://releases.hashicorp.com/terraform/1.14.0/terraform_1.14.0_darwin_arm64.zip";
      hash = "sha256-IQ9PS4QMgC/yOwU4rcf7X6S8zpkQNndCUqmKwl1Igyo=";
      stripRoot = false;  # the zip is a flat list of files, not a directory
    };
    installPhase = ''
      mkdir -p $out/bin
      install -m755 terraform $out/bin/terraform
    '';
  };
in

{
  # Determinate already manages the Nix daemon, so nix-darwin shouldn't.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin"; # use x86_64-darwin for Intel CPU

  system.primaryUser = user;
  users.users.${user} = {
    home = "/Users/${user}";
  };
  programs.zsh.enable = true;
  environment.systemPackages = [ terraform_1_14_0 ];
  system.stateVersion = 6;
  system.defaults = {
    NSGlobalDomain = {
      KeyRepeat = 2;          # fast key repeat
      InitialKeyRepeat = 15;  # short delay before repeat
      _HIHideMenuBar = false; # keep the menu bar visible
      AppleShowAllExtensions = true;
    };
    dock.autohide = true;
    finder.FXPreferredViewStyle = "Nlsv";  # list view by default
    finder.CreateDesktop = false;          # clean desktop
    trackpad.Clicking = true;              # tap to click
  };
  system.defaults.CustomUserPreferences = {
    NSGlobalDomain = {
      AppleMenuBarVisibleInFullscreen = true; # true keeps the menu bar visible, false auto-hides it
      "com.apple.sound.beep.volume" = 0.0;    # silence the system alert sound
      "com.apple.sound.beep.feedback" = false; # no beep when pressing volume keys
      "com.apple.sound.uiaudio.enabled" = 0;  # silence other UI sounds (empty trash, lock, etc.)
    };
  };
  # OpenSuperWhisper starts at login as a menu bar app. A user LaunchAgent is the declarative
  # way to get that; the app's own "launch at login" toggle registers a non-declarative login
  # item, so prefer this and leave that toggle off. LimitLoadToSessionType keeps it from firing in
  # non-GUI (SSH-only) sessions.
  launchd.user.agents.opensuperwhisper = {
    serviceConfig = {
      ProgramArguments = [ "/Applications/OpenSuperWhisper.app/Contents/MacOS/OpenSuperWhisper" ];
      RunAtLoad = true;
      LimitLoadToSessionType = "Aqua";
    };
  };
  nix-homebrew = {
    enable = true;
    inherit user;
    autoMigrate = true;
  };

  # Remote Login (sshd) so the Whip phone app (github.com/kosumic/whip) can reach
  # this Mac over Tailscale and drive herdr. Native nix-darwin 26.05 module: enables
  # Apple's built-in sshd via `launchctl enable/bootstrap` - deliberately NOT
  # `systemsetup -setremotelogin`, which requires Full Disk Access. Also generates
  # host keys and writes /etc/ssh/sshd_config.d snippets. The whipair pairing flow
  # authorizes an SSH key; password auth stays enabled per stock sshd_config.
  #
  # History: we first tried a custom `system.activationScripts.enableSshd` script
  # for this, but nix-darwin 26.05 assembles /run/current-system/activate from a
  # hardcoded whitelist of script names (see modules/system/activation-scripts.nix),
  # so custom names are silently dropped - two green-looking rebuilds never started
  # sshd. Verified by grepping /run/current-system/activate for the script body.
  services.openssh.enable = true;

  # services.openssh alone did not make sshd survive reboots (observed on macOS
  # 26.6): its launchd block only bootstraps sshd for the CURRENT session, which
  # is why port 22 answers until the machine restarts. The boot-time decision
  # comes from launchd's overrides DB, /var/db/com.apple.xpc.launchd/disabled.plist,
  # which still had com.openssh.sshd => true after a green rebuild (Settings >
  # General > Sharing > Remote Login reads the same DB and showed the toggle OFF).
  # Apple's ssh.plist itself also ships Disabled=true, so a MISSING override entry
  # still means off at boot - only an explicit `false` keeps sshd starting.
  # So: on every activation, force the override to false (enable; then load -w;
  # then systemsetup, which can need Full Disk Access), bootstrap sshd for the
  # current session, then VERIFY the DB actually says false. A silent no-op at
  # exactly this step is how the machine ended up half-fixed twice, so verify
  # and warn loudly instead of trusting exit codes.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    _sshd_boot_state() {
      /usr/bin/plutil -extract "com.openssh.sshd" raw -o - /var/db/com.apple.xpc.launchd/disabled.plist 2>/dev/null
    }
    if [ "$(_sshd_boot_state)" != "false" ]; then
      /bin/launchctl enable system/com.openssh.sshd \
        || /bin/launchctl load -w /System/Library/LaunchDaemons/ssh.plist \
        || /usr/sbin/systemsetup -f -setremotelogin on \
        || true
    fi
    /bin/launchctl print system/com.openssh.sshd >/dev/null 2>&1 \
      || /bin/launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist \
      || true
    if [ "$(_sshd_boot_state)" != "false" ]; then
      echo "openssh: WARNING - sshd is marked disabled in launchd's overrides DB;" >&2
      echo "openssh: it is running now but will NOT start at next boot." >&2
      echo "openssh: toggle System Settings > General > Sharing > Remote Login ON," >&2
      echo "openssh: then re-run rebuild so this check can go green." >&2
    fi
  '';

  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";  # remove anything not listed here
    onActivation.autoUpdate = true;
    onActivation.extraFlags = [ "--force" ];
    taps = [
      {
        name = "b451c/quickmd";  # QuickMD ships only via its own tap, not homebrew-cask
        trusted = true;          # Homebrew 6+ refuses to load casks from untrusted taps
      }
    ];
    brews = [
      "herdr"
      "pyenv"
      "python@3.13"
      "poetry"
      "gemini-cli"
      # terraform lives in the pinned terraform_1_14_0 derivation at the top -
      # homebrew-core is frozen at 1.5.7, so the brew would zap-fight the pin
      "sqlite"
      "clippy"
      "treehouse"
      "git-filter-repo"
      "duti"
    ];
    casks = [
      "wezterm"
      "claude-code"
      "copilot-cli"
      "signal"
      "telegram"
      "whatsapp"
      "brave-browser"
      "zed"
      "rectangle"
      "google-drive"
      "opensuperwhisper"
      "quickmd"
      "caffeine"
      "tailscale-app"
    ];
  };
}
