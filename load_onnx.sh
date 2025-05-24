#!/usr/bin/env bash

set -euo pipefail

TXT_MODEL_ID="${1:-1--vO9y3gU3TTyPoKMicJKPfupN41F0GV}"
VISION_MODEL_ID="${2:-1-3x8Z-YMvWHet1co18701Tu67kYbPS68}"

# Directory for storing ONNX models
MODEL_DIR="onnx_models"
TEXT_MODEL_PATH="$MODEL_DIR/text_model.onnx"
VISION_MODEL_PATH="$MODEL_DIR/vision_model.onnx"

# Ensure gdown is installed
if ! command -v gdown &> /dev/null; then
    echo "📦 gdown is not installed. Installing it..."
    if command -v pip3 &> /dev/null; then
        pip3 install --upgrade gdown
    elif command -v pip &> /dev/null; then
        pip install --upgrade gdown
    else
        echo "❌ pip or pip3 is required to install gdown." >&2
        exit 1
    fi

    if ! command -v gdown &> /dev/null; then
        echo "❌ gdown installation failed. Please install manually." >&2
        exit 1
    fi
fi

# Create the model directory
mkdir -p "$MODEL_DIR"

# Download text model if missing
if [ ! -f "$TEXT_MODEL_PATH" ]; then
    echo "⬇️ Downloading text model..."
    gdown --id "$TXT_MODEL_ID" -O "$TEXT_MODEL_PATH" || {
        echo "❌ Failed to download text model."
        exit 1
    }
else
    echo "✅ Text model already exists: $TEXT_MODEL_PATH"
fi

# Download vision model if missing
if [ ! -f "$VISION_MODEL_PATH" ]; then
    echo "⬇️ Downloading vision model..."
    gdown --id "$VISION_MODEL_ID" -O "$VISION_MODEL_PATH" || {
        echo "❌ Failed to download vision model."
        exit 1
    }
else
    echo "✅ Vision model already exists: $VISION_MODEL_PATH"
fi

# Run Python code to download a model from Hugging Face
echo "📦 Downloading CLIP processor from Hugging Face..."
python3 <<EOF
try:
    from transformers import CLIPProcessor
    CLIPProcessor.from_pretrained("openai/clip-vit-base-patch32")
    print("✅ CLIPProcessor loaded successfully.")
except Exception as e:
    print(f"❌ Failed to load CLIPProcessor: {e}")
    exit(1)
EOF

echo "✅ All models are ready in '$MODEL_DIR'"
