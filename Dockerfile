# LiteLLM proxy that exposes a GitHub Copilot subscription as an
# Anthropic-compatible API (/v1/messages) for Claude Code and similar tools.
#
# Routes Claude requests through the github_copilot provider directly via
# GithubCopilotMessagesConfig (see config.yaml) — the provider injects the
# Copilot bearer token itself, so there is no copilot_auth.py callback.
#
# Base carries GithubCopilotMessagesConfig (ghcr.io/haha1903/litellm, branch
# feat/native-messages-provider). docker-entrypoint.sh writes GH_COPILOT_TOKEN
# into the file the Authenticator reads ($GITHUB_COPILOT_TOKEN_DIR/access-token)
# at startup.
FROM ghcr.io/haha1903/litellm:native-test

WORKDIR /app

COPY config.yaml /app/config.yaml
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

# Where the github_copilot Authenticator reads the long-lived OAuth token and
# caches the short-lived API key.
ENV GITHUB_COPILOT_TOKEN_DIR=/app/copilot-creds

EXPOSE 4000

ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["--config", "/app/config.yaml", "--port", "4000"]
