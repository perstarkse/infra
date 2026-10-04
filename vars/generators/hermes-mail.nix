# Himalaya mail configuration for the personal agent (Hermes).
#
# ONE operator-supplied file: `config.toml` is pasted in full via
# `clan vars generate --generator hermes-mail` (multiline-hidden prompt), so
# account addresses and passwords never enter git, the flake or /nix/store.
# modules/system/hermes.nix installs it hermes-owned 0400 at
# ${stateDir}/home/.config/himalaya/config.toml — the container HOME's XDG
# path, so bare `himalaya` inside the container just works. Himalaya has no
# daemon: rotation re-installs the file and the next invocation picks it up,
# no restarter. The installed copy is excluded from the hermes restic job;
# this generator is the source of truth.
#
# The schema below is himalaya **1.2.0** (nixpkgs nixos-26.05), NOT master.
# The two are incompatible and the failure is silent at the wrong layer: the
# 2.x spellings (`imap.server`, `imap.sasl.plain.*`, `smtp.server`,
# `mailbox.alias.*`) are unknown fields that 1.2.0 ignores, so the file still
# LOADS and `himalaya account list` still exits 0 — with an empty BACKENDS
# column — while every real command dies with "feature not available, or
# backend configuration for this functionality is not set". Always check the
# BACKENDS column after editing: "IMAP, SMTP" or "IMAP" is correct, blank
# means the account block was not understood.
#
# Passwords do NOT live in this file. Each account pulls its own from an env
# var via `backend.auth.cmd`, so this config is safe to cat, paste into a
# session, or hand to someone else. The values go in the EXISTING hermes-env
# secret (one HIMALAYA_PASS_<ALIAS> line per account) — no second generator.
#
# NAMING IS LOAD-BEADING, DO NOT "IMPROVE" IT: Hermes publishes a static
# blocklist of credential env names that it STRIPS from every child process it
# spawns, so a terminal-launched himalaya never sees them
# (tools/environments/local_env_policy.py:_HERMES_PROVIDER_ENV_BLOCKLIST).
# `EMAIL_ADDRESS`, `EMAIL_PASSWORD`, `EMAIL_IMAP_HOST`, `EMAIL_SMTP_HOST` and
# `EMAIL_HOME_ADDRESS*` are on it — they belong to Hermes' own single-account
# email channel (gateway/config_env.py:Platform.EMAIL) — and using them here
# would make every login fail with "cannot get secret from command: empty
# output". Names outside that declared set pass through untouched; the
# matching is by exact name, not by suffix.
#
# The chain that makes this work, and what breaks it:
#   hermes-env secret -> $HERMES_HOME/.env -> load_hermes_dotenv() writes
#   os.environ (hermes_cli/env_loader.py) -> the agent's terminal child
#   inherits it -> auth.cmd expands $HIMALAYA_PASS_* -> himalaya sends it.
# A cron job also calls load_hermes_dotenv(), so scheduled triage sees the
# same values. Consequence worth stating plainly: this moves the password out
# of a file, it does NOT hide it from the agent — the agent runs as the user
# that authenticates, so it can read the password either way (`cat` the config,
# or `printenv`). It buys "the config is not a secret", not a trust boundary.
#
# Authoritative reference for this version:
# https://github.com/pimalaya/himalaya/blob/v1.2.0/config.sample.toml
#
# Hosts, ports and account aliases below are real and verified against
# nixpkgs' himalaya 1.2.0 (`account list` exit 0, BACKENDS column as
# expected). Only email/login stay blank: those are the lines the operator
# fills in, and they are why this file is still a secret.
#
#   # Self-hosted, receive-only. Note 993 + "tls" (implicit): the mailserver
#   # has enableImap=false / enableImapSsl=true, so there is no 143/STARTTLS.
#   [accounts.personal]
#   default = true
#   email = "<you>@<your-domain>"
#   display-name = "<name>"
#   backend.type = "imap"
#   backend.host = "<your-mail-host>"
#   backend.port = 993
#   backend.encryption.type = "tls"
#   backend.login = "<you>@<your-domain>"
#   backend.auth.type = "password"
#   backend.auth.cmd = "sh -c 'printf %s \"$HIMALAYA_PASS_PERSONAL\"'"
#   folder.aliases.inbox = "INBOX"
#   folder.aliases.sent = "Sent"
#   folder.aliases.drafts = "Drafts"
#   folder.aliases.trash = "Trash"
#
#   # Same host, sending allowed. The send backend is a SEPARATE tree under
#   # message.send.backend.* — not a top-level smtp table. 465 + "tls"
#   # (implicit), because enableSubmission=false / enableSubmissionSsl=true:
#   # port 587 STARTTLS is NOT listening.
#   [accounts.services]
#   email = "<alias>@<your-domain>"
#   display-name = "<name>"
#   backend.type = "imap"
#   backend.host = "<your-mail-host>"
#   backend.port = 993
#   backend.encryption.type = "tls"
#   backend.login = "<alias>@<your-domain>"
#   backend.auth.type = "password"
#   backend.auth.cmd = "sh -c 'printf %s \"$HIMALAYA_PASS_SERVICES\"'"
#   message.send.backend.type = "smtp"
#   message.send.backend.host = "<your-mail-host>"
#   message.send.backend.port = 465
#   message.send.backend.encryption.type = "tls"
#   message.send.backend.login = "<alias>@<your-domain>"
#   message.send.backend.auth.type = "password"
#   message.send.backend.auth.cmd = "sh -c 'printf %s \"$HIMALAYA_PASS_SERVICES\"'"
#   folder.aliases.inbox = "INBOX"
#   folder.aliases.sent = "Sent"
#   folder.aliases.drafts = "Drafts"
#   folder.aliases.trash = "Trash"
#
#   # Gmail, receive-only: an app password (2-step verification on) is
#   # required, the account password is refused over SASL PLAIN. Omit the
#   # message.send.backend block entirely to make an account receive-only —
#   # it then lists as "IMAP" with no SMTP in `account list`.
#   [accounts.gmail]
#   email = "<you>@gmail.com"
#   backend.type = "imap"
#   backend.host = "imap.gmail.com"
#   backend.port = 993
#   backend.encryption.type = "tls"
#   backend.login = "<you>@gmail.com"
#   backend.auth.type = "password"
#   backend.auth.cmd = "sh -c 'printf %s \"$HIMALAYA_PASS_GMAIL\"'"
#
# Use `printf %s`, never `echo` and never `cat`: himalaya takes the command's
# stdout verbatim, and a trailing newline is part of the password.
#
# `folder.aliases.*` is ACCOUNT-level in 1.2.0: the same key at top level is
# a hard TOML parse error (verified), unlike the 2.x `mailbox.alias.*` form.
#
# The two other 1.2.0 auth spellings are deliberately unused: `.keyring` needs
# a D-Bus keyring daemon that container mode has no reason to run, and
# `.raw` is the inline literal this whole arrangement exists to avoid.
#
# After any edit, run `himalaya account list` INSIDE the container and read
# the BACKENDS column: "IMAP, SMTP" or "IMAP" is correct, blank means the
# account block was silently ignored. `himalaya envelope list -a <name>` is
# the next check — it is the first command that actually talks to the server,
# and the only way to catch a password that never reaches the session.
_: {
  "hermes-mail" = {
    share = true;
    files = {
      "config.toml" = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      "config.toml" = {
        description = "Himalaya config.toml for the agent (full TOML, one [accounts.NAME] per mailbox; omit smtp for receive-only)";
        persist = true;
        type = "multiline-hidden";
      };
    };
    script = ''
      cp "$prompts/config.toml" "$out/config.toml"
    '';
    meta = {
      tags = ["hermes" "hermes-mail" "agent" "mail"];
    };
  };
}
