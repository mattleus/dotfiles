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
    nodejs    # npm, for the firstmate toolchain below
    # the font everything renders in
    nerd-fonts.hack
    pkgs.rectangle
  ];
  fonts.fontconfig.enable = true;
  home.sessionVariables.EDITOR = "nvim";

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
    initContent = ''
      bindkey '^f' autosuggest-accept
      # Automatically include hidden files in tab completion and wildcards (*)
      setopt globdots
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
    userName = "Matt Leus";
    userEmail = "matthew.leus@cohere.com";
    lfs.enable = true;
    extraConfig = {
      pull.rebase = false;
    };
    aliases = {
      pushup = "!f() { git checkout -b \"$1\" && git push -u origin HEAD; }; f";
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
    matchBlocks = {
      "github-reliant" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/reliant-github";
        identitiesOnly = true;
      };
      "github-cohere" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/cohere-github";
        identitiesOnly = true;
      };
      "github-personal" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/personal-github";
        identitiesOnly = true;
      };
      "oracle2" = {
        hostname = "64.181.219.59";
        port = 22;
        user = "matt";
        identityFile = "~/.ssh/matt-reliant-oracle";
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
  home.activation.installNoMistakes = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ! command -v no-mistakes >/dev/null 2>&1; then
      run bash -c "curl -fsSL https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh | sh"
    fi
  '';

  home.activation.cloneFirstmate = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    firstmateDir="${config.home.homeDirectory}/repos/public/firstmate"
    if [ ! -d "$firstmateDir" ]; then
      run git clone https://github.com/kunchenguid/firstmate "$firstmateDir"
    fi
  '';

  # gh-axi, chrome-devtools-axi, and lavish-axi each need one-time hook setup after their
  # first install; the command -v guard keeps that from re-running on later switches.
  home.activation.installAxiTools = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if ! command -v gh-axi >/dev/null 2>&1; then
      run npm install -g gh-axi
      run gh-axi setup hooks
    fi
    if ! command -v chrome-devtools-axi >/dev/null 2>&1; then
      run npm install -g chrome-devtools-axi
      run chrome-devtools-axi setup hooks
    fi
    if ! command -v lavish-axi >/dev/null 2>&1; then
      run npm install -g lavish-axi
      run lavish-axi setup hooks
    fi
    if ! command -v tasks-axi >/dev/null 2>&1; then
      run npm install -g tasks-axi
    fi
    if ! command -v quota-axi >/dev/null 2>&1; then
      run npm install -g quota-axi
    fi
  '';
}
