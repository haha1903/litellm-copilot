# LiteLLM proxy that exposes a GitHub Copilot subscription as an
# Anthropic-compatible API (/v1/messages) for Claude Code and similar tools.
#
# Routes Claude requests to Copilot's native Anthropic endpoint (see config.yaml)
# so PDF document blocks pass through. Runs on the stock LiteLLM image.
#
# Adds:
#   - config.yaml          : model mapping to the anthropic provider @ Copilot
#   - copilot_auth.py      : callback that keeps a fresh Copilot bearer token in env
#   - docker-entrypoint.sh : injects the Copilot OAuth token from env at startup
FROM ghcr.io/berriai/litellm:main-stable

WORKDIR /app

COPY config.yaml /app/config.yaml
COPY copilot_auth.py /app/copilot_auth.py
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

# Where the Authenticator reads the long-lived OAuth token and caches the
# short-lived API key. PYTHONPATH lets LiteLLM import the copilot_auth callback.
ENV GITHUB_COPILOT_TOKEN_DIR=/app/copilot-creds
ENV PYTHONPATH=/app

EXPOSE 4000

ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["--config", "/app/config.yaml", "--port", "4000"]
