{ self }:

{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.services.nrgha-api;
in

{
  meta.maintainers = with lib.maintainers; [ defelo ];
  _file = ./module.nix;

  options.services.nrgha-api = {
    enable = lib.mkEnableOption "nrgha-api";

    package = lib.mkPackageOption self.packages.${pkgs.stdenv.hostPlatform.system} "nrgha-api" {
      pkgsText = "nixpkgs-review-gha.packages.\${system}";
    };

    domain = lib.mkOption {
      type = lib.types.nonEmptyStr;
      description = "Name of the nginx virtual host to use and configure.";
      example = "nrgha-api.example.org";
    };

    oidcClientId = lib.mkOption {
      type = lib.types.nonEmptyStr;
      description = ''
        OIDC client id / audience for this instance.
        Should not be reused.
        Defaults to the value of `config.services.nrgha-api.domain` in reverse domain name notation.
      '';
    };

    githubTokenFile = lib.mkOption {
      type = lib.types.path;
      description = "Path of a file which contains a GitHub token with permissions to create comments on the NixOS/nixpkgs repository.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Extra command line arguments to pass to `nrgha-api serve`.";
      default = [ ];
    };

    logLevel = lib.mkOption {
      type = lib.types.str;
      description = ''
        Log level of the nrgha-api server.
        See <https://docs.rs/tracing-subscriber/latest/tracing_subscriber/filter/struct.EnvFilter.html#directives> for more information.
      '';
      default = "info";
    };
  };

  config = lib.mkIf cfg.enable {
    services.nrgha-api = {
      oidcClientId = lib.pipe cfg.domain [
        (lib.splitString ".")
        lib.reverseList
        (lib.concatStringsSep ".")
        lib.mkDefault
      ];
    };

    systemd.sockets.nrgha-api = {
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "%t/nrgha-api.sock";
        Service = "nrgha-api.service";
        SocketMode = "0666";
      };
    };

    systemd.services.nrgha-api = {
      wantedBy = [ "multi-user.target" ];

      requires = [
        "nrgha-api.socket"
        "network-online.target"
      ];
      after = [
        "nrgha-api.socket"
        "network-online.target"
      ];

      environment.RUST_LOG = cfg.logLevel;

      serviceConfig = {
        Type = "exec";
        Restart = "always";

        DynamicUser = true;
        User = "nrgha-api";
        Group = "nrgha-api";

        LoadCredential = [ "github-token:${cfg.githubTokenFile}" ];

        ExecStart = lib.escapeShellArgs (
          [
            (lib.getExe cfg.package)
            "serve"
            "--oidc-client-id=${cfg.oidcClientId}"
            "--github-token-file=%d/github-token"
          ]
          ++ cfg.extraArgs
        );

        # Hardening
        AmbientCapabilities = [ "" ];
        CapabilityBoundingSet = [ "" ];
        DevicePolicy = "closed";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProcSubset = "pid";
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RemoveIPC = true;
        RestrictAddressFamilies = [ "AF_INET AF_INET6 AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SocketBindDeny = "any";
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        UMask = "0077";
      };
    };

    services.nginx.enable = true;
    services.nginx.virtualHosts.${cfg.domain}.locations."/".proxyPass =
      "http://unix:/run/nrgha-api.sock";
  };
}
