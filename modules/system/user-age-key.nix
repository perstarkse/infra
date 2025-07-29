{
  config.flake.nixosModules.user-age-key = {config, ...}: {
    systemd.services.setup-user-age-key = {
      description = "Setup user age private key";
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        mkdir -p /home/${config.my.mainUser.name}/.config/sops/age/
        cp ${config.my.secrets."user-age-key/keys.txt"} /home/${config.my.mainUser.name}/.config/sops/age/keys.txt
        chown ${config.my.mainUser.name}:users /home/${config.my.mainUser.name}/.config/sops/age/keys.txt
        chmod 600 /home/${config.my.mainUser.name}/.config/sops/age/keys.txt
      '';
    };
  };
}
