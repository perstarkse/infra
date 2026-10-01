# Environment file for the personal agent (Hermes).
#
# KEY=VALUE lines only. Consumed by modules/system/hermes.nix as
# `environmentFiles`, which the upstream NixOS module merges into
# $HERMES_HOME/.env on every activation. The generator is the source of truth —
# .env is regenerated from it, so it is excluded from the agent's restic backup
# rather than backed up.
#
# This file is also the single home for the Signal account number:
# modules/system/signal-cli.nix reads SIGNAL_ACCOUNT from it at unit start
# rather than taking it as a Nix option, so the number never enters the flake,
# the git tree or the /nix/store, and the daemon and the agent cannot disagree.
#
# Minimum — one provider key:
#
#   OPENROUTER_API_KEY=sk-or-...        (default provider; also OPENAI_API_KEY,
#                                       ANTHROPIC_API_KEY, GEMINI_API_KEY,
#                                       GEMINI/GOOGLE, GROQ, MISTRAL,
#                                       DEEPSEEK, XAI, FIREWORKS, NOUS)
#
# Signal (all four are needed; the daemon reads only the account):
#
#   SIGNAL_HTTP_URL=http://127.0.0.1:8080   signal-cli HTTP endpoint
#   SIGNAL_ACCOUNT=+46XXXXXXXXX             E.164, the linked number
#   SIGNAL_ALLOWED_USERS=+46XXXXXXXXX      who may message the agent
#   SIGNAL_HOME_CHANNEL=+46XXXXXXXXX       default target for cron deliveries
#
# The X placeholders are deliberately not valid E.164: signal-cli refuses to
# start on a malformed SIGNAL_ACCOUNT rather than dialling the wrong account.
#
# Leave SIGNAL_GROUP_ALLOWED_USERS unset: groups stay disabled by default.
# Signal additionally understands MEDIA: tags, chunking and native formatting
# with no extra configuration.
_: {
  "hermes-env" = {
    share = true;
    files = {
      env = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      env = {
        description = "Agent environment file (KEY=VALUE lines, e.g. OPENROUTER_API_KEY=...)";
        persist = true;
        type = "multiline-hidden";
      };
    };
    script = ''
      cp "$prompts/env" "$out/env"
    '';
    meta = {
      tags = ["hermes" "hermes-env" "agent"];
    };
  };
}
