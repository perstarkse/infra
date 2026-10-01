# SSH keypair for the personal agent's fleet access.
#
# Two halves with different exposure, delivered differently:
#
#   private_key — secret with neededFor = "users", delivered to the users-scope
#                 tree. Only the hermes user on makemake holds an ACL reader, and
#                 it reaches the agent through my.secrets.exposeUserSecrets
#                 (modules/system/hermes.nix).
#   public_key  — the accepting half, delivered to /run/secrets (see the note on
#                 `secret = false` below) and installed root-owned into
#                 /etc/ssh/authorized_keys.d/agent by
#                 modules/system/agent-ssh-access.nix.
#
# Clan deploys whole generators, so both halves land on every machine carrying
# the tag. Off makemake, private_key is root-owned 0400 with no ACL reader, so
# it is not readable by any local account.
#
# Leave the prompt empty on first run to generate a fresh pair; re-prompt only to
# rotate (the public half is always derived from the private half, so the two
# cannot drift).
{pkgs, ...}: {
  "agent-ssh-key" = {
    share = true;
    runtimeInputs = [pkgs.openssh];
    files = {
      private_key = {
        mode = "0400";
        neededFor = "users";
      };
      public_key = {
        mode = "0444";
        # Deliberately NOT `secret = false`. A public key is not sensitive, but
        # marking it non-secret makes Clan treat it as a *value* (readable via
        # my.secrets.getValue) instead of a deployed file — so it never lands in
        # /run/secrets and the install unit in modules/system/agent-ssh-access.nix
        # waits forever on a path that can never exist. Encrypted at rest in the
        # var store is a non-issue for a value that is published in
        # authorized_keys anyway, and this matches wake-proxy-keep-awake-ssh,
        # which delivers both halves to /run/secrets.
      };
    };
    prompts = {
      private_key = {
        description = "Agent SSH private key (empty to generate a fresh ed25519 pair; re-prompt to rotate)";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      # clan-core pre-seeds $out/private_key with `cat $prompts/private_key`,
      # so an empty (generate) prompt leaves an empty file behind and
      # ssh-keygen blocks on `Overwrite (y/n)?` instead of generating.
      # rm first: user-supplied keys are re-copied below, generated keys
      # start from a clean path.
      rm -f "$out/private_key" "$out/private_key.pub"
      if [ -s "$prompts/private_key" ]; then
        cp "$prompts/private_key" "$out/private_key"
      else
        ssh-keygen -t ed25519 -C "agent-ops" -f "$out/private_key" -N ""
      fi
      # -y derives the public half and preserves the key's comment. Do not
      # append one: ssh-keygen already emits a trailing newline, so appending
      # produces a two-line "key file" that standard parsers reject.
      ssh-keygen -y -f "$out/private_key" > "$out/public_key"
      chmod 0400 "$out/private_key"
      chmod 0444 "$out/public_key"
    '';
    meta = {
      tags = ["agent" "ssh" "agent-ssh-key"];
    };
  };
}
