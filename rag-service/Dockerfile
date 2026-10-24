# ==============================================================================
# RAG Context & Document Ingestion Microservice - Dockerfile
# Hardened according to CIS Docker Benchmark
# Target: Python 3.11 + FastAPI + pypdf + python-docx
# ==============================================================================

FROM voice-whisper-service:1.0.0

USER 0:0

# Copy local wheels for offline installation
COPY wheels/ /wheels/
RUN /opt/venv/bin/pip install --no-cache-dir /wheels/pypdf-*.whl /wheels/typing_extensions-*.whl || true && \
    rm -rf /wheels

# Prepare data storage directories with non-root ownership
RUN mkdir -p /app/data/markdown /tmp/rag_uploads && \
    chown -R 10001:10001 /app/data /tmp/rag_uploads && \
    chmod 1777 /tmp/rag_uploads

WORKDIR /app
COPY --chown=10001:10001 app/ /app/app/

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH="/app" \
    RAG_DATA_DIR="/app/data" \
    OLLAMA_URL="http://ollama-service:11434"

USER 10001:10001
EXPOSE 8090

HEALTHCHECK --interval=20s --timeout=5s --start-period=10s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8090/health').read()" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8090", "--workers", "1"]
