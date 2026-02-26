# happy.nix

Reusable NixOS modules for Happy Server and Happy Codex instances.

## Modules

- `nixosModules.happy-server`
- `nixosModules.happy-stack`

## Happy Server (services.happy-server)

Minimal example:

```nix
services.happy-server = {
  enable = true;
  publicUrl = "https://happy.example.com";
  envFile = "/var/lib/happy/env";
  bindAddress = "127.0.0.1";
  port = 3000;
};
```

Storage modes:

```nix
# Default: pglite + local files
services.happy-server.storage.mode = "pglite";

# Local containers (pick and choose or bundle)
services.happy-server.storage.mode = "local";
services.happy-server.storage.local.bundle.enable = true;

# External services
services.happy-server.storage.mode = "external";
services.happy-server.storage.external.databaseUrl = "postgres://...";
services.happy-server.storage.external.redisUrl = "redis://...";
services.happy-server.storage.external.s3.endpoint = "s3.example.com";
```

Schema initialization (required)

Happy Server needs the database schema loaded before it can serve traffic. Run one of these once
after the container starts:

```sh
# PGlite mode (default)
sudo podman exec happy-server-happy-server \
  yarn --cwd packages/happy-server standalone migrate

# Postgres mode (local or external)
sudo podman exec happy-server-happy-server \
  yarn --cwd packages/happy-server prisma migrate deploy
```

PGlite uses the embedded database at `PGLITE_DIR`. Postgres uses `DATABASE_URL` (set by the module
for local containers or external services).

Key options:

- `image` (default `ghcr.io/cdenneen/happy-server:latest`)
- `envFile` (default `/var/lib/happy/env`)
- `publicUrl`, `port`, `bindAddress`
- `dataDir`, `pgliteDir`, `filesDir`
- `handyMasterSecret` (optional; generated once if missing)

## Happy Codex (services.happy-stack)

```nix
services.happy-stack = {
  enable = true;
  mode = "user"; # or "system"
  instances = [
    {
      name = "workspace";
      workspace = "/path/to/workspace";
      happyServerUrl = "https://happy.example.com";
    }
  ];
};
```

Each instance starts a `happy codex` service in the specified workspace.

## CI

- `nix flake check` on PRs/pushes
- Weekly flake.lock update PRs
