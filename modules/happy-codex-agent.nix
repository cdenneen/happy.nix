{
  config,
  lib,
  pkgs,
  ...
}:

{
  options.services."happy-codex-agent" = {
    enable = lib.mkEnableOption "Happy codex agent instances";
    mode = lib.mkOption {
      type = lib.types.enum [
        "user"
        "system"
      ];
      default = "user";
      description = "Systemd service mode for codex instances.";
    };
    happyBin = lib.mkOption {
      type = lib.types.str;
      default = "happy";
      description = "Happy CLI command used to launch codex.";
    };
    pathPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Extra packages to add to PATH for the codex service.";
    };
    instances = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule (
          { ... }:
          {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                description = "Instance name (used in unit name).";
              };
              workspace = lib.mkOption {
                type = lib.types.str;
                description = "Workspace directory for the instance.";
              };
              happyServerUrl = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Optional HAPPY_SERVER_URL override.";
              };
            };
          }
        )
      );
      default = [ ];
      description = "Happy codex instances to run.";
    };
  };

  config =
    let
      cfg = config.services."happy-codex-agent";
      mkService = name: instance: {
        description = "Happy codex (${name})";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = if cfg.mode == "system" then [ "multi-user.target" ] else [ "default.target" ];
        serviceConfig = {
          Type = "simple";
          WorkingDirectory = instance.workspace;
          ExecStart = "${cfg.happyBin} codex";
          Restart = "on-failure";
          RestartSec = 5;
          Environment =
            lib.optional (cfg.pathPackages != [ ]) "PATH=${lib.makeBinPath cfg.pathPackages}"
            ++ lib.optional (instance.happyServerUrl != null) "HAPPY_SERVER_URL=${instance.happyServerUrl}";
        };
      };

      serviceSet = lib.listToAttrs (
        map (instance: {
          name = "happy-codex-${instance.name}";
          value = mkService instance.name instance;
        }) cfg.instances
      );
    in
    lib.mkMerge [
      (lib.mkIf ((cfg.enable or false) && cfg.mode == "system") {
        systemd.services = serviceSet;
      })
      (lib.mkIf ((cfg.enable or false) && cfg.mode == "user") {
        systemd.user.services = serviceSet;
      })
    ];
}
