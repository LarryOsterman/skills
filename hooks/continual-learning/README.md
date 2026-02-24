---
name: 'Continual Learning'
description: 'Hooks that enable AI coding agents to learn, reflect, and persist knowledge across sessions'
tags: ['learning', 'memory', 'reflection', 'productivity', 'featured']
---

# Continual Learning Hook

Enable your AI coding agent to learn from every session. This hook set implements the **continual learning loop** — capturing tool outcomes, reflecting on patterns, and persisting knowledge so each session starts smarter than the last.

## The Problem

AI coding agents start every session from scratch. You correct them, they adapt — then the session ends and the knowledge is lost. Next session: same mistakes, same corrections, infinite loop.

## The Solution

```
Experience → Capture → Reflect → Persist → Apply
```

This hook set closes the loop by:

1. **Loading context** at session start — past session summaries, accumulated learnings
2. **Tracking outcomes** during the session — which tools succeed, which fail
3. **Reflecting** at session end — analyzing patterns, identifying repeated failures
4. **Persisting** learnings to a SQLite database and optional memory file

## How It Works

### Session Start (`load-session-start.sh`)
- Queries `~/.copilot/session-store.db` for recent sessions in the current project
- Loads accumulated learnings from `~/.copilot/continual-learning.db`
- Surfaces the local `.github/memory/learnings.md` file if present

### During Session (`track-tool-use.sh`)
- Records every tool invocation and its result (success/failure)
- Builds a tool usage history in `~/.copilot/continual-learning.db`
- Lightweight — adds <5ms per tool call

### Session End (`reflect-session-end.sh`)
- Analyzes tool outcomes: total usage, failure rate, top tools
- Detects repeated failure patterns (same tool failing multiple times)
- Persists failure patterns as learnings
- Appends a session summary to `.github/memory/learnings.md`
- Cleans up data older than 7 days

## Installation

1. Copy the hook folder to your repository:
   ```bash
   cp -r hooks/continual-learning .github/hooks/
   ```

2. Ensure scripts are executable:
   ```bash
   chmod +x .github/hooks/continual-learning/scripts/*.sh
   ```

3. Optionally create a memory file for project-specific learnings:
   ```bash
   mkdir -p .github/memory
   echo "# Project Learnings" > .github/memory/learnings.md
   ```

4. Commit to your repository's default branch.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `SKIP_CONTINUAL_LEARNING` | unset | Set to `true` to disable entirely |
| `MEMORY_FILE` | `.github/memory/learnings.md` | Path to the project memory file |

## Database Schema

The hook creates `~/.copilot/continual-learning.db` with two tables:

```sql
-- Tool invocation history (auto-cleaned after 7 days)
CREATE TABLE tool_outcomes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT,
    tool_name TEXT,
    result_type TEXT,
    timestamp INTEGER,
    recorded_at TEXT DEFAULT (datetime('now'))
);

-- Persistent learnings extracted from sessions
CREATE TABLE learnings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category TEXT,      -- 'failure_pattern', 'correction', 'preference'
    content TEXT,       -- The actual learning
    source TEXT,        -- Where it came from (session ID, timestamp)
    created_at TEXT DEFAULT (datetime('now'))
);
```

## The Compound Effect

| Week | State |
|------|-------|
| Week 1 | Agent starts fresh each session, repeats mistakes |
| Week 4 | Database has failure patterns, agent avoids known issues |
| Week 12 | Rich history of learnings, agent rarely makes previously-seen mistakes |

## Combining with Agent Memory

If your coding agent supports a `store_memory` tool or similar, the learnings from this hook can inform what the agent persists. The hook provides the **infrastructure** (capture, store, surface) while the agent provides the **intelligence** (deciding what's worth remembering).

## Requirements

- `sqlite3` for database operations
- `jq` for JSON parsing (optional, gracefully degrades)
- Bash 4+ with standard Unix tools

## Privacy

- Tool outcomes are stored locally in `~/.copilot/continual-learning.db`
- No tool arguments or prompt content is logged — only tool names and result types
- Memory file is project-local and should be in `.gitignore` if sensitive
- All data stays local — no external network calls
