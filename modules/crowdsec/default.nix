{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.crowdsec;
  format = pkgs.formats.yaml {};
  configFile = format.generate "crowdsec.yaml" cfg.settings;

  pkg = cfg.package;

  patternsDir = pkgs.buildPackages.symlinkJoin {
    name = "crowdsec-patterns";
    paths = [cfg.patterns pkg.patterns ];
  };

  defaultSettings = with lib; {
    common = {
      daemonize = mkForce false;
      log_media = mkForce "stdout";
    };
    config_paths = {
      config_dir = mkDefault "/var/lib/crowdsec/config";
      data_dir = mkDefault dataDir;
      hub_dir = mkDefault hubDir;
      index_path = mkDefault "${hubDir}/.index.json";
      simulation_path = mkDefault "${pkg}/share/crowdsec/config/simulation.yaml";
      pattern_dir = mkDefault patternsDir;
    };
    db_config = {
      type = mkDefault "sqlite";
      db_path = mkDefault "${dataDir}/crowdsec.db";
      use_wal = true;
    };
    crowdsec_service = {
      enable = mkDefault true;
      acquisition_dir = let
        yamlFiles = map (format.generate "acquisition.yaml") cfg.acquisitions;
        dir = pkgs.buildPackages.runCommand "crowdsec-acquisitions" {} ''
          mkdir -p $out
          ${lib.optionalString (yamlFiles != []) ''
            cp ${lib.concatStringsSep " " yamlFiles} $out
          ''}
        '';
      in
        mkDefault dir;
    };
    api = {
      client = {
        credentials_path = mkDefault "${stateDir}/local_api_credentials.yaml";
      };
      server = {
        enable = mkDefault true;
        listen_uri = mkDefault "127.0.0.1:8080";

        console_path = mkDefault "${stateDir}/console.yaml";
        profiles_path = mkDefault "${pkg}/share/crowdsec/config/profiles.yaml";

        online_client.credentials_path = mkDefault "${stateDir}/online_api_credentials.yaml";
      };
    };
    prometheus = {
      enabled = mkDefault true;
      level = mkDefault "full";
      listen_addr = mkDefault "127.0.0.1";
      listen_port = mkDefault 6060;
    };
  };

  user = "crowdsec";
  group = "crowdsec";
  stateDir = "/var/lib/crowdsec";
  dataDir = "${stateDir}/data";
  hubDir = "${stateDir}/hub";
in {
  options.services.crowdsec = with lib; {
    enable = mkEnableOption "CrowSec Security Engine";
    package = mkOption {
      description = "The crowdsec package to use in this module";
      type = types.package;
      default = pkgs.callPackage ../../packages/crowdsec {};
    };
    name = mkOption {
      type = types.str;
      description = ''
        Name of the machine when registering it at the central or local api.
      '';
      default = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
    };
    enrollKeyFile = mkOption {
      description = ''
        The file containing the enrollment key used to enroll the engine at the central api console.
        See <https://docs.crowdsec.net/docs/next/console/enrollment/#where-can-i-find-my-enrollment-key> for details.
      '';
      type = types.nullOr types.path;
      default = null;
    };
    acquisitions = mkOption {
      type = with types; listOf format.type;
      default = [];
      description = ''
        A list of acquisition specifications, which define the data sources you want to be parsed.
        See <https://docs.crowdsec.net/u/getting_started/post_installation/acquisition_new> for details.
      '';
      example = [
        {
          source = "journalctl";
          journalctl_filter = ["_SYSTEMD_UNIT=sshd.service"];
          labels.type = "syslog";
        }
      ];
    };
    patterns = mkOption {
      description = ''
        A set of pattern files for parsing logs, in the form "type" to file containing the corresponding GROK patterns.
        Files in the derriviatons will be merged into one and must only contains files in the root of the derivation.
        All default patterns are automatically included.
        See <https://github.com/crowdsecurity/crowdsec/tree/master/config/patterns>.
      '';
      type = types.listOf types.package; #types.attrsOf types.pathInStore;
      default = [];
      example = lib.literalExpression ''
        [ (pkgs.writeTextDir "ssh" (builtins.readFile ./patterns/ssh)) ]
      '';
    };
    settings = mkOption {
      description = ''
        Settings for Crowdsec. Refer to the defaults at
        <https://github.com/crowdsecurity/crowdsec/blob/master/config/config.yaml>.
      '';
      type = format.type;
      default = {};
    };
    allowLocalJournalAccess = mkOption {
      description = ''
        Allow acquisitions from local systemd-journald.
        For details, see <https://doc.crowdsec.net/docs/data_sources/journald>.
      '';
      type = types.bool;
      default = false;
    };
    extraExecStartPre = mkOption {
      description = mkDoc ''
        Script run pre starting the engine (e.g. to add bouncers or install collections)
      '';
      type = types.lines;
      default = [];
    };
  };
  config = let
    cscli = pkgs.writeScriptBin "cscli" ''
      #!${pkgs.runtimeShell}
      set -eu
      set -o pipefail

      # cscli needs crowdsec on it's path in order to be able to run `cscli explain`
      export PATH=$PATH:${lib.makeBinPath [pkg]}

      exec ${pkg}/bin/cscli -c=${configFile} "''${@}"
    '';
  in
    lib.mkIf (cfg.enable) {
      services.crowdsec.settings = defaultSettings;

      environment = {
        systemPackages = [cscli];
      };

      systemd.packages = [pkg];
      systemd.timers.crowdsec-update-hub = {
        description = "Update the crowdsec hub index";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = "yes";
          Unit = "crowdsec-update-hub.service";
        };
      };
      systemd.services = let
        sudo_doas =
          if config.security.doas.enable == true
          then "${pkgs.doas}/bin/doas"
          else "${pkgs.sudo}/bin/sudo";
      in {
        crowdsec-update-hub = {
          description = "Update the crowdsec hub index";
          path = [cscli];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${sudo_doas} -u crowdsec ${cscli}/bin/cscli --error hub upgrade";
            ExecStartPost = " systemctl restart crowdsec.service";
          };
        };

        crowdsec = {
          description = "CrowdSec is a free, modern & collaborative behavior detection engine, coupled with a global IP reputation network.";

          path = [cscli];

          wantedBy = ["multi-user.target"];
          after = ["network-online.target"];
          wants = ["network-online.target"];
          serviceConfig = with lib; {
            User = "crowdsec";
            Group = "crowdsec";
            Restart = "on-failure";

            LimitNOFILE = mkDefault 65536;

            CapabilityBoundingSet = mkDefault [];

            NoNewPrivileges = mkDefault true;
            LockPersonality = mkDefault true;
            RemoveIPC = mkDefault true;

            ReadWritePaths = [stateDir];
            ProtectSystem = mkDefault "strict";

            PrivateUsers = mkDefault true;
            ProtectHome = mkDefault true;
            PrivateTmp = mkDefault true;

            PrivateDevices = mkDefault true;
            ProtectHostname = mkDefault true;
            ProtectKernelTunables = mkDefault true;
            ProtectKernelModules = mkDefault true;
            ProtectControlGroups = mkDefault true;

            ProtectProc = mkDefault "invisible";
            ProcSubset = mkIf (!cfg.allowLocalJournalAccess) (mkDefault "pid");

            RestrictNamespaces = mkDefault true;
            RestrictRealtime = mkDefault true;
            RestrictSUIDSGID = mkDefault true;

            SystemCallFilter = mkDefault ["@system-service" "@network-io"];
            SystemCallArchitectures = ["native"];
            SystemCallErrorNumber = mkDefault "EPERM";

            ExecPaths = ["/nix/store"];
            NoExecPaths = ["/"];

            ExecStart = "${pkg}/bin/crowdsec -c ${configFile}";
            ExecStartPre = let
              script = pkgs.writeScriptBin "crowdsec-setup" ''
                #!${pkgs.runtimeShell}
                set -eu
                set -o pipefail

                ${lib.optionalString cfg.settings.api.server.enable ''
                  if [ ! -s "${cfg.settings.api.client.credentials_path}" ]; then
                    cscli machine add "${cfg.name}" --auto
                  fi
                ''}

                ${lib.optionalString (cfg.enrollKeyFile != null) ''
                  if ! grep -q password "${cfg.settings.api.server.online_client.credentials_path}" ]; then
                    cscli capi register
                  fi

                  cscli hub update

                  if [ ! -e "${cfg.settings.api.server.console_path}" ]; then
                    cscli console enroll "$(cat ${cfg.enrollKeyFile})" --name ${cfg.name}
                  fi
                ''}
                ${cfg.extraExecStartPre}
              '';
            in ["${script}/bin/crowdsec-setup"];
          };
        };
      };
      systemd.tmpfiles.rules = [
        "d '${stateDir}' 0750 ${user} ${group} - -"
        "d '${dataDir}' 0750 ${user} ${group} - -"
        "d '${hubDir}' 0750 ${user} ${group} - -"
        "f '${cfg.settings.api.server.online_client.credentials_path}' 0750 ${user} ${group} - -"
        "f '${cfg.settings.config_paths.index_path}' 0750 ${user} ${group} - {}"
      ];
      users.users.${user} = {
        name = lib.mkDefault user;
        description = lib.mkDefault "Crowdsec service user";
        isSystemUser = lib.mkDefault true;
        group = lib.mkDefault group;
        extraGroups = lib.mkIf cfg.allowLocalJournalAccess ["systemd-journal"];
      };

      users.groups.${group} = lib.mapAttrs (name: lib.mkDefault) {};
    };
}
