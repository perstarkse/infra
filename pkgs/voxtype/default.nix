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
  version = "0.4.2";

  src = fetchFromGitHub {
    owner = "peteonrails";
    repo = "voxtype";
    rev = "v0.4.2";
    hash = "sha256-6UGjmVgamqfywTeonkbx5lp2NauCBMfAwRgg00YYLiQ=";
  };

  cargoHash = "sha256-ssQ5wUZeLzOwY2Hj1b8aL90SQ95/VJz+YvJcmX7sOCQ=";

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
