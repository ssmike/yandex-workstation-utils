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
          sha256 = "e76b00993bcc8533850b635d329be09eaa5d619cce89b0bd116aa391a49309bc";
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

    yc-yubikey-cli = stdenv.mkDerivation rec {
      name = "yc-yubikey-cli";
      src = fetchurl {
        url = "https://infra.s3.mds.yandex.net/yc-yubikey-cli/build/linux/stable/yc-yubikey-cli";
        sha256 = "fa4a0de6b4b5f95ee3913c3497eb5e31a8a9df24d5a28659dda5ec1d941c3271";
      };

      dontUnpack = true;

      ldPath = nixpkgs.lib.makeLibraryPath [stdenv.cc.cc pkgs.pcsclite];

      nativeBuildInputs = [ pkgs.makeWrapper ];

      installPhase = ''
        install -D $src $out/lib/yc-yubikey-cli
        patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
                "$out/lib/yc-yubikey-cli" 

        makeWrapper $out/lib/yc-yubikey-cli $out/bin/yc-yubikey-cli \
              --suffix LD_LIBRARY_PATH : ${ldPath}
        '';
    };

    pssh = stdenv.mkDerivation rec {
      name = "pssh";

      version-helper = "PSSH_VERSION=$(curl https://infra.s3.mds.yandex.net/pssh/release/stable)";

      src = fetchurl {
        url = "https://infra.s3.mds.yandex.net/pssh/release/1.7.12/linux/amd64/pssh";
        sha256 = "f830a900d59470b962bec237a59a0800979bda26d25ded7b0c1d2714ba149f0a";
      };

      dontUnpack = true;

      ldPath = nixpkgs.lib.makeLibraryPath [stdenv.cc.cc pkgs.pcsclite];

      nativeBuildInputs = [ pkgs.makeWrapper ];

      installPhase = ''
        install -D $src $out/lib/pssh
        patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
                "$out/lib/pssh" 

        makeWrapper $out/lib/pssh $out/bin/pssh \
              --suffix LD_LIBRARY_PATH : ${ldPath}
        '';

    };

    itsme = stdenv.mkDerivation {
      name = "itsme-cli";
      src = fetchurl {
        url = "https://s3.mds.yandex.net/linux/yandex-itsme-cli.deb";
        sha256 = "a666ff7356725eae179c319c32df2615c4d7c37bc751510c29eaeea9b1ab0940";
      };

      dontUnpack = true;
      nativeBuildInputs = [ pkgs.autoPatchelfHook pkgs.binutils ];

      buildPhase = ''
        ar x $src
        tar xvf data.tar.gz
      '';

      installPhase = ''
        mkdir -p $out/bin
        mv usr/bin/itsme-cli $out/bin
      '';
    };

    osquery = with pkgs; callPackage ./osquery/default.nix {};

    add-packages = final: prev: prev // {
      yandex-arc = arc;
      inherit osquery;
      inherit yc-yubikey-cli;
      inherit pssh;
      inherit itsme;
    };
    override-vpn = final : prev : prev // {
      openvpn = prev.openvpn.override {
         openssl = prev.openssl_legacy;
         pkcs11Support = true;
      };
    };
  in
  {
    packages.${system} = {
      inherit arc;
      inherit arc-wrapped;
      inherit osquery;
      inherit yc-yubikey-cli;
      inherit pssh;
      inherit itsme;
    };
    overlays = {
      inherit add-packages;
    };
    nixosModules = rec {
      ya-packages = {pkgs,...}: {
        nixpkgs.overlays = [add-packages override-vpn];
        environment.systemPackages = with pkgs; [yandex-arc pssh];
      };
      osquery = import ./osquery/service.nix;
      itsme = import ./itsme.nix;
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
        imports = [ya-packages osquery itsme yandex-osquery];
      };
    };
  };
}
