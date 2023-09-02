{ config, lib, pkgs, ... }:

let
    override-vpn = final : prev : prev // {
      openvpn = prev.openvpn.override {
         pkcs11Support = true;
      };
    };
in
{
  nixpkgs.overlays = [ override-vpn ];

  services.pcscd.enable = true;

  security.tpm2 = {
    enable = true;
    pkcs11.enable = true;
    applyUdevRules = true;
    abrmd.enable = true;
    tctiEnvironment.enable = true;
  };

  environment.systemPackages = with pkgs; [
    openvpn
    dmidecode
    opensc
    gnutls
    tpm2-tools
    tpm2-tss
    tpm2-pkcs11
    libp11
    itsme
  ];

  # Без этого, p11tool не может найти libtpm2
  environment.etc."pkcs11/modules/libtpm2-pkcs11".text = ''
    module: /run/current-system/sw/lib/libtpm2_pkcs11.so
    critical: yes
  '';
}
