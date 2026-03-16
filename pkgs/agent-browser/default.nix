{
  lib,
  fetchFromGitHub,
  makeWrapper,
  playwright-driver,
  rustPlatform,
  pkg-config,
  openssl,
}:
rustPlatform.buildRustPackage rec {
  pname = "agent-browser";
  version = "0.20.10";

  src = fetchFromGitHub {
    owner = "vercel-labs";
    repo = "agent-browser";
    rev = "1fd8e9d09a3fe434d5edca4415a12af7712ed85a";
    hash = "sha256-dL9mGtpWfgkrEjOE9FGY/HODli0r+Mk6gn88w85yRvI=";
  };

  sourceRoot = "source/cli";

  # Work around cargo setup hooks expecting Cargo.lock at the source root.
  prePatch = ''
    cp Cargo.lock ../Cargo.lock || true
  '';

  cargoHash = "sha256-ko/S5Sez2z6GPQePpbzndEYKJk7A+02BjBCv76ZL+zY=";

  doCheck = false;

  nativeBuildInputs = [
    pkg-config
    makeWrapper
  ];

  buildInputs = [openssl];

  postInstall = ''
    chromium=$(find -L ${playwright-driver.browsers} -name chrome -type f -executable | head -n1)

    if [ -z "$chromium" ]; then
      echo "Error: Could not find chrome binary in ${playwright-driver.browsers}"
      exit 1
    fi

    wrapProgram $out/bin/agent-browser \
      --set AGENT_BROWSER_EXECUTABLE_PATH "$chromium"
  '';

  meta = {
    description = "Headless browser automation CLI for AI agents";
    homepage = "https://github.com/vercel-labs/agent-browser";
    license = lib.licenses.asl20;
    mainProgram = "agent-browser";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
