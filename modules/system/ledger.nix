{
  config.flake.nixosModules.ledger = {
    hardware.ledger.enable = true;
    services.udev.extraRules = ''
      SUBSYSTEM=="usb", ATTR{idVendor}=="20a0", ATTR{idProduct}=="41e5", MODE="0666"
    '';
  };
}
