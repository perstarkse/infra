# io wiring for agent-microvm (microvm.nix replacement for the libvirt oumu).
#
# Disabled by default — the libvirt oumu (my.libvirtd) stays the live path.
# Flip `enable = true` and uncomment the vms.oumu block to cut over. Doing so
# also requires adding an `oumu-vm` flake input and exposing it as
# `ctx.inputs.oumuVm` in flake/parts/clan.nix.
_: {
  agent-microvm.host = {
    enable = false;
    # io keeps VM state on the SSD, not the default /var/lib/agent-microvms.
    # The oumu guest must set agent-microvm.guest.storageRoot to match.
    storageRoot = "/storage/microvms";

    # vms.oumu = {
    #   enable = true;
    #   autostart = false;
    #   flake = ctx.inputs.oumuVm;
    #   updateFlake = "git+https://github.com/perstarkse/oumu";
    #   deployKeyFile = config.my.secrets.getPath "openclawd-deploy-key" "private_key";
    # };
  };
}
