# Thin wrapper re-exporting the external agent-microvm flake's host module,
# so machines import it as a normal `ctx.flake.nixosModules.agent-microvm`.
# The guest module is consumed directly by each guest flake (e.g. oumu-inner)
# from the same external input — infra never needs the guest side.
{inputs, ...}: {
  config.flake.nixosModules.agent-microvm = inputs.agent-microvm.nixosModules.host;
}
