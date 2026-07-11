{
  config.flake.nixosModules.ledger = {
    lib,
    config,
    ...
  }: let
    cfg = config.my.ledger;
    ledgerGroup = "ledger";
    mainUser = config.my.mainUser.name;
  in {
    options.my.ledger.enable = lib.mkEnableOption "Ledger hardware wallet udev/system support";
    config = lib.mkIf cfg.enable {
      hardware.ledger.enable = true;

      users.groups.${ledgerGroup} = {};
      users.users.${mainUser}.extraGroups = lib.mkAfter [ledgerGroup];

      services.udev.extraRules = lib.mkAfter ''
        SUBSYSTEM=="usb", ATTR{idVendor}=="20a0", ATTR{idProduct}=="41e5", GROUP="${ledgerGroup}", MODE="0660"
      '';
    };
  };
}
