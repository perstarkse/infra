# io wiring for agent-microvm (microvm.nix replacement for the libvirt VM).
#
# Disabled by default — the libvirt VM (my.libvirtd) stays the live path.
# Flip `enable = true` and add a guest flake input to cut over.
_: {
  agent-microvm.host = {
    enable = false;
    # io keeps VM state on the SSD, not the default /var/lib/agent-microvms.
    # A guest flake must set agent-microvm.guest.storageRoot to match.
    storageRoot = "/storage/microvms";
  };
}