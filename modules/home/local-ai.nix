{
  config.flake.homeModules.local-ai = {
    pkgs,
    lib,
    config,
    ...
  }: let
    cfg = config.my.local-ai;
    vllm-manager = pkgs.writeScriptBin "vllm-manager" ''
      #!/usr/bin/env bash
      set -e

      # Configuration
      # 0.21.0-xpu (2026-08) is the first image line with Qwen3.5 / Gemma 4 support
      IMAGE="intel/vllm:0.21.0-xpu"
      CONTAINER_NAME="vllm-arc"
      PORT="8009"

      # Model Definitions — Qwen3.8-teacher distill on the Qwen3.5 arch.
      # Only tiny is configured: larger Qwen3.8 distills (4B bf16 8.6GB, 9B AWQ
      # 8.0GB) exceed the shared-desktop VRAM budget (measured 9B @ 0.9 util
      # starved the desktop to ~1GB and froze it). util 0.55 leaves ~5GB free
      # for the desktop and transient whisper-v3 dictation.
      declare -A MODELS
      MODELS[tiny]="empero-ai/Qwen3.8-2B-Distill"

      # Context Lengths (native is 256K — capped to VRAM budget)
      declare -A CONTEXT
      CONTEXT[tiny]="16384"

      # GPU memory utilization
      declare -A UTIL
      UTIL[tiny]="0.55"

      # Helper Functions
      show_help() {
        echo "vLLM Manager for Intel Arc"
        echo "Usage: vllm-manager [COMMAND] [MODEL]"
        echo ""
        echo "Commands:"
        echo "  start [MODEL]   Start vLLM with specified model"
        echo "  stop            Stop and remove the vLLM container"
        echo "  logs            Follow container logs"
        echo "  status          Check container status"
        echo ""
        echo "Available Models:"
        for key in "''${!MODELS[@]}"; do
          echo "  $key: ''${MODELS[$key]}"
        done
      }

      start_vllm() {
        local model_key=$1
        if [ -z "$model_key" ]; then
          echo "Error: No model specified."
          show_help
          exit 1
        fi

        local model_id=''${MODELS[$model_key]}
        if [ -z "$model_id" ]; then
          echo "Error: Unknown model '$model_key'"
          show_help
          exit 1
        fi

        echo "Starting vLLM with model: $model_key ($model_id)..."

        # Save active model state
        mkdir -p $HOME/.cache/vllm
        echo "$model_key" > $HOME/.cache/vllm/active_model

        # Check for Hugging Face Token (if needed for gated models)
        # We rely on the user having it in their env or systemd

        # Cleanup
        if [ "$(docker ps -aq -f name=''${CONTAINER_NAME})" ]; then
          docker rm -f ''${CONTAINER_NAME} > /dev/null
        fi

        # Do NOT override the image entrypoint: it sources oneAPI setvars.sh,
        # which sets LD_LIBRARY_PATH (e.g. libccl.so.1) required by torch.
        docker run -d \
          --init \
          --name ''${CONTAINER_NAME} \
          --net=host \
          --ipc=host \
          --device /dev/dri:/dev/dri \
          -v /dev/dri/by-path:/dev/dri/by-path \
          -v $HOME/.cache/huggingface:/root/.cache/huggingface \
          -e VLLM_WORKER_MULTIPROC_METHOD=spawn \
          -e HUGGING_FACE_HUB_TOKEN=$HUGGING_FACE_HUB_TOKEN \
          ''${IMAGE} \
          bash -c "
            python3 -m vllm.entrypoints.openai.api_server \
            --model $model_id \
            --served-model-name local-model \
            --dtype float16 \
            --enforce-eager \
            --tensor-parallel-size 1 \
            --gpu-memory-utilization ''${UTIL[$model_key]} \
            --port ''${PORT} \
            --trust-remote-code \
            --max-model-len ''${CONTEXT[$model_key]} \
            --no-enable-prefix-caching \
            --no-enable-log-requests
          "

        echo "Container launched. Logs:"
        docker logs -f ''${CONTAINER_NAME}
      }

      case "$1" in
        start)
          start_vllm "$2"
          ;;
        stop)
          docker rm -f ''${CONTAINER_NAME}
          echo "Stopped."
          ;;
        logs)
          docker logs -f ''${CONTAINER_NAME}
          ;;
        status)
          docker ps -f name=''${CONTAINER_NAME}
          ;;
        *)
          show_help
          ;;
      esac
    '';

    lmods = pkgs.writeShellScriptBin "lmods" ''
      active_model="default"
      if [ -f $HOME/.cache/vllm/active_model ]; then
        active_model=$(cat $HOME/.cache/vllm/active_model)
      fi

      exec ${pkgs.mods}/bin/mods --api vllm --topp 0.9 --role "$active_model" "$@"
    '';
  in {
    options.my.local-ai.enable = lib.mkEnableOption "local AI tooling (vllm-manager, aichat, mods)";

    config = lib.mkIf cfg.enable {
      home.packages = with pkgs; [
        aichat
        vllm-manager
        lmods
        mods # Ensure base mods is available
      ];

      xdg.configFile."aichat/config.yaml".text = ''
        model: local
        clients:
          - type: openai
            name: local
            api_base: http://localhost:8009/v1
            api_key: empty
            models:
              - name: local-model
      '';

      xdg.configFile."mods/mods.yml".text = ''
        default-model: local-model
        apis:
          vllm:
            base-url: http://localhost:8009/v1
            api-key: empty
            models:
              local-model:
                aliases: ["local"]
                max-input-chars: 65536
                top-p: 0.9
                roles:
                  tiny: "You are Qwen3.8 distilled, a concise and fast assistant."
                  default: "You are a helpful assistant.""
      '';
    };
  };
}
