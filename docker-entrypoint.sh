#!/bin/sh
# Custom entrypoint: bridge env-injected GitHub Copilot token into the file the
# LiteLLM github_copilot provider expects, then hand off to LiteLLM's own
# entrypoint.
#
# Why: the github_copilot provider reads a long-lived OAuth token from
# $GITHUB_COPILOT_TOKEN_DIR/access-token and auto-derives/refreshes the
# short-lived Copilot API key (api-key.json) from it. In a non-interactive
# deployment (ACA) there's no device flow, so we inject the long-lived token
# via the GH_COPILOT_TOKEN env var and write it to that file at startup.
set -e

mkdir -p "$GITHUB_COPILOT_TOKEN_DIR"

if [ -n "$GH_COPILOT_TOKEN" ]; then
  printf '%s' "$GH_COPILOT_TOKEN" > "$GITHUB_COPILOT_TOKEN_DIR/access-token"
else
  echo "WARNING: GH_COPILOT_TOKEN is not set — github_copilot requests will fail until a token is provided." >&2
fi

# Hand off to LiteLLM's production entrypoint, passing through the CMD
# (--config / --port). Path is relative to WORKDIR /app in the base image.
exec docker/prod_entrypoint.sh "$@"
