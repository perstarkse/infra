_: {
  config.flake.nixosModules.accounted-ocr = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.my.accounted-ocr;

    proxyPort = cfg.proxy.port;

    # Python libs needed by the proxy regardless of backend
    proxyLibs =
      [pkgs.python3Packages.requests pkgs.python3Packages.pytesseract]
      ++ lib.optionals (cfg.backend == "local") [pkgs.python3Packages.pyyaml];

    # Which Ollama package to use: Vulkan variant if iGPU acceleration is
    # requested (works on Intel N100 UHD Graphics), else CPU-only.
    ollamaPkg =
      if cfg.llm.ollama.igpu
      then pkgs.ollama-vulkan
      else pkgs.ollama;

    # Bedrock API proxy — intercepts InvokeModel from accounted's Bedrock SDK,
    # runs Tesseract OCR locally, then sends extracted text to a configurable
    # LLM backend (remote API or local Ollama) for structured parsing.
    proxyPkg = let
      pdftoppm = "${lib.getBin pkgs.poppler-utils}/bin/pdftoppm";
    in
      pkgs.writers.writePython3Bin "accounted-ocr-proxy" {
        flakeIgnore = ["E501" "E302" "W503" "E265" "E401"];
        libraries = proxyLibs;
      } ''
        import base64
        import json
        import os
        import subprocess
        import sys
        import tempfile
        import traceback
        from http.server import HTTPServer, BaseHTTPRequestHandler

        import requests
        import pytesseract

        OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434")
        OCR_LANG = os.environ.get("OCR_LANG", "swe+eng")
        LLM_MODEL = os.environ.get("LLM_MODEL", "qwen2.5:3b")
        PROXY_PORT = int(os.environ.get("PROXY_PORT", "2080"))
        PDFTOPPM = "${pdftoppm}"

        # Remote API settings (used when BACKEND=remote)
        OPENAI_API_BASE = os.environ.get("OPENAI_API_BASE", "")
        OPENAI_API_KEY_PATH = "/etc/accounted-ocr/openai-key"
        OPENAI_API_KEY = ""
        LLM_BACKEND = os.environ.get("LLM_BACKEND", "local")  # "local" or "remote"

        # Read API key from file at startup
        _key_file = OPENAI_API_KEY_PATH
        if LLM_BACKEND == "remote" and os.path.exists(_key_file):
            with open(_key_file) as f:
                OPENAI_API_KEY = f.read().strip()

        SUPPORTED_MEDIA_TYPES = {
            "application/pdf",
            "image/jpeg",
            "image/png",
            "image/webp",
            "image/gif",
            "image/tiff",
            "image/bmp",
        }


        def decode_document(content_blocks):
            """Extract the first document/image from Anthropic content blocks."""
            for block in content_blocks:
                if not isinstance(block, dict):
                    continue
                if block.get("type") in ("document", "image"):
                    src = block.get("source", {})
                    if src.get("type") == "base64":
                        return src["data"], src.get("media_type", "application/octet-stream")
            raise ValueError("No document/image found")


        def ocr_to_text(base64_data, mime_type):
            """Run Tesseract OCR on the base64-encoded document."""
            raw = base64.b64decode(base64_data)
            with tempfile.NamedTemporaryFile(suffix=".tmp", delete=False) as tmp:
                tmp_path = tmp.name
                tmp.write(raw)
            try:
                if mime_type == "application/pdf":
                    out_prefix = tmp_path + "_page"
                    subprocess.run(
                        [PDFTOPPM, "-f", "1", "-l", "1",
                         "-r", "300", "-tiff", tmp_path, out_prefix],
                        check=True, capture_output=True, timeout=120,
                    )
                    # pdftoppm -tiff creates .tif (three-letter), not .tiff
                    img_path = out_prefix + "-1.tif"
                    text = pytesseract.image_to_string(img_path, lang=OCR_LANG)
                    os.unlink(img_path)
                else:
                    text = pytesseract.image_to_string(tmp_path, lang=OCR_LANG)
            except subprocess.TimeoutExpired:
                text = ""
            except Exception as e:
                print(f"Tesseract error: {e}", file=sys.stderr)
                text = ""
            finally:
                os.unlink(tmp_path)
            return text.strip()


        def parse_with_llm_local(system_text, ocr_text):
            """Send OCR text to local Ollama for structured extraction."""
            prompt = (
                "Below is the OCR-extracted text from an invoice or receipt document. "
                "Extract the fields per the system instructions. JSON only.\n\n"
                "OCR TEXT:\n" + ocr_text
            )
            try:
                resp = requests.post(
                    f"{OLLAMA_URL}/api/chat",
                    json={
                        "model": LLM_MODEL,
                        "stream": False,
                        "format": "json",
                        "messages": [
                            {"role": "system", "content": system_text},
                            {"role": "user", "content": prompt},
                        ],
                    },
                    timeout=300,
                )
                resp.raise_for_status()
                return resp.json().get("message", {}).get("content", "")
            except Exception as e:
                print(f"Ollama error: {e}", file=sys.stderr)
                traceback.print_exc(file=sys.stderr)
                return ""


        def parse_with_llm_remote(system_text, ocr_text):
            """Send OCR text to remote OpenAI-compatible API."""
            prompt = (
                "Below is the OCR-extracted text from an invoice or receipt document. "
                "Extract the fields per the system instructions. JSON only.\n\n"
                "OCR TEXT:\n" + ocr_text
            )
            url = OPENAI_API_BASE.rstrip("/") + "/chat/completions"
            headers = {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {OPENAI_API_KEY}",
            }
            body = {
                "model": LLM_MODEL,
                "messages": [
                    {"role": "system", "content": system_text},
                    {"role": "user", "content": prompt},
                ],
                "response_format": {"type": "json_object"},
            }
            try:
                resp = requests.post(url, headers=headers, json=body, timeout=300)
                resp.raise_for_status()
                data = resp.json()
                return data.get("choices", [{}])[0].get("message", {}).get("content", "")
            except Exception as e:
                print(f"Remote API error: {e}", file=sys.stderr)
                traceback.print_exc(file=sys.stderr)
                return ""


        def parse_with_llm(system_text, ocr_text):
            if LLM_BACKEND == "remote" and OPENAI_API_BASE:
                return parse_with_llm_remote(system_text, ocr_text)
            return parse_with_llm_local(system_text, ocr_text)


        class ProxyHandler(BaseHTTPRequestHandler):
            def do_POST(self):
                path = self.path
                if "invoke-with-response-stream" in path:
                    self._send_ok({})
                    return
                if "/invoke" not in path:
                    self.send_response(404)
                    self.end_headers()
                    return

                length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(length)
                try:
                    req = json.loads(body)
                except json.JSONDecodeError:
                    self.send_response(400)
                    self.end_headers()
                    return

                system_blocks = req.get("system", "")
                system_text = ""
                if isinstance(system_blocks, list):
                    for b in system_blocks:
                        if isinstance(b, dict) and b.get("type") == "text":
                            system_text += b.get("text", "")
                    if system_text.endswith("JSON only."):
                        system_text = system_text[:-10]
                elif isinstance(system_blocks, str):
                    system_text = system_blocks

                messages = req.get("messages", [])
                user_content = []
                for msg in messages:
                    if msg.get("role") == "user":
                        content = msg.get("content", [])
                        if isinstance(content, list):
                            user_content = content
                        elif isinstance(content, str):
                            user_content = [{"type": "text", "text": content}]

                if not user_content:
                    self._send_ok({})
                    return

                try:
                    b64data, mime_type = decode_document(user_content)
                except ValueError:
                    self._send_ok({})
                    return

                if mime_type not in SUPPORTED_MEDIA_TYPES:
                    print(f"Unsupported media type: {mime_type}", file=sys.stderr)
                    self._send_ok({})
                    return

                ocr_text = ocr_to_text(b64data, mime_type)
                if not ocr_text:
                    print("OCR returned empty text", file=sys.stderr)
                    self._send_ok({})
                    return

                llm_output = parse_with_llm(system_text, ocr_text)
                if not llm_output:
                    self._send_ok({})
                    return

                llm_output = llm_output.strip()
                if llm_output.startswith("```"):
                    parts = llm_output.split("\n", 1)
                    if len(parts) > 1:
                        llm_output = parts[1]
                    if "```" in llm_output:
                        llm_output = llm_output.rsplit("```", 1)[0]
                self._send_ok(llm_output.strip())

            def _send_ok(self, result_text):
                if isinstance(result_text, str):
                    body = result_text
                elif isinstance(result_text, dict):
                    body = json.dumps(result_text)
                else:
                    body = str(result_text)
                resp_body = json.dumps({
                    "id": "msg_local_ocr_001",
                    "type": "message",
                    "role": "assistant",
                    "content": [{"type": "text", "text": body}],
                    "model": "local-ocr",
                    "stop_reason": "end_turn",
                    "stop_sequence": None,
                    "usage": {"input_tokens": 0, "output_tokens": len(body)},
                })
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(resp_body.encode())

            def log_message(self, fmt, *args):
                print(f"[ocr-proxy] {fmt % args}", file=sys.stderr)


        if __name__ == "__main__":
            # Listen on 0.0.0.0 so Docker containers (accounted app) can reach us.
            # The host firewall restricts external access.
            server = HTTPServer(("0.0.0.0", PROXY_PORT), ProxyHandler)
            print(f"Bedrock OCR proxy listening on 0.0.0.0:{PROXY_PORT}", file=sys.stderr)
            try:
                server.serve_forever()
            except KeyboardInterrupt:
                server.shutdown()
      '';
  in {
    options.my.accounted-ocr = {
      enable = lib.mkEnableOption "Local Bedrock OCR proxy for Accounted";

      backend = lib.mkOption {
        type = lib.types.enum ["local" "remote"];
        default = "local";
        description = ''
          LLM backend for structured invoice extraction.

          - `local`: runs Ollama on-device (Intel iGPU via Vulkan if llm.ollama.igpu is set)
          - `remote`: uses an OpenAI-compatible API (set llm.remote.* options)
        '';
      };

      proxy.port = lib.mkOption {
        type = lib.types.port;
        default = 2080;
        description = "Port for the Bedrock API proxy to listen on";
      };

      ocrLanguage = lib.mkOption {
        type = lib.types.str;
        default = "swe+eng";
        description = "Tesseract OCR language(s)";
      };

      llm = {
        # Settings for local Ollama backend
        ollama = {
          model = lib.mkOption {
            type = lib.types.str;
            default = "qwen2.5:3b";
            description = "Ollama model for structured extraction. For N100 CPU: qwen2.5:3b (fast), qwen2.5:7b (slower but better), phi3:mini, llama3.2:3b";
          };

          igpu = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Use Intel iGPU (Vulkan) acceleration for Ollama. Requires /dev/dri render node (present on N100).";
          };

          listenAddress = lib.mkOption {
            type = lib.types.str;
            default = "127.0.0.1";
            description = "Ollama listen address";
          };

          port = lib.mkOption {
            type = lib.types.port;
            default = 11434;
            description = "Ollama API port";
          };
        };

        # Settings for remote OpenAI-compatible API backend
        remote = {
          apiBase = lib.mkOption {
            type = lib.types.str;
            default = "";
            example = "https://api.openai.com/v1";
            description = "OpenAI-compatible API base URL. Set with 'backend = \"remote\"' to use a cloud LLM instead of local Ollama.";
          };

          apiKeyFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            example = "/run/secrets/openai-key";
            description = "Path to file containing the API key. Read at runtime, not stored in the Nix store.";
          };

          model = lib.mkOption {
            type = lib.types.str;
            default = "gpt-4o-mini";
            description = "Model name for the remote API (e.g. gpt-4o-mini, claude-sonnet-4, etc.)";
          };
        };
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.my.accounted.enable;
          message = "my.accounted-ocr requires my.accounted.enable = true.";
        }
        {
          assertion = cfg.backend == "local" || (cfg.backend == "remote" && cfg.llm.remote.apiBase != "");
          message = "my.accounted-ocr: when backend = \"remote\", llm.remote.apiBase must be set.";
        }
      ];

      # Firewall: allow Docker containers to reach the proxy
      networking.firewall.allowedTCPPorts = [proxyPort];

      # Common deps (always needed)
      environment.systemPackages = with pkgs; [
        poppler-utils
        tesseract5
      ];
      environment.sessionVariables.TESSDATA_PREFIX = "${pkgs.tesseract5.tessdata}";

      # ── Local backend: Ollama ────────────────────────────────────
      services.ollama = lib.mkIf (cfg.enable && cfg.backend == "local") {
        enable = true;
        host = cfg.llm.ollama.listenAddress;
        port = cfg.llm.ollama.port;
        package = ollamaPkg;
        # For Intel iGPU Vulkan: add render group, ensure DRI devices
        loadModels = [cfg.llm.ollama.model];
      };

      # Ensure the ollama service can access the iGPU when Vulkan is used:
      # mesa provides the Intel ANV Vulkan driver (libvulkan_intel.so); the
      # VK_ICD_FILENAMES override is needed because systemd services do not
      # inherit the system profile's XDG search paths.
      hardware.graphics = lib.mkIf (cfg.backend == "local" && cfg.llm.ollama.igpu) {
        enable = true;
      };

      systemd.services.ollama = lib.mkIf (cfg.backend == "local" && cfg.llm.ollama.igpu) {
        serviceConfig = {
          # Allow DRI render nodes (/dev/dri/renderD*)
          DeviceAllow = lib.mkForce [
            "char-drm"
            "char-fb"
            "char-kfd"
            "/dev/dri/renderD128"
          ];
          SupplementaryGroups = ["render"];
        };
        environment = {
          VK_ICD_FILENAMES = "${pkgs.mesa}/share/vulkan/icd.d/intel_icd.x86_64.json";
          # Ollama skips integrated GPUs unless explicitly enabled
          OLLAMA_IGPU_ENABLE = "1";
        };
      };

      # ── Bedrock API proxy service ────────────────────────────────
      systemd.services.accounted-ocr-proxy = let
        baseEnv = {
          OLLAMA_URL = "http://${cfg.llm.ollama.listenAddress}:${toString cfg.llm.ollama.port}";
          OCR_LANG = cfg.ocrLanguage;
          PROXY_PORT = toString proxyPort;
        };
        backendEnv =
          if cfg.backend == "remote"
          then {
            LLM_BACKEND = "remote";
            LLM_MODEL = cfg.llm.remote.model;
            OPENAI_API_BASE = cfg.llm.remote.apiBase;
          }
          else {
            LLM_BACKEND = "local";
            LLM_MODEL = cfg.llm.ollama.model;
          };
      in {
        description = "Accounted local Bedrock OCR proxy";
        after =
          ["network.target"]
          ++ lib.optionals (cfg.backend == "local") ["ollama.service"];
        requires =
          lib.optionals (cfg.backend == "local") ["ollama.service"];
        wantedBy = ["multi-user.target"];
        environment = baseEnv // backendEnv;
        serviceConfig = {
          ExecStart = "${proxyPkg}/bin/accounted-ocr-proxy";
          Restart = "always";
          RestartSec = "5s";
          User = "root";
        };
      };

      # ── Make accounted-stack depend on env injection ─────────────
      systemd.services.accounted-stack = lib.mkIf config.my.accounted.enable {
        requires = ["accounted-ocr-inject-env.service"];
        after = ["accounted-ocr-inject-env.service"];
      };

      # ── Inject Bedrock proxy vars + API key into accounted's .env ─
      systemd.services.accounted-ocr-inject-env = lib.mkIf config.my.accounted.enable (
        let
          apiKeySource =
            if cfg.backend == "remote" && cfg.llm.remote.apiKeyFile != null
            then ''cat "${cfg.llm.remote.apiKeyFile}"''
            else ''echo "fake-local-ocr"'';
        in {
          description = "Inject Bedrock proxy env vars into Accounted .env";
          after = ["accounted-env-render.service"];
          requires = ["accounted-env-render.service"];
          before = ["accounted-stack.service"];
          wantedBy = ["multi-user.target"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            set -euo pipefail
            ENV=${config.my.accounted.dataDir}/stack/.env
            # Use the host's LAN address so the Docker container can reach our proxy.
            # 127.0.0.1 from inside the container points to the container, not the host.
              HOST_IP=${config.my.listenNetworkAddress}
              # Replace any existing values (handles redeploys with changed IPs)
              sed -i '/^ANTHROPIC_BEDROCK_BASE_URL=/d' "$ENV"
              sed -i '/^AWS_ENDPOINT_URL=/d' "$ENV"
              sed -i '/^AWS_REGION=/d' "$ENV"
              sed -i '/^AWS_ACCESS_KEY_ID=/d' "$ENV"
              sed -i '/^AWS_SECRET_ACCESS_KEY=/d' "$ENV"
              echo "ANTHROPIC_BEDROCK_BASE_URL=http://$HOST_IP:${toString proxyPort}" >> "$ENV"
              echo "AWS_REGION=eu-north-1" >> "$ENV"
              echo "AWS_ACCESS_KEY_ID=fake-local-ocr" >> "$ENV"
              echo "AWS_SECRET_ACCESS_KEY=fake-local-ocr" >> "$ENV"
            # For remote backend: write API key so the proxy reads it at startup
            if [ "${cfg.backend}" = "remote" ] && [ -n "${toString cfg.llm.remote.apiKeyFile}" ]; then
              mkdir -p /etc/accounted-ocr
              ${apiKeySource} > /etc/accounted-ocr/openai-key
              chmod 0600 /etc/accounted-ocr/openai-key
            fi
          '';
        }
      );
    };
  };
}
