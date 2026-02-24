{
  lib,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  playwright-driver,
  rustPlatform,
  pkg-config,
  openssl,
  pnpm,
  cacert,
  nodejs,
}: let
  version = "0.14.0-unstable-2026-02-23";
  src = fetchFromGitHub {
    owner = "vercel-labs";
    repo = "agent-browser";
    rev = "2fe7394dbeb89efb00e56899dd71f32db5ec1dee";
    hash = "sha256-oDgnxQ09e1IUd1kfgr75TNiYOf5VpMXG9DjfGG4OGwA=";
  };

  cli = rustPlatform.buildRustPackage {
    pname = "agent-browser-cli";
    inherit version src;

    # Build only the CLI directory
    sourceRoot = "source/cli";

    # Workaround for cargo check hook looking for Cargo.lock in the wrong place
    # when sourceRoot is a subdirectory
    prePatch = ''
      cp Cargo.lock ../Cargo.lock || true
    '';

    cargoHash = "sha256-94w9V+NZiWeQ3WbQnsKxVxlvsCaOJR0Wm6XVc85Lo88=";

    nativeBuildInputs = [pkg-config];
    buildInputs = [openssl];
  };

  pnpmDeps = stdenv.mkDerivation {
    pname = "agent-browser-pnpm-deps";
    inherit version src;
    nativeBuildInputs = [pnpm cacert];
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-QqW+zCYWSCm30+h//mRg+bqnT8hOSm2mPYpVB+kLCnA=";

    buildPhase = ''
      export HOME=$TMPDIR
      pnpm config set store-dir $out
      pnpm install --frozen-lockfile --ignore-scripts
    '';

    dontInstall = true;
    dontFixup = true;
  };
in
  stdenv.mkDerivation {
    pname = "agent-browser";
    inherit version src;

    nativeBuildInputs = [pnpm nodejs makeWrapper];

    buildPhase = ''
      export HOME=$TMPDIR
      export PNPM_STORE_DIR=$TMPDIR/pnpm-store

      # Use a writable copy of the pre-fetched pnpm store
      cp -r ${pnpmDeps} "$PNPM_STORE_DIR"
      chmod -R +w "$PNPM_STORE_DIR"

      # Restore pnpm store
      pnpm config set store-dir "$PNPM_STORE_DIR"
      pnpm config set package-import-method copy

      # Install deps
      pnpm install --offline --frozen-lockfile --ignore-scripts

      # Build
      pnpm run build
    '';

    installPhase = ''
      mkdir -p $out/lib/node_modules/agent-browser
      cp -r . $out/lib/node_modules/agent-browser

      # Install rust binary
      mkdir -p $out/lib/node_modules/agent-browser/bin
      rm -f $out/lib/node_modules/agent-browser/bin/agent-browser
      cp ${cli}/bin/agent-browser $out/lib/node_modules/agent-browser/bin/agent-browser

      # Create symlink
      mkdir -p $out/bin
      ln -s $out/lib/node_modules/agent-browser/bin/agent-browser $out/bin/agent-browser

      # Find chromium binary
      # Use -L to follow symlinks since playwright-browsers contains symlinks to store paths
      chromium=$(find -L ${playwright-driver.browsers} -name chrome -type f -executable | head -n1)

      if [ -z "$chromium" ]; then
        echo "Error: Could not find chrome binary in ${playwright-driver.browsers}"
        ls -la ${playwright-driver.browsers}
        exit 1
      fi

      # Patch browser.js to respect executablePath
      sed -i 's/headless: options.headless ?? true/headless: options.headless ?? true, executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH/' $out/lib/node_modules/agent-browser/dist/browser.js

      # Wrap
      wrapProgram $out/bin/agent-browser \
        --set PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH "$chromium" \
        --set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD "1"
    '';

    meta = {
      description = "Headless browser automation CLI for AI agents";
      homepage = "https://github.com/vercel-labs/agent-browser";
      license = lib.licenses.asl20;
      mainProgram = "agent-browser";
      platforms = lib.platforms.linux ++ lib.platforms.darwin;
    };
  }
