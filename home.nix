{ config, pkgs, lib, user, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in

{
  home.username = user;
  home.homeDirectory = "/Users/${user}";
  home.stateVersion = "24.11";
  home.packages = with pkgs; [
    # cli i use constantly
    ripgrep   # fast search
    fd        # fast find
    fzf       # fuzzy finder
    jq        # json on the command line
    gh        # github cli
    lazygit
    mc        # midnight commander
    neovim
    google-cloud-sdk  # gcloud CLI
    nodejs    # general JS/TS dev use
    opencode  # AI coding agent for the terminal
    # the font everything renders in
    nerd-fonts.hack
    pkgs.rectangle
  ];
  fonts.fontconfig.enable = true;
  home.sessionVariables.EDITOR = "nvim";
  # so tools installed by the activation scripts below (no-mistakes) resolve on PATH
  home.sessionPath = [ "${config.home.homeDirectory}/.local/bin" ];

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
    initContent = ''
      bindkey '^f' autosuggest-accept
      # Automatically include hidden files in tab completion and wildcards (*)
      setopt globdots

      # Mirrors the directory-to-identity mapping in programs.git.includes below:
      # switch the active `gh` account to match whichever account's directory tree we're in.
      _gh_auth_autoswitch() {
        local user=""
        case "$PWD" in
          "$HOME"/repos/github/mattleus(|/*))    user="mattleus" ;;
          "$HOME"/repos/github/reliant-ai(|/*))  user="matt-reliant" ;;
          "$HOME"/repos/github/cohere-ai(|/*))   user="mattleus-cohere" ;;
        esac
        [[ -n "$user" ]] && gh auth switch -u "$user" -h github.com &>/dev/null
      }
      chpwd_functions+=(_gh_auth_autoswitch)
    '';
    shellAliases = {
      ".." = "cd ..";
      add = "git add .";
      push = "git push";
      pull = "git pull";
      m = "git switch main";
      cc = "claude --dangerously-skip-permissions";
      co = "codex --full-auto";
      ls = "ls -A";
    };
  };

  # Multiple GitHub accounts, routed by which folder a repo lives in.
  # Each account gets its own SSH key + host alias (programs.ssh below);
  # these includes rewrite the plain git@github.com: remote to the right
  # alias and set the matching commit identity, so remotes never need editing.
  programs.git = {
    enable = true;
    lfs.enable = true;
    settings = {
      user.name = "Matt Leus";
      user.email = "matthew.leus@cohere.com";
      pull.rebase = false;
      alias.pushup = "!f() { git checkout -b \"$1\" && git push -u origin HEAD; }; f";
    };
    includes = [
      {
        condition = "gitdir:~/repos/github/reliant-ai/";
        contents = {
          user.email = "matt@reliant.ai";
          url."git@github-reliant:".insteadOf = "git@github.com:";
        };
      }
      {
        condition = "gitdir:~/repos/github/cohere-ai/";
        contents = {
          user.email = "matthew.leus@cohere.com";
          url."git@github-cohere:".insteadOf = "git@github.com:";
        };
      }
      {
        condition = "gitdir:~/repos/github/mattleus/";
        contents = {
          user.email = "matthew.leus@gmail.com";
          url."git@github-personal:".insteadOf = "git@github.com:";
        };
      }
    ];
  };

  programs.ssh = {
    enable = true;
    # home-manager's old default ssh_config values, restated explicitly so
    # disabling enableDefaultConfig (below) changes nothing about behavior.
    enableDefaultConfig = false;
    settings = {
      "*" = {
        ForwardAgent = false;
        AddKeysToAgent = "no";
        Compression = false;
        ServerAliveInterval = 0;
        ServerAliveCountMax = 3;
        HashKnownHosts = false;
        UserKnownHostsFile = "~/.ssh/known_hosts";
        ControlMaster = "no";
        ControlPath = "~/.ssh/master-%r@%n:%p";
        ControlPersist = "no";
      };
      "github-reliant" = {
        HostName = "github.com";
        User = "git";
        IdentityFile = "~/.ssh/reliant-github";
        IdentitiesOnly = true;
      };
      "github-cohere" = {
        HostName = "github.com";
        User = "git";
        IdentityFile = "~/.ssh/cohere-github";
        IdentitiesOnly = true;
      };
      "github-personal" = {
        HostName = "github.com";
        User = "git";
        IdentityFile = "~/.ssh/personal-github";
        IdentitiesOnly = true;
      };
      "oracle2" = {
        HostName = "64.181.219.59";
        Port = 22;
        User = "matt";
        IdentityFile = "~/.ssh/matt-reliant-oracle";
      };
    };
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
      };
      cmd_duration.format = "[$duration]($style) ";
    };
  };

  # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/wezterm".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
  home.file.".config/herdr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/settings.json";
  home.file.".claude/statusline-command.sh".source=
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/statusline-command.sh";


  # Keep Pi's credential and runtime state local by linking only authored files and directories.
  home.file.".pi/agent/themes".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/themes";
  home.file.".pi/agent/extensions".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/extensions";
  home.file.".pi/agent/models.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/models.json";
  home.file.".pi/agent/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/settings.json";

  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";

  # firstmate toolchain: none of these have a Homebrew formula or nixpkgs package, so they're
  # installed declaratively via home.activation instead of by hand. Each block guards on the
  # tool already being present, so re-running `darwin-rebuild switch` is a no-op once installed.
  #
  # `darwin-rebuild switch` runs these under sudo's locked-down PATH (macOS secure_path), which
  # has neither Homebrew's nor Nix's bin dirs on it. Every guard and command below therefore
  # uses an absolute path instead of relying on PATH lookup - a bare `npm` or `command -v gh-axi`
  # here silently can't find anything and either no-ops or errors out with "command not found".
  home.activation.installNoMistakes = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -x "$HOME/.local/bin/no-mistakes" ]; then
      run mkdir -p "$HOME/.local/bin"
      # exporting PATH here (not relying on the ambient one) makes the installer's own
      # "am I on PATH" check pick $HOME/.local/bin, so it symlinks there instead of the
      # sudo-only /usr/local/bin fallback, which would hang this non-interactive activation.
      run bash -c "PATH=\"\$HOME/.local/bin:\$PATH\" curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh | sh"
    fi
  '';

  home.activation.cloneFirstmate = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    firstmateDir="${config.home.homeDirectory}/repos/public/firstmate"
    if [ ! -d "$firstmateDir" ]; then
      run /usr/bin/git clone https://github.com/kunchenguid/firstmate "$firstmateDir"
    fi
  '';

  # gh-axi, chrome-devtools-axi, and lavish-axi each need one-time hook setup after their
  # first install. Installed via Homebrew's npm (its bundled npmrc points `prefix` at
  # /opt/homebrew, which is user-writable; Nix's own npm defaults `prefix` into the read-only
  # Nix store and can't do global installs at all).
  #
  # npm itself, and every CLI it installs here, keeps a generic `#!/usr/bin/env node` shebang
  # (Homebrew only rewrites shebangs for its own formulae, not for `npm install -g` output).
  # `env` resolves `node` via PATH, and sudo's secure_path has no /opt/homebrew/bin on it, so
  # PATH is fixed up once for this whole activation block rather than per call.
  home.activation.installAxiTools = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="/opt/homebrew/bin:$PATH"
    npm=/opt/homebrew/bin/npm
    if [ ! -x /opt/homebrew/bin/gh-axi ]; then
      run "$npm" install -g gh-axi
      run /opt/homebrew/bin/gh-axi setup hooks
    fi
    if [ ! -x /opt/homebrew/bin/chrome-devtools-axi ]; then
      run "$npm" install -g chrome-devtools-axi
      run /opt/homebrew/bin/chrome-devtools-axi setup hooks
    fi
    if [ ! -x /opt/homebrew/bin/lavish-axi ]; then
      run "$npm" install -g lavish-axi
      run /opt/homebrew/bin/lavish-axi setup hooks
    fi
    if [ ! -x /opt/homebrew/bin/tasks-axi ]; then
      run "$npm" install -g tasks-axi
    fi
    if [ ! -x /opt/homebrew/bin/quota-axi ]; then
      run "$npm" install -g quota-axi
    fi
  '';
}
