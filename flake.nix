{
  inputs = {
    nixpkgs.url = github:NixOs/nixpkgs/nixos-22.11;
  };

  outputs = {nixpkgs,...}:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    stdenv = pkgs.stdenv;
    fetchurl = pkgs.fetchurl;
    arc = stdenv.mkDerivation rec {
      name = "arc";

      src = fetchurl {
          url = "https://get.arc-vcs.yandex.net/launcher/linux";
          sha256 = "27891715d5f2684f9a15f91d058df700e87c15499c77ca456438eb8fbeeeec70";
      };

      dontUnpack = true;

      installPhase = ''
          mkdir -p $out/bin
          echo "#!${pkgs.python3}/bin/python" > $out/bin/arc
          cat $src >> $out/bin/arc
          chmod +x $out/bin/arc
      '';
      };
    arc-wrapped = pkgs.buildFHSUserEnv {
        name = "arc";
        targetPkgs = pkgs: with pkgs; [arc pkgs.python3];
        runScript = "${pkgs.python3}/bin/python3 ${arc}/bin/arc";
      };
    osquery = with pkgs; callPackage ./osquery/default.nix {};

    add-packages = final: prev: prev // {
      yandex-arc = arc;
      inherit osquery;
    };
  in
  {
    packages.${system} = {
      inherit arc;
      inherit arc-wrapped;
      inherit osquery;
    };
    overlays = {
      inherit add-packages;
    };
    nixosModules = rec {
      ya-packages = {pkgs,...}: {
        nixpkgs.overlays = [add-packages];
        environment.systemPackages = with pkgs; [yandex-arc];
      };
      osquery = import ./osquery/service.nix;
      yandex-osquery = {...}: {
        services.osquery-custom.enable = true;
        services.osquery-custom.flags = {
          # Configuration control flags
          disable_extensions="true";
          disable_audit="false";
          config_plugin="tls";
          config_refresh="14";
          host_identifier="uuid";
          # just use default
          #database_path="/var/lib/osquery/osquery.dbq";

          # Daemon control flags
          force="true";
          watchdog_level="0";
          watchdog_utilization_limit="30";

          # Remote settings flags
          tls_hostname="oscar-n.sec.yandex.net";
          tls_server_certs="/var/lib/osquery/certs.pem";
          enroll_secret_path="/var/lib/osquery/enroll_secret";
          config_tls_endpoint="/api/v1/osquery/config";
          enroll_tls_endpoint="/api/v1/osquery/enroll";

          # Logging/results flags
          logger_tls_endpoint="/logger";
          logger_plugin="tls";
          logger_min_status="10";
          logger_min_stderr="10";
          stderrthreshold="3";
        };
      };
      default = {...}: {
        imports = [ya-packages osquery yandex-osquery];
      };
    };
  };
}
