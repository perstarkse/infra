{
  config.flake.nixosModules.restic = {config, ...}: {
    config = {
      services.restic.backups = {
        daily = {
          initialize = true;

          environmentFile = config.my.secrets."restic-repo-file/vault-name";
          repositoryFile = config.my.secrets."restic-env-file/env";
          passwordFile = config.my.secrets."restic-password/password";

          paths = [
            "${config.users.users.p.home}/documents"
          ];

          pruneOpts = [
            "--keep-daily 7"
            "--keep-weekly 5"
            "--keep-monthly 12"
          ];
        };
      };
    };
  };
}
