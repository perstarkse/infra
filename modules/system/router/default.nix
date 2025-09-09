{
  config.flake.nixosModules.router = {modules, ...}: {
    imports = with modules.nixosModules; [
      router-core
      router-network
      router-firewall
      router-dhcp
      router-dns
      router-nginx
      router-monitoring
      router-wireguard
    ];
  };
}
