# hermes-inspect: read-only CLI for the personal agent on makemake, plus two
# chat paths (a one-shot API turn and the real Hermes TUI over a PTY).
#
# Why a package and not a shell function: it needs curl and jq on PATH, and
# the fleet wants to override the target/port/paths without editing the
# script — hence plain arguments with defaults, callPackage-able.
#
# Why plain `ssh` and not `clan ssh`: clan ssh resolves the machine through
# the flake, so the CLI only ran from inside a checkout of the infra repo and
# needed an ssh-agent socket, because the fleet key lives in an agent rather
# than in a file. A plain `ssh root@<host>` needs neither — any workstation
# holding the fleet key in ~/.ssh can run it from any directory. Absolute
# paths are still used for everything the remote script touches, since a
# non-interactive ssh command runs under the target's root shell with no
# useful PATH.
#
# Why the API key is read on the remote side: the agent's env secret is
# deployed to /run/secrets-for-users and root can read it there, so the key
# never travels over the wire or into the local shell's argv/history. The old
# shape pulled it out with `clan vars get` on every call.
{
  lib,
  writeShellApplication,
  openssh,
  coreutils,
  jq,
  util-linux,
  # Fleet targets. Overridable so a second agent host needs no script edit.
  machine ? "makemake",
  # ssh target. The host part must resolve from the workstation running this
  # (router split DNS, or the 10.0.0.x address).
  sshUser ? "root",
  # ssh target. The host part must resolve from the workstation running this.
  # makemake.lan (not the bare clan machine name): router split DNS serves
  # the FQDN, while the bare name is a Clan-side alias that only exists to
  # `clan ssh`, and plain ssh cannot use it.
  sshHost ? "makemake.lan",
  # Gateway API server (API_SERVER_PORT in the agent's env secret).
  apiPort ? 8642,
  # Agent state root; the module that owns it defines my.hermes.stateDir.
  stateDir ? "/var/lib/hermes",
  # Absolute NixOS paths on the target (/bin/bash does not exist there).
  remoteBash ? "/run/current-system/sw/bin/bash",
  remoteCurl ? "/run/current-system/sw/bin/curl",
  # base64 on the target, for the request body (see api()).
  remoteBase64 ? "/run/current-system/sw/bin/base64",
  # env(1) on the target: the TUI launch carries HERMES_HOME as its own argv
  # element so no shell re-splitting can eat it (see the tui case).
  remoteEnv ? "/run/current-system/sw/bin/env",
  # Deployed agent env secret: the single home of SIGNAL_ACCOUNT and, since
  # 2026-10-01, API_SERVER_KEY. Root reads it over ssh (which lands as root),
  # so the key never has to come back to this machine.
  remoteEnvSecret ? "/run/secrets-for-users/vars/hermes-env/env",
  # signal-cli's SSE port; shown by `status` so a dead channel is obvious.
  signalPort ? 8085,
}:
writeShellApplication {
  name = "hermes-inspect";
  runtimeInputs = [
    openssh
    coreutils
    jq
    util-linux
  ];
  text = ''
    set -euo pipefail

    TARGET=${lib.escapeShellArg sshUser}@${lib.escapeShellArg (
      if sshHost != null
      then sshHost
      else machine
    )}
    API="127.0.0.1:${toString apiPort}"
    HERMES_HOME_REMOTE="${stateDir}/.hermes"
    HERMES_BIN_REMOTE="${stateDir}/current-package/bin/hermes"

    # Absolute NixOS paths on the TARGET. /bin/bash does not exist there, and
    # clan ssh -c execs exactly one binary, so every remote invocation is
    # `bash -c` with an absolute path to everything it touches.
    REMOTE_BASH=${lib.escapeShellArg remoteBash}
    REMOTE_CURL=${lib.escapeShellArg remoteCurl}
    REMOTE_BASE64=${lib.escapeShellArg remoteBase64}
    REMOTE_ENV=${lib.escapeShellArg remoteEnv}
    REMOTE_ENV_SECRET=${lib.escapeShellArg remoteEnvSecret}

    show_usage() {
      local exit_code="''${1:-1}"
      cat <<USAGE
    Usage: hermes-inspect <command> [args]

    Read-only views of the personal agent on ${machine}, plus two chat paths.

    Inspect:
      status                gateway + signal-cli state, API port, SSE socket
      capabilities          API feature/endpoint table (proves the server is up)
      sessions [limit]      recent sessions (default 10)
      session <id>          one session's metadata + message history
      insights [days]       token/cost/activity analytics (default 30d)
      usage [--json]        provider rate-limit windows
      logs [lines]          gateway journal tail (default 50)

    Chat:
      ask <message...>      one agent turn over the API (new session)
      ask --session <id> …  one agent turn continuing an existing session
      tui                   the real Hermes TUI on ${machine}, over a PTY

    -h, --help              Show this help
    USAGE
      exit "$exit_code"
    }

    # The script rides STDIN, and bash is invoked explicitly. Both details are
    # load-bearing:
    #   - stdin, not argv: root's login shell on makemake is FISH, which
    #     mis-parses bash quoting (a %q-escaped command came back as
    #     "hostname contains invalid characters", then "fish: Unknown
    #     command"). `bash -s` reads the program from stdin, so the remote
    #     shell never has to interpret it at all.
    #   - bash -s, not `bash -c`: same reason, one layer fewer.
    # -T: no PTY, so the command is not wrapped in a tty and stdin stays
    # clean for the script.
    remote() {
      printf '%s\n' "$1" | ssh -T "$TARGET" "$REMOTE_BASH" -s
    }

    # The key is read from the deployed secret ON the target, so it never
    # crosses the SSH connection or lands in local argv/history.
    api() {
      local path="$1" body="''${2:-}"
      local B64=""
      if [ -n "$body" ]; then
        B64=$(printf '%s' "$body" | base64 | tr -d '\n')
      fi
      # A request body rides base64 INSIDE the script, decoded to a temp file
      # on the target and fed to curl with --data-binary @file.
      #
      # It cannot ride stdin any more: stdin now carries the script itself
      # (see remote). It used to, and that is exactly why this changed — the
      # body was silently dropped and the API answered "Invalid JSON in
      # request body" while ask() still exited 0 with null fields.
      #
      # base64 rather than a quoted literal: the body may contain quotes,
      # $(…), newlines and backslashes, and one more escaping layer here is
      # how those get corrupted. Base64 has no shell metacharacters at all.
      local body_setup=""
      if [ -n "$body" ]; then
        # mktemp runs ON the target, inside the script: the path must be
        # valid and writable there, not here.
        body_setup="body=\$(/run/current-system/sw/bin/mktemp)
        printf %s $B64 | $REMOTE_BASE64 -d > \"\$body\""
      fi
      local data_arg=""
      if [ -n "$body" ]; then
        data_arg="--data-binary @\"\$body\""
      fi
      local cmd="set -euo pipefail
        key=\$(sed -n 's/^API_SERVER_KEY=//p' $REMOTE_ENV_SECRET | tail -n 1)
        [ -n \"\$key\" ] || { echo 'hermes-inspect: no API_SERVER_KEY in the agent env secret' >&2; exit 1; }
        $body_setup
        $REMOTE_CURL -sS -m 900 -H \"Authorization: Bearer \$key\" \
          -H 'Content-Type: application/json' $data_arg '$API$path'
        ''${body:+rm -f \"\$body\"}"
      remote "$cmd"
    }

    # One-shot CLI runs. The CLI reads .container-mode from HERMES_HOME and
    # execs itself into the container, so no docker plumbing is needed here.
    agent_cli() {
      remote "HERMES_HOME=$HERMES_HOME_REMOTE $HERMES_BIN_REMOTE $(printf '%q ' "$@")"
    }

    [ $# -ge 1 ] || show_usage 1
    cmd="$1"; shift

    case "$cmd" in
      -h|--help) show_usage 0 ;;

      status)
        remote "systemctl is-active hermes-agent signal-cli
          ss -tln | grep -E ':${toString apiPort} |:${toString signalPort} ' || true" ;;

      capabilities)
        api /v1/capabilities | jq '{model, features, endpoints: (.endpoints | keys)}' ;;

      sessions)
        api "/api/sessions?limit=''${1:-10}" | jq '{sessions: [.data[] | {id, source, model, title, message_count, tool_call_count, input_tokens, output_tokens, last_active}]}' ;;

      session)
        [ $# -ge 1 ] || { echo "hermes-inspect session <id>" >&2; exit 2; }
        api "/api/sessions/$1" | jq .
        api "/api/sessions/$1/messages" | jq '{messages: [.data[] | {role, tool: (.tool_calls // [] | map(.function.name)), preview: ((.content // "" | tostring) + " " + ([.tool_calls // [] | .[].function.arguments] | join(" "))) | .[0:300]}]}' ;;

      insights)
        agent_cli insights --days "''${1:-30}" ;;

      usage)
        agent_cli usage "$@" ;;

      logs)
        remote "journalctl -u hermes-agent --no-pager -n ''${1:-50}" ;;

      ask)
        # Session-scoped turn: POST /api/sessions creates one, then
        # /api/sessions/<id>/chat runs a single synchronous agent turn with the
        # session's own history. Same route the peer's `hermes peer dm` uses.
        # Bodies go out base64'd (see api) so the message text — which may
        # contain quotes, $(…) and newlines — survives both hops verbatim.
        session=""
        if [ "''${1:-}" = "--session" ]; then
          [ $# -ge 2 ] || { echo "hermes-inspect ask --session <id> <message...>" >&2; exit 2; }
          session="$2"; shift 2
        fi
        [ $# -ge 1 ] || { echo "hermes-inspect ask <message...>" >&2; exit 2; }
        message="$*"
        if [ -z "$session" ]; then
          session=$(api /api/sessions "$(jq -nc --arg t "hermes-inspect $(date +%F' '%T)" '{title: $t}')" \
            | jq -r '.session.id')
        fi
        api "/api/sessions/$session/chat" "$(jq -nc --arg m "$message" '{message: $m}')" \
          | jq '{session_id, reply: .message.content, usage, runtime: .runtime.model}' ;;

      tui)
        # The real TUI, on the target, inside the container: the host CLI
        # routes through .container-mode.
        #
        # `env` and not `bash -c 'VAR=x cmd'`: ssh joins its argv with spaces
        # and the target's login shell (FISH, not bash) re-splits it, so the
        # single-quoted command string arrived as separate words. bash then
        # took `HERMES_HOME=…` as its whole -c script — a bare assignment, a
        # no-op — and `hermes --tui` became positional parameters that never
        # ran. Symptom: "Connection to makemake.lan closed." with exit 0 and
        # zero bytes of output. `env VAR=x cmd` carries the assignment as its
        # own argv element, which no re-splitting can break.
        #
        # `script` is what makes this work at all: a non-interactive ssh
        # allocates no PTY, and the TUI refuses to start without one
        # (hermes_cli/main.py checks stdin/stdout isatty). -t for the remote
        # PTY, script for the local one.
        exec script -qec "ssh -t $TARGET $REMOTE_ENV HERMES_HOME=$HERMES_HOME_REMOTE $HERMES_BIN_REMOTE --tui" /dev/null ;;

      *)
        echo "Unknown command: $cmd" >&2
        show_usage 1
        ;;
    esac
  '';
}
