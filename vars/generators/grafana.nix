{
  "grafana" = {
    share = true;
    files = {
      secret_key = {
        mode = "0400";
        neededFor = "users";
      };
    };
    # No prompts declared: a random signing key has no human meaning, so
    # clan must never ask interactively. The generator only runs for
    # missing secrets, so the value is stable once generated (no rotation).
    script = ''
      head -c 32 /dev/urandom | od -v -An -tx1 | tr -d ' \n' > "$out/secret_key"
    '';
    meta.tags = ["service" "grafana" "io"];
  };
}
