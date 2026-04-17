{
  lib,
  stdenvNoCC,
  fetchurl,
  binwalk,
  coreutils,
  findutils,
  gnugrep,
  version ? "5.0.6",
  url ? "https://fw-download.ubnt.com/data/unifi-os-server/1856-linux-x64-5.0.6-33f4990f-6c68-4e72-9d9c-477496c22450.6-x64",
  sha256,
}:
stdenvNoCC.mkDerivation rec {
  pname = "unifi-os-server-image";
  inherit version;

  src = fetchurl {
    inherit url sha256;
  };

  nativeBuildInputs = [
    binwalk
    coreutils
    findutils
    gnugrep
  ];

  dontUnpack = true;

  installPhase = ''
    set -euo pipefail

    work="$PWD/work"
    mkdir -p "$work"
    cp "$src" "$work/unifi-os-installer"
    chmod u+w "$work/unifi-os-installer"
    cd "$work"

    binwalk -e ./unifi-os-installer >/dev/null

    image_tar="$(find . -type f -name image.tar | head -n1)"
    discovery_bin="$(find . -type f -name discovery | head -n1)"
    uosserver_bin="$(find . -type f -name uosserver | head -n1)"
    uosserver_service_bin="$(find . -type f -name uosserver-service | head -n1)"
    updater_service_bin="$(find . -type f -name updater-service | head -n1)"
    pasta_bin="$(find . -type f -name pasta | head -n1)"
    purge_bin="$(find . -type f -name purge | head -n1)"
    if [ -z "$image_tar" ]; then
      echo "Could not find embedded image.tar in UniFi OS installer" >&2
      exit 1
    fi
    if [ -z "$discovery_bin" ] || [ -z "$uosserver_bin" ] || [ -z "$uosserver_service_bin" ] || [ -z "$updater_service_bin" ]; then
      echo "UniFi OS installer is missing one or more required runtime binaries" >&2
      exit 1
    fi

    mkdir -p "$out"
    cp "$image_tar" "$out/image.tar"

    if [ -n "$discovery_bin" ]; then
      cp "$discovery_bin" "$out/discovery"
      chmod +x "$out/discovery"
    fi

    for bin in \
      "$uosserver_bin:$out/uosserver" \
      "$uosserver_service_bin:$out/uosserver-service" \
      "$updater_service_bin:$out/updater-service" \
      "$pasta_bin:$out/pasta" \
      "$purge_bin:$out/purge"
    do
      src_path="''${bin%%:*}"
      out_path="''${bin#*:}"
      if [ -n "$src_path" ]; then
        cp "$src_path" "$out_path"
        chmod +x "$out_path"
      fi
    done
  '';

  passthru.unifiOs = {
    containerName = "uosserver";
    imageTag = "uosserver:0.0.54";
    ports = {
      discoveryHelper = 11002;
      discoveryTarget = 10003;
      supervisorWebsocket = 11084;
    };
    binaries = {
      imageTar = "image.tar";
      discovery = "discovery";
      runtime = "uosserver";
      runtimeService = "uosserver-service";
      updaterService = "updater-service";
      pasta = "pasta";
      purge = "purge";
    };
  };

  meta = with lib; {
    description = "Extracted OCI image archive from the UniFi OS Server installer";
    homepage = "https://help.ui.com/hc/en-us/articles/34210126298775-Self-Hosting-UniFi";
    license = licenses.unfreeRedistributableFirmware;
    platforms = platforms.linux;
    sourceProvenance = with sourceTypes; [binaryNativeCode];
  };
}
