# LiteLLM proxy that exposes a GitHub Copilot subscription as an
# Anthropic-compatible API (/v1/messages) for Claude Code and similar tools.
#
# Derives from the official LiteLLM image and adds:
#   - config.yaml          : Claude Code model-name -> github_copilot mapping
#   - docker-entrypoint.sh : injects the Copilot OAuth token from env at startup
FROM ghcr.io/berriai/litellm:main-stable

WORKDIR /app

COPY config.yaml /app/config.yaml
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

# Where the github_copilot provider reads/writes its token + derived API key.
ENV GITHUB_COPILOT_TOKEN_DIR=/app/copilot-creds

EXPOSE 4000

ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["--config", "/app/config.yaml", "--port", "4000"]
