_: {
  config.flake.nixosModules.webdav-htpasswd-secret = {
    config,
    pkgs,
    ...
  }: {
    my.secrets.declarations = [
      (config.my.secrets.mkSharedSecret {
        name = "webdav-htpasswd";
        runtimeInputs = [pkgs.apacheHttpd];
        files = {
          htpasswd = {mode = "0400";};
          password = {mode = "0400";};
        };
        script = ''
          username="webdav"
          password=$(head -c 24 /dev/urandom | base64 -w0 | tr -d '/+=')
          htpasswd -nbB "$username" "$password" > "$out/htpasswd"
          echo "$password" > "$out/password"
        '';
      })
    ];
  };
}
