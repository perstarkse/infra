{
  config.flake.nixosModules.router = {ctx, ...}: {
    imports = with ctx.flake.nixosModules; [
      router-core
      router-network
      router-firewall
      router-dhcp
      router-dns
      router-nginx
      router-monitoring
      router-wireguard
      router-security
    ];
  };
}
