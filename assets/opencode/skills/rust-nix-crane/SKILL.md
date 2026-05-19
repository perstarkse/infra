---
name: rust-nix-crane
description: Build Rust projects with Crane in Nix flakes. Use when adding Rust crates to a workspace, configuring crane builds, vendoring dependencies, handling workspace builds, or cross-compiling Rust projects. Specific to the politikerstod-project style of crane + flake-utils.
---

# Rust Nix Crane Builds

Crane is the standard Nix builder for Rust projects. This project pattern uses `crane` + `flake-utils` to produce multi-crate workspace builds.

## Quick reference

```bash
nix build .#                    # Build default package
nix build .#politikerstod-cli   # Build specific crate
nix develop                     # Enter dev shell with Rust toolchain
cargo build                     # Build inside dev shell
cargo test                      # Run tests inside dev shell
```

## Flake structure (politikerstod pattern)

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    crane.url = "github:ipetkov/crane";
  };

  outputs = { self, nixpkgs, flake-utils, crane }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs { inherit system; };
      craneLib = (crane.mkLib pkgs).overrideToolchain
        (pkgs.rust-bin.stable.latest.default.override {
          extensions = ["rust-src" "rust-analyzer"];
        });
      src = craneLib.cleanCargoSource ./.;
      commonArgs = {
        inherit src;
        strictDeps = true;
        nativeBuildInputs = with pkgs; [ pkg-config ];
        buildInputs = with pkgs; [ openssl ];
      };
      cargoArtifacts = craneLib.buildDepsOnly commonArgs;
    in {
      packages.default = craneLib.buildPackage (commonArgs // {
        inherit cargoArtifacts;
        cargoExtraArgs = "-p politikerstod-server";
      });
      devShells.default = craneLib.devShell {
        packages = with pkgs; [ cargo-insta sea-orm-cli ];
      };
    });
}
```

## Adding a new crate to the workspace

1. Add the crate to the root `Cargo.toml` workspace members:
```toml
[workspace]
members = [
  "crates/politikerstod-core",
  "crates/politikerstod-db",
  "crates/new-crate",
]
```

2. Add the crate path to `craneLib.cleanCargoSource` if it filters:
```nix
src = craneLib.cleanCargoSource (craneLib.path ./.);
```

3. If the new crate adds dependencies, rebuild cargo artifacts:
```bash
nix build .#cargoArtifacts
```

4. Add a Nix package output for the new crate if it produces a binary:
```nix
packages.new-crate = craneLib.buildPackage (commonArgs // {
  inherit cargoArtifacts;
  cargoExtraArgs = "-p new-crate";
});
```

## Cargo.lock and vendoring

Crane uses `cargoVendorDir` for offline builds. When Cargo.lock changes:
- Run `craneLib.vendorCargoDeps` (or use the default vendor behavior)
- If using `craneLib.cleanCargoSource`, the lock file must be in the cleaned source
- Re-run `nix build` — crane automatically picks up lockfile changes

## Common build inputs

For typical Rust web/scraper projects:

```nix
nativeBuildInputs = with pkgs; [
  pkg-config
  protobuf         # if using tonic/grpc
  cmake            # if deps need cmake
];

buildInputs = with pkgs; [
  openssl
  onnxruntime      # if using ML
  tesseract        # if using OCR
  leptonica        # tesseract dependency
];
```

## Cross-compilation

```nix
packages.aarch64-linux = craneLib.buildPackage (commonArgs // {
  inherit cargoArtifacts;
  CARGO_BUILD_TARGET = "aarch64-unknown-linux-musl";
  HOST_CC = "${pkgs.stdenv.cc.nativePrefix}cc";
  TARGET_CC = "${pkgs.pkgsCross.aarch64-multiplatform.stdenv.cc}/bin/aarch64-unknown-linux-musl-cc";
});
```

## Common pitfalls

- **Forgot to update `cargoArtifacts`**: After adding new deps, rebuild deps first or use `craneLib.buildPackage` without `cargoArtifacts` temporarily.
- **`cleanCargoSource` strips needed files**: If the build needs files outside Cargo.toml (e.g. protobuf defs, config files), add them to the source.
- **Feature flags not passed through**: Use `cargoExtraArgs = "-p crate --features full"` for explicit features.
- **DevShell missing tools**: Add `cargo-insta`, `sea-orm-cli`, `cargo-watch` to devShell packages.
