{pkgs, ...}: {
  "supabase" = {
    share = true;
    runtimeInputs = [pkgs.openssl pkgs.coreutils];
    files = {
      env = {
        mode = "0400";
        neededFor = "users";
      };
    };
    prompts = {
      smtp_user = {
        description = "smtp2go SMTP username for Supabase Auth emails";
        persist = true;
        type = "hidden";
      };
      smtp_pass = {
        description = "smtp2go SMTP password for Supabase Auth emails";
        persist = true;
        type = "hidden";
      };
      aws_access_key_id = {
        description = "Garage S3 access key ID for Supabase Storage (format GK + 24 hex chars; auto-generated if empty)";
        persist = true;
        type = "hidden";
      };
      aws_secret_access_key = {
        description = "Garage S3 secret access key for Supabase Storage (64 hex chars; auto-generated if empty)";
        persist = true;
        type = "hidden";
      };
    };
    # Port of supabase/docker/utils/generate-keys.sh (legacy HS256 JWT keys).
    script = ''
      set -euo pipefail

      _prompts_dir="''${prompts:-}"
      if [ -z "$_prompts_dir" ] || [ ! -d "$_prompts_dir" ]; then
        _prompts_dir=""
      fi

      pval() {
        if [ -n "$_prompts_dir" ] && [ -s "$_prompts_dir/$1" ]; then
          tr -d '\n' < "$_prompts_dir/$1"
        fi
      }

      b64url() {
        openssl enc -base64 -A | tr '+/' '-_' | tr -d '='
      }

      jwt_secret="$(openssl rand -base64 30 | tr -d '\n')"

      gen_token() {
        payload_b64="$(printf %s "$1" | b64url)"
        header_b64="$(printf %s '{"alg":"HS256","typ":"JWT"}' | b64url)"
        signed_content="''${header_b64}.''${payload_b64}"
        signature="$(printf %s "$signed_content" | openssl dgst -binary -sha256 -hmac "$jwt_secret" | b64url)"
        printf '%s' "''${signed_content}.''${signature}"
      }

      iat="$(date +%s)"
      exp="$((iat + 5 * 365 * 24 * 3600))"
      anon_key="$(gen_token "{\"role\":\"anon\",\"iss\":\"supabase\",\"iat\":$iat,\"exp\":$exp}")"
      service_role_key="$(gen_token "{\"role\":\"service_role\",\"iss\":\"supabase\",\"iat\":$iat,\"exp\":$exp}")"

      # Garage key IDs: GK + 12 hex bytes. Secrets: 32 hex bytes.
      aws_id="$(pval aws_access_key_id)"
      if ! echo "$aws_id" | grep -E '^GK[0-9a-fA-F]{24}$' >/dev/null 2>&1; then
        aws_id="GK$(openssl rand -hex 12)"
      fi
      aws_secret="$(pval aws_secret_access_key)"
      [ -n "$aws_secret" ] || aws_secret="$(openssl rand -hex 32)"

      smtp_user="$(pval smtp_user)"
      smtp_pass="$(pval smtp_pass)"

      {
        echo "JWT_SECRET=$jwt_secret"
        echo "ANON_KEY=$anon_key"
        echo "SERVICE_ROLE_KEY=$service_role_key"
        echo "POSTGRES_PASSWORD=$(openssl rand -hex 16)"
        echo "DASHBOARD_PASSWORD=$(openssl rand -hex 16)"
        echo "SECRET_KEY_BASE=$(openssl rand -base64 48 | tr -d '\n')"
        echo "REALTIME_DB_ENC_KEY=$(openssl rand -hex 8)"
        echo "VAULT_ENC_KEY=$(openssl rand -hex 16)"
        echo "PG_META_CRYPTO_KEY=$(openssl rand -base64 24 | tr -d '\n')"
        echo "LOGFLARE_PUBLIC_ACCESS_TOKEN=$(openssl rand -base64 24 | tr -d '\n')"
        echo "LOGFLARE_PRIVATE_ACCESS_TOKEN=$(openssl rand -base64 24 | tr -d '\n')"
        echo "S3_PROTOCOL_ACCESS_KEY_ID=$(openssl rand -hex 16)"
        echo "S3_PROTOCOL_ACCESS_KEY_SECRET=$(openssl rand -hex 32)"
        echo "AWS_ACCESS_KEY_ID=$aws_id"
        echo "AWS_SECRET_ACCESS_KEY=$aws_secret"
        echo "SMTP_USER=$smtp_user"
        echo "SMTP_PASS=$smtp_pass"
      } > "$out/env"
      chmod 0400 "$out/env"
    '';
    meta.tags = ["supabase" "makemake"];
  };
}
