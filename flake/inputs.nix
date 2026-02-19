{
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

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
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  stylix = {
    url = "github:danth/stylix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  hyprland.url = "github:hyprwm/Hyprland/v0.50.0?submodules=1";
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

  niri = {
    url = "github:perstarkse/niri";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  private-infra = {
    url = "git+ssh://git@github.com/perstarkse/private-infra.git";
  };

  minne = {
    url = "github:perstarkse/minne";
  };

  saas-minne = {
    url = "git+ssh://git@github.com/perstarkse/saas-minne.git?ref=main&submodules=1";
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

  nix-minecraft.url = "github:Infinidoge/nix-minecraft";

  treefmt-nix = {
    url = "github:numtide/treefmt-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  playwright-mcp-latest = {
    url = "github:theodorton/nixpkgs?ref=playwright-1.55.0";
  };

  nous = {
    url = "git+ssh://git@github.com/perstarkse/nous.git";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  politikerstod = {
    url = "git+ssh://git@github.com/perstarkse/politikerstod.git";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  wol-web-proxy = {
    url = "git+ssh://git@github.com/perstarkse/wol-web-proxy.git";
  };

  nix-topology = {
    url = "github:oddlama/nix-topology";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
