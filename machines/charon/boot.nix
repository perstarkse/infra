{
  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.grub.useOSProber = false;

  # Setting mem sleep to deep to avoid issues with suspend resuming
  boot.kernelParams = ["mem_sleep_default=deep"];

  # Setup keyfile
  boot.initrd.secrets = {
    "/crypto_keyfile.bin" = null;
  };
}
