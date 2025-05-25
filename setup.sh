set -euo pipefail


MODEL_NAME="${1:-qwen2.5vl:3b}"
# ─── Helpers ───────────────────────────────────────────────────────────────────

detect_package_manager() {
    if   command -v apt-get  &> /dev/null; then echo "apt-get"
    elif command -v dnf      &> /dev/null; then echo "dnf"
    elif command -v yum      &> /dev/null; then echo "yum"
    elif command -v apk      &> /dev/null; then echo "apk"
    elif command -v pacman   &> /dev/null; then echo "pacman"
    else
        echo "Error: Could not detect package manager." >&2
        exit 1
    fi
}

install_if_missing() {
    local want="$1" real_pkg

    case "$want" in
      pip3)     real_pkg="python3-pip"     ;;
      python3)  real_pkg="python3"          ;;
      sh)       real_pkg="bash"             ;;
      curl)     real_pkg="curl"             ;;
      # add other mappings here as needed...
      *)        real_pkg="$want"            ;;
    esac

    if ! command -v "$want" &> /dev/null; then
        echo "Installing missing dependency: $want (package: $real_pkg)"
        local pm
        pm=$(detect_package_manager)
        case "$pm" in
            apt-get)  sudo apt-get update && sudo apt-get install -y "$real_pkg" ;;
            yum)      sudo yum install -y "$real_pkg" ;;
            dnf)      sudo dnf install -y "$real_pkg" ;;
            apk)      sudo apk add --no-cache "$real_pkg" ;;
            pacman)   sudo pacman -Sy --noconfirm "$real_pkg" ;;
            *)        echo "Unsupported package manager: $pm" >&2; exit 1 ;;
        esac
    fi
}

# Bulk-install all the extra build and dev libs you need for wheels
install_build_deps() {
    local pm
    pm=$(detect_package_manager)
    echo "Installing build dependencies via $pm..."
    case "$pm" in
      apt-get)
        sudo apt-get update
        sudo apt-get install -y \
          python3-dev build-essential \
          libatlas-base-dev libopenblas-dev libomp-dev \
          libjpeg-dev zlib1g-dev
        ;;
      dnf)
        sudo dnf install -y \
          python3-devel @development-tools \
          atlas-devel openblas-devel libomp-devel \
          libjpeg-turbo-devel zlib-devel
        ;;
      yum)
        sudo yum install -y \
          python3-devel @development \
          atlas-devel openblas-devel libomp-devel \
          libjpeg-turbo-devel zlib-devel
        ;;
      apk)
        sudo apk update
        sudo apk add --no-cache \
          python3-dev build-base \
          openblas-dev libjpeg-turbo-dev zlib-dev
        ;;
      pacman)
        sudo pacman -Sy --noconfirm \
          python-devel base-devel \
          openblas libjpeg-turbo zlib
        ;;
      *)
        echo "Unsupported package manager: $pm" >&2
        exit 1
        ;;
    esac
}

# ─── Main Setup ────────────────────────────────────────────────────────────────

echo "🔍 Checking for core CLI tools..."
install_if_missing curl
install_if_missing sh
install_if_missing python3
install_if_missing pip3

echo "🛠️ Installing C/C++ build dependencies..."
install_build_deps

echo "📦 Upgrading pip, setuptools, wheel..."
python3 -m pip install --upgrade pip setuptools wheel


echo "📥 Installing Python dependencies from requirements.txt..."
if [[ -f "requirements.txt" ]]; then
    python3 -m pip install --no-cache-dir -r requirements.txt
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
    ./load_ollama.sh "$MODEL_NAME"
else
    echo "Error: load_ollama.sh not found." >&2
    exit 1
fi

echo "✅ Setup completed successfully."
