{inputs, ...}: {
  config.flake.homeModules.default-layout = {
    pkgs,
    lib,
    ...
  }: let
    mainMod = "SUPER";
  in {
    wayland.windowManager.hyprland.settings = {
      general = {
        gaps_in = 0;
        gaps_out = 0;
        border_size = 1;
        layout = "dwindle";
      };

      dwindle = {
        pseudotile = true;
        preserve_split = true;
        force_split = 2;
        smart_split = false;
        smart_resizing = true;
      };

      bind = [
        "${mainMod}, H, movefocus, l"
        "${mainMod}, J, movefocus, d"
        "${mainMod}, K, movefocus, u"
        "${mainMod}, L, movefocus, r"
        "${mainMod}, left, movefocus, l"
        "${mainMod}, right, movefocus, r"
        "${mainMod}, up, movefocus, u"
        "${mainMod}, down, movefocus, d"

        "${mainMod} SHIFT, H, movewindow, l"
        "${mainMod} SHIFT, J, movewindow, d"
        "${mainMod} SHIFT, K, movewindow, u"
        "${mainMod} SHIFT, L, movewindow, r"
        "${mainMod} SHIFT, left, movewindow, l"
        "${mainMod} SHIFT, right, movewindow, r"
        "${mainMod} SHIFT, up, movewindow, u"
        "${mainMod} SHIFT, down, movewindow, d"

        "${mainMod}, R, layoutmsg, presel r"
        "${mainMod} SHIFT, R, layoutmsg, presel l"
        "${mainMod}, U, layoutmsg, presel u"
        "${mainMod} SHIFT, U, layoutmsg, presel d"

        "${mainMod}, S, layoutmsg, split"
        "${mainMod} SHIFT, S, layoutmsg, togglesplit"
  
        "${mainMod} SHIFT, Q, killactive,"
        "${mainMod}, F, fullscreen, 0"
        "${mainMod} SHIFT, F, togglefloating,"
      ];
    };
  };
} 