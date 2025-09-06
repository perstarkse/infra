{
  config.flake.homeModules.fish = {
    config,
    lib,
    osConfig,
    pkgs,
    ...
  }: {
    programs.fish = {
      enable = true;
      interactiveShellInit = ''
        set fish_greeting
      '';
      shellAliases = {
        "ls" = "${pkgs.eza}/bin/eza";
        "ll" = "${pkgs.eza}/bin/eza -l --icons=auto --git";
        "la" = "${pkgs.eza}/bin/eza -la --icons=auto --git";
        "ls-latest" = "${pkgs.eza}/bin/eza --icons=auto -l --sort=modified --reverse --git";
        "ls-perms" = "${pkgs.eza}/bin/eza --icons=auto -l --octal-permissions --git";
        "ls-all" = "${pkgs.eza}/bin/eza --icons=auto -la --git";
        "ls-size" = "${pkgs.eza}/bin/eza --icons=auto -l --sort=size --reverse --git";
        "ls-tree" = "${pkgs.eza}/bin/eza --tree --level=2 --icons=auto";
        "ls-dirs" = "${pkgs.eza}/bin/eza -D --icons=auto";
        "ls-files" = "${pkgs.eza}/bin/eza -f --icons=auto";
        "wlc" = "${pkgs.wl-clipboard}/bin/wl-copy";
      };
      functions = {
        ns = ''
          if test (count $argv) -eq 0
            echo "Usage: ns pkg1 [pkg2 ...]"
            return 1
          end
          set refs
          for pkg in $argv
            set -a refs nixpkgs#$pkg
          end
          nix shell $refs
        '';
        ctllm = ''
          # Usage: ctllm LOCATION [FILETYPE]
          if test (count $argv) -lt 1
            echo "Usage: ctllm LOCATION [FILETYPE]"
            echo "Examples:"
            echo "  ctllm .          # all files (auto-detect language)"
            echo "  ctllm ./src nix  # only .nix files in ./src"
            return 1
          end

          set location $argv[1]
          if test (count $argv) -ge 2
            set filetype $argv[2]
          else
            set filetype "*"
          end

          if test "$filetype" = "*"
            set find_pattern '*'
            set auto_detect 1
          else
            set find_pattern "*.$filetype"
            set auto_detect 0
            set fence_lang $filetype
          end

          function detect_lang
            set fname (basename $argv[1])
            set ext (string split -r -m1 . $fname)[-1]
            switch $ext
              case nix;   echo nix
              case py;    echo python
              case js;    echo javascript
              case ts;    echo typescript
              case json;  echo json
              case yaml yml; echo yaml
              case sh bash zsh fish; echo shell
              case md;    echo markdown
              case html;  echo html
              case css;   echo css
              case go;    echo go
              case rs;    echo rust
              case c;     echo c
              case h;     echo c
              case cpp cxx cc; echo cpp
              case java;  echo java
              case '*';   echo text
            end
          end

          find $location -type f -name "$find_pattern" -print0 | while read -z file
            # Skip unwanted dirs
            if string match -q "*/.git/*" $file; or string match -q "*/node_modules/*" $file; or string match -q "*/.direnv/*" $file
              continue
            end

            # Skip binary / big files
            set ext (string lower (string split -r -m1 . $file)[-1])
            switch $ext
              case png jpg jpeg gif webp pdf
                continue
            end

            if test (stat -c%s $file) -gt 1048576
              continue
            end

            if test $auto_detect -eq 1
              set fence_lang (detect_lang $file)
            end

            printf '\n# %s\n\n```%s\n' $file $fence_lang
            cat -- $file
            printf '\n```\n'
          end
        '';
        gui = ''
          if test (count $argv) -gt 0
            swaymsg exec -- $argv
          else
            echo "Usage: gui <command>"
            return 1
          end
          complete -c gui -w command
        '';
      };
    };
  };
}
