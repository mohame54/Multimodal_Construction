#!/usr/bin/env bash

set -euo pipefail

# Function to detect the system's package manager
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt-get"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v apk &> /dev/null; then
        echo "apk"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    else
        echo "Error: Could not detect package manager." >&2
        exit 1
    fi
}

# Function to install a missing package
install_if_missing() {
    local pkg="$1"
    if ! command -v "$pkg" &> /dev/null; then
        echo "Installing missing dependency: $pkg"
        local pm
        pm=$(detect_package_manager)
        case "$pm" in
            apt-get) sudo apt-get update && sudo apt-get install -y "$pkg" ;;
            yum) sudo yum install -y "$pkg" ;;
            dnf) sudo dnf install -y "$pkg" ;;
            apk) sudo apk add "$pkg" ;;
            pacman) sudo pacman -Sy --noconfirm "$pkg" ;;
            *) echo "Unsupported package manager: $pm" >&2; exit 1 ;;
        esac
    fi
}

# Ensure required CLI tools are available
install_if_missing curl
install_if_missing sh
install_if_missing python3
install_if_missing pip3


# Install Python dependencies from requirements.txt
if [[ -f "requirements.txt" ]]; then
    echo "Installing Python dependencies..."
    python3 -m pip install -q --no-cache-dir -r requirements.txt
else
    echo "Error: requirements.txt not found." >&2
    exit 1
fi

# Run model setup scripts
if [[ -f "./load_onnx.sh" ]]; then
    echo "Running load_onnx.sh..."
    ./load_onnx.sh
else
    echo "Error: load_onnx.sh not found." >&2
    exit 1
fi

if [[ -f "./load_ollama.sh" ]]; then
    echo "Running load_ollama.sh..."
    ./load_ollama.sh
else
    echo "Error: load_ollama.sh not found." >&2
    exit 1
fi

echo "✅ Setup completed successfully."
