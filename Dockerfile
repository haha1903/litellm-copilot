# LiteLLM proxy that exposes a GitHub Copilot subscription as an
# Anthropic-compatible API (/v1/messages) for Claude Code and similar tools.
#
# Uses a patched LiteLLM image (ghcr.io/haha1903/litellm) that fixes web search
# returning empty results for native web_search_* clients like Claude Code.
# See https://github.com/haha1903/litellm — branch fix/websearch-native-block-detection.
# Revert to ghcr.io/berriai/litellm:main-stable once that fix is upstream.
#
# Adds:
#   - config.yaml          : Claude Code model-name -> github_copilot mapping
#   - docker-entrypoint.sh : injects the Copilot OAuth token from env at startup
FROM ghcr.io/haha1903/litellm:patched-latest

WORKDIR /app

COPY config.yaml /app/config.yaml
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

# Where the github_copilot provider reads/writes its token + derived API key.
ENV GITHUB_COPILOT_TOKEN_DIR=/app/copilot-creds

EXPOSE 4000

ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["--config", "/app/config.yaml", "--port", "4000"]
