{pkgs, ...}: {
  "journal-upload" = {
    share = true;
    runtimeInputs = [pkgs.openssl pkgs.coreutils];
    files = {
      "ca.pem" = {
        mode = "0400";
        neededFor = "services";
      };
      "server.pem" = {
        mode = "0400";
        neededFor = "services";
      };
      "server.key" = {
        mode = "0400";
        neededFor = "services";
      };
      "client.pem" = {
        mode = "0400";
        neededFor = "services";
      };
      "client.key" = {
        mode = "0400";
        neededFor = "services";
      };
    };
    script = ''
      set -euo pipefail
      umask 077
      mkdir -p "$out"

      # mTLS PKI for systemd-journal-upload → systemd-journal-remote.
      # ca.pem is the trust anchor on both ends; server.* is the io
      # journal-remote listener cert; client.* is makemake's journal-upload
      # client cert. Regenerate + redeploy both machines to rotate.
      tmp=$(mktemp -d)
      trap 'rm -rf "$tmp"' EXIT

      openssl ecparam -name prime256v1 -genkey -noout -out "$tmp/ca.key"
      openssl req -x509 -new -key "$tmp/ca.key" -sha256 -days 3650 -subj "/CN=journal-upload-ca" -out "$out/ca.pem"

      openssl ecparam -name prime256v1 -genkey -noout -out "$tmp/server.key"
      openssl req -new -key "$tmp/server.key" -subj "/CN=io.lan" -out "$tmp/server.csr"
      printf 'subjectAltName=DNS:io.lan,DNS:localhost,IP:10.0.0.1\n' > "$tmp/server.ext"
      openssl x509 -req -in "$tmp/server.csr" -CA "$out/ca.pem" -CAkey "$tmp/ca.key" -CAcreateserial -days 825 -sha256 -extfile "$tmp/server.ext" -out "$out/server.pem"
      install -m 0400 "$tmp/server.key" "$out/server.key"

      openssl ecparam -name prime256v1 -genkey -noout -out "$tmp/client.key"
      openssl req -new -key "$tmp/client.key" -subj "/CN=makemake.lan" -out "$tmp/client.csr"
      openssl x509 -req -in "$tmp/client.csr" -CA "$out/ca.pem" -CAkey "$tmp/ca.key" -CAcreateserial -days 825 -sha256 -out "$out/client.pem"
      install -m 0400 "$tmp/client.key" "$out/client.key"
    '';
    meta.tags = ["journal-upload"];
  };
}
