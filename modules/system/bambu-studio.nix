{
  config.flake.nixosModules.bambu-studio = {
    lib,
    pkgs,
    config,
    ...
  }: let
    cfg = config.my.bambu-studio;
    # Printing's slicer ran on nixos-unstable; track the same channel here.
    bambu-studio = pkgs.unstable.bambu-studio;

    # GUI sessions here run niri (Wayland + XWayland). Launch through a
    # wrapper that guarantees DISPLAY/WAYLAND_DISPLAY are exported (with
    # this machine's fallbacks) before exec, so the slicer starts from any
    # context — desktop launcher, terminal, remote — even when the session
    # vars are set but not exported.
    bambu-studio-launcher = pkgs.writeShellScriptBin "bambu-studio" ''
      export DISPLAY="''${DISPLAY:-:0}"
      export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-wayland-1}"
      exec "${bambu-studio}/bin/bambu-studio" "$@"
    '';

    # The stock package is not on PATH (the wrapper shadows its binary
    # name), so its upstream .desktop file never reaches the closure.
    # Ship our own entry pointing at the wrapper (bare name → PATH lookup)
    # with upstream's metadata, plus its icon from the already-fetched
    # source tree (no network).
    desktop-item = pkgs.makeDesktopItem {
      name = "bambu-studio";
      desktopName = "Bambu Studio";
      genericName = "3D Printing Software";
      exec = "bambu-studio %U";
      icon = "BambuStudio";
      categories = [
        "Graphics"
        "3DGraphics"
        "Engineering"
      ];
      mimeTypes = [
        "model/stl"
        "model/3mf"
        "application/vnd.ms-3mfdocument"
        "application/prs.wavefront-obj"
        "application/x-amf"
        "x-scheme-handler/bambustudio"
      ];
    };

    icon = pkgs.runCommand "bambu-studio-icon" {} ''
      mkdir -p $out/share/icons/hicolor/192x192/apps
      cp ${bambu-studio.src}/resources/images/BambuStudio_192px.png \
        $out/share/icons/hicolor/192x192/apps/BambuStudio.png
    '';
  in {
    options.my.bambu-studio.enable = lib.mkEnableOption "Bambu Studio slicer (P1S)";

    config = lib.mkIf cfg.enable {
      environment.systemPackages = [
        bambu-studio-launcher
        desktop-item
        icon
      ];
    };
  };
}
