{pkgs, ...}: {
  "accounted" = {
    share = true;
    runtimeInputs = [pkgs.coreutils];
    files = {
      env = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      env = {
        description = "Optional extra Accounted env lines (RESEND_API_KEY=..., ANTHROPIC_API_KEY=..., etc.)";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      set -euo pipefail

      _prompts_dir="''${prompts:-}"
      if [ -z "$_prompts_dir" ] || [ ! -d "$_prompts_dir" ]; then
        _prompts_dir=""
      fi

      {
        echo "CRON_SECRET=$(head -c 32 /dev/urandom | base64 -w0)"
        # Runtime escape hatch from the capability paywall.
        # NEXT_PUBLIC_SELF_HOSTED alone is not enough: the GHCR image inlines it
        # during the Next build as the __NEXT_PUBLIC_SELF_HOSTED__ sentinel and
        # the comparison constant-folds to false, so the self-hosted all-on
        # branch in lib/entitlements/has-capability.ts never executes. Only the
        # DISABLE_PAYWALL branch reads process.env at runtime.
        echo "DISABLE_PAYWALL=true"
        if [ -n "$_prompts_dir" ] && [ -s "$_prompts_dir/env" ]; then
          # Drop any CRON_SECRET the operator pasted; we always own that value.
          grep -vE '^[[:space:]]*CRON_SECRET=' "$_prompts_dir/env" || true
        fi
      } > "$out/env"
      chmod 0400 "$out/env"
    '';
    meta.tags = ["accounted" "makemake"];
  };
}
