{...}: {
  config.flake.homeModules.hy3-layout = {lib, ...}: let
    mainMod = "SUPER";
  in {
    wayland.windowManager.hyprland.settings = {
      general = lib.mkForce {
        gaps_in = 0;
        gaps_out = 0;
        border_size = 1;
        layout = "hy3";
      };

      plugin = {
        hy3 = {
          no_gaps_when_only = 1;

          node_collapse_policy = 2;

          group_inset = 10;

          tab_first_window = false;

          tabs = {
            height = 22;

            padding = 6;

            from_top = false;

            radius = 6;

            border_width = 2;

            render_text = true;

            text_center = true;

            text_font = "Sans";

            text_height = 8;

            text_padding = 3;

            col = {
              active = "rgba(33ccff40)";
              "active.border" = "rgba(33ccffee)";
              "active.text" = "rgba(ffffffff)";

              focused = "rgba(60606040)";
              "focused.border" = "rgba(808080ee)";
              "focused.text" = "rgba(ffffffff)";

              inactive = "rgba(30303020)";
              "inactive.border" = "rgba(606060aa)";
              "inactive.text" = "rgba(ffffffff)";

              urgent = "rgba(ff223340)";
              "urgent.border" = "rgba(ff2233ee)";
              "urgent.text" = "rgba(ffffffff)";

              locked = "rgba(90903340)";
              "locked.border" = "rgba(909033ee)";
              "locked.text" = "rgba(ffffffff)";
            };

            blur = true;

            opacity = 1.0;
          };

          autotile = {
            enable = false;

            ephemeral_groups = true;

            trigger_width = 0;

            trigger_height = 0;

            workspaces = "all";
          };
        };
      };

      bind = [
        "${mainMod}, V, hy3:makegroup, v"
        "${mainMod} SHIFT, V, hy3:makegroup, h"
        "${mainMod}, T, hy3:makegroup, tab"
        "${mainMod} SHIFT, T, hy3:changegroup, toggletab"

        "${mainMod}, H, hy3:movefocus, l"
        "${mainMod}, J, hy3:movefocus, d"
        "${mainMod}, K, hy3:movefocus, u"
        "${mainMod}, L, hy3:movefocus, r"
        "${mainMod}, left, hy3:movefocus, l"
        "${mainMod}, right, hy3:movefocus, r"
        "${mainMod}, up, hy3:movefocus, u"
        "${mainMod}, down, hy3:movefocus, d"

        "${mainMod} SHIFT, H, hy3:movewindow, l"
        "${mainMod} SHIFT, J, hy3:movewindow, d"
        "${mainMod} SHIFT, K, hy3:movewindow, u"
        "${mainMod} SHIFT, L, hy3:movewindow, r"
        "${mainMod} SHIFT, left, hy3:movewindow, l"
        "${mainMod} SHIFT, right, hy3:movewindow, r"
        "${mainMod} SHIFT, up, hy3:movewindow, u"
        "${mainMod} SHIFT, down, hy3:movewindow, d"
      ];
    };
  };
}
