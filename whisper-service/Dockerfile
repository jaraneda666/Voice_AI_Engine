# syntax=docker/dockerfile:1.4
# ==============================================================================
# Whisper Transcription Microservice - Multi-stage Dockerfile
# Hardened according to CIS Docker Benchmark
# Target: Python 3.11 + faster-whisper (CTranslate2)
# ==============================================================================

# ------------------------------------------------------------------------------
# Stage 1: Build Dependencies
# ------------------------------------------------------------------------------
FROM python:3.11-slim-bookworm AS builder

WORKDIR /build

# Install compilation essentials if needed for wheels
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Create virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
RUN pip install --no-cache-dir --retries 5 --timeout 30 \
    --index-url https://pypi.org/simple \
    --extra-index-url https://mirrors.aliyun.com/pypi/simple/ \
    -r requirements.txt

# ------------------------------------------------------------------------------
# Stage 2: Runtime Image (Hardened & Rootless)
# ------------------------------------------------------------------------------
FROM python:3.11-slim-bookworm AS runner

# CIS Benchmark: Install only strictly needed runtime tools (ffmpeg for audio)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Remove dangerous/unnecessary setuid/setgid binaries to prevent privilege escalation
RUN find / -xdev -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true

# CIS Benchmark: Dedicated non-root user and group (10001:10001)
RUN groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -s /sbin/nologin -d /app appuser

# Create required application directories and assign ownership
RUN mkdir -p /app /tmp/audio_ram /app/.cache /models && \
    chown -R 10001:10001 /app /tmp/audio_ram /app/.cache /models && \
    chmod 1777 /tmp && \
    chmod 1700 /tmp/audio_ram

# Copy virtual environment from builder stage
COPY --from=builder --chown=10001:10001 /opt/venv /opt/venv

WORKDIR /app

# Copy application source code with restricted permissions
COPY --chown=10001:10001 app/ /app/app/

# Environment configuration
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH="/app" \
    HF_HOME="/models" \
    TMPDIR="/tmp" \
    AUDIO_RAM_DIR="/tmp/audio_ram"

# CIS Benchmark: Execute as non-root user
USER 10001:10001

# Expose internal service port
EXPOSE 8000

# Healthcheck validating internal service availability
HEALTHCHECK --interval=20s --timeout=5s --start-period=30s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health').read()" || exit 1

# Launch FastAPI via uvicorn
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
