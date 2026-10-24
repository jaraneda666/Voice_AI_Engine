#!/usr/bin/env bash
# ==============================================================================
# Voice_AI_Engine - Startup Script (Linux & macOS)
# Automatic Environment & Hardware Detection (NVIDIA GPU vs CPU)
# Multi-arch compatible: x86_64 and ARM64 (Apple Silicon M1/M2/M3/M4)
# ==============================================================================

set -eo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}================================================================${NC}"
echo -e "${BOLD}${BLUE}         Voice AI Engine - Iniciador Multiplataforma            ${NC}"
echo -e "${BOLD}${BLUE}================================================================${NC}"

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

# 4. Detección de Sistema Operativo y Aceleración de Hardware (GPU vs CPU)
OS_TYPE="$(uname -s)"
ARCH_TYPE="$(uname -m)"
USE_CPU=false

# Parámetro manual --cpu
for arg in "$@"; do
    if [ "$arg" == "--cpu" ]; then
        USE_CPU=true
    fi
done

if [ "$USE_CPU" = true ]; then
    echo -e "${YELLOW}[CONFIG] Modo forzado por usuario: Ejecución 100% CPU.${NC}"
elif [ "$OS_TYPE" == "Darwin" ]; then
    echo -e "${YELLOW}[INFO] macOS detectado (${ARCH_TYPE}). Docker Desktop en macOS no soporta GPU NVIDIA.${NC}"
    echo -e "${YELLOW}[INFO] Activando perfil optimizado 100% CPU (compatible con Apple Silicon e Intel).${NC}"
    USE_CPU=true
elif ! command -v nvidia-smi &> /dev/null; then
    echo -e "${YELLOW}[INFO] No se detectó utilitario nvidia-smi en el sistema host.${NC}"
    echo -e "${YELLOW}[INFO] Activando perfil optimizado 100% CPU.${NC}"
    USE_CPU=true
elif ! docker info 2>/dev/null | grep -iq "nvidia"; then
    echo -e "${YELLOW}[INFO] GPU NVIDIA detectada, pero Docker no tiene configurado el NVIDIA Container Toolkit.${NC}"
    echo -e "${YELLOW}[INFO] Activando perfil seguro 100% CPU para prevenir fallos de inicio.${NC}"
    USE_CPU=true
else
    echo -e "${GREEN}[INFO] Entorno Linux con GPU NVIDIA y runtime oficial detectado.${NC}"
    echo -e "${GREEN}[INFO] Activando perfil de aceleración por GPU (CUDA/cuDNN).${NC}"
fi

# 5. Ejecución del Despliegue con Docker Compose
if [ "$USE_CPU" = true ]; then
    COMPOSE_CMD="docker compose -f docker-compose.yml -f docker-compose.cpu.yml"
else
    COMPOSE_CMD="docker compose -f docker-compose.yml"
fi

echo -e "\n${BOLD}${BLUE}[INFO] Construyendo e iniciando contenedores en segundo plano...${NC}"
echo -e "${YELLOW}Comando: ${COMPOSE_CMD} up -d --build${NC}\n"

${COMPOSE_CMD} up -d --build

# 6. Resumen de Servicios y Verificación
echo -e "\n${BOLD}${GREEN}================================================================${NC}"
echo -e "${BOLD}${GREEN}         Voice AI Engine iniciado exitosamente                  ${NC}"
echo -e "${BOLD}${GREEN}================================================================${NC}"
echo -e "• Puerta de Enlace Segura (HTTPS): ${BOLD}https://localhost:8443${NC}"
echo -e "• Módulo RAG & Ingesta Documental: ${BOLD}https://localhost:8443/rag/ui${NC}"
echo -e "• Healthcheck General:             ${BOLD}https://localhost:8443/proxy-health${NC}"
echo -e "• Panel Bastionado Portainer:      ${BOLD}https://localhost:9443${NC}"
echo -e "• Red de Contenedores Interna:     ${BOLD}voice-ai-net (Aislamiento Total)${NC}"
echo -e "\nPara consultar logs en tiempo real:"
echo -e "  ${YELLOW}${COMPOSE_CMD} logs -f${NC}\n"
