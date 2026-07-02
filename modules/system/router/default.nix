{config, ...}: let
  inherit (config) flake;
in {
  config.flake.nixosModules.router = {
    imports = with flake.nixosModules; [
      router-core
      router-network
      router-firewall
      router-dhcp
      router-dns
      router-nginx
      router-monitoring
      router-casting
      router-wireguard
      router-security
    ];
  };
}
