#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="${1:-app-harness}"

echo "Scaffolding generic agentic harness in ./${PROJECT_NAME}..."

# 1. Directory Tree
mkdir -p "${PROJECT_NAME}"/{.agent/{skills/{supabase-ops/scripts,modern-ui/references,test-runner/scripts},rules},supabase/{migrations,seed},src/{components,hooks,lib,types},tests}

cd "${PROJECT_NAME}"

# 2. Root Context Anchor (GEMINI.md)
cat << 'EOF' > GEMINI.md
# Agent Governance & System Invariants

## Project Overview
Modern web application with a React frontend and Supabase (PostgreSQL, Auth, Edge Functions) backend managed locally via `npx supabase`.

## Technology Stack
- Frontend: React (TypeScript) + Tailwind CSS + Lucide Icons
- Backend & DB: Supabase (Local instance via `npx supabase`)
- Data Client: `@supabase/supabase-js`
- Package Manager: `pnpm` (or `npm`)

## Hard Invariants (Never Violate)
1. **Database Schema Changes**: NEVER run ad-hoc raw SQL directly against the DB. All schema changes MUST be authored as declarative migrations inside `supabase/migrations/<timestamp>_<name>.sql` and applied via `make db-diff` or `make db-reset`.
2. **Deterministic Primitives**: Always invoke tasks through the `Makefile` (`make verify`, `make test`, `make lint`). Do not invent shell flags.
3. **Secrets & Keys**: Never hardcode credentials. Local development relies strictly on local keys output by `npx supabase status` loaded via `.env.local`.
4. **Git Safety**: Never run destructive git operations (`git reset --hard`, `git push --force`).

## Definition of Done
Any task completed by an agent or subagent must pass `make verify`.
EOF

# 3. Deterministic Command Surface (Makefile)
cat << 'EOF' > Makefile
.PHONY: setup verify test lint db-start db-stop db-reset db-status db-diff clean

# Master Quality Gate
verify: lint test

lint:
	@echo "Checking formatting and linting..."
	@which pnpm > /dev/null 2>&1 && pnpm lint || npm run lint --if-present

test:
	@echo "Running test suite..."
	@which pnpm > /dev/null 2>&1 && pnpm test || npm test --if-present

# Supabase Local Engine Controls
db-start:
	npx supabase start

db-stop:
	npx supabase stop

db-status:
	npx supabase status

db-reset:
	npx supabase db reset

db-diff:
	@read -p "Migration name: " name; npx supabase db diff -f $$name

clean:
	rm -rf dist build .cache node_modules/.cache
EOF

# 4. Agent Skills
# Skill 1: Supabase Operations
cat << 'EOF' > .agent/skills/supabase-ops/SKILL.md
---
name: supabase-ops
description: Manages local Supabase services, schema migrations, and database status verification.
---

# Supabase Management Protocol
1. Check local instance status using `./scripts/check_supabase.sh`.
2. Schema Guidelines:
   - Always enable Row Level Security (RLS) on new public tables:
     `ALTER TABLE public.<table_name> ENABLE ROW LEVEL SECURITY;`
   - Create explicit RLS policies for `select`, `insert`, `update`, and `delete`.
   - Never commit ad-hoc mutations; generate a timestamped file in `supabase/migrations/`.
3. Apply changes with `make db-reset` or `npx supabase migration up`.
EOF

cat << 'EOF' > .agent/skills/supabase-ops/scripts/check_supabase.sh
#!/usr/bin/env bash
set -e

echo "Verifying local Supabase container status..."
if npx supabase status > /dev/null 2>&1; then
  echo "SUCCESS: Supabase services are running locally."
  exit 0
else
  echo "WARNING: Supabase is offline. Run 'make db-start' to launch."
  exit 1
fi
EOF
chmod +x .agent/skills/supabase-ops/scripts/check_supabase.sh

# Skill 2: Modern UI System
cat << 'EOF' > .agent/skills/modern-ui/SKILL.md
---
name: modern-ui
description: Enforces clean, modern UI/UX design standards, component composition, responsive layouts, and Tailwind styling.
---

# Modern UI/UX Guidelines
- **Visual Design**: Clean, minimal aesthetics. Neutral background tones (`bg-zinc-950` dark or `bg-zinc-50` light) with high-contrast typography.
- **Component Primitives**:
  - Prefer headless, accessible primitives (Radix UI / shadcn style conventions).
  - Co-locate component state, loading skeletons, and empty states.
  - Buttons and inputs must have distinct focus, hover, active, and disabled states (`transition-all duration-150`).
- **Data States**: Every UI view that fetches from Supabase must handle 4 states:
  1. `idle`
  2. `loading` (use subtle skeleton pulse, not intrusive spinners)
  3. `error` (user-readable recovery action)
  4. `empty` (call to action for first-time use)
EOF

cat << 'EOF' > .agent/skills/modern-ui/references/design-tokens.md
# Visual Tokens
- Surface: bg-zinc-950 (Dark), bg-white (Light)
- Card/Panel: bg-zinc-900 (Dark), bg-zinc-50 (Light)
- Border: border-zinc-800/80 (Dark), border-zinc-200 (Light)
- Text Primary: text-zinc-100 (Dark), text-zinc-900 (Light)
- Text Muted: text-zinc-400 (Dark), text-zinc-500 (Light)
- Accent: indigo-500 / emerald-500
EOF

# Skill 3: Test Runner & Verification
cat << 'EOF' > .agent/skills/test-runner/SKILL.md
---
name: test-runner
description: Runs end-to-end and unit test suites, parsing errors and reporting actionable diffs.
---

# Test Verification Protocol
1. Execute `make test`.
2. If tests fail:
   - Identify whether failure is an assertion mismatch, missing mock, or DB schema conflict.
   - Fix the underlying code or migration—do NOT alter test assertions to force a pass unless the spec changed.
EOF

# 5. Scoped Domain Rules
cat << 'EOF' > .agent/rules/database.md
# Scoped Rules: Database & Backend (supabase/)
- All new public tables must have an `id uuid default gen_random_uuid() primary key`.
- Add `created_at timestamptz default now() not null`.
- Always enable RLS and write granular policies.
- Type definitions must be synchronized: run `npx supabase gen types typescript --local > src/types/database.types.ts`.
EOF

cat << 'EOF' > .agent/rules/frontend.md
# Scoped Rules: Frontend (src/)
- Use TypeScript strictly; avoid `any`.
- Keep Supabase client calls isolated in custom hooks (`src/hooks/`) or service functions (`src/lib/`).
- Do not make raw Supabase client calls directly inside view components.
- Adhere to design tokens specified in `.agent/skills/modern-ui/`.
EOF

# 6. Environment & Configuration Stubs
cat << 'EOF' > .env.example
VITE_SUPABASE_URL=http://127.0.0.1:54321
VITE_SUPABASE_ANON_KEY=your-local-anon-key-from-supabase-status
EOF

cat << 'EOF' > .gitignore
node_modules/
dist/
build/
.cache/
.env
.env.local
.DS_Store
.supabase/
supabase/.temp/
EOF

cat << 'EOF' > .mcp.json
{
  "mcpServers": {}
}
EOF

# 7. Starter Stubs for Supabase & Source Code
cat << 'EOF' > supabase/seed.sql
-- Initial seed data for local testing
-- e.g., INSERT INTO public.profiles (id, username) VALUES (...);
EOF

cat << 'EOF' > src/lib/supabaseClient.ts
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'http://127.0.0.1:54321';
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || '';

export const supabase = createClient(supabaseUrl, supabaseAnonKey);
EOF

cat << 'EOF' > tests/smoke.test.ts
import { describe, it, expect } from 'vitest';

describe('Harness Sanity Check', () => {
  it('environment runs test assertions', () => {
    expect(true).toBe(true);
  });
});
EOF

echo "Generic React + Supabase harness scaffolded successfully in ./${PROJECT_NAME}."
echo "Next steps:"
echo "  1. cd ${PROJECT_NAME}"
echo "  2. make db-start   (Starts local Supabase via Docker)"
echo "  3. Open CLI session with 'agy' and delegate tasks!"