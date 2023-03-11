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
  in
  {
    packages.${system} = {
      inherit arc;
      inherit arc-wrapped;
      inherit osquery;
    };

  };
}
