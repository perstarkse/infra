{inputs, ...}: {
  config.flake.homeModules.voxtype = {
    pkgs,
    lib,
    config,
    ...
  }: let
    cfg = config.my.voxtype;
    inherit (pkgs.stdenv.hostPlatform) system;
    defaultPackage = inputs.voxtype.packages.${system}.default;
  in {
    imports = [inputs.voxtype.homeManagerModules.default];

    options.my.voxtype.enable = lib.mkEnableOption "voxtype voice transcription";

    config = lib.mkIf cfg.enable {
      programs.voxtype.package = lib.mkDefault defaultPackage;

      programs.voxtype.settings = {
        audio = lib.mkDefault {
          device = "default";
          sample_rate = 16000;
          max_duration_secs = 200;
          feedback = {
            enabled = true;
            theme = "default";
            volume = 0.7;
          };
        };
        whisper.language = lib.mkDefault "auto";
        text.spoken_punctuation = lib.mkDefault true;
        output = lib.mkDefault {
          mode = "type";
          fallback_to_clipboard = true;
          type_delay_ms = 0;
          notification = {
            on_recording_start = false;
            on_recording_stop = false;
            on_transcription = false;
          };
        };
      };
    };
  };
}
