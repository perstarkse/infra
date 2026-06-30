{
  config.flake.homeModules.nix-scaffold = _: {
    programs.fish.functions.nix-init-project = {
      description = "Scaffold a new project from ~/repos/nix-scaffold (--default|--rust).";
      wraps = "nix";
      body = ''
        # Where the nix-scaffold flake lives. Override with NIX_SCAFFOLD_DIR.
        set -l scaffold_dir $NIX_SCAFFOLD_DIR
        if test -z "$scaffold_dir"
          set scaffold_dir $HOME/repos/nix-scaffold
        end

        # Parse args: --default|--rust <project-name>?
        set -l template default
        set -l positional

        while set -q argv[1]
          switch $argv[1]
            case --default --rust
              set template (string replace -- '--' ''' $argv[1])
            case --help -h
              echo "Usage: nix-init-project [--default|--rust] <project-name>"
              echo ""
              echo "Templates:"
              echo "  --default  Nix-first project with flake-parts, direnv, treefmt, git-hooks"
              echo "  --rust     Rust project with crane, fenix, mold, and CI checks"
              echo ""
              echo "Environment:"
              echo "  NIX_SCAFFOLD_DIR  Path to the nix-scaffold flake (default: ~/repos/nix-scaffold)"
              return 0
            case --
              set positional $positional $argv[2..-1]
              set -e argv
            case '-*'
              echo "nix-init-project: unknown flag '$argv[1]'" >&2
              echo "Run 'nix-init-project --help' for usage." >&2
              return 2
            case '*'
              set positional $positional $argv[1]
          end
          set -e argv[1]
        end

        if test (count $positional) -ne 1
          echo "nix-init-project: expected exactly one project name" >&2
          echo "Run 'nix-init-project --help' for usage." >&2
          return 2
        end

        set -l name $positional[1]

        if not test -d $scaffold_dir
          echo "nix-init-project: scaffold flake not found at $scaffold_dir" >&2
          echo "Set NIX_SCAFFOLD_DIR to override." >&2
          return 1
        end

        if test -e $name
          echo "nix-init-project: '$name' already exists in $(pwd)" >&2
          return 1
        end

        echo "Scaffolding $template project '$name' from $scaffold_dir"

        # `nix flake init -t <path>#<template> <name>` creates the named
        # directory at the current working directory and copies the template
        # files into it. --refresh picks up local edits to the source flake.
        if not command nix --extra-experimental-features 'nix-command flakes' \
            flake init -t "git+file://$scaffold_dir?ref=HEAD#$template" \
            --refresh $name
          echo "nix-init-project: nix flake init failed" >&2
          return 1
        end

        echo ""
        echo "Done. Next steps:"
        echo "  cd $name"
        echo "  git init && git add -A && git commit -m 'chore: initial scaffold'"
        echo "  direnv allow"
        echo "  nix fmt && nix flake check"
      '';
    };
  };
}
