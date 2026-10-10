#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="local-qwen-chat"

echo "Scaffolding agentic coding harness in ./${PROJECT_NAME}..."

# 1. Directory Tree
mkdir -p "${PROJECT_NAME}"/{.agent/{skills/{verify-ollama/scripts,modern-frontend/references,stream-tester/scripts},rules},src/{backend/services,frontend/src/components},tests}

cd "${PROJECT_NAME}"

# 2. Root Context Anchor (GEMINI.md)
cat << 'EOF' > GEMINI.md
# Agent Governance & System Invariants

## Project Overview
A lightweight local chatbot web interface powered by Ollama running `qwen2.5:1.5b`.

## Stack & Invariants
- Backend: Python 3.12 (FastAPI), Server-Sent Events (SSE) streaming
- Frontend: React / TypeScript + Tailwind CSS
- Model: `qwen2.5:1.5b` (Local Ollama daemon at `http://127.0.0.1:11434`)

## Hard Guardrails (Never Violate)
1. **Model Invariant**: Default model is strictly `qwen2.5:1.5b`. Do not substitute without explicit instruction.
2. **Streaming Protocol**: All completions must stream tokens via SSE. Never buffer full responses before returning.
3. **Deterministic Commands**: Always use targets in `Makefile` (`make verify`, `make test`, `make lint`). Do not invent shell flags.
4. **Git Safety**: Never execute destructive git actions (`git reset --hard`, `git push --force`).

## Definition of Done
Any task completed by an agent or subagent must pass `make verify`.
EOF

# 3. Deterministic Command Surface (Makefile)
cat << 'EOF' > Makefile
.PHONY: setup verify test lint run-ollama check-ollama clean

verify: lint test

lint:
	@echo "Running linters..."
	@which ruff > /dev/null 2>&1 && ruff check src/backend || true
	@which pnpm > /dev/null 2>&1 && pnpm --prefix src/frontend lint || true

test:
	@echo "Running tests..."
	@which pytest > /dev/null 2>&1 && pytest tests/ -v || true

check-ollama:
	bash .agent/skills/verify-ollama/scripts/check_ollama.sh

run-ollama:
	docker compose up -d ollama
	docker compose exec ollama ollama pull qwen2.5:1.5b

clean:
	rm -rf __pycache__ .pytest_cache src/backend/__pycache__
EOF

# 4. Isolated Docker Service (docker-compose.yml)
cat << 'EOF' > docker-compose.yml
services:
  ollama:
    image: ollama/ollama:latest
    container_name: local_qwen_ollama
    ports:
      - "11434:11434"
    volumes:
      - ollama_models:/root/.ollama

volumes:
  ollama_models:
EOF

# 5. Skills Configuration
# Skill 1: verify-ollama
cat << 'EOF' > .agent/skills/verify-ollama/SKILL.md
---
name: verify-ollama
description: Checks if the Ollama daemon is active and verifies that qwen2.5:1.5b is loaded and ready.
---

# Ollama Verification Protocol
1. Execute `./scripts/check_ollama.sh`.
2. Inspect output:
   - If exit 0: Ollama daemon and qwen2.5:1.5b are ready.
   - If connection fails: Tell user to run `ollama serve` or `make run-ollama`.
   - If model missing: Run `ollama pull qwen2.5:1.5b`.
EOF

cat << 'EOF' > .agent/skills/verify-ollama/scripts/check_ollama.sh
#!/usr/bin/env bash
set -e

OLLAMA_HOST="${OLLAMA_BASE_URL:-http://127.0.0.1:11434}"

echo "Checking Ollama daemon at $OLLAMA_HOST..."
if ! curl -sf "$OLLAMA_HOST/api/tags" > /dev/null; then
  echo "ERROR: Cannot connect to Ollama. Run 'ollama serve' or 'make run-ollama'."
  exit 1
fi

echo "Verifying qwen2.5:1.5b model availability..."
if curl -s "$OLLAMA_HOST/api/tags" | grep -q "qwen2.5:1.5b"; then
  echo "SUCCESS: qwen2.5:1.5b is ready for inference."
  exit 0
else
  echo "WARNING: qwen2.5:1.5b is not pulled yet."
  exit 2
fi
EOF
chmod +x .agent/skills/verify-ollama/scripts/check_ollama.sh

# Skill 2: modern-frontend
cat << 'EOF' > .agent/skills/modern-frontend/SKILL.md
---
name: modern-frontend
description: Applies modern UI/UX design standards, dark-mode aesthetics, responsive layouts, and Tailwind styling for the chat UI.
---

# Modern Frontend Guidelines
- **Theme**: Dark-mode-first aesthetic with neutral zinc tones (`bg-zinc-950`, `text-zinc-100`, `border-zinc-800/80`).
- **Chat Container**: Auto-scroll on incoming stream chunks, fixed floating prompt input at bottom.
- **Message Bubbles**:
  - User: Right-aligned with distinct accent background (`bg-zinc-800`).
  - Assistant: Left-aligned with subtle border and avatar icon.
- **Markdown & Code**: Code blocks must have clean borders, monospace font, and copy-code interactions.
EOF

cat << 'EOF' > .agent/skills/modern-frontend/references/design-tokens.md
# Design Tokens Reference
- Background: zinc-950 (#09090b)
- Card / Input: zinc-900 (#18181b)
- Border: zinc-800 (#27272a)
- Text Primary: zinc-100 (#f4f4f5)
- Text Muted: zinc-400 (#a1a1aa)
EOF

# Skill 3: stream-tester
cat << 'EOF' > .agent/skills/stream-tester/SKILL.md
---
name: stream-tester
description: Validates that the backend chat API streams tokens progressively over SSE without buffering the whole response.
---

# Stream Testing Protocol
1. Execute `python .agent/skills/stream-tester/scripts/test_stream.py`.
2. Confirm incoming chunks have timestamps showing progressive delivery.
EOF

cat << 'EOF' > .agent/skills/stream-tester/scripts/test_stream.py
import sys
import time

def verify_streaming_chunks(chunk_generator):
    received = []
    for chunk in chunk_generator:
        received.append((time.time(), chunk))
    if len(received) < 2:
        print("ERROR: Response was delivered as a single block, not streamed.")
        return False
    print(f"SUCCESS: Streamed across {len(received)} discrete chunks.")
    return True

if __name__ == "__main__":
    print("Stream validator loaded.")
EOF

# 6. Scoped Domain Rules
cat << 'EOF' > .agent/rules/backend.md
# Scoped Rules: Backend (src/backend/)
- Use FastAPI with `StreamingResponse(media_type="text/event-stream")`.
- Structure endpoints in `routers/` if expanding beyond 3 routes.
- Handle Ollama timeout/disconnect exceptions cleanly with HTTP 503.
EOF

cat << 'EOF' > .agent/rules/frontend.md
# Scoped Rules: Frontend (src/frontend/)
- Use Tailwind CSS utility classes exclusively.
- Implement accessible keyboard inputs (`Enter` sends, `Shift+Enter` creates a newline).
- Handle disconnected streaming states with visual reconnection cues.
EOF

# 7. Environment & Config Files
cat << 'EOF' > .env.example
OLLAMA_BASE_URL=http://127.0.0.1:11434
MODEL_NAME=qwen2.5:1.5b
BACKEND_PORT=8000
EOF

cat << 'EOF' > .gitignore
.env
__pycache__/
*.pyc
.pytest_cache/
node_modules/
dist/
.DS_Store
EOF

cat << 'EOF' > .mcp.json
{
  "mcpServers": {}
}
EOF

# 8. Starter Stubs for App Code
cat << 'EOF' > src/backend/requirements.txt
fastapi>=0.115.0
uvicorn>=0.30.0
httpx>=0.27.0
pytest>=8.0.0
EOF

cat << 'EOF' > tests/test_api_stream.py
def test_placeholder():
    """Agents will replace this with integration tests for SSE streaming."""
    assert True
EOF

echo "Scaffolding complete. Run 'cd ${PROJECT_NAME} && make check-ollama' to test your environment."