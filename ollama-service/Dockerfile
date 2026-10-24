# ==============================================================================
# Ollama LLM Service - Hardened Dockerfile
# Hardened according to CIS Docker Benchmark
# Target: Non-root execution (10001:10001) with read-only rootfs compatibility
# ==============================================================================

FROM ollama/ollama:latest

# CIS Benchmark: Create dedicated non-root user and directories
RUN useradd -u 10001 -U -d /home/ollama -s /bin/bash ollama && \
    mkdir -p /home/ollama/.ollama /prompts && \
    chown -R 10001:10001 /home/ollama /prompts

# Copy entrypoint and clinical prompts
COPY --chown=10001:10001 entrypoint.sh /entrypoint.sh
COPY --chown=10001:10001 prompts/ /prompts/

RUN chmod 0755 /entrypoint.sh

# Remove unnecessary setuid/setgid binaries
RUN find / -xdev -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true

# Environment configuration for non-root home & models
ENV HOME=/home/ollama \
    OLLAMA_MODELS=/home/ollama/.ollama/models \
    OLLAMA_HOST=0.0.0.0:11434

# CIS Benchmark: Run as non-root user
USER 10001:10001
WORKDIR /home/ollama

EXPOSE 11434

HEALTHCHECK --interval=25s --timeout=10s --start-period=60s --retries=5 \
    CMD ollama list > /dev/null 2>&1 || exit 1

ENTRYPOINT ["/entrypoint.sh"]
