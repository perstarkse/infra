{
  config.flake.nixosModules.sound = {pkgs, ...}: {
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };

    environment.systemPackages = with pkgs; [
      pavucontrol
    ];
  };
}
