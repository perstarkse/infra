{
  config.flake.homeModules.fish = {
    config,
    lib,
    osConfig,
    pkgs,
    ...
  }: {
    programs.fish = {
      enable = true;
      interactiveShellInit = ''
        set fish_greeting
      '';
      shellAliases = {
        "ls" = "${pkgs.eza}/bin/eza";
        "ll" = "${pkgs.eza}/bin/eza -l --icons=auto --git";
        "la" = "${pkgs.eza}/bin/eza -la --icons=auto --git";
        "ls-latest" = "${pkgs.eza}/bin/eza --icons=auto -l --sort=modified --reverse --git";
        "ls-perms" = "${pkgs.eza}/bin/eza --icons=auto -l --octal-permissions --git";
        "ls-all" = "${pkgs.eza}/bin/eza --icons=auto -la --git";
        "ls-size" = "${pkgs.eza}/bin/eza --icons=auto -l --sort=size --reverse --git";
        "ls-tree" = "${pkgs.eza}/bin/eza --tree --level=2 --icons=auto";
        "ls-dirs" = "${pkgs.eza}/bin/eza -D --icons=auto";
        "ls-files" = "${pkgs.eza}/bin/eza -f --icons=auto";
        "wlc" = "${pkgs.wl-clipboard}/bin/wl-copy";
      };
      functions = {
        ns = ''
          if test (count $argv) -eq 0
            echo "Usage: ns pkg1 [pkg2 ...]"
            return 1
          end
          set refs
          for pkg in $argv
            set -a refs nixpkgs#$pkg
          end
          nix shell $refs
        '';
      };
    };
  };
}
