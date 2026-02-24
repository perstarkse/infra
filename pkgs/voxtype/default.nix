{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  bindgenHook,
  cmake,
  git,
  alsa-lib,
  shaderc,
  vulkan-headers,
  vulkan-loader,
  enableVulkan ? false,
}:
rustPlatform.buildRustPackage {
  pname = "voxtype";
  version = "0.6.2-unstable-2026-02-22";

  src = fetchFromGitHub {
    owner = "peteonrails";
    repo = "voxtype";
    rev = "a7bde400235084a6a73ca623d43dd44f9564297d";
    hash = "sha256-NsuqqJnTaj7CQT3SmsnbNnoc9axXm/tyBm4yrcDGmAE=";
  };

  cargoHash = "sha256-yT3xqcIPtIgKBBeu56t4fWBMHaUfM9ROuL9IVCi0EhA=";

  cargoBuildFlags = lib.optionals enableVulkan ["--features" "gpu-vulkan"];

  nativeBuildInputs =
    [
      pkg-config
      bindgenHook
      cmake
      git
    ]
    ++ lib.optionals enableVulkan [shaderc];

  buildInputs =
    [alsa-lib]
    ++ lib.optionals enableVulkan [
      vulkan-headers
      vulkan-loader
    ];

  doCheck = false;

  meta = {
    description = "Push-to-talk voice-to-text for Linux";
    homepage = "https://voxtype.io";
    license = lib.licenses.mit;
    mainProgram = "voxtype";
    platforms = lib.platforms.linux;
  };
}
