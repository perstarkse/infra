{
  config.flake.homeModules.node = {
    pkgs,
    config,
    ...
  }: {
    config = {
      home.packages = with pkgs; [nodejs];
      home.sessionVariables = {
        NPM_CONFIG_PREFIX = "${config.home.homeDirectory}/.npm-global";
      };
      home.sessionPath = ["${config.home.homeDirectory}/.npm-global/bin"];

      home.file.".npmrc".text = ''
        prefix=${config.home.homeDirectory}/.npm-global
      '';

      home.file.".config/fish/conf.d/10-npm-global.fish".text = ''
        # set once if missing, keep as universal so login + interactive shells get it
        set -q NPM_CONFIG_PREFIX; or set -Ux NPM_CONFIG_PREFIX "$HOME/.npm-global"

        # prepend to PATH idempotently
        if not contains "$HOME/.npm-global/bin" $fish_user_paths
          fish_add_path --prepend "$HOME/.npm-global/bin"
        end
      '';
    };
  };
}
