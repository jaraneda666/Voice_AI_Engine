# ==============================================================================
# AI API Gateway Microservice - Dockerfile
# Inherits hardened base and venv from voice-whisper-service:1.0.0 (Zero network overhead)
# Target: Python 3.11 + FastAPI Internal Orchestrator
# ==============================================================================

FROM voice-whisper-service:1.0.0

WORKDIR /app

# Copy application core logic
COPY --chown=10001:10001 core/ /app/core/

# Environment configuration for internal service routing
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH="/app" \
    WHISPER_URL="http://whisper-service:8000" \
    OLLAMA_URL="http://ollama-service:11434"

USER 10001:10001
EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health').read()" || exit 1

CMD ["uvicorn", "core.engine_api:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "2"]
