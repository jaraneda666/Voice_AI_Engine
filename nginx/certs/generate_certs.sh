#!/usr/bin/env bash
# Generador de certificados TLS para entornos Linux / Docker
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEY_PATH="${SCRIPT_DIR}/server.key"
CRT_PATH="${SCRIPT_DIR}/server.crt"

if [[ -f "${KEY_PATH}" && -f "${CRT_PATH}" ]]; then
    echo "[INFO] Certificados TLS ya existen en ${SCRIPT_DIR}."
    exit 0
fi

echo "[INFO] Generando par de claves TLS autofirmadas..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "${KEY_PATH}" \
    -out "${CRT_PATH}" \
    -subj "/CN=voice-ai.local/O=TalitaKum/OU=IA-OnPremise"

chmod 600 "${KEY_PATH}"
chmod 644 "${CRT_PATH}"
echo "[OK] Certificados generados en ${SCRIPT_DIR}."
