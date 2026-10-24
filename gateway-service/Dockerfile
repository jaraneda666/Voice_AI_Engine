# ==============================================================================
# AI API Gateway Microservice - Multi-stage Dockerfile
# Hardened according to CIS Docker Benchmark v1.6.0
# Target: Python 3.11 + FastAPI Internal Orchestrator
# Portability: Dual index fallback for environments with DNS/CDN sinkholes
# ==============================================================================

# ------------------------------------------------------------------------------
# Stage 1: Build Dependencies
# ------------------------------------------------------------------------------
FROM python:3.11-slim-bookworm AS builder

WORKDIR /build

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
RUN pip install --no-cache-dir --retries 5 --timeout 20 \
    --index-url https://pypi.org/simple \
    --extra-index-url https://mirrors.aliyun.com/pypi/simple/ \
    -r requirements.txt

# ------------------------------------------------------------------------------
# Stage 2: Runtime Image (Hardened & Rootless)
# ------------------------------------------------------------------------------
FROM python:3.11-slim-bookworm AS runner

# Remove dangerous/unnecessary setuid/setgid binaries to prevent privilege escalation
RUN find / -xdev -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true

# CIS Benchmark: Dedicated non-root user and group (10001:10001)
RUN groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -s /sbin/nologin -d /app appuser

# Create required application directory and assign ownership
RUN mkdir -p /app && \
    chown -R 10001:10001 /app && \
    chmod 1777 /tmp

# Copy virtual environment from builder stage
COPY --from=builder --chown=10001:10001 /opt/venv /opt/venv

WORKDIR /app

# Copy application core logic
COPY --chown=10001:10001 core/ /app/core/

# Environment configuration for internal service routing
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH="/app" \
    WHISPER_URL="http://whisper-service:8000" \
    OLLAMA_URL="http://ollama-service:11434" \
    RAG_URL="http://rag-service:8090"

USER 10001:10001
EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health').read()" || exit 1

CMD ["uvicorn", "core.engine_api:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "2"]
