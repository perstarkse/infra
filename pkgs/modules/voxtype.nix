{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.voxtype;

  defaultPackage = pkgs.callPackage ../voxtype {
    inherit (pkgs) pkg-config cmake git shaderc;
    bindgenHook = pkgs.rustPlatform.bindgenHook;
    inherit (pkgs) alsa-lib vulkan-headers vulkan-loader;
    enableVulkan = cfg.enableVulkan;
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
    "large-v3-turbo" = "sha256-H8cPd0046xaZk6w5Huo1fvR8iHV+9y7llDh5t+jivGk=";
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
      whisper = {
        model = cfg.model;
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
      defaultText = lib.literalExpression "pkgs.callPackage ../voxtype { ... }";
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
}
