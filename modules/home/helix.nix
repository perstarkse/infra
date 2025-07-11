{
  config.flake.homeModules.helix = {
    lib,
    pkgs,
    config,
    inputs,
    ...
  }: let
    # --- The actual Home Manager module starts here ---
    cfg = config.my.programs.helix;

    # Central registry mapping a language name to its required config.
    langDefs = {
      nix = {
        packages = [pkgs.nil pkgs.alejandra];
        language = [
          {
            name = "nix";
            language-servers = ["nil"];
            formatter.command = "alejandra";
          }
        ];
      };
      rust = {
        packages = [pkgs.rust-analyzer];
        language = [
          {
            name = "rust";
            auto-format = true;
            language-servers = ["rust-analyzer"];
          }
        ];
      };
      python = {
        packages = [pkgs.python3-lsp-server];
        language = [
          {
            name = "python";
            language-servers = ["pylsp"];
          }
        ];
      };
      web = {
        packages = with pkgs; [nodePackages.typescript-language-server nodePackages.vscode-langservers-extracted tailwindcss-language-server];
        language = [
          {
            name = "typescript";
            language-servers = ["typescript-language-server"];
          }
          {
            name = "javascript";
            language-servers = ["typescript-language-server"];
          }
          {
            name = "svelte";
            language-servers = ["svelteserver" "tailwindcss-ls" "typescript-language-server"];
          }
          {
            name = "html";
            language-servers = ["vscode-html-language-server" "tailwindcss-ls"];
          }
          {
            name = "css";
            language-servers = ["vscode-css-language-server" "tailwindcss-ls"];
          }
        ];
        language-server.tailwindcss-ls.command = "${pkgs.tailwindcss-language-server}/bin/tailwindcss-language-server";
      };
      markdown = {
        packages = [pkgs.marksman pkgs.mdformat];
        language = [
          {
            name = "markdown";
            language-servers = ["marksman"];
            formatter.command = "${pkgs.mdformat}/bin/mdformat";
          }
        ];
        language-server.marksman.command = "${pkgs.marksman}/bin/marksman";
      };
      jinja = {
        packages = [pkgs.unstable.jinja-lsp];
        language = [
          {
            name = "jinja";
            language-servers = ["jinjalsp"];
          }
        ];
        language-server.jinjalsp.command = "${pkgs.unstable.jinja-lsp}/bin/jinja-lsp";
      };
    };

    # Filter and aggregate the definitions based on user's choice
    enabledDefs = lib.attrsets.filterAttrs (name: _: lib.lists.elem name cfg.languages) langDefs;
    allPackages = lib.flatten (lib.mapAttrsToList (_: def: def.packages or []) enabledDefs);
    allLanguages = lib.flatten (lib.mapAttrsToList (_: def: def.language or []) enabledDefs);
    allLanguageServers = lib.foldl' lib.recursiveUpdate {} (lib.mapAttrsToList (_: def: def.language-server or {}) enabledDefs);
  in {
    options.my.programs.helix = {
      enable = lib.mkEnableOption "modular helix configuration";
      languages = lib.mkOption {
        type = with lib.types; listOf (enum (builtins.attrNames langDefs));
        default = [];
        example = ["nix" "web" "python"];
        description = "List of languages/language groups to enable for Helix.";
      };
    };

    config = lib.mkIf cfg.enable {
      home.packages = allPackages;

      programs.helix = {
        enable = true;
        # package = inputs.helix-master.packages."x86_64-linux".default;
        defaultEditor = true;
        settings = {
          keys.normal = {space.c = ":clipboard-yank";};
          editor.line-number = "relative";
        };
        languages = {
          language = allLanguages;
          language-server = allLanguageServers;
        };
      };
    };
  };
}
