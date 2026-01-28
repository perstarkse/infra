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
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "peteonrails";
    repo = "voxtype";
    rev = "v0.5.0";
    hash = "sha256-Prz0kSvf+gfsOIe9hMOTqWsMHrVLrww7DC/Jva8+GpA=";
  };

  cargoHash = "sha256-DtHjMAnh5TGunuOc+2u6lOoqOfonR17RiM6CtVqyxuM=";

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
