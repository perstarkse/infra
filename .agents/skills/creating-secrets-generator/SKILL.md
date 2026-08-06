---
name: creating-secrets-generator
description: Creates Clan vars/generators for secrets management. Use when adding secrets, API keys, environment files, or credentials for services.
---

# Creating Secrets Generators

Secrets in this repo are managed via Clan's vars system. Generators live in `vars/generators/` and produce encrypted secret files that services consume at runtime.

## Generator Location

Create generators at: `vars/generators/<secret-name>.nix`

## Generator Structure

```nix
{
  "<secret-name>" = {
    share = true;  # Share across machines (usually true)
    
    files = {
      "<filename>" = {
        mode = "0400";           # File permissions
        neededFor = "users";     # Required for systemd services
      };
    };
    
    prompts = {
      "<filename>" = {
        description = "Human-readable prompt for this secret";
        persist = true;          # Remember the value
        type = "hidden";         # Don't echo input (use for secrets)
      };
    };
    
    script = ''
      # Generator script (see patterns below)
    '';
    
    meta.tags = ["<machine-tag>" "<service-tag>"];
  };
}
```

## Script Patterns

### Pattern 1: Simple Copy (user-provided only)

For secrets that must be provided manually (API keys, tokens):

```nix
script = ''
  cp "$prompts/api_key" "$out/api_key"
'';
```

### Pattern 2: Robust Prompt Handling (preferred)

For secrets that can be user-provided OR auto-generated:

```nix
script = ''
  # Robust prompts handling
  _prompts_dir="''${prompts:-}"
  if [ -z "$_prompts_dir" ] || [ ! -d "$_prompts_dir" ]; then
     _prompts_dir=""
  fi

  if [ -n "$_prompts_dir" ] && [ -s "$_prompts_dir/env" ]; then
    # User provided input
    cp "$_prompts_dir/env" "$out/env"
  else
    # Auto-generate defaults
    echo "# Auto-generated secrets" > "$out/env"
    secret=$(head -c 32 /dev/urandom | base64 -w0)
    echo "SECRET_KEY=$secret" >> "$out/env"
  fi
'';
```

### Pattern 3: Single-line secret (strip newlines)

For secrets that must be a single line (passwords, tokens):

```nix
script = ''
  cat "$prompts/password" | tr -d '\n' > "$out/password"
'';
```

## Common File Types

### Environment file (multi-line KEY=VALUE)

```nix
files.env = { mode = "0400"; neededFor = "users"; };
prompts.env = { description = "Environment variables (KEY=VALUE)"; persist = true; type = "hidden"; };
```

### API key (single value)

```nix
files.api_key = { mode = "0400"; neededFor = "users"; };
prompts.api_key = { description = "API key for <service>"; persist = true; type = "hidden"; };
```

### Credentials file

```nix
files.credentials = { mode = "0400"; neededFor = "users"; };
```

## Tags

Tags determine which machines receive the secret. Add the secret's tags to the machine's `my.secrets.discover.includeTags`:

```nix
# In vars/generators/my-service.nix
meta.tags = ["service" "my-service" "makemake"];

# In machines/makemake/configuration.nix
my.secrets.discover = {
  enable = true;
  dir = ../../vars/generators;
  includeTags = ["makemake" "my-service" ...];
};
```

## Granting Access

Services need read access to secrets:

```nix
my.secrets.allowReadAccess = [
  {
    readers = ["my-service"];  # systemd user/service name
    path = config.my.secrets.getPath "my-service-env" "env";
  }
];
```

## Consuming in Services

Reference secrets in systemd services:

```nix
systemd.services.my-service.serviceConfig = {
  EnvironmentFile = [(config.my.secrets.getPath "my-service-env" "env")];
};
```

## Generate Secrets

After creating the generator:

```bash
# Auto-generate (uses script fallback)
clan vars generate --match <secret-name>

# Interactive (prompts for input)
clan vars generate --match <secret-name> --no-sandbox
```

## Complete Example

`vars/generators/my-app.nix`:

```nix
{
  "my-app" = {
    share = true;
    files = {
      env = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      env = {
        description = "My App environment variables";
        persist = true;
        type = "hidden";
      };
    };
    script = ''
      _prompts_dir="''${prompts:-}"
      if [ -z "$_prompts_dir" ] || [ ! -d "$_prompts_dir" ]; then
         _prompts_dir=""
      fi

      if [ -n "$_prompts_dir" ] && [ -s "$_prompts_dir/env" ]; then
        cp "$_prompts_dir/env" "$out/env"
      else
        echo "# Auto-generated" > "$out/env"
        secret=$(head -c 32 /dev/urandom | base64 -w0)
        echo "MY_APP_SECRET=$secret" >> "$out/env"
      fi
    '';
    meta.tags = ["service" "my-app"];
  };
}
```

## After Creating

1. Run `git add vars/generators/<name>.nix`
2. Run `clan vars generate --match <name>`
3. Add tag to machine's `includeTags`
4. Add `allowReadAccess` entry if needed
5. Reference in service with `config.my.secrets.getPath`
6. If consumed on `io` router/exposed services, run `nix build path:.#predeploy-check`
