{ config, lib, pkgs, ... }:

with builtins;
with lib;
let
  cfg = config.services.osquery;
  logsDirectoryPrefix = "/var/log/";
  stateDirectoryPrefix = "/var/lib/";
  flags = rec {
    # conf is the osquery configuration file used when the --config_plugin=filesystem.
    # filesystem is the osquery default value for the config_plugin flag.
    conf = pkgs.writeText "osquery.conf" (toJSON cfg.settings);

    # flagfile is the file containing osquery command line flags to be provided to the application using the special --flagfile option.
    flagfile = pkgs.writeText "osquery.flags"
      (concatStringsSep "\n"
        (mapAttrsToList (name: value: "--${name}=${value}")
          # Use the conf derivation if not otherwise specified.
          ({ config_path = conf; } // cfg.flags)));
  };
in
{
  options.services.osquery = {
    enable = mkEnableOption (mdDoc "osqueryd daemon");

    settings = mkOption {
      default = { };
      description = mdDoc ''
        Configuration to be written to the osqueryd JSON configuration file.
        To understand the configuration format, refer to https://osquery.readthedocs.io/en/stable/deployment/configuration/#configuration-components.
      '';
      example = {
        options.utc = false;
      };
      type = types.attrs;
    };

    flags = mkOption {
      default = { };
      description = mdDoc ''
        Attribute set of flag names and values to be written to the osqueryd flagfile.
        For more information, refer to https://osquery.readthedocs.io/en/stable/installation/cli-flags.
      '';
      example = {
        config_refresh = "10";
      };
      type = with types;
        let
          pathWithPrefix = prefix: mkOptionType {
            name = "path with prefix";
            description = "path with prefix \"${prefix}\"";
            descriptionClass = "noun";
            check = with (lib.strings);
              x: path.check x && hasPrefix prefix (toString x);
            merge = mergeEqualOption;
          };
        in
        submodule {
          freeformType = attrsOf str;
          options = {
            database_path = mkOption {
              default = stateDirectoryPrefix + "osquery/osquery.db";
              description = mdDoc "Path used for the database file.";
              type = pathWithPrefix stateDirectoryPrefix;
            };
            logger_path = mkOption {
              default = logsDirectoryPrefix + "osquery";
              description = mdDoc "Base directory used for logging.";
              # Systemd sytem unit LogsDirectory starts with /var/log/.
              type = pathWithPrefix logsDirectoryPrefix;
            };
            pidfile = mkOption {
              default = "/run/osquery/osqueryd.pidfile";
              description = mdDoc "Path used for pidfile.";
              type = pathWithPrefix "/run/";
            };
          };
        };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.osquery ];
    systemd.services.osqueryd = {
      after = [ "network.target" "syslog.service" ];
      description = "The osquery daemon";
      preStart = ''
        mkdir -p $(dirname ${escapeShellArg cfg.flags.pidfile})
      '';
      serviceConfig = with lib.strings; with lib.lists; {
        ExecStart = "${pkgs.osquery}/bin/osqueryd --flagfile ${flags.flagfile}";
        PIDFile = cfg.flags.pidfile;

        LogsDirectory = [ (removePrefix logsDirectoryPrefix cfg.flags.logger_path) ];
        StateDirectory = [
          (
            let
              directory = concatStringsSep "/"
                (init (splitString "/" (normalizePath cfg.flags.database_path)));
            in
            (removePrefix stateDirectoryPrefix directory)
          )
        ];

        Restart = "on-failure";
        TimeoutStartSec = "infinity";
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
}
