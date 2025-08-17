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
    };
  };
}
