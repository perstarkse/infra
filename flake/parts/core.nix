{inputs, ...}: {
  imports = [
    inputs.clan-core.flakeModules.default
    inputs.home-manager.flakeModules.home-manager
    inputs.treefmt-nix.flakeModule
    (inputs.import-tree ../../modules)
  ];

  systems = ["x86_64-linux"];

  flake.lib.endpoints = import ../lib/endpoints.nix {inherit (inputs.nixpkgs) lib;};
  flake.lib.versions = import ../lib/versions.nix;
  # Canonical backup-job inventory for the sedna deadman (pure constant, no
  # cross-machine eval — arch #6).
  flake.lib.backupJobs = import ../lib/backup-jobs.nix;
  # Canonical public-domain registry (pure constant, no cross-machine eval
  # — arch #6). MUST equal io's derived my.publicDomains; enforced by the
  # sedna subset assertions + io's registry-equality lint.
  flake.lib.publicDomains = {
    "invoices.stark.pub" = "stark.pub";
    "mail.stark.pub" = "stark.pub";
    "minne-demo.stark.pub" = "stark.pub";
    "minne.stark.pub" = "stark.pub";
    "nous.fyi" = "nous.fyi";
    "orebro.politikerstod.stark.pub" = "stark.pub";
    "politikerstod.stark.pub" = "stark.pub";
    "request.stark.pub" = "stark.pub";
    "wake.stark.pub" = "stark.pub";
    "wg.stark.pub" = "stark.pub";
  };
}
