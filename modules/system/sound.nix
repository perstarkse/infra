{
  config.flake.nixosModules.sound = {
    lib,
    pkgs,
    config,
    ...
  }: let
    cfg = config.my.sound;
  in {
    options.my.sound.enable = lib.mkEnableOption "PipeWire audio";
    config = lib.mkIf cfg.enable {
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
  };
}
