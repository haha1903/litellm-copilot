"""Keep a fresh GitHub Copilot token in the env for the anthropic provider.

The proxy routes Claude requests to Copilot's native Anthropic endpoint via the
``anthropic/`` provider (config.yaml), which bypasses the github_copilot
provider's built-in token refresh. Copilot's short-lived token expires every
~30 min, so this callback refreshes ANTHROPIC_API_KEY from the long-lived OAuth
token (via the shared Authenticator) on a background timer and before each
request. The web-search agentic-loop follow-up reads the same env var, so it
stays valid too.
"""

import os
import threading
import time

from litellm.integrations.custom_logger import CustomLogger
from litellm.llms.github_copilot.authenticator import Authenticator

COPILOT_API_BASE = "https://api.githubcopilot.com"
REFRESH_INTERVAL_SECONDS = 900  # < Copilot's ~30 min token expiry


class CopilotAuth(CustomLogger):
    def __init__(self) -> None:
        super().__init__()
        self._auth = Authenticator()
        self._refresh()
        threading.Thread(target=self._loop, daemon=True).start()

    def _refresh(self) -> None:
        try:
            os.environ["ANTHROPIC_API_KEY"] = self._auth.get_api_key()
            os.environ["ANTHROPIC_API_BASE"] = COPILOT_API_BASE
        except Exception:  # noqa: BLE001 - never let a refresh failure crash the proxy
            pass

    def _loop(self) -> None:
        while True:
            time.sleep(REFRESH_INTERVAL_SECONDS)
            self._refresh()

    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        self._refresh()
        # Copilot requires `Authorization: Bearer <token>`, but the anthropic
        # provider sends a non-OAuth key as `x-api-key`. Inject the bearer
        # header (and Copilot's editor headers) explicitly so the request is
        # accepted; refreshed per request so the token never goes stale.
        token = os.environ.get("ANTHROPIC_API_KEY", "")
        headers = data.get("extra_headers") or {}
        headers["Authorization"] = f"Bearer {token}"
        headers.setdefault("Editor-Version", "vscode/1.96.0")
        headers.setdefault("Copilot-Integration-Id", "vscode-chat")
        data["extra_headers"] = headers
        return data


copilot_auth = CopilotAuth()
