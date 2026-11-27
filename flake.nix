{
  description = "dotfiles";
  inputs = {
    # Use `github:NixOS/nixpkgs/nixpkgs-26.05-darwin` to use Nixpkgs 26.05.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    # Use `github:nix-darwin/nix-darwin/nix-darwin-26.05` to use Nixpkgs 26.05.
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # Whip (github.com/kosumic/whip) is the third-party phone client for herdr.
    # We only use its whipair package: the one-shot QR pairing helper that
    # authorizes the phone's SSH key onto this Mac.
    whip.url = "github:kosumic/whip";

    # pstack, Lauren Tan's agent skill pack (MIT), linked into the agents' skill
    # folders by pstack.nix. Pinned to a commit; see pstack.nix to bump it.
    pstack = {
      url = "github:cursor/plugins/b7b93c36be9bcc36a74db438e0fd385d660bc559";
      flake = false;
    };
  };

  outputs = inputs@{ self, nix-darwin, nix-homebrew, home-manager, nixpkgs, whip, pstack }:
    let
      # The one username line to change if this isn't your machine.
      # bootstrap.sh offers to rewrite this for you if your macOS username differs.
      user = "matt";
    in
    {
      darwinConfigurations."mac" = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit user; };
        modules = [
          ./configuration.nix
          nix-homebrew.darwinModules.nix-homebrew
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "preNixBackup";
            home-manager.extraSpecialArgs = { inherit user whip pstack; };
            home-manager.users.${user} = import ./home.nix;
          }
        ];
      };
    };
}
