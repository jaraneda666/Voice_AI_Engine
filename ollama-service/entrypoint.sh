#!/usr/bin/env bash
# ==============================================================================
# Ollama Service Entrypoint Script
# Voice AI Engine - Private Clinical Speech & Medical NLP Subsystem
# Hardened non-root automation for startup and model pulling
# ==============================================================================

set -eo pipefail

MODEL_TO_PULL="${MODEL_NAME:-llama3.1:8b-instruct-q4_K_M}"
OLLAMA_HOST="${OLLAMA_HOST:-0.0.0.0:11434}"

echo "[INFO] [ollama-service] Iniciando demonio Ollama en segundo plano..."
echo "[INFO] [ollama-service] Modelo objetivo configurado: ${MODEL_TO_PULL}"

# Capture PID for graceful shutdown handling
ollama serve &
SERVER_PID=$!

cleanup() {
    echo "[INFO] [ollama-service] Recibida señal de detención. Terminando servidor Ollama (PID: ${SERVER_PID})..."
    kill -TERM "${SERVER_PID}" 2>/dev/null || true
    wait "${SERVER_PID}" 2>/dev/null || true
    echo "[INFO] [ollama-service] Servidor Ollama detenido correctamente."
    exit 0
}

trap cleanup SIGINT SIGTERM

# Esperar a que el servidor Ollama esté disponible
echo "[INFO] [ollama-service] Esperando que el servidor Ollama responda en ${OLLAMA_HOST}..."
MAX_RETRIES=30
RETRY_COUNT=0

until ollama list > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ "${RETRY_COUNT}" -ge "${MAX_RETRIES}" ]; then
        echo "[ERROR] [ollama-service] Tiempo de espera agotado al conectar con el servidor Ollama."
        exit 1
    fi
    sleep 2
done

echo "[INFO] [ollama-service] Servidor Ollama en línea y operativo."

# Verificar si el modelo configurado ya está disponible en almacenamiento persistente
echo "[INFO] [ollama-service] Verificando presencia del modelo: ${MODEL_TO_PULL}..."
if ollama list | grep -q "${MODEL_TO_PULL%%:*}"; then
    echo "[INFO] [ollama-service] El modelo ${MODEL_TO_PULL} ya se encuentra disponible localmente."
else
    echo "[INFO] [ollama-service] Modelo no encontrado. Iniciando descarga automática (ollama pull ${MODEL_TO_PULL})..."
    if ollama pull "${MODEL_TO_PULL}"; then
        echo "[INFO] [ollama-service] Descarga e inicialización de ${MODEL_TO_PULL} completada con éxito."
    else
        echo "[WARN] [ollama-service] Falló la descarga de ${MODEL_TO_PULL}. Verifique conectividad o volumen precalentado."
    fi
fi

# Mantener proceso vivo en foreground respondiendo a señales
echo "[INFO] [ollama-service] Subsistema Ollama listo para recibir solicitudes de estructuración clínica."
wait "${SERVER_PID}"
