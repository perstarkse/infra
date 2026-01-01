{
  config.flake.homeModules.voxtype = {
    lib,
    config,
    ...
  }: {
    imports = [
      ../../pkgs/modules/voxtype.nix
    ];

    config = lib.mkIf config.programs.voxtype.enable {
      programs.voxtype.settings = {
        audio = {
          device = "default";
          sample_rate = 16000;
          max_duration_secs = 200;
          feedback = {
            enabled = true;
            theme = "default";
            volume = 0.7;
          };
        };
        whisper = {
          language = "en";
        };
        text = {
          spoken_punctuation = true;
        };
        output = {
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
