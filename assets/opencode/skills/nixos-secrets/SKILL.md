---
name: nixos-secrets
description: Manage secrets in the heliosphere homelab using clan vars and sops-nix. Use when adding secrets to a service, creating clan vars generators, wiring secret consumption, managing secret rotation, or debugging secret resolution paths.
---

# NixOS Secrets Management

Secrets in this homelab are managed through clan vars (generators + discovery) and sops-nix.

## Which secrets system to use

| System | Use when |
|--------|----------|
| **clan vars generators** | Pre-existing secrets in `vars/generators/` that need tag-based discovery. Preferred for shared/infra-level secrets. |
| **`mkMachineSecret`** | Machine-local secrets generated on first deploy. Use for API keys, tokens specific to a single host. |
| **sops-nix** | Encrypted files in the repo (`sops/`). Use for config-level secrets that need version control. |

## clan vars generators (recommended)

Generators live in `vars/generators/`. Each is a Nix file defining what secrets to generate and which tags they carry.

**Discovery pattern — consuming pre-existing secrets:**
```nix
my.secrets.discover = {
  enable = true;
  dir = ../../vars/generators;
  includeTags = ["minne"];
};
```

This pulls all generators tagged `minne` into the machine's secret set.

**Accessing discovered secrets:**
```nix
config.my.secrets.getPath "minne-env" "env"
# → /run/secrets/vars/minne-env/env
```

## mkMachineSecret (machine-local)

For secrets that don't exist in vars/generators and are specific to a single machine:

```nix
my.secrets.declarations = [
  (config.my.secrets.mkMachineSecret {
    name = "my-service-env";
    files."env" = {
      mode = "0400";
      additionalReaders = ["my-service"];
    };
    prompts."api-key".input = {
      description = "API key for My Service";
      type = "hidden";
      persist = true;
    };
    script = ''
      echo "API_KEY=$(cat "$prompts/api-key")" > "$out/env"
    '';
  })
];
```

**Fields:**
- `name` — unique identifier, becomes the secret directory name
- `files.<name>` — output file with `mode`, `owner`, `group`, `additionalReaders`
- `prompts.<key>.input` — user-facing prompt for initial secret entry
- `script` — bash generating the secret file from prompts
- `generator` — optional path to a generator script (alternative to prompts+script)
- `tags` — optional tags for cross-machine sharing

**On first deploy**, the user is prompted for each `prompts.<key>`. Values are persisted and reused on subsequent deploys.

**Service consumption in systemd:**
```nix
systemd.services.my-service = {
  serviceConfig.LoadCredential = [
    "env:${config.my.secrets.getPath "my-service-env" "env"}"
  ];
};
```

## sops-nix

For version-controlled encrypted secrets:

```nix
sops.secrets."my-service-token" = {
  sopsFile = ../../sops/secrets.yaml;
  mode = "0400";
  owner = config.my.mainUser.name;
};
```

Decrypted at activation time to `/run/secrets/my-service-token`.

## Tag conventions

| Tag | Purpose |
|-----|---------|
| `minne` | Minne application secrets |
| `politikerstod` | Politikerstod application secrets |
| `oumu` | Oumu VM secrets |
| `garage` | Garage S3 credentials |
| `backups` | Backup target credentials |
| `mailserver` | Mailserver secrets |
| `router` | Router-level secrets (DNS API tokens, CF tokens) |

## Common pitfalls

- **Forgot `additionalReaders`**: The service's systemd user needs read access. Add the service user/group name to `additionalReaders`.
- **Generator script references stale paths**: Generator output paths are captured at evaluation time. If paths change, re-evaluate.
- **`getPath` in test stubs**: Use `import ./lib/secrets-stub.nix { inherit lib; getPathDefault = "..."; }` in test Nix files.
- **sops key rotation**: After rotating age keys, re-encrypt with `sops updatekeys <file>`.
