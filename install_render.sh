#!/usr/bin/env bash
# ==============================================================================
# Voice AI Engine - Render & Standard CPU Environment Installer
# Optimized strictly for non-GPU / standard CPU cloud instances and servers.
# ==============================================================================

set -eo pipefail

# ------------------------------------------------------------------------------
# Color and Formatting Definitions
# ------------------------------------------------------------------------------
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ------------------------------------------------------------------------------
# Default Variables & Flags
# ------------------------------------------------------------------------------
FLAG_TIER=""
FLAG_MODEL=""
FLAG_WHISPER=""
CHECK_ONLY=false
DRY_RUN=false
START_CONTAINERS=false

SELECTED_TIER=""
SELECTED_MODEL=""
SELECTED_WHISPER=""

# ------------------------------------------------------------------------------
# Help and Usage Information
# ------------------------------------------------------------------------------
show_help() {
    cat << EOF
Usage: ./install_render.sh [OPTIONS]

Voice AI Engine installer for Render.com and standard CPU Linux environments.

Options:
  --tier <1|2|3>       Preset hardware tier based on RAM:
                         Tier 1: Free / Starter (512MB - 2GB RAM)
                         Tier 2: Standard (2GB - 4GB RAM)
                         Tier 3: Pro / Dedicated (4GB - 8GB+ RAM)
  --model <name>       Override target LLM model (e.g., llama3.2:3b, qwen2.5:1.5b)
  --whisper <model>    Override Whisper model (tiny, base, small, medium)
  --check-only         Run system pre-flight verification and exit
  --dry-run            Simulate operations without writing files or starting services
  --start              Automatically start Docker Compose services upon completion
  -h, --help           Show this help message and exit

Examples:
  ./install_render.sh --check-only
  ./install_render.sh --tier 2
  ./install_render.sh --tier 1 --whisper tiny --model llama3.2:1b
  ./install_render.sh --dry-run --tier 2
EOF
}

# ------------------------------------------------------------------------------
# Parse Command-Line Arguments
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tier)
            if [[ -n "$2" && "$2" =~ ^[1-3]$ ]]; then
                FLAG_TIER="$2"
                shift 2
            else
                log_error "Option --tier requires an argument: 1, 2, or 3."
                exit 1
            fi
            ;;
        --model)
            if [[ -n "$2" ]]; then
                FLAG_MODEL="$2"
                shift 2
            else
                log_error "Option --model requires a model name argument."
                exit 1
            fi
            ;;
        --whisper)
            if [[ -n "$2" ]]; then
                FLAG_WHISPER="$2"
                shift 2
            else
                log_error "Option --whisper requires a whisper model argument (e.g. tiny, base, small, medium)."
                exit 1
            fi
            ;;
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --start)
            START_CONTAINERS=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

echo -e "${BOLD}${CYAN}================================================================${NC}"
echo -e "${BOLD}${CYAN}    Voice AI Engine - Render & CPU Environment Installer        ${NC}"
echo -e "${BOLD}${CYAN}================================================================${NC}"

# ------------------------------------------------------------------------------
# Auto-generate requirements-render.txt if Missing
# ------------------------------------------------------------------------------
ensure_requirements_file() {
    local req_file="requirements-render.txt"
    if [ ! -f "$req_file" ]; then
        log_warn "${req_file} not found. Auto-generating consolidated CPU requirements..."
        if [ "$DRY_RUN" = false ]; then
            cat << 'EOF' > "$req_file"
# ==============================================================================
# Voice AI Engine - Consolidated Requirements for Render & CPU Environments
# Pinned compatible versions across Gateway, Whisper, RAG, and Testing modules
# Target: Python 3.10 / 3.11 / 3.12 (Strict CPU runtime)
# ==============================================================================

# Core Web & API Framework
fastapi>=0.110.0,<0.116.0
uvicorn[standard]>=0.28.0,<0.33.0
python-multipart>=0.0.9,<0.0.20
pydantic>=2.6.0,<2.11.0
pydantic-settings>=2.2.0,<2.8.0

# Speech-to-Text & Phonetic Transcription
faster-whisper>=1.0.0,<1.2.0

# Document Parsing & RAG Ingestion
pypdf>=4.0.0,<5.5.0
python-docx>=1.1.0,<1.2.0

# HTTP Client & Inter-service Networking
requests>=2.31.0,<3.0.0
httpx>=0.27.0,<0.29.0

# Test Suite & Async Verification
pytest>=8.0.0,<9.0.0
pytest-asyncio>=0.23.0,<0.26.0
EOF
            log_ok "Successfully generated ${req_file}."
        else
            log_info "[DRY-RUN] Would create ${req_file}."
        fi
    else
        log_ok "Consolidated requirements file (${req_file}) is present."
    fi
}

# ------------------------------------------------------------------------------
# Pre-Flight System Requirements Checks
# ------------------------------------------------------------------------------
OS_TYPE="$(uname -s)"
ARCH_TYPE="$(uname -m)"

# 1. Total System RAM
HOST_RAM_MB=0
if [ "$OS_TYPE" = "Darwin" ]; then
    if command -v sysctl &> /dev/null; then
        MEM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
        HOST_RAM_MB=$((MEM_BYTES / 1048576))
    fi
elif [ -f /proc/meminfo ]; then
    MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    if [ -n "$MEM_KB" ]; then
        HOST_RAM_MB=$((MEM_KB / 1024))
    fi
elif command -v free &> /dev/null; then
    HOST_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
fi

HOST_RAM_GB=$(awk "BEGIN {printf \"%.2f\", $HOST_RAM_MB/1024}")

# 2. CPU Cores
CPU_CORES=1
if command -v nproc &> /dev/null; then
    CPU_CORES=$(nproc)
elif [ "$OS_TYPE" = "Darwin" ] && command -v sysctl &> /dev/null; then
    CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
elif command -v getconf &> /dev/null; then
    CPU_CORES=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
fi

# 3. Available Disk Space in Current Path
DISK_AVAIL_MB=0
if command -v df &> /dev/null; then
    DISK_AVAIL_KB=$(df -k . | awk 'NR==2 {print $4}')
    if [ -n "$DISK_AVAIL_KB" ]; then
        DISK_AVAIL_MB=$((DISK_AVAIL_KB / 1024))
    fi
fi
DISK_AVAIL_GB=$(awk "BEGIN {printf \"%.2f\", $DISK_AVAIL_MB/1024}")

# 4. Check Required Tools
MISSING_TOOLS=()
command -v curl &> /dev/null || MISSING_TOOLS+=("curl")

PYTHON_CMD=""
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
elif command -v python &> /dev/null; then
    PYTHON_CMD="python"
else
    MISSING_TOOLS+=("python3")
fi

DOCKER_AVAILABLE=false
if command -v docker &> /dev/null; then
    DOCKER_AVAILABLE=true
fi

DOCKER_COMPOSE_AVAILABLE=false
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE_AVAILABLE=true
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_AVAILABLE=true
fi

# Print Pre-Flight Diagnostics
echo -e "\n${BOLD}${CYAN}[PRE-FLIGHT DIAGNOSTICS]${NC}"
echo -e "  - Operating System : ${GREEN}${OS_TYPE} (${ARCH_TYPE})${NC}"
echo -e "  - Available RAM    : ${GREEN}${HOST_RAM_GB} GB (${HOST_RAM_MB} MB)${NC}"
echo -e "  - CPU Cores        : ${GREEN}${CPU_CORES}${NC}"
echo -e "  - Free Disk Space  : ${GREEN}${DISK_AVAIL_GB} GB${NC}"

if [ -n "$PYTHON_CMD" ]; then
    PY_VER=$($PYTHON_CMD --version 2>&1 | awk '{print $2}')
    echo -e "  - Python Runtime   : ${GREEN}${PYTHON_CMD} (v${PY_VER})${NC}"
else
    echo -e "  - Python Runtime   : ${RED}Not found${NC}"
fi

if [ "$DOCKER_AVAILABLE" = true ]; then
    DOCKER_VER=$(docker --version 2>&1 | head -n 1)
    echo -e "  - Docker Engine    : ${GREEN}${DOCKER_VER}${NC}"
else
    echo -e "  - Docker Engine    : ${YELLOW}Not found (Render native web service or container builder required)${NC}"
fi

if [ "$DOCKER_COMPOSE_AVAILABLE" = true ]; then
    echo -e "  - Docker Compose   : ${GREEN}Installed & Operational${NC}"
else
    echo -e "  - Docker Compose   : ${YELLOW}Not found (Optional if deploying directly via Render Blueprint)${NC}"
fi

ensure_requirements_file

# Report Missing Tools
if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    log_warn "Missing system packages detected: ${MISSING_TOOLS[*]}"
    echo "  To install missing packages on Debian/Ubuntu/Render VM:"
    echo "  sudo apt-get update && sudo apt-get install -y ${MISSING_TOOLS[*]}"
fi

# Disk space check recommendation
if [ "$DISK_AVAIL_MB" -gt 0 ] && [ "$DISK_AVAIL_MB" -lt 8192 ]; then
    log_warn "Free disk space is under 8 GB (${DISK_AVAIL_GB} GB). Model downloads may require additional disk."
fi

# ------------------------------------------------------------------------------
# Hardware-Aware Tier Recommendation
# ------------------------------------------------------------------------------
RECOMMENDED_TIER=2
if [ "$HOST_RAM_MB" -gt 0 ]; then
    if [ "$HOST_RAM_MB" -lt 2048 ]; then
        RECOMMENDED_TIER=1
    elif [ "$HOST_RAM_MB" -lt 4096 ]; then
        RECOMMENDED_TIER=2
    else
        RECOMMENDED_TIER=3
    fi
fi

if [ "$CHECK_ONLY" = true ]; then
    echo -e "\n${BOLD}${GREEN}[RESULT] Pre-flight system check completed.${NC}"
    echo -e "Recommended Hardware Profile Tier: ${BOLD}Tier ${RECOMMENDED_TIER}${NC}"
    exit 0
fi

# ------------------------------------------------------------------------------
# Hardware-Aware Selection Menu (Interactive & Automated)
# ------------------------------------------------------------------------------
select_tier() {
    if [ -n "$FLAG_TIER" ]; then
        SELECTED_TIER="$FLAG_TIER"
        log_info "Using hardware tier provided via CLI: Tier ${SELECTED_TIER}"
        return
    fi

    # Non-interactive fallback: auto-select recommended tier
    if [ ! -t 0 ]; then
        SELECTED_TIER="$RECOMMENDED_TIER"
        log_info "Non-interactive environment detected. Auto-selecting recommended Tier ${SELECTED_TIER}."
        return
    fi

    echo -e "\n${BOLD}${CYAN}[HARDWARE-AWARE MODEL SELECTION]${NC}"
    echo "Select the configuration tier matching your Render instance or CPU specs:"
    echo ""
    echo -e "  ${BOLD}1) Tier 1 (Free / Starter Plan - 512MB to 2GB RAM)${NC}"
    echo "     - Whisper STT : tiny / base (int8)"
    echo "     - Ollama LLM  : llama3.2:1b or qwen2.5:1.5b"
    echo ""
    echo -e "  ${BOLD}2) Tier 2 (Standard Plan - 2GB to 4GB RAM)${NC} [Default / Recommended]"
    echo "     - Whisper STT : small (int8)"
    echo "     - Ollama LLM  : llama3.2:3b or qwen2.5:3b"
    echo ""
    echo -e "  ${BOLD}3) Tier 3 (Pro / Dedicated CPU - 4GB to 8GB+ RAM)${NC}"
    echo "     - Whisper STT : small / medium (int8)"
    echo "     - Ollama LLM  : llama3.1:8b-instruct-q4_K_M or qwen2.5:7b-instruct-q4_K_M"
    echo ""

    read -r -p "Enter tier [1-3] (Default: ${RECOMMENDED_TIER}): " USER_TIER_INPUT
    USER_TIER_INPUT=${USER_TIER_INPUT:-$RECOMMENDED_TIER}

    if [[ "$USER_TIER_INPUT" =~ ^[1-3]$ ]]; then
        SELECTED_TIER="$USER_TIER_INPUT"
    else
        log_warn "Invalid selection. Defaulting to Tier ${RECOMMENDED_TIER}."
        SELECTED_TIER="$RECOMMENDED_TIER"
    fi
}

select_models_for_tier() {
    case "$SELECTED_TIER" in
        1)
            DEFAULT_WHISPER="tiny"
            DEFAULT_MODEL="llama3.2:1b"
            ALT_MODEL="qwen2.5:1.5b"
            ;;
        2)
            DEFAULT_WHISPER="small"
            DEFAULT_MODEL="llama3.2:3b"
            ALT_MODEL="qwen2.5:3b"
            ;;
        3)
            DEFAULT_WHISPER="small"
            DEFAULT_MODEL="llama3.1:8b-instruct-q4_K_M"
            ALT_MODEL="qwen2.5:7b-instruct-q4_K_M"
            ;;
    esac

    # Handle Whisper Model
    if [ -n "$FLAG_WHISPER" ]; then
        SELECTED_WHISPER="$FLAG_WHISPER"
    else
        SELECTED_WHISPER="$DEFAULT_WHISPER"
    fi

    # Handle LLM Model
    if [ -n "$FLAG_MODEL" ]; then
        SELECTED_MODEL="$FLAG_MODEL"
    elif [ -t 0 ] && [ -z "$FLAG_TIER" ]; then
        echo -e "\nSelect Ollama LLM model for Tier ${SELECTED_TIER}:"
        echo "  1) ${DEFAULT_MODEL} (Recommended)"
        echo "  2) ${ALT_MODEL}"
        read -r -p "Enter choice [1-2] (Default: 1): " MODEL_CHOICE
        if [ "$MODEL_CHOICE" = "2" ]; then
            SELECTED_MODEL="$ALT_MODEL"
        else
            SELECTED_MODEL="$DEFAULT_MODEL"
        fi
    else
        SELECTED_MODEL="$DEFAULT_MODEL"
    fi
}

select_tier
select_models_for_tier

echo -e "\n${BOLD}${CYAN}[SELECTED CONFIGURATION]${NC}"
echo -e "  - Hardware Profile : ${GREEN}CPU (Non-GPU)${NC}"
echo -e "  - Selected Tier    : ${GREEN}Tier ${SELECTED_TIER}${NC}"
echo -e "  - Whisper STT Model: ${GREEN}${SELECTED_WHISPER} (int8 quantized)${NC}"
echo -e "  - Ollama LLM Model : ${GREEN}${SELECTED_MODEL}${NC}"

# ------------------------------------------------------------------------------
# Configure Strictly for CPU (.env Configuration)
# ------------------------------------------------------------------------------
set_env_key() {
    local key="$1"
    local value="$2"
    local file="$3"

    if grep -q "^${key}=" "$file" 2>/dev/null; then
        # Replace existing key in place
        sed -i.bak "s|^${key}=.*|${key}=${value}|" "$file" && rm -f "${file}.bak"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

configure_env() {
    local env_file=".env"
    log_info "Configuring environment variables in ${env_file} strictly for CPU..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would configure .env with:"
        echo "  HARDWARE_PROFILE=cpu"
        echo "  WHISPER_DEVICE=cpu"
        echo "  WHISPER_COMPUTE_TYPE=int8"
        echo "  WHISPER_CPU_FALLBACK=true"
        echo "  WHISPER_MODEL=${SELECTED_WHISPER}"
        echo "  OLLAMA_NUM_GPU=0"
        echo "  LLM_MODEL=${SELECTED_MODEL}"
        echo "  EMBED_MODEL=${SELECTED_MODEL}"
        echo "  OLLAMA_NUM_PARALLEL=1"
        return
    fi

    # Create .env from template if missing
    if [ ! -f "$env_file" ]; then
        if [ -f ".env.example" ]; then
            log_info "Copying initial .env from .env.example..."
            cp .env.example "$env_file"
        else
            log_info "Creating clean .env file..."
            touch "$env_file"
        fi
    fi

    # Apply strict CPU settings
    set_env_key "HARDWARE_PROFILE" "cpu" "$env_file"
    set_env_key "WHISPER_DEVICE" "cpu" "$env_file"
    set_env_key "WHISPER_COMPUTE_TYPE" "int8" "$env_file"
    set_env_key "WHISPER_CPU_FALLBACK" "true" "$env_file"
    set_env_key "WHISPER_MODEL" "${SELECTED_WHISPER}" "$env_file"
    set_env_key "OLLAMA_NUM_GPU" "0" "$env_file"
    set_env_key "LLM_MODEL" "${SELECTED_MODEL}" "$env_file"
    set_env_key "EMBED_MODEL" "${SELECTED_MODEL}" "$env_file"
    set_env_key "OLLAMA_KEEP_ALIVE" "24h" "$env_file"
    set_env_key "OLLAMA_NUM_PARALLEL" "1" "$env_file"

    log_ok "Successfully updated ${env_file} with CPU-optimized settings."
}

configure_env

# ------------------------------------------------------------------------------
# Setup TLS Certificates for Reverse Proxy
# ------------------------------------------------------------------------------
setup_tls_certificates() {
    local cert_dir="nginx/certs"
    local cert_file="${cert_dir}/server.crt"
    local key_file="${cert_dir}/server.key"

    if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
        log_ok "TLS certificates found in ${cert_dir}."
        return 0
    fi

    log_warn "TLS certificates missing. Generating self-signed certificates for local TLS..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would generate self-signed certificates in ${cert_dir}."
        return 0
    fi

    mkdir -p "$cert_dir"
    if command -v openssl &> /dev/null; then
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout "$key_file" -out "$cert_file" \
            -subj "/CN=voice-ai.local/O=Voice AI Engine/OU=AI Security" > /dev/null 2>&1
        log_ok "TLS certificates generated using host OpenSSL."
    elif [ "$DOCKER_AVAILABLE" = true ]; then
        docker run --rm -v "${PWD}/${cert_dir}:/certs" alpine/openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout /certs/server.key -out /certs/server.crt \
            -subj "/CN=voice-ai.local/O=Voice AI Engine/OU=AI Security" > /dev/null 2>&1
        log_ok "TLS certificates generated using Docker OpenSSL."
    else
        log_warn "Could not generate TLS certificates: neither OpenSSL nor Docker is available."
    fi
}

setup_tls_certificates

# ------------------------------------------------------------------------------
# Docker Compose Execution & Instructions
# ------------------------------------------------------------------------------
COMPOSE_CMD="docker compose -f docker-compose.yml -f docker-compose.cpu.yml up -d --build"

echo -e "\n${BOLD}${CYAN}================================================================${NC}"
echo -e "${BOLD}${GREEN}[INSTALLATION READY] Voice AI Engine CPU Environment Prepared${NC}"
echo -e "${BOLD}${CYAN}================================================================${NC}"
echo -e "To launch the full engine with standard CPU constraints, run:"
echo -e "  ${BOLD}${GREEN}${COMPOSE_CMD}${NC}\n"

if [ "$START_CONTAINERS" = true ]; then
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would execute: ${COMPOSE_CMD}"
    elif [ "$DOCKER_AVAILABLE" = true ] && [ "$DOCKER_COMPOSE_AVAILABLE" = true ]; then
        log_info "Executing Docker Compose CPU startup..."
        eval "$COMPOSE_CMD"
    else
        log_error "Cannot start containers: Docker or Docker Compose is not installed."
        exit 1
    fi
fi

exit 0

