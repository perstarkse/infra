{
  config.flake.homeModules.local-ai = {
    pkgs,
    config,
    lib,
    ...
  }: let
    vllm-manager = pkgs.writeScriptBin "vllm-manager" ''
      #!/usr/bin/env bash
      set -e

      # Configuration
      IMAGE="intel/vllm:0.11.1-xpu"
      CONTAINER_NAME="vllm-arc"
      PORT="8009"

      # Model Definitions
      declare -A MODELS
      MODELS[r1]="deepseek-ai/DeepSeek-R1-Distill-Qwen-7B"
      MODELS[r1-awq]="casperhansen/deepseek-r1-distill-qwen-7b-awq"
      MODELS[r1-8b-awq]="stelterlab/DeepSeek-R1-0528-Qwen3-8B-AWQ"
      MODELS[olmo]="kaitchup/Olmo-3-7B-Think-awq-w4a16-asym"
      MODELS[tiny]="facebook/opt-125m"

      # Quantization Settings
      declare -A QUANT
      QUANT[r1]=""
      QUANT[r1-awq]="awq"
      QUANT[r1-8b-awq]="awq"
      QUANT[olmo]="awq"
      QUANT[tiny]=""

      # Context Lengths
      declare -A CONTEXT
      CONTEXT[r1]="32768"
      CONTEXT[r1-awq]="32768"
      CONTEXT[r1-8b-awq]="20480"
      CONTEXT[olmo]="32768"
      CONTEXT[tiny]="2048"

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

        # Build Command Arguments
        local quant_arg=""
        if [ -n "''${QUANT[$model_key]}" ]; then
          quant_arg="--quantization ''${QUANT[$model_key]}"
        fi

        docker run -d \
          --name ''${CONTAINER_NAME} \
          --net=host \
          --ipc=host \
          --device /dev/dri:/dev/dri \
          -v /dev/dri/by-path:/dev/dri/by-path \
          -v $HOME/.cache/huggingface:/root/.cache/huggingface \
          -e VLLM_WORKER_MULTIPROC_METHOD=spawn \
          -e HUGGING_FACE_HUB_TOKEN=$HUGGING_FACE_HUB_TOKEN \
          --entrypoint /bin/bash \
          ''${IMAGE} \
          -c "
            python3 -m vllm.entrypoints.openai.api_server \
            --model $model_id \
            --served-model-name local-model \
            --dtype float16 \
            $quant_arg \
            --enforce-eager \
            --tensor-parallel-size 1 \
            --gpu-memory-util 0.8 \
            --port ''${PORT} \
            --trust-remote-code \
            --max-model-len ''${CONTEXT[$model_key]} \
            --no-enable-prefix-caching \
            --disable-log-requests
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
                r1: "You are DeepSeek R1, a helpful and reasoning AI assistant."
                r1-awq: "You are DeepSeek R1, a helpful and reasoning AI assistant."
                r1-8b-awq: "You are DeepSeek R1, a helpful and reasoning AI assistant."
                olmo: "You are AllenAI Olmo, a thinking model engaging in deep reasoning."
                tiny: "You are a concise test assistant."
                default: "You are a helpful assistant."
    '';
  };
}
