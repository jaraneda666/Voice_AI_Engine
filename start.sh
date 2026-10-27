#!/usr/bin/env bash
# ==============================================================================
# Voice_AI_Engine - Startup Script Multiplataforma (Linux & macOS)
# Automatic Environment & Hardware Detection (NVIDIA GPU vs CPU)
# Multi-arch compatible: x86_64 and ARM64 (Apple Silicon M1/M2/M3/M4)
# ==============================================================================

set -eo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m'

echo -e "${BOLD}${CYAN}================================================================${NC}"
echo -e "${BOLD}${CYAN}         Voice AI Engine - Iniciador Inteligente Multiplataforma${NC}"
echo -e "${BOLD}${CYAN}================================================================${NC}"

# 1. Verificar presencia de Docker y Docker Compose
if ! command -v docker &> /dev/null; then
    echo -e "${RED}[ERROR] Docker no se encuentra instalado o no está en el PATH.${NC}"
    echo "Instale Docker desde https://docs.docker.com/get-docker/ e intente nuevamente."
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo -e "${RED}[ERROR] Docker Compose v2 no se encuentra disponible.${NC}"
    exit 1
fi

# 2. Configurar archivo .env base si no existe
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        echo -e "${YELLOW}[INFO] Archivo .env no detectado. Creando plantilla desde .env.example...${NC}"
        cp .env.example .env
    else
        echo -e "${YELLOW}[WARN] No se encontró .env ni .env.example. Se utilizarán valores por defecto de docker-compose.yml.${NC}"
    fi
fi

# 3. Verificar o generar certificados SSL para Nginx si faltan
if [ ! -f "nginx/certs/server.crt" ] || [ ! -f "nginx/certs/server.key" ]; then
    echo -e "${YELLOW}[INFO] Certificados TLS no encontrados en nginx/certs/. Generando certificados autofirmados...${NC}"
    mkdir -p nginx/certs
    if command -v openssl &> /dev/null; then
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout nginx/certs/server.key -out nginx/certs/server.crt \
            -subj "/CN=voice-ai.local/O=Voice AI Engine/OU=AI Security" > /dev/null 2>&1
    else
        docker run --rm -v "${PWD}/nginx/certs:/certs" alpine/openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout /certs/server.key -out /certs/server.crt \
            -subj "/CN=voice-ai.local/O=Voice AI Engine/OU=AI Security" > /dev/null 2>&1
    fi
    echo -e "${GREEN}[OK] Certificados generados correctamente.${NC}"
fi

# 4. Parámetros manuales
USE_CPU=false
FORCE_GPU=false
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --cpu)
            USE_CPU=true
            ;;
        --force-gpu)
            FORCE_GPU=true
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
    esac
done

# 5. Detección Exhaustiva de Hardware y Recursos
echo -e "\n${BOLD}${CYAN}[INFO] Analizando arquitectura y especificaciones del equipo...${NC}"

OS_TYPE="$(uname -s)"
ARCH_TYPE="$(uname -m)"

# A. Memoria RAM del Host
HOST_RAM_GB="Desconocido"
if [ "$OS_TYPE" == "Darwin" ]; then
    if command -v sysctl &> /dev/null; then
        MEM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
        if [ "$MEM_BYTES" -gt 0 ]; then
            HOST_RAM_GB=$(awk "BEGIN {printf \"%.1f\", $MEM_BYTES/1073741824}")
        fi
    fi
elif [ -f /proc/meminfo ]; then
    MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    if [ -n "$MEM_KB" ]; then
        HOST_RAM_GB=$(awk "BEGIN {printf \"%.1f\", $MEM_KB/1048576}")
    fi
fi

# B. Recursos Docker
DOCKER_RAM_GB="Desconocido"
DOCKER_CPUS=$(docker info --format '{{.NCPU}}' 2>/dev/null || echo "N/A")
DOCKER_MEM_BYTES=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
if [ -n "$DOCKER_MEM_BYTES" ] && [ "$DOCKER_MEM_BYTES" -gt 0 ] 2>/dev/null; then
    DOCKER_RAM_GB=$(awk "BEGIN {printf \"%.1f\", $DOCKER_MEM_BYTES/1073741824}")
fi

# C. Detección de GPU NVIDIA y VRAM
GPU_DETECTED=false
GPU_NAME="Ninguna GPU NVIDIA compatible detectada"
VRAM_MB=0
VRAM_GB=0

if command -v nvidia-smi &> /dev/null; then
    SMI_LINE=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>/dev/null | head -n 1 || true)
    if [ -n "$SMI_LINE" ]; then
        GPU_NAME=$(echo "$SMI_LINE" | cut -d',' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        VRAM_MB=$(echo "$SMI_LINE" | cut -d',' -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -cd '0-9')
        if [ -n "$VRAM_MB" ] && [ "$VRAM_MB" -gt 0 ]; then
            VRAM_GB=$(awk "BEGIN {printf \"%.1f\", $VRAM_MB/1024}")
            GPU_DETECTED=true
        fi
    fi
fi

# D. Soporte Docker NVIDIA
DOCKER_NVIDIA_SUPPORT=false
if docker info 2>/dev/null | grep -Eiq "(nvidia|cdi: docker.com/gpu)"; then
    DOCKER_NVIDIA_SUPPORT=true
    DOCKER_GPU_STATUS="Activo / Compatible"
else
    DOCKER_GPU_STATUS="No disponible en Docker"
fi

# 6. Matriz Inteligente de Decisión y Recomendación
MIN_VRAM_GB=6.0
DECISION_REASON=""
RECOMMENDATION_DETAILS=""

if [ "$USE_CPU" = true ]; then
    DECISION_REASON="Modo forzado manualmente por el usuario mediante parámetro --cpu."
    RECOMMENDATION_DETAILS="Ejecución 100% CPU."
elif [ "$OS_TYPE" == "Darwin" ]; then
    USE_CPU=true
    DECISION_REASON="macOS detectado (${ARCH_TYPE}). Docker Desktop en macOS no admite aceleración NVIDIA CUDA."
    RECOMMENDATION_DETAILS="Perfil universal CPU optimizado activado (compatible con Apple Silicon e Intel)."
elif [ "$GPU_DETECTED" = false ]; then
    USE_CPU=true
    DECISION_REASON="No se detectó GPU NVIDIA ni comando nvidia-smi en el sistema host."
    RECOMMENDATION_DETAILS="Perfil universal CPU (int8) activado automáticamente."
elif [ "$DOCKER_NVIDIA_SUPPORT" = false ]; then
    USE_CPU=true
    DECISION_REASON="GPU detectada (${GPU_NAME}), pero Docker no cuenta con NVIDIA Container Toolkit activo."
    RECOMMENDATION_DETAILS="Perfil seguro CPU activado para prevenir excepciones en el daemon Docker."
elif awk "BEGIN {exit !($VRAM_GB < $MIN_VRAM_GB)}"; then
    if [ "$FORCE_GPU" = true ]; then
        USE_CPU=false
        DECISION_REASON="GPU forzada por parámetro --force-gpu a pesar de contar con ${VRAM_GB} GB VRAM."
        RECOMMENDATION_DETAILS="ADVERTENCIA: Podrían ocurrir desbordamientos de memoria VRAM (CUDA OOM) con modelos grandes."
    else
        USE_CPU=true
        DECISION_REASON="GPU detectada (${GPU_NAME}) dispone de ${VRAM_GB} GB VRAM (Mínimo recomendado: ${MIN_VRAM_GB} GB)."
        RECOMMENDATION_DETAILS="Para evitar caídas por falta de memoria de video (CUDA OOM) al cargar Whisper Large y Llama 3.1 8B, se recomienda y activa automáticamente el perfil 100% CPU optimizado (int8)."
    fi
else
    USE_CPU=false
    DECISION_REASON="GPU NVIDIA (${GPU_NAME}) con ${VRAM_GB} GB VRAM y soporte Docker verificado."
    RECOMMENDATION_DETAILS="Aceleración completa por GPU (CUDA/cuDNN) activada."
fi

# 7. Panel Visual Informativo
echo -e ""
echo -e "${CYAN}+------------------------------------------------------------------------+${NC}"
echo -e "${CYAN}|                DIAGNOSTICO AUTOMATICO DE HARDWARE                      |${NC}"
echo -e "${CYAN}+------------------------------------------------------------------------+${NC}"
echo -e "  * Sistema Operativo:       ${OS_TYPE} (${ARCH_TYPE})"
echo -e "  * Memoria RAM Host:        ${HOST_RAM_GB} GB"
echo -e "  * Recursos Docker:         ${DOCKER_RAM_GB} GB RAM | ${DOCKER_CPUS} vCPUs"
if [ "$GPU_DETECTED" = true ]; then
    echo -e "  * GPU Detectada:           ${GPU_NAME}"
    echo -e "  * Memoria VRAM GPU:        ${VRAM_GB} GB (${VRAM_MB} MB)"
    echo -e "  * Soporte Docker GPU:      ${DOCKER_GPU_STATUS}"
else
    echo -e "  * GPU Detectada:           Ninguna GPU NVIDIA compatible"
fi
echo -e "${CYAN}+------------------------------------------------------------------------+${NC}"
echo -e "${CYAN}|                PERFIL SELECCIONADO Y RECOMENDACION                     |${NC}"
echo -e "${CYAN}+------------------------------------------------------------------------+${NC}"
if [ "$USE_CPU" = true ]; then
    echo -e "  * MODO SELECCIONADO:       ${YELLOW}[ PERFIL 100% CPU OPTIMIZADO ]${NC}"
else
    echo -e "  * MODO SELECCIONADO:       ${GREEN}[ PERFIL ACELERACION GPU (CUDA) ]${NC}"
fi
echo -e "  * Causa / Diagnóstico:     ${GRAY}${DECISION_REASON}${NC}"
echo -e "  * Recomendación Técnica:   ${GRAY}${RECOMMENDATION_DETAILS}${NC}"
echo -e "${CYAN}+------------------------------------------------------------------------+${NC}"

# 8. Ejecución del Despliegue con Docker Compose
if [ "$USE_CPU" = true ]; then
    COMPOSE_CMD="docker compose -f docker-compose.yml -f docker-compose.cpu.yml"
else
    COMPOSE_CMD="docker compose -f docker-compose.yml"
fi

if [ "$DRY_RUN" = true ]; then
    echo -e "\n${CYAN}[DRY RUN] Diagnóstico finalizado sin iniciar contenedores.${NC}"
    echo -e "Comando resultante que se ejecutará:"
    echo -e "  ${YELLOW}${COMPOSE_CMD} up -d --build${NC}"
    exit 0
fi

echo -e "\n${BOLD}${CYAN}[INFO] Construyendo e iniciando contenedores en segundo plano...${NC}"
echo -e "${YELLOW}${COMPOSE_CMD} up -d --build${NC}\n"

${COMPOSE_CMD} up -d --build

# 9. Resumen de Servicios
echo -e "\n${BOLD}${GREEN}================================================================${NC}"
echo -e "${BOLD}${GREEN}         Voice AI Engine iniciado exitosamente                  ${NC}"
echo -e "${BOLD}${GREEN}================================================================${NC}"
echo -e "* Puerta de Enlace Segura (HTTPS): ${BOLD}https://localhost:8443${NC}"
echo -e "* Módulo RAG & Ingesta Documental: ${BOLD}https://localhost:8443/rag/ui${NC}"
echo -e "* Healthcheck General:             ${BOLD}https://localhost:8443/proxy-health${NC}"
echo -e "* Panel Bastionado Portainer:      ${BOLD}https://localhost:9443${NC}"
echo -e "* Red de Contenedores Interna:     ${BOLD}voice-ai-net (Aislamiento Total)${NC}"
echo -e "\nPara consultar logs en tiempo real:"
echo -e "  ${YELLOW}${COMPOSE_CMD} logs -f${NC}\n"
