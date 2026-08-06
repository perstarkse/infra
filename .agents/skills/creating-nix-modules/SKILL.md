---
name: creating-nix-modules
description: Creates NixOS and Home Manager modules following the dendritic flake-parts pattern. Use when asked to create a new module, add a service, or write a nix module file.
---

# Creating Nix Modules

This repo uses the **dendritic pattern** where every file is a flake-parts module. Modules are auto-imported via `import-tree`.

## Module Locations

- **NixOS modules**: `modules/system/<name>.nix`
- **Home Manager modules**: `modules/home/<name>.nix`
- **Complex modules**: `modules/system/<name>/` or `modules/home/<name>/` directories

## Dendritic Module Structure

### NixOS Module Template

```nix
{
  config.flake.nixosModules.<moduleName> = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.<moduleName>;
  in {
    options.my.<moduleName> = {
      enable = lib.mkEnableOption "Enable <service description>";

      # Add options here with lib.mkOption
    };

    config = lib.mkIf cfg.enable {
      # Configuration goes here
    };
  };
}
```

### Home Manager Module Template

```nix
{
  config.flake.homeModules.<moduleName> = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.<moduleName>;
  in {
    options.my.<moduleName> = {
      enable = lib.mkEnableOption "Enable <feature description>";
    };

    config = lib.mkIf cfg.enable {
      # Home Manager configuration
    };
  };
}
```

### Simple Home Module (no options)

For modules that are always-on with no configuration:

```nix
{
  config.flake.homeModules.<moduleName> = {
    config,
    lib,
    pkgs,
    ...
  }: {
    # Direct configuration, no options
    programs.example.enable = true;
  };
}
```

## Key Conventions

1. **Module registration**: `config.flake.nixosModules.<name>` or `config.flake.homeModules.<name>`
3. **Options namespace**: Always under `my.<moduleName>`
4. **Config alias**: Use `let cfg = config.my.<moduleName>; in` for readability
5. **Conditional config**: Wrap with `lib.mkIf cfg.enable { ... }`
6. **File naming**: kebab-case (e.g., `my-service.nix`)

## Accessing Flake Inputs

**Only** add the outer `{inputs, ...}:` wrapper when you need direct access to flake inputs (e.g., packages from external flakes). This is preferred over adding inputs to `specialArgs` in flake.nix.

```nix
{inputs, ...}: {
  config.flake.nixosModules.example = {pkgs, ...}: {
    config = {
      environment.systemPackages = [
        inputs.someFlake.packages.${pkgs.system}.default
      ];
    };
  };
}
```

If you don't need inputs, omit the wrapper entirely—just use `{ config.flake... }`.

## Secrets Integration

Use the vars-helper for secrets:

```nix
# Reference a secret path
EnvironmentFile = [(config.my.secrets.getPath "secret-name" "file")];
```

## After Creating a Module

**CRITICAL**: Always run `git add` on new files before building:

```bash
git add modules/system/<new-module>.nix
# or
git add modules/home/<new-module>.nix
```

Nix flakes only see tracked files. Builds will fail if you forget this step.

## Validation

After creating a module, validate with:

```bash
nix flake check path:.
# or build a specific machine
nix build path:.#nixosConfigurations.<machine>.config.system.build.toplevel
```

If your change touches router behavior or `machines/io/configuration.nix`, also run:

```bash
nix build path:.#router-checks
nix build path:.#final-checks
```
