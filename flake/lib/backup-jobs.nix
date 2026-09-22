# Canonical backup-job inventory for the sedna deadman (single source, no
# cross-machine eval: sedna reads this via ctx.flake.lib, never via
# nixosConfigurations.<other>.config — arch #6). Senders ping per local
# config.my.backups; keep this list in sync when adding/removing jobs.
# Check:job list must equal (makemake.my.backups ++ io.my.backups) names.
[
  "accounted"
  "home-assistant"
  "mail"
  "minne-saas"
  "nous"
  "openwebui"
  "overseerr"
  "paperless"
  "politikerstod-lekeberg"
  "radarr"
  "sonarr"
  "supabase"
  "surrealdb"
  "surrealdb-saas"
  "unifi"
  "vaultwarden"
]
