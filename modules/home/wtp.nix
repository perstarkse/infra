{
  config.flake.homeModules.wtp = {
    pkgs,
    lib,
    config,
    ...
  }: let
    cfg = config.programs.wtp;

    version = "unstable-2025-01-27";
    rev = "7678ba7378236bb5457c1526cef9b2011280af2b";
    srcHash = "sha256-bCJBGKsmGjZr4f8xlc/6t5n3ffDrjP1FaeZ4JBEYyAg=";
    vendorHash = "sha256-11cYheopXBFmxGOddUafvkEz6TlY6pgtmCTPGMbhhhE=";

    defaultPackage = pkgs.buildGoModule {
      pname = "wtp";
      inherit version;
      src = pkgs.fetchFromGitHub {
        owner = "satococoa";
        repo = "wtp";
        inherit rev;
        hash = srcHash;
      };
      subPackages = ["cmd/wtp"];
      inherit vendorHash;
      doCheck = false;
      ldflags = [
        "-s"
        "-w"
        "-X"
        "main.version=${version}"
        "-X"
        "main.commit=${rev}"
        "-X"
        "main.date=unknown"
      ];
    };

    fishIntegrationEnabled =
      cfg.enableFishIntegration && (config.programs.fish.enable or false);
  in {
    options.programs.wtp = {
      enable = lib.mkEnableOption "Install the wtp CLI and optional shell helpers.";

      package = lib.mkOption {
        type = lib.types.package;
        default = defaultPackage;
        defaultText = lib.literalExpression "pkgs.buildGoModule { ... }";
        description = "Package to install for the wtp CLI.";
      };

      enableFishIntegration = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install completions and helpers for fish when fish is enabled.";
      };

      enableFishCdWrapper = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Wrap the fish wtp function to support 'wtp cd' directory switching.";
      };
    };

    config = lib.mkIf cfg.enable {
      home.packages = [cfg.package];

      programs.fish = lib.mkIf fishIntegrationEnabled {
        functions = lib.mkMerge [
          {
            "__fish_wtp_dynamic_complete" = ''
              function __fish_wtp_dynamic_complete --description 'wtp dynamic completion helper'
                set -l tokens (commandline -opc)
                set -l args
                set -l token_count (count $tokens)
                if test $token_count -gt 1
                  set args $tokens[2..-1]
                end

                set -l current (commandline -ct)

                if test -n "$current"
                  if string match -q -- '-*' $current
                    set args $args $current
                  end
                end

                set args $args --generate-shell-completion

                if not command -sq wtp
                  return
                end

                set -l raw (env WTP_SHELL_COMPLETION=1 wtp $args)
                for line in $raw
                  if test -z "$line"
                    continue
                  end

                  set -l parts (string split -m 1 ":" -- $line)
                  if test (count $parts) -gt 1
                    set -l remainder $parts[2]
                    if string match -q "* *" $remainder
                      echo $parts[1]
                      continue
                    end
                  end

                  echo $line
                end
              end
            '';
          }
          (lib.mkIf cfg.enableFishCdWrapper {
            wtp = ''
              function wtp
                for arg in $argv
                  if test "$arg" = "--generate-shell-completion"
                    command wtp $argv
                    return $status
                  end
                end

                if test "$argv[1]" = "cd"
                  if test -z "$argv[2]"
                    echo "Usage: wtp cd <worktree>" >&2
                    return 1
                  end
                  set -l target_dir (command wtp cd $argv[2] 2>/dev/null)
                  if test $status -eq 0 -a -n "$target_dir"
                    cd $target_dir
                  else
                    command wtp cd $argv[2]
                  end
                else
                  command wtp $argv
                end
              end
            '';
          })
        ];

        interactiveShellInit = lib.mkAfter ''
          complete -c wtp -f -a '(__fish_wtp_dynamic_complete)'
        '';
      };
    };
  };
}
