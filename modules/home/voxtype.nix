{
  config.flake.homeModules.voxtype = {
    pkgs,
    lib,
    config,
    ...
  }: let
    cfg = config.programs.voxtype;

    version = "0.4.2";
    rev = "a93f75b97400fccae21c3b1868d1ba41821b918d";
    srcHash = "sha256-6UGjmVgamqfywTeonkbx5lp2NauCBMfAwRgg00YYLiQ=";
    cargoHash = "sha256-ssQ5wUZeLzOwY2Hj1b8aL90SQ95/VJz+YvJcmX7sOCQ=";

    defaultPackage = pkgs.rustPlatform.buildRustPackage {
      pname = "voxtype";
      inherit version;
      src = pkgs.fetchFromGitHub {
        owner = "peteonrails";
        repo = "voxtype";
        rev = "v${version}";
        hash = srcHash;
      };
      inherit cargoHash;
      cargoBuildFlags = lib.optionals cfg.enableVulkan ["--features" "gpu-vulkan"];
      nativeBuildInputs = [
        pkgs.pkg-config
        pkgs.rustPlatform.bindgenHook
        pkgs.cmake
        pkgs.git
      ] ++ lib.optionals cfg.enableVulkan [
        pkgs.shaderc
      ];
      buildInputs =
        [pkgs.alsa-lib]
        ++ lib.optionals cfg.enableVulkan [
          pkgs.vulkan-headers
          pkgs.vulkan-loader
        ];
      doCheck = false;
    };

    modelFilenames = {
      tiny = "ggml-tiny.bin";
      "tiny.en" = "ggml-tiny.en.bin";
      base = "ggml-base.bin";
      "base.en" = "ggml-base.en.bin";
      small = "ggml-small.bin";
      "small.en" = "ggml-small.en.bin";
      medium = "ggml-medium.bin";
      "medium.en" = "ggml-medium.en.bin";
      "large-v3" = "ggml-large-v3.bin";
      "large-v3-turbo" = "ggml-large-v3-turbo.bin";
    };

    defaultModelHashes = {
      "base.en" = "sha256-oDd5yG3zMjB19eeWyyzlAp8A7Ihp7uP9+4l6/jbG0AI=";
      "tiny.en" = "sha256-kh5M+Ghv3Zk9zQgaXaW2w2W/3hFi5ysI11rHUomSCx8=";
    };

    modelIsKnown = lib.hasAttr cfg.model modelFilenames;
    modelFilename = modelFilenames.${cfg.model} or cfg.model;
    modelHash =
      if cfg.modelHash != null
      then cfg.modelHash
      else defaultModelHashes.${cfg.model} or null;
    modelUrl =
      if cfg.modelUrl != null
      then cfg.modelUrl
      else "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${modelFilename}";
    modelSource =
      if modelIsKnown && modelHash != null
      then
        pkgs.fetchurl {
          url = modelUrl;
          hash = modelHash;
        }
      else null;

    tomlFormat = pkgs.formats.toml {};
    configFile = tomlFormat.generate "voxtype-config.toml" (lib.recursiveUpdate {
        hotkey = {
          enabled = false;
          key = "SCROLLLOCK";
        };
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
          model = cfg.model;
          language = "en";
        };
        output = {
          mode = "type";
          fallback_to_clipboard = true;
          type_delay_ms = 0;
          notification = {
            on_recording_start = false; # Notify when PTT activates
            on_recording_stop = false; # Notify when transcribing
            on_transcription = false; # Show transcribed text
          };
        };
        state_file = "auto";
      }
      cfg.settings);
  in {
    options.programs.voxtype = {
      enable = lib.mkEnableOption "Enable the voxtype voice typing daemon";

      package = lib.mkOption {
        type = lib.types.package;
        default = defaultPackage;
        defaultText = lib.literalExpression "pkgs.rustPlatform.buildRustPackage { ... }";
        description = "Package to install for voxtype.";
      };

      model = lib.mkOption {
        type = lib.types.str;
        default = "base.en";
        description = "Whisper model name or path to a .bin file.";
      };

      modelHash = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "SHA-256 hash (SRI) for the model download.";
      };

      modelUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Override the download URL for the Whisper model.";
      };

      settings = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        description = "Extra entries merged into voxtype config.toml.";
      };

      enableService = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run the voxtype daemon as a systemd user service.";
      };

      enableVulkan = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Build voxtype with Vulkan GPU acceleration.";
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = !(modelIsKnown && modelHash == null);
          message = "programs.voxtype.modelHash must be set for model '${cfg.model}'.";
        }
      ];

      home.packages = with pkgs; [
        cfg.package
        wtype
        wl-clipboard
      ];

      xdg.configFile."voxtype/config.toml".source = configFile;

      xdg.dataFile = lib.mkIf (modelSource != null) {
        "voxtype/models/${modelFilename}".source = modelSource;
      };

      systemd.user.services.voxtype = lib.mkIf cfg.enableService {
        Unit = {
          Description = "Voxtype voice typing daemon";
          PartOf = ["graphical-session.target"];
          After = ["graphical-session.target"];
        };
        Service = {
          ExecStart = "${cfg.package}/bin/voxtype";
          Environment = "XDG_RUNTIME_DIR=%t";
          RuntimeDirectory = "voxtype";
          RuntimeDirectoryMode = "0700";
          Restart = "on-failure";
        };
        Install = {
          WantedBy = ["graphical-session.target"];
        };
      };
    };
  };
}
