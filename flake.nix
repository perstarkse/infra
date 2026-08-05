{
  description = "A dendritic clan configuration with flake-parts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    "nixpkgs-unstable".url = "github:NixOS/nixpkgs/nixos-unstable";

    # Kernel branch pinned for charon's Battlemage GPU-init support
    # (see machines/charon/configuration.nix). Locked here so eval does not
    # depend on an out-of-lockfile getFlake fetch.
    "nixpkgs-612" = {
      url = "github:NixOS/nixpkgs/afbbf774e2087c3d734266c22f96fca2e78d3620";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
    };

    clan-core = {
      url = "git+https://git.clan.lol/clan/clan-core";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    import-tree.url = "github:vic/import-tree";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:danth/stylix/718c14e8ecba215a65ff955c187fadb9732ddd01";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    private-infra = {
      url = "git+ssh://git@github.com/perstarkse/private-infra.git";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs."nixpkgs-stable".follows = "nixpkgs";
      inputs."simple-nixos-mailserver".inputs.nixpkgs.follows = "nixpkgs";
    };

    saas-minne = {
      url = "git+ssh://git@github.com/perstarkse/saas-minne.git?ref=main&submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    NixVirt = {
      url = "https://flakehub.com/f/AshleyYakeley/NixVirt/*.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    vars-helper = {
      url = "github:perstarkse/clan-vars-helper";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };

    niri-focus-flash = {
      url = "github:perstarkse/niri-focus-flash";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nous = {
      url = "git+ssh://git@github.com/perstarkse/nous.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    politikerstod = {
      url = "git+ssh://git@github.com/perstarkse/politikerstod.git";
    };

    wol-web-proxy = {
      url = "git+ssh://git@github.com/perstarkse/wol-web-proxy.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    indicator-alert-daemon = {
      url = "github:perstarkse/indicator-alert-daemon";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    agent-tooling = {
      url = "git+ssh://git@github.com/perstarkse/agent-tooling.git";
    };

    voxtype = {
      url = "github:peteonrails/voxtype";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    agent-microvm = {
      url = "git+file:///home/p/repos/agent-microvm";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    digikey-mcp = {
      url = "git+file:///home/p/repos/digikey-mcp";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        ./flake/parts/core.nix
        ./flake/parts/clan.nix
        ./flake/parts/per-system.nix
      ];
    };
}
