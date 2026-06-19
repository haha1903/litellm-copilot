# litellm-copilot

A [LiteLLM](https://github.com/BerriAI/litellm) proxy that exposes a **GitHub Copilot** subscription as an **Anthropic-compatible API** (`/v1/messages`), so tools like **Claude Code** can run on your Copilot models.

It maps Claude Code's model names (`claude-opus-4.8`, `claude-sonnet-4.6`, `claude-haiku-4.5`, including the `[1m]` long-context tag) to the equivalent Copilot backend models, and translates Anthropic Messages requests/streaming to and from the `github_copilot` provider.

Built on the official `ghcr.io/berriai/litellm` image. Designed to run on Azure Container Apps (ACA) or any container host.

---

## How auth works (read this first)

GitHub Copilot uses two tokens:

| Token | What | Lifetime | Who manages it |
|---|---|---|---|
| **Long-lived OAuth token** (`ghu_...`) | GitHub device-flow token | Months / until revoked | **You** — obtain offline once, inject via env |
| Short-lived Copilot API key (`tid=...`) | Per-session Copilot key | ~30 min | **LiteLLM** — auto-derived & refreshed from the long-lived token |

You only ever provide the **long-lived `ghu_...` token**. The container writes it to the file LiteLLM expects, and LiteLLM handles the rest (derives and refreshes the short-lived key automatically — no interactive login needed at runtime).

---

## Step 1 — get your long-lived Copilot token (offline, one-time)

Run the GitHub device flow locally with a Python env that has LiteLLM installed:

```bash
# isolated env (any Python 3.11–3.13)
python3 -m venv /tmp/llc && /tmp/llc/bin/pip install 'litellm[proxy]'

export GITHUB_COPILOT_TOKEN_DIR=/tmp/copilot-creds
mkdir -p "$GITHUB_COPILOT_TOKEN_DIR"

# Triggers the device flow: prints a URL + code, blocks until you authorize.
/tmp/llc/bin/python - <<'PY'
import litellm
litellm.set_verbose = True
litellm.completion(
    model="github_copilot/gpt-4o",
    messages=[{"role": "user", "content": "ping"}],
    extra_headers={"Editor-Version": "vscode/1.96.0", "Copilot-Integration-Id": "vscode-chat"},
)
PY
```

It prints something like `Please visit https://github.com/login/device and enter code XXXX-XXXX`. Authorize with the GitHub account that has Copilot access. When it returns, your token is in:

```bash
cat /tmp/copilot-creds/access-token   # -> ghu_xxxxxxxxxxxxxxxxxxxx
```

Keep that `ghu_...` value — it's the `GH_COPILOT_TOKEN` you'll configure in ACA.

> **A paid GitHub Copilot subscription is required.**

---

## Step 2 — pick a master key

The proxy is access-controlled by a master key (so a public ACA URL can't be used by strangers to burn your Copilot quota). Pick any secret that **starts with `sk-`**:

```bash
echo "sk-$(openssl rand -hex 24)"   # e.g. sk-9f3c... — save this
```

Clients send this as their Anthropic auth token.

---

## Step 3 — deploy to Azure Container Apps

The image is published to `ghcr.io/haha1903/litellm-copilot` (public — no registry credentials needed).

```bash
RG=litellm-copilot-rg
ENV=litellm-copilot-env
APP=litellm-copilot
LOCATION=southeastasia

az group create -n "$RG" -l "$LOCATION"
az containerapp env create -n "$ENV" -g "$RG" -l "$LOCATION"

az containerapp create \
  -n "$APP" -g "$RG" --environment "$ENV" \
  --image ghcr.io/haha1903/litellm-copilot:latest \
  --target-port 4000 --ingress external \
  --min-replicas 1 --max-replicas 1 \
  --secrets gh-copilot-token="ghu_REPLACE_ME" master-key="sk-REPLACE_ME" \
  --env-vars \
    GH_COPILOT_TOKEN=secretref:gh-copilot-token \
    LITELLM_MASTER_KEY=secretref:master-key
```

- `GH_COPILOT_TOKEN` — the `ghu_...` from Step 1
- `LITELLM_MASTER_KEY` — the `sk-...` from Step 2
- `--min-replicas 1` keeps it warm so the short-lived Copilot key stays refreshed (scale-to-zero would cold-start each time, which still works but adds latency)

Get the URL:

```bash
az containerapp show -n "$APP" -g "$RG" --query properties.configuration.ingress.fqdn -o tsv
```

> Health probe endpoint (if you configure one): `GET /health/liveliness` on port 4000.

---

## Step 4 — point Claude Code at it

```bash
export ANTHROPIC_BASE_URL="https://<your-aca-fqdn>"
export ANTHROPIC_AUTH_TOKEN="sk-..."   # the master key from Step 2
claude
```

That's it — Claude Code now runs on your Copilot subscription.

---

## Available models

The Copilot backend currently exposes these Claude models (all but the 4.5-tier are 1M context):

| Model | Context |
|---|---|
| `claude-opus-4.8`, `claude-opus-4.7`, `claude-opus-4.6` | 1M |
| `claude-sonnet-4.6` | 1M |
| `claude-opus-4.5`, `claude-sonnet-4.5` | 200K |
| `claude-haiku-4.5` | 200K |

Each model is mapped explicitly in `config.yaml` (both the dotted name Claude Code displays and the dash form it sometimes sends). To support a new model, add a `model_list` entry pointing its name at the matching `github_copilot/<name>` backend.

---

## Web search (optional)

The GitHub Copilot backend can't run Anthropic's native `web_search` server tool. To make web search work in Claude Code anyway, this proxy uses LiteLLM's built-in **`websearch_interception`**: when Claude Code sends a `web_search` tool, the proxy runs the search server-side via **Brave** (primary) or **Tavily** (fallback), feeds the results back to the model, and returns the answer.

Enable it by setting either or both API keys as env vars (no config change needed — `config.yaml` already wires up both providers):

```bash
BRAVE_API_KEY=...     # primary
TAVILY_API_KEY=...    # fallback
```

On ACA, add them the same way as the other secrets:

```bash
az containerapp update -n litellm-copilot -g <rg> \
  --set-env-vars BRAVE_API_KEY=secretref:brave-key TAVILY_API_KEY=secretref:tavily-key \
  --secrets brave-key="..." tavily-key="..."
```

If neither key is set, web search requests fall back to the model answering without search (no error).

> **Behavior note:** this is a real server-side agentic loop — the search result is sent back through the Copilot model to compose the final answer, so a web-search turn costs one extra model round-trip. Results are returned as text rather than Claude's native citation cards.

---

## Run locally (Docker)

```bash
docker build -t litellm-copilot .
docker run --rm -p 4000:4000 \
  -e GH_COPILOT_TOKEN="ghu_..." \
  -e LITELLM_MASTER_KEY="sk-test" \
  litellm-copilot

# verify
curl -s http://localhost:4000/health/liveliness
curl -s http://localhost:4000/v1/messages \
  -H "x-api-key: sk-test" -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"claude-sonnet-4.6","max_tokens":32,"messages":[{"role":"user","content":"say hi"}]}'
```

---

## Releasing a new image

Push a semver tag — GitHub Actions builds multi-arch (`amd64` + `arm64`) and pushes to GHCR:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

Tags published: `vX.Y.Z`, `vX.Y`, `vX`, and `latest`.

---

## Configuration reference

| Env var | Required | Description |
|---|---|---|
| `GH_COPILOT_TOKEN` | yes | Long-lived GitHub Copilot OAuth token (`ghu_...`) |
| `LITELLM_MASTER_KEY` | yes | Proxy access key clients must send (`sk-...`) |
| `BRAVE_API_KEY` | no | Brave Search API key — enables web search (primary provider) |
| `TAVILY_API_KEY` | no | Tavily Search API key — web search fallback provider |
| `GITHUB_COPILOT_TOKEN_DIR` | no | Where the token/derived key live in-container (default `/app/copilot-creds`) |

Credits: built on [BerriAI/litellm](https://github.com/BerriAI/litellm); inspired by [ericc-ch/copilot-api](https://github.com/ericc-ch/copilot-api).
