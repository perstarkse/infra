{pkgs, ...}: {
  "heartbeat-tls" = {
    share = true;
    runtimeInputs = [pkgs.openssl pkgs.coreutils];
    files = {
      "ca.pem" = {
        mode = "0400";
        neededFor = "services";
      };
      "server-cert.pem" = {
        mode = "0400";
        neededFor = "services";
      };
      "server-key.pem" = {
        mode = "0400";
        neededFor = "services";
      };
    };
    script = ''
      set -euo pipefail
      umask 077
      mkdir -p "$out"

      # TLS PKI for io's heartbeat push → sedna's heartbeat receiver across
      # the public internet. Server-auth only: the bearer token remains the
      # authenticator, TLS keeps it off the wire. ca.pem is pinned on io via
      # my.heartbeat.push.caCertFile; the server cert carries SAN IP
      # 130.61.55.4 (sedna's WAN address). Regenerate + redeploy both
      # machines to rotate.
      tmp=$(mktemp -d)
      trap 'rm -rf "$tmp"' EXIT

      openssl ecparam -name prime256v1 -genkey -noout -out "$tmp/ca.key"
      openssl req -x509 -new -key "$tmp/ca.key" -sha256 -days 3650 -subj "/CN=heartbeat-ca" -out "$out/ca.pem"

      openssl ecparam -name prime256v1 -genkey -noout -out "$tmp/server.key"
      openssl req -new -key "$tmp/server.key" -subj "/CN=sedna" -out "$tmp/server.csr"
      printf 'subjectAltName=IP:130.61.55.4,DNS:sedna.lan\n' > "$tmp/server.ext"
      openssl x509 -req -in "$tmp/server.csr" -CA "$out/ca.pem" -CAkey "$tmp/ca.key" -CAcreateserial -days 825 -sha256 -extfile "$tmp/server.ext" -out "$out/server-cert.pem"
      install -m 0400 "$tmp/server.key" "$out/server-key.pem"
    '';
    meta.tags = ["heartbeat"];
  };
}
