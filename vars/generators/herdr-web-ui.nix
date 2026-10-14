# herdr-web-ui access token (HERDR_WEB_TOKEN).
#
# The plugin's gate is off while the token is unset: anyone who can reach the
# bridge can type into panes. This generator is the single source; makemake
# (herdr as `agent`) exposes it via my.secrets.exposeUserSecrets straight into
# the plugin's config dir as `.env` (KEY=value lines; .env wins over `env`,
# supported since plugin 0.3.25 — the pinned checkout includes it).
#
# Regenerate = rotate: re-run the generator (`clan vars generate`), redeploy,
# then restart makemake's herdr user service (the bridge reads the token once
# at start). Wakeproxy's password gate sits in front of the proxied vhost, so
# this token is the second layer, not the only one.
#
# Script-only generator (no prompt): regeneration happens when the generator
# definition changes or on a forced re-run, never silently mid-flight.
{pkgs, ...}: {
  "herdr-web-ui" = {
    share = true;
    runtimeInputs = [pkgs.openssl];
    files = {
      plugin_env = {
        mode = "0400";
        neededFor = "users";
      };
    };
    script = ''
      printf 'HERDR_WEB_TOKEN=%s\n' "$(openssl rand -hex 32)" > "$out/plugin_env"
    '';
    meta = {
      tags = ["herdr-web-ui"];
    };
  };
}
