{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.happy-server;

  localPostgres =
    cfg.storage.mode == "local"
    && (cfg.storage.local.bundle.enable || cfg.storage.local.postgres.enable);
  localRedis =
    cfg.storage.mode == "local" && (cfg.storage.local.bundle.enable || cfg.storage.local.redis.enable);
  localMinio =
    cfg.storage.mode == "local" && (cfg.storage.local.bundle.enable || cfg.storage.local.minio.enable);

  externalDb = cfg.storage.mode == "external" && cfg.storage.external.databaseUrl != null;
  externalRedis = cfg.storage.mode == "external" && cfg.storage.external.redisUrl != null;
  externalS3 = cfg.storage.mode == "external" && cfg.storage.external.s3.endpoint != null;

  minioPublicUrl =
    if cfg.storage.local.minio.publicUrl != null then
      cfg.storage.local.minio.publicUrl
    else if cfg.publicUrl != null then
      "${cfg.publicUrl}/minio"
    else
      null;

  s3PublicUrl = if externalS3 then cfg.storage.external.s3.publicUrl else minioPublicUrl;

  envBase = {
    "PORT" = toString cfg.port;
  }
  // lib.optionalAttrs (cfg.publicUrl != null) {
    "PUBLIC_URL" = cfg.publicUrl;
  };

  containerDataDir = "/data";
  containerFilesDir = "${containerDataDir}/files";
  containerPgliteDir = "${containerDataDir}/pglite";

  envFiles = {
    "DATA_DIR" = containerDataDir;
    "FILES_DIR" = containerFilesDir;
  };

  envPglite = {
    "PGLITE_DIR" = containerPgliteDir;
  };

  envDb =
    lib.optionalAttrs localPostgres {
      "DATABASE_URL" =
        "postgresql://${cfg.storage.local.postgres.user}:${cfg.storage.local.postgres.password}"
        + "@happy-server-postgres:${toString cfg.storage.local.postgres.port}/${cfg.storage.local.postgres.db}";
    }
    // lib.optionalAttrs externalDb {
      "DATABASE_URL" = cfg.storage.external.databaseUrl;
    };

  envRedis =
    lib.optionalAttrs localRedis {
      "REDIS_URL" = "redis://happy-server-redis:${toString cfg.storage.local.redis.port}";
    }
    // lib.optionalAttrs externalRedis {
      "REDIS_URL" = cfg.storage.external.redisUrl;
    };

  envS3 =
    lib.optionalAttrs (localMinio || externalS3) {
      "S3_HOST" = if externalS3 then cfg.storage.external.s3.endpoint else "happy-server-minio";
      "S3_PORT" = toString (
        if externalS3 then cfg.storage.external.s3.port else cfg.storage.local.minio.port
      );
      "S3_USE_SSL" =
        if externalS3 then
          lib.boolToString cfg.storage.external.s3.useSsl
        else
          lib.boolToString cfg.storage.local.minio.useSsl;
      "S3_BUCKET" = if externalS3 then cfg.storage.external.s3.bucket else cfg.storage.local.minio.bucket;
      "S3_ACCESS_KEY" =
        if externalS3 then cfg.storage.external.s3.accessKey else cfg.storage.local.minio.accessKey;
      "S3_SECRET_KEY" =
        if externalS3 then cfg.storage.external.s3.secretKey else cfg.storage.local.minio.secretKey;
    }
    // lib.optionalAttrs (s3PublicUrl != null) {
      "S3_PUBLIC_URL" = s3PublicUrl;
    };

  pgliteEnabled = !localPostgres && !externalDb;

  serverEnv =
    envBase // envFiles // (if pgliteEnabled then envPglite else { }) // envDb // envRedis // envS3;

  envFileScript = pkgs.writeShellScript "happy-env" ''
    set -euo pipefail
    env_file="${cfg.envFile}"
    env_dir="$(${pkgs.coreutils}/bin/dirname "$env_file")"
    ${pkgs.coreutils}/bin/mkdir -p "$env_dir"

    secret_from_option="${lib.escapeShellArg (cfg.handyMasterSecret or "")}"
    secret=""

    if [ -f "$env_file" ]; then
      secret="$(${pkgs.gnugrep}/bin/grep -E '^HANDY_MASTER_SECRET=' "$env_file" | ${pkgs.coreutils}/bin/head -n1 | ${pkgs.coreutils}/bin/cut -d= -f2- || true)"
    fi

    if [ -z "$secret" ]; then
      if [ -n "$secret_from_option" ]; then
        secret="$secret_from_option"
      else
        secret="$(${pkgs.openssl}/bin/openssl rand -hex 32)"
      fi

      if [ -f "$env_file" ]; then
        tmp_file="$(${pkgs.coreutils}/bin/mktemp)"
        ${pkgs.gnugrep}/bin/grep -v '^HANDY_MASTER_SECRET=' "$env_file" > "$tmp_file" || true
        ${pkgs.coreutils}/bin/printf 'HANDY_MASTER_SECRET=%s\n' "$secret" >> "$tmp_file"
        ${pkgs.coreutils}/bin/mv "$tmp_file" "$env_file"
      else
        ${pkgs.coreutils}/bin/printf 'HANDY_MASTER_SECRET=%s\n' "$secret" > "$env_file"
      fi
      ${pkgs.coreutils}/bin/chmod 600 "$env_file"
    fi
  '';
in
{
  options.services.happy-server = {
    enable = lib.mkEnableOption "Happy server";
    image = lib.mkOption {
      type = lib.types.str;
      default = "ghcr.io/cdenneen/happy-server:latest";
      description = "Container image for happy-server.";
    };
    envFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/happy/env";
      description = "Env file path used by happy-server.";
    };
    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Bind address for published container ports.";
    };
    publicUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Public URL for happy-server.";
    };
    port = lib.mkOption {
      type = lib.types.int;
      default = 3000;
      description = "Port for happy-server.";
    };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/happy/data";
      description = "Base data directory for happy-server.";
    };
    pgliteDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/happy/data/pglite";
      description = "PGLite storage directory.";
    };
    filesDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/happy/data/files";
      description = "Local file storage directory.";
    };
    dataOwner = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "Owner for local data directories.";
    };
    dataGroup = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Group for local data directories.";
    };
    dataMode = lib.mkOption {
      type = lib.types.str;
      default = "0750";
      description = "Mode for local data directories.";
    };
    handyMasterSecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional HANDY_MASTER_SECRET override.";
    };
    storage = {
      mode = lib.mkOption {
        type = lib.types.enum [
          "pglite"
          "local"
          "external"
        ];
        default = "pglite";
        description = "Storage mode for happy-server.";
      };
      local = {
        bundle.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable local Postgres, Redis, and MinIO containers.";
        };
        postgres = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable local Postgres container.";
          };
          image = lib.mkOption {
            type = lib.types.str;
            default = "postgres:16";
            description = "Postgres container image.";
          };
          port = lib.mkOption {
            type = lib.types.int;
            default = 5432;
            description = "Postgres container port.";
          };
          dataDir = lib.mkOption {
            type = lib.types.str;
            default = "/var/lib/happy/postgres";
            description = "Postgres data directory on host.";
          };
          user = lib.mkOption {
            type = lib.types.str;
            default = "postgres";
            description = "Postgres username.";
          };
          password = lib.mkOption {
            type = lib.types.str;
            default = "postgres";
            description = "Postgres password.";
          };
          db = lib.mkOption {
            type = lib.types.str;
            default = "happy-server";
            description = "Postgres database name.";
          };
        };
        redis = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable local Redis container.";
          };
          image = lib.mkOption {
            type = lib.types.str;
            default = "redis:7.4-alpine";
            description = "Redis container image.";
          };
          port = lib.mkOption {
            type = lib.types.int;
            default = 6379;
            description = "Redis container port.";
          };
          dataDir = lib.mkOption {
            type = lib.types.str;
            default = "/var/lib/happy/redis";
            description = "Redis data directory on host.";
          };
        };
        minio = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable local MinIO container.";
          };
          image = lib.mkOption {
            type = lib.types.str;
            default = "minio/minio:latest";
            description = "MinIO container image.";
          };
          port = lib.mkOption {
            type = lib.types.int;
            default = 9000;
            description = "MinIO service port.";
          };
          consolePort = lib.mkOption {
            type = lib.types.int;
            default = 9001;
            description = "MinIO console port.";
          };
          dataDir = lib.mkOption {
            type = lib.types.str;
            default = "/var/lib/happy/minio";
            description = "MinIO data directory on host.";
          };
          accessKey = lib.mkOption {
            type = lib.types.str;
            default = "happyadmin";
            description = "MinIO access key.";
          };
          secretKey = lib.mkOption {
            type = lib.types.str;
            default = "happyadmin123";
            description = "MinIO secret key.";
          };
          bucket = lib.mkOption {
            type = lib.types.str;
            default = "happy";
            description = "MinIO bucket name.";
          };
          publicUrl = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Public URL for MinIO objects.";
          };
          useSsl = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable SSL for MinIO.";
          };
        };
      };
      external = {
        databaseUrl = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "External database URL.";
        };
        redisUrl = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "External Redis URL.";
        };
        s3 = {
          endpoint = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "External S3 endpoint host.";
          };
          port = lib.mkOption {
            type = lib.types.int;
            default = 9000;
            description = "External S3 port.";
          };
          useSsl = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "External S3 SSL enabled.";
          };
          accessKey = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "External S3 access key.";
          };
          secretKey = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "External S3 secret key.";
          };
          bucket = lib.mkOption {
            type = lib.types.str;
            default = "happy";
            description = "External S3 bucket.";
          };
          publicUrl = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "External S3 public URL.";
          };
        };
      };
    };
    workspaceRoot = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/happy/workspace";
      description = "Workspace root mounted into container (for local tools).";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.podman.enable = lib.mkDefault true;
    virtualisation.oci-containers.backend = "podman";

    systemd.services.happy-server-env = {
      description = "Ensure happy-server env file";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = envFileScript;
      };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} ${cfg.dataMode} ${cfg.dataOwner} ${cfg.dataGroup} - -"
      "d ${cfg.pgliteDir} ${cfg.dataMode} ${cfg.dataOwner} ${cfg.dataGroup} - -"
      "d ${cfg.filesDir} ${cfg.dataMode} ${cfg.dataOwner} ${cfg.dataGroup} - -"
    ]
    ++ lib.optionals localPostgres [
      "d ${cfg.storage.local.postgres.dataDir} ${cfg.dataMode} ${cfg.dataOwner} ${cfg.dataGroup} - -"
    ]
    ++ lib.optionals localRedis [
      "d ${cfg.storage.local.redis.dataDir} ${cfg.dataMode} ${cfg.dataOwner} ${cfg.dataGroup} - -"
    ]
    ++ lib.optionals localMinio [
      "d ${cfg.storage.local.minio.dataDir} ${cfg.dataMode} ${cfg.dataOwner} ${cfg.dataGroup} - -"
    ];

    virtualisation.oci-containers.containers."happy-server-happy-server" = {
      image = cfg.image;
      environment = serverEnv;
      environmentFiles = [ cfg.envFile ];
      volumes = [
        "${cfg.workspaceRoot}:/workspace:ro"
        "${cfg.dataDir}:/data:rw"
      ];
      ports = [
        "${cfg.bindAddress}:${toString cfg.port}:3000/tcp"
      ];
      dependsOn = lib.concatLists [
        (lib.optional localPostgres "happy-server-postgres")
        (lib.optional localRedis "happy-server-redis")
        (lib.optional localMinio "happy-server-minio")
      ];
      log-driver = "journald";
    };

    systemd.services."podman-happy-server-happy-server" = {
      after = [ "happy-server-env.service" ];
      requires = [ "happy-server-env.service" ];
    };

    virtualisation.oci-containers.containers."happy-server-postgres" = lib.mkIf localPostgres {
      image = cfg.storage.local.postgres.image;
      environment = {
        "POSTGRES_DB" = cfg.storage.local.postgres.db;
        "POSTGRES_USER" = cfg.storage.local.postgres.user;
        "POSTGRES_PASSWORD" = cfg.storage.local.postgres.password;
      };
      volumes = [
        "${cfg.storage.local.postgres.dataDir}:/var/lib/postgresql/data:rw"
      ];
      ports = [
        "${cfg.bindAddress}:${toString cfg.storage.local.postgres.port}:5432/tcp"
      ];
      log-driver = "journald";
    };

    virtualisation.oci-containers.containers."happy-server-redis" = lib.mkIf localRedis {
      image = cfg.storage.local.redis.image;
      volumes = [
        "${cfg.storage.local.redis.dataDir}:/data:rw"
      ];
      ports = [
        "${cfg.bindAddress}:${toString cfg.storage.local.redis.port}:6379/tcp"
      ];
      log-driver = "journald";
    };

    virtualisation.oci-containers.containers."happy-server-minio" = lib.mkIf localMinio {
      image = cfg.storage.local.minio.image;
      environment = {
        "MINIO_ROOT_USER" = cfg.storage.local.minio.accessKey;
        "MINIO_ROOT_PASSWORD" = cfg.storage.local.minio.secretKey;
      };
      volumes = [
        "${cfg.storage.local.minio.dataDir}:/data:rw"
      ];
      ports = [
        "${cfg.bindAddress}:${toString cfg.storage.local.minio.port}:9000/tcp"
        "${cfg.bindAddress}:${toString cfg.storage.local.minio.consolePort}:9001/tcp"
      ];
      cmd = [
        "server"
        "/data"
        "--console-address"
        ":9001"
      ];
      log-driver = "journald";
    };

    virtualisation.oci-containers.containers."happy-server-minio-init" = lib.mkIf localMinio {
      image = "minio/mc:latest";
      environment = {
        "S3_ACCESS_KEY" = cfg.storage.local.minio.accessKey;
        "S3_SECRET_KEY" = cfg.storage.local.minio.secretKey;
        "S3_BUCKET" = cfg.storage.local.minio.bucket;
      };
      dependsOn = [ "happy-server-minio" ];
      extraOptions = [
        "--entrypoint=[\"/bin/sh\", \"-c\", \" mc alias set happy http://happy-server-minio:9000 \\\"$S3_ACCESS_KEY\\\" \\\"$S3_SECRET_KEY\\\" && mc mb -p happy/\\\"$S3_BUCKET\\\" && mc anonymous set download happy/\\\"$S3_BUCKET\\\" || true \"]"
      ];
      log-driver = "journald";
    };
  };
}
