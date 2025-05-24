#!/bin/bash

# Usage: ./load_ollama.sh <model_name>
# Example: ./load_ollama.sh llama2

#!/usr/bin/env bash

set -euo pipefail

MODEL_NAME="${1:-qwen2.5vl:3b}"


# Install Ollama if not present
if ! command -v ollama &> /dev/null; then
    echo "Ollama is not installed. Installing now..."
    curl -fsSL https://ollama.com/install.sh | sh
    if ! command -v ollama &> /dev/null; then
        echo "Installation failed. Please install Ollama manually." >&2
        exit 1
    fi
fi

# Start Ollama server if not running
if ! pgrep -f "ollama serve" > /dev/null; then
    echo "Starting Ollama server in the background..."
    nohup ollama serve > ollama_server.log 2>&1 &
    sleep 5
    if ! pgrep -f "ollama serve" > /dev/null; then
        echo "Failed to start Ollama server. Check ollama_server.log for details." >&2
        exit 1
    fi
else
    echo "Ollama server is already running."
fi

# Ensure model is available
if ! ollama list | awk '{print $1}' | grep -Fxq "$MODEL_NAME"; then
    echo "Model '$MODEL_NAME' not found locally. Pulling from Ollama registry..."
    if ! ollama pull "$MODEL_NAME"; then
        echo "Failed to pull model '$MODEL_NAME'." >&2
        exit 1
    fi
else
    echo "Model '$MODEL_NAME' is already available."
fi

echo "✅ Ollama is running and model '$MODEL_NAME' is loaded."
