# Oumu VM - Inner NixOS Configuration

This is the self-managing NixOS configuration for the Oumu AI assistant VM.

## Architecture

- **Host**: `io` (router) runs the VM via libvirt
- **VM**: This configuration runs inside the VM
- **Isolation**: VM has internet access but cannot reach LAN (10.0.0.0/8)
- **Storage**: 120GB root disk on io's /storage SSD
- **RAM**: 4GB allocated

## Initial Setup

1. First boot will have minimal NixOS
2. SSH into the VM (via io: `virsh console oumu` or SSH if configured)
3. Clone this repo to `/etc/nixos/`:
   ```bash
   sudo git clone git@github.com:perstarkse/oumu-vm.git /etc/nixos
   cd /etc/nixos
   sudo nixos-rebuild switch --flake .#oumu
   ```

## Self-Management

This VM can edit its own configuration:

```bash
# Edit configuration
sudo nano /etc/nixos/configuration.nix

# Rebuild
sudo nixos-rebuild switch --flake /etc/nixos#oumu

# Commit and push changes
cd /etc/nixos
git add .
git commit -m "Update: <description>"
git push
```

## Secrets

API keys are stored in `/var/lib/oumu/secrets/` (systemd credentials or plain files).
**Do not commit secrets to git!**

## Network

- VM IP: Assigned via DHCP (192.168.200.x range)
- Gateway: 192.168.200.1 (io's libvirt bridge)
- DNS: Via io's unbound
- **No access to**: 10.0.0.0/8 (your LAN)

## Maintenance

- **From io**: `virsh list`, `virsh console oumu`, `virsh shutdown oumu`
- **Disk location**: `/storage/libvirt/oumu/images/oumu-root.qcow2`
- **Logs**: `journalctl -u oumu` (inside VM)
