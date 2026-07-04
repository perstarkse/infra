{
  description = "A dendritic clan configuration with flake-parts";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    "nixpkgs-unstable".url = "github:NixOS/nixpkgs/nixos-unstable";

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

    hyprland = {
      url = "github:hyprwm/Hyprland/v0.50.0?submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };

    hyprnstack = {
      url = "github:perstarkse/hyprNStack";
      inputs.hyprland.follows = "hyprland";
    };

    hy3 = {
      url = "github:outfoxxed/hy3?ref=hl0.50.0";
      inputs.hyprland.follows = "hyprland";
    };

    private-infra = {
      url = "git+ssh://git@github.com/perstarkse/private-infra.git";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs."nixpkgs-stable".follows = "nixpkgs";
      inputs."simple-nixos-mailserver".inputs.nixpkgs.follows = "nixpkgs";
    };

    minne = {
      url = "github:perstarkse/minne";
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

    sway-focus-flash = {
      url = "github:perstarkse/sway-focus-flash";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-minecraft = {
      url = "github:Infinidoge/nix-minecraft";
      inputs.nixpkgs.follows = "nixpkgs";
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
      url = "github:perstarkse/symbol-alert-notifier";
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
