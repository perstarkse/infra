# Tether: bridge an iPhone to the Linux Wayland desktop (clipboard sync, file
# transfer, messages/notifications over Bluetooth).
#
# Upstream builds use CMake FetchContent for nlohmann_json and googletest.
# Those sub-builds cannot fetch from the network in the nix sandbox, so
# FETCHCONTENT_SOURCE_DIR_* points them at the nixpkgs source trees.
{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  gettext,
  nlohmann_json,
  gtest,
  wayland,
  openssl,
  glib,
  gtk3,
  gtk-layer-shell,
  libnotify,
  avahi,
  bluez,
  wrapGAppsHook3,
  gsettings-desktop-schemas,
  version ? "0.2.18",
  rev ? "cf18fd4b245d70e843b57d1bb6bf8e32f1293e2c",
  hash ? "sha256-Ygevoa/gEt80HyRYeWmVGDIwi4Eyl8XVz/RABcGK03Q=",
}:
stdenv.mkDerivation {
  pname = "tether";
  inherit version;

  src = fetchFromGitHub {
    owner = "zackb";
    repo = "tether";
    inherit rev hash;
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    gettext
    wrapGAppsHook3
  ];

  buildInputs = [
    nlohmann_json
    wayland
    openssl
    glib
    gtk3
    gtk-layer-shell
    libnotify
    avahi
    gsettings-desktop-schemas
  ];

  postPatch = ''
    # No .git in the fetchFromGitHub tree, so upstream's `git describe` fallback
    # would label the build "0.2.18-unknown"; report the clean version instead.
    substituteInPlace CMakeLists.txt \
      --replace 'set(TETHER_VERSION "''${PROJECT_VERSION}-unknown")' 'set(TETHER_VERSION "''${PROJECT_VERSION}")'
  '';

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    # Baked into the shipped bluetooth-experimental.conf drop-in, only shown by
    # `tether --bt-setup` printouts. On NixOS the real bluetoothd ExecStart is
    # managed by hardware.bluetooth and the drop-in is never applied.
    "-DBLUETOOTHD_PATH=${bluez}/libexec/bluetooth/bluetoothd"
    "-DFETCHCONTENT_SOURCE_DIR_JSON=${nlohmann_json.src}"
    "-DFETCHCONTENT_SOURCE_DIR_GOOGLETEST=${gtest.src}"
    # These default to absolute /etc paths, which the fixed-output install fails
    # to write; redirect into $out and keep the real manifest locations to HM.
    "-DCHROME_MESSAGING_DIR=${placeholder "out"}/etc/chromium/native-messaging-hosts"
    "-DGOOGLE_CHROME_MESSAGING_DIR=${placeholder "out"}/etc/chromium/native-messaging-hosts"
  ];

  postInstall = ''
    test -f $out/lib/mozilla/native-messaging-hosts/com.tether.extension.json
    test -f $out/etc/chromium/native-messaging-hosts/com.tether.extension.json
  '';

  # tetherd spawns tether-dialog next to /proc/self/exe with a PATH fallback;
  # all binaries land in the same $out/bin. btmgmt is popen()'d for Bluetooth
  # diagnostics, so bluez must be on the daemon user's PATH at runtime.
  meta = with lib; {
    description = "Bridge an iPhone to the Linux desktop: clipboard, files, messages, and notifications";
    homepage = "https://github.com/zackb/tether";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "tetherd";
  };
}
