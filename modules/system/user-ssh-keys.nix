{
  config.flake.nixosModules.user-ssh-keys = {config, ...}: {
    systemd.services.setup-user-ssh-key = {
      description = "Setup user SSH private key";
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
      };
      after = [ "sops-install-secrets.target" ];
      requires = [ "sops-install-secrets.target" ];
      script = ''
        mkdir -p /home/${config.my.mainUser.name}/.ssh
        cp ${config.my.secrets."user-ssh-key/id_ed25519"} /home/${config.my.mainUser.name}/.ssh/id_ed25519
        cp ${config.my.secrets."user-ssh-key-pub/id_ed25519.pub"} /home/${config.my.mainUser.name}/.ssh/id_ed25519.pub
        chown ${config.my.mainUser.name}:users /home/${config.my.mainUser.name}/.ssh/id_ed25519
        chown ${config.my.mainUser.name}:users /home/${config.my.mainUser.name}/.ssh/id_ed25519.pub
        chmod 600 /home/${config.my.mainUser.name}/.ssh/id_ed25519
        chmod 600 /home/${config.my.mainUser.name}/.ssh/id_ed25519.pub
      '';
    };
  };
}
