{
  description = "Happy server and codex Nix modules";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      nixosModules.happy-server = import ./modules/happy-server.nix;
      nixosModules.happy-codex-agent = import ./modules/happy-codex-agent.nix;
      nixosModules.happy-agent = import ./modules/happy-agent.nix;
      nixosModules.happy-stack = import ./modules/happy-stack.nix;

      apps = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          happyCodex = pkgs.writeShellScriptBin "happy-codex-agent" ''
            set -euo pipefail
            exec ${pkgs.happy-coder}/bin/happy codex
          '';
          happyAgent = pkgs.writeShellScriptBin "happy-agent" ''
            set -euo pipefail
            exec ${pkgs.happy-coder}/bin/happy
          '';
          happyServer = pkgs.writeShellScriptBin "happy-server" ''
            set -euo pipefail
            image="''${HAPPY_SERVER_IMAGE:-ghcr.io/cdenneen/happy-server:latest}"
            secret="''${HANDY_MASTER_SECRET:-dev-secret}"
            data_dir="$(mktemp -d)"
            trap 'rm -rf "$data_dir"' EXIT
            ${pkgs.podman}/bin/podman run --rm \
              -p 3000:3000 \
              -e HANDY_MASTER_SECRET="$secret" \
              -e DATA_DIR=/data \
              -e PGLITE_DIR=/data/pglite \
              -v "$data_dir:/data" \
              "$image"
          '';
        in
        {
          happy-server = {
            type = "app";
            program = "${happyServer}/bin/happy-server";
          };
          happy-codex-agent = {
            type = "app";
            program = "${happyCodex}/bin/happy-codex-agent";
          };
          happy-agent = {
            type = "app";
            program = "${happyAgent}/bin/happy-agent";
          };
        }
      );
    };
}
