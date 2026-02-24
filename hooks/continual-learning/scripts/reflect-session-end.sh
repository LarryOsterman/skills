#!/bin/bash

# Continual Learning: Reflect and persist learnings at session end
#
# Analyzes the session's tool usage patterns, generates a summary,
# and persists insights to the plugin database for future sessions.
#
# This hook:
# 1. Summarizes tool outcomes (successes, failures, patterns)
# 2. Appends learnings to the local memory file if it exists
# 3. Stores structured learnings in the plugin SQLite database

set -euo pipefail

if [[ "${SKIP_CONTINUAL_LEARNING:-}" == "true" ]]; then
  exit 0
fi

INPUT=$(cat)

PLUGIN_DB="$HOME/.copilot/continual-learning.db"
MEMORY_FILE="${MEMORY_FILE:-.github/memory/learnings.md}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if ! command -v sqlite3 &>/dev/null || [ ! -f "$PLUGIN_DB" ]; then
  echo "🧠 Session ended — no database available for reflection"
  exit 0
fi

# Analyze this session's tool usage
TOTAL_TOOLS=$(sqlite3 "$PLUGIN_DB" \
  "SELECT COUNT(*) FROM tool_outcomes
   WHERE recorded_at > datetime('now', '-4 hours');" 2>/dev/null || echo "0")

FAILURES=$(sqlite3 "$PLUGIN_DB" \
  "SELECT COUNT(*) FROM tool_outcomes
   WHERE result_type = 'failure'
   AND recorded_at > datetime('now', '-4 hours');" 2>/dev/null || echo "0")

# Get most-used tools this session
TOP_TOOLS=$(sqlite3 "$PLUGIN_DB" \
  "SELECT tool_name || ' (' || COUNT(*) || 'x)'
   FROM tool_outcomes
   WHERE recorded_at > datetime('now', '-4 hours')
   GROUP BY tool_name
   ORDER BY COUNT(*) DESC
   LIMIT 5;" 2>/dev/null || echo "none")

# Get failure patterns
FAIL_PATTERNS=$(sqlite3 "$PLUGIN_DB" \
  "SELECT tool_name || ' (' || COUNT(*) || ' failures)'
   FROM tool_outcomes
   WHERE result_type = 'failure'
   AND recorded_at > datetime('now', '-4 hours')
   GROUP BY tool_name
   HAVING COUNT(*) > 1
   ORDER BY COUNT(*) DESC;" 2>/dev/null || echo "")

# Log session summary
echo "🧠 Session reflection:"
echo "  Tools used: $TOTAL_TOOLS (failures: $FAILURES)"
echo "  Top tools: $TOP_TOOLS"

if [ -n "$FAIL_PATTERNS" ]; then
  echo "  ⚠️ Repeated failures: $FAIL_PATTERNS"

  # Store failure pattern as a learning
  sqlite3 "$PLUGIN_DB" \
    "INSERT INTO learnings (category, content, source)
     VALUES ('failure_pattern', 'Repeated failures: $(echo "$FAIL_PATTERNS" | tr "'" "''")', 'session_end_$TIMESTAMP');" 2>/dev/null || true
fi

# Append to memory file if the directory exists
MEMORY_DIR=$(dirname "$MEMORY_FILE")
if [ -d "$MEMORY_DIR" ]; then
  {
    echo ""
    echo "## Session $TIMESTAMP"
    echo "- Tools used: $TOTAL_TOOLS, failures: $FAILURES"
    echo "- Top tools: $TOP_TOOLS"
    if [ -n "$FAIL_PATTERNS" ]; then
      echo "- Failure patterns: $FAIL_PATTERNS"
    fi
  } >> "$MEMORY_FILE"
  echo "  📝 Updated $MEMORY_FILE"
fi

# Clean old tool outcomes (keep last 7 days)
sqlite3 "$PLUGIN_DB" \
  "DELETE FROM tool_outcomes
   WHERE recorded_at < datetime('now', '-7 days');" 2>/dev/null || true

exit 0
