# Shared LAN→WAN ntfy fan-out. One helper, three publishers (backups,
# storage-alerts, heartbeat) — they already drifted in retry/timeout/header
# shape once, so fan-out lives here, not in three bespoke curl blocks.
# Failure warns to the journal and never masks the calling unit (precedent:
# failover transition notices — delivery failure warns, operation continues).
{pkgs}: {
  publishAlert = pkgs.writeShellScript "publish-alert" ''
    set -euo pipefail
    # $1 topic, $2 token file ("-" or missing = no auth), $3 title,
    # $4 message, $5 priority, $6 tags.
    topic="''${1:?topic required}"
    token_file="''${2:-}"
    title="''${3:?title required}"
    message="''${4:?message required}"
    priority="''${5:-default}"
    tags="''${6:-}"

    auth_args=()
    if [ -n "$token_file" ] && [ "$token_file" != "-" ] && [ -f "$token_file" ]; then
      auth_args=(-H "Authorization: Bearer $(<"$token_file")")
    fi

    headers=(
      -fsS
      -H "Title: $title"
      -H "Priority: $priority"
    )
    if [ -n "$tags" ]; then
      headers+=(-H "Tags: $tags")
    fi

    lan_url="''${ALERT_LAN_URL:-https://ntfy.lan.stark.pub}"
    wan_url="''${ALERT_WAN_URL:-https://ntfy.stark.pub}"

    if ${pkgs.curl}/bin/curl "''${headers[@]}" "''${auth_args[@]}" \
      --connect-timeout 3 --max-time 10 \
      --data-binary "$message" \
      "$lan_url/$topic" >/dev/null 2>&1; then
      exit 0
    fi

    if [ -n "$wan_url" ] \
      && ${pkgs.curl}/bin/curl "''${headers[@]}" "''${auth_args[@]}" \
        --connect-timeout 5 --max-time 15 \
        --data-binary "$message" \
        "$wan_url/$topic" >/dev/null 2>&1; then
      exit 0
    fi

    echo "WARNING: publish-alert [$topic] failed via LAN ($lan_url) and WAN ($wan_url)" >&2
    exit 0
  '';
}
