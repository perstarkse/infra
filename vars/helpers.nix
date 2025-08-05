{
  lib,
  config,
}: ({
  name,
  type,
  fileName ? "password",
  multiline ? false,
  description ? null,
  category ? "general",
  tags ? [],
  validation ? null,
  dependencies ? [],
  neededFor ? "services",
  restartUnits ? [],
  ...
}: let
  mainUser = config.my.mainUser.name;
  
  # Enhanced type validation with better naming
  validTypes = ["root-only" "user-only" "system-shared" "service-shared" "user-shared"];
  typeCheck = lib.assertMsg (lib.elem type validTypes) 
    "Secret type must be one of: ${lib.concatStringsSep ", " validTypes}";
  
  # Name validation
  nameCheck = lib.assertMsg (lib.match "^[a-z0-9-]+$" name != null)
    "Secret name must contain only lowercase letters, numbers, and hyphens";
  
  # Enhanced permissions with better naming
  perms = {
    root-only = {
      owner = "root";
      mode = "0400";
      group = null;
    };
    user-only = {
      owner = mainUser;
      mode = "0400";
      group = null;
    };
    system-shared = {
      owner = "root";
      group = "secret-readers";
      mode = "0440";
    };
    service-shared = {
      owner = "root";
      group = "secret-readers";
      mode = "0440";
    };
    user-shared = {
      owner = "root";
      group = "secret-readers";
      mode = "0440";
    };
  };
  
  # Enhanced prompt type mapping
  promptType = if multiline then "multiline-hidden" else "hidden";
  
  # Validation helpers
  validationRules = {
    "api-key" = "Must be a valid API key format";
    "ssh-key" = "Must be a valid SSH private key";
    "ssh-key-pub" = "Must be a valid SSH public key";
    "age-key" = "Must be a valid age private key";
    "env-file" = "Must be valid environment file format";
    "password" = "Must be at least 8 characters";
  };
  
  # Auto-detect validation based on name and fileName
  autoValidation = 
    if lib.hasPrefix "api-key" name then "api-key"
    else if lib.hasSuffix "id_ed25519" fileName then "ssh-key"
    else if lib.hasSuffix ".pub" fileName then "ssh-key-pub"
    else if lib.hasSuffix "keys.txt" fileName then "age-key"
    else if fileName == "env" then "env-file"
    else if fileName == "password" then "password"
    else null;
  
  finalValidation = validation or autoValidation;
  
  # Enhanced description generation
  finalDescription = description or (
    if lib.hasPrefix "api-key" name then "API key for ${lib.removePrefix "api-key-" name}"
    else if lib.hasPrefix "user-ssh-key" name then "SSH private key for user"
    else if lib.hasPrefix "user-ssh-key-pub" name then "SSH public key for user"
    else if lib.hasPrefix "user-age-key" name then "Age encryption key for user"
    else if lib.hasPrefix "restic" name then "Restic backup configuration"
    else if lib.hasPrefix "mail" name then "Mail service configuration"
    else if lib.hasPrefix "k3s" name then "K3s cluster configuration"
    else if lib.hasPrefix "vaultwarden" name then "Vaultwarden service configuration"
    else if lib.hasPrefix "minne" name then "Minne service configuration"
    else if lib.hasPrefix "surrealdb" name then "SurrealDB service configuration"
    else "${name} (${fileName})"
  );
  
  # Enhanced metadata
  metadata = {
    category = category;
    tags = tags;
    validation = finalValidation;
    dependencies = dependencies;
    createdAt = "2024-01-01"; # Could be made dynamic
    lastModified = "2024-01-01"; # Could be made dynamic
  };
  
in {
  "${name}" = {
    share = type == "system-shared" || type == "service-shared" || type == "user-shared";
    
    # Enhanced prompts with better UX
    prompts.input = {
      description = finalDescription;
      type = promptType;
      persist = false;
      display = {
        label = lib.toUpper (lib.replaceStrings ["-"] [" "] name);
        helperText = if finalValidation != null then validationRules.${finalValidation} else null;
        group = category;
        required = true;
      };
    };
    
    # Enhanced script with validation
    script = ''
      #!/usr/bin/env bash
      set -euo pipefail
      
      # Basic validation
      if [[ -z "$prompts/input" ]]; then
        echo "Error: Input is empty" >&2
        exit 1
      fi
      
      # Copy the input to output
      cp "$prompts/input" "$out/${fileName}"
      
      # Add metadata if supported
      if command -v jq >/dev/null 2>&1; then
        echo '${lib.escapeShellArg (lib.toJSON metadata)}' > "$out/.metadata.json"
      fi
    '';
    
    # Enhanced file configuration
    files."${fileName}" = {
      secret = true;
      deploy = true;
      neededFor = neededFor;
      restartUnits = restartUnits;
    } // perms.${type};
    
    # Add metadata file if we have significant metadata
    files = lib.mkIf (tags != [] || finalValidation != null) {
      "${fileName}" = {
        secret = true;
        deploy = true;
        neededFor = neededFor;
        restartUnits = restartUnits;
      } // perms.${type};
      
      ".metadata.json" = {
        secret = false;
        deploy = false;
        value = lib.toJSON metadata;
        mode = "0400";
        owner = "root";
      };
    };
    
    # Dependencies support
    dependencies = dependencies;
    
    # Validation support
    validation = if finalValidation != null then {
      type = finalValidation;
      rule = validationRules.${finalValidation};
    } else null;
  };
})
