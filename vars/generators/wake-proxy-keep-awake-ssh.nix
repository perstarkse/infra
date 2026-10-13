{
  config,
  pkgs,
  ...
}: {
  "wake-proxy-keep-awake-ssh" = {
    share = true;
    runtimeInputs = [pkgs.openssh];
    files = {
      private_key =
        {
          mode = "0400";
          neededFor = "services";
        }
        # `or false`, not .enable: machines that deploy this generator without
        # importing the wake-proxy module (makemake's wake-charon lease does,
        # and does not run wakeproxy) must not fail eval on the missing option.
        // pkgs.lib.optionalAttrs (config.services.wakeproxy.enable or false) {
          owner = "wake-proxy";
        };
      public_key = {
        mode = "0444";
      };
    };
    script = ''
      ssh-keygen -t ed25519 -C "wakeproxy-keep-awake" -f "$out/private_key" -N ""
      mv "$out/private_key.pub" "$out/public_key"
    '';
    meta = {
      tags = ["wake-proxy" "keep-awake" "ssh"];
    };
  };
}
