# GitHub commit *signing* key for the personal agent (decision C1,
# docs/p-agent-collab-roadmap.md). Signing-only: cannot authenticate to
# anything — a leak forges attestation, not access.
#
# Mirrors vars/generators/agent-ssh-key.nix (prompt-rotate pattern, public half
# always derived so the halves cannot drift).
#
#   private_key — 0400 neededFor = "users", copied to
#                 /home/agent/.ssh/git_sign_ed25519 by
#                 my.secrets.exposeUserSecrets (machines/charon/configuration.nix);
#                 git's user.signingkey points at this file directly (the public
#                 half is never deployed to the agent's home).
#   public_key  — two consumers, both root-side: registered on github.com as a
#                 *signing* key by the owner (browser step, once), and installed
#                 into root-owned /etc/ssh/allowed_signers by the
#                 install-agent-allowed-signers unit in
#                 machines/charon/configuration.nix.
#
# Signer identity: agent commits carry author agent <agent@stark.pub>, committer
# Per Stark <per@stark.pub>. GitHub matches signatures against the *committer*
# email, so the badge reads as p — attribution lives in the author field and
# local verification (allowed_signers maps agent@stark.pub to this key).
{pkgs, ...}: {
  "agent-git-sign" = {
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
        description = "Agent git signing private key (empty to generate a fresh ed25519 pair; re-prompt to rotate)";
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
        ssh-keygen -t ed25519 -C "agent-git-sign" -f "$out/private_key" -N ""
        chmod 0400 "$out/private_key"
        mv "$out/private_key.pub" "$out/public_key"
      fi
      chmod 0444 "$out/public_key"
    '';
    meta = {
      tags = ["agent-git" "agent-git-sign"];
    };
  };
}
