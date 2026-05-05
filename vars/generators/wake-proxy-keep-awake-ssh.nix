{pkgs, ...}: {
  "wake-proxy-keep-awake-ssh" = {
    share = true;
    runtimeInputs = [pkgs.openssh];
    files = {
      private_key = {
        mode = "0400";
        owner = "wake-proxy";
        neededFor = "services";
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
