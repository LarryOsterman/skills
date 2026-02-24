#!/bin/bash

# Continual Learning: Load past learnings at session start
#
# Queries the global session store for recent patterns and surfaces
# accumulated learnings from the memory file so the agent starts
# each session with context from previous work.
#
# Environment:
#   SKIP_CONTINUAL_LEARNING - "true" to disable (default: unset)
#   MEMORY_FILE             - path to learnings file (default: .github/memory/learnings.md)

set -euo pipefail

if [[ "${SKIP_CONTINUAL_LEARNING:-}" == "true" ]]; then
  exit 0
fi

INPUT=$(cat)

CWD=$(pwd)
MEMORY_FILE="${MEMORY_FILE:-.github/memory/learnings.md}"
SESSION_STORE_DB="$HOME/.copilot/session-store.db"
PLUGIN_DB="$HOME/.copilot/continual-learning.db"

# Initialize plugin DB
if command -v sqlite3 &>/dev/null; then
  sqlite3 "$PLUGIN_DB" <<'SQL'
CREATE TABLE IF NOT EXISTS tool_outcomes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT,
    tool_name TEXT,
    result_type TEXT,
    timestamp INTEGER,
    recorded_at TEXT DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS learnings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category TEXT,
    content TEXT,
    source TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);
SQL
fi

# Surface recent session history for this project
CONTEXT=""

if [ -f "$SESSION_STORE_DB" ] && command -v sqlite3 &>/dev/null; then
  RECENT=$(sqlite3 "$SESSION_STORE_DB" \
    "SELECT summary FROM sessions
     WHERE cwd LIKE '%${CWD##*/}%'
     ORDER BY updated_at DESC LIMIT 3;" 2>/dev/null || echo "")

  if [ -n "$RECENT" ]; then
    CONTEXT="Recent sessions in this project:\n$RECENT"
  fi

  # Surface any stored learnings
  LEARNED=$(sqlite3 "$PLUGIN_DB" \
    "SELECT category || ': ' || content FROM learnings
     ORDER BY created_at DESC LIMIT 10;" 2>/dev/null || echo "")

  if [ -n "$LEARNED" ]; then
    CONTEXT="$CONTEXT\n\nPersisted learnings:\n$LEARNED"
  fi
fi

# Check for project-local memory file
if [ -f "$MEMORY_FILE" ]; then
  LINE_COUNT=$(wc -l < "$MEMORY_FILE" | tr -d ' ')
  CONTEXT="$CONTEXT\n\n📝 Memory file ($MEMORY_FILE) has $LINE_COUNT lines of accumulated learnings."
fi

if [ -n "$CONTEXT" ]; then
  echo "🧠 Continual learning active — loaded context from previous sessions"
  echo -e "$CONTEXT" >&2
else
  echo "🧠 Continual learning active — no prior context found (first session)"
fi

exit 0
