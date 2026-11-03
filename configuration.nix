{ user, pkgs, ... }:

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
      "terraform"
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
