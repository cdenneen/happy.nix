# Agent Guide (happy.nix)

This repo provides reusable NixOS modules for Happy Server and Happy Codex instances.

## Modules

- `nixosModules.happy-server`
- `nixosModules.happy-codex-agent`
- `nixosModules.happy-agent`

## Happy Server Options

- `services.happy-server.enable`
- `services.happy-server.image` (default `ghcr.io/cdenneen/happy-server:latest`)
- `services.happy-server.envFile` (default `/var/lib/happy/env`)
- `services.happy-server.publicUrl`, `services.happy-server.port`, `services.happy-server.bindAddress`
- `services.happy-server.dataDir`, `services.happy-server.pgliteDir`, `services.happy-server.filesDir`
- `services.happy-server.handyMasterSecret` (optional)

Storage modes:

- `services.happy-server.storage.mode = "pglite" | "local" | "external"`
- Local containers: `storage.local.{postgres,redis,minio}.enable` or `storage.local.bundle.enable`
- External services: `storage.external.databaseUrl`, `storage.external.redisUrl`, `storage.external.s3.*`

## Happy Codex Instances

`services.happy-codex-agent.instances = [ { name, workspace, happyServerUrl? } ... ]`

- Default mode: user services (`services.happy-codex-agent.mode = "user"`)
- Set `mode = "system"` to use system services instead.

## CI

- CI runs `nix flake check` on PRs and pushes.
- Weekly flake.lock update PRs via GitHub Actions.

## Pre-commit

- Run `nix fmt` before committing changes.
