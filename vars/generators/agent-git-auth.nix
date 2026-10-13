# GitHub *authentication* key for the personal agent. Account-level write
# key: pushes to any repo
# p can access — accepted deliberately, one key for ~40 repos; deploy still
# needs p's pane and the key grants nothing beyond git-over-ssh.
#
# Mirrors vars/generators/agent-ssh-key.nix exactly (prompt-rotate pattern,
# public half always derived so the halves cannot drift):
#
#   private_key — 0400 neededFor = "users", copied to
#                 /home/agent/.ssh/git_auth_ed25519 by my.secrets.exposeUserSecrets
#                 on every machine that opts in (charon and makemake, owner
#                 decision 2026-10-13). The generators are share = true: ONE
#                 keypair fleet-wide, no per-machine GitHub registration.
#   public_key  — registered on github.com by the owner (browser step, once).
#                 Never used for SSH auth anywhere; only GitHub accepts it.
#
# Auth key vs signing key: this one can push; agent-git-sign can only attest.
# The two are separate generators so a signing-key leak cannot write and an
# auth-key leak cannot forge attestation.
{pkgs, ...}: {
  "agent-git-auth" = {
    share = true;
    runtimeInputs = [pkgs.openssh];
    files = {
      private_key = {
        mode = "0400";
        neededFor = "users";
      };
      public_key = {
        mode = "0444";
        # NOT `secret = false`: a non-secret file is treated as a *value*
        # (readable via my.secrets.getValue) instead of a deployed file, so it
        # never lands in /run/secrets. Same reasoning as agent-ssh-key.nix.
      };
    };
    prompts = {
      private_key = {
        description = "Agent GitHub auth private key (empty to generate a fresh ed25519 pair; re-prompt to rotate)";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      # Same empty-prompt trap as agent-ssh-key.nix: clan pre-seeds $out with
      # the prompt content, and ssh-keygen blocks on an existing file.
      rm -f "$out/private_key" "$out/private_key.pub"
      if [ -s "$prompts/private_key" ]; then
        cp "$prompts/private_key" "$out/private_key"
        # ssh-keygen refuses group/world-readable private keys ("bad
        # permissions"): the build sandbox hands us 0644, tighten first.
        chmod 0400 "$out/private_key"
        ssh-keygen -y -f "$out/private_key" > "$out/public_key"
      else
        ssh-keygen -t ed25519 -C "agent-git-auth" -f "$out/private_key" -N ""
        chmod 0400 "$out/private_key"
        mv "$out/private_key.pub" "$out/public_key"
      fi
      chmod 0444 "$out/public_key"
    '';
    meta = {
      tags = ["agent-git" "agent-git-auth"];
    };
  };
}
