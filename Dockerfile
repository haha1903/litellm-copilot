# LiteLLM proxy that exposes a GitHub Copilot subscription as an
# Anthropic-compatible API (/v1/messages) for Claude Code and similar tools.
#
# Routes Claude requests through the github_copilot provider directly via
# GithubCopilotMessagesConfig (see config.yaml) — the provider injects the
# Copilot bearer token itself, so there is no copilot_auth.py callback.
#
# Base (ghcr.io/haha1903/litellm:v0.3.0, branch build-image) carries both the
# native GithubCopilotMessagesConfig and the agentic-loop web_search
# server_tool_use fix. docker-entrypoint.sh writes GH_COPILOT_TOKEN into the
# file the Authenticator reads ($GITHUB_COPILOT_TOKEN_DIR/access-token) at
# startup.
FROM ghcr.io/haha1903/litellm:v0.3.0

WORKDIR /app

COPY config.yaml /app/config.yaml
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

# Where the github_copilot Authenticator reads the long-lived OAuth token and
# caches the short-lived API key.
ENV GITHUB_COPILOT_TOKEN_DIR=/app/copilot-creds

# Use the bundled anthropic-beta headers config (which aliases github_copilot ->
# anthropic) instead of fetching it remotely. The beta-header filter drops any
# header for a provider not in the config; without this the remote config (no
# github_copilot entry) would strip anthropic-beta: context-management-* and the
# Copilot backend would 400 on context_management requests from Claude Code.
ENV LITELLM_LOCAL_ANTHROPIC_BETA_HEADERS=True

EXPOSE 4000

ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["--config", "/app/config.yaml", "--port", "4000"]
