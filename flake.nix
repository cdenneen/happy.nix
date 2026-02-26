{
  description = "Happy server and codex Nix modules";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    {
      nixosModules.happy-server = import ./modules/happy-server.nix;
      nixosModules.happy-stack = import ./modules/happy-stack.nix;
    };
}
