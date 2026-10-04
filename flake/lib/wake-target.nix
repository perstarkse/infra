# Wake-on-LAN target for charon: single source for both consumers.
#
# Consumed by machines/io (services.wakeproxy) and modules/system/wake-charon.nix
# (the magic-packet script on makemake). Reading it from one file is the point:
# a duplicated MAC in two places is a silent drift bug, and cross-machine eval
# (makemake reaching into nixosConfigurations.io.config) is forbidden — see
# flake.lib.backupJobs for the same pattern.
{
  # charon enp4s0 (systemd.network.links."40-enp4s0" sets WakeOnLan = "magic").
  mac = "f0:2f:74:de:91:0a";
  broadcastIp = "10.0.0.255";
  broadcastPort = 9;

  # charon LAN address; also the readiness target (TCP connect, never the
  # wakeproxy HTTP frontend — that path is CSRF-guarded and password-login'd).
  host = "10.0.0.15";
  sshPort = 22;

  wakeTimeout = 180;
  pollInterval = 2;
}
