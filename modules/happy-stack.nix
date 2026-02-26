{ lib, ... }:

{
  imports = [
    ./happy-codex-agent.nix
    (lib.mkRenamedOptionModule [ "services" "happy-stack" ] [ "services" "happy-codex-agent" ])
  ];
}
