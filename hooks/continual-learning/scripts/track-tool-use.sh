#!/bin/bash

# Continual Learning: Track tool outcomes for pattern analysis
#
# Records tool usage results to build a history of what works
# and what fails, enabling pattern detection across sessions.

set -euo pipefail

if [[ "${SKIP_CONTINUAL_LEARNING:-}" == "true" ]]; then
  exit 0
fi

INPUT=$(cat)

PLUGIN_DB="$HOME/.copilot/continual-learning.db"

# Extract tool info from hook input
TOOL_NAME=""
RESULT_TYPE=""
TIMESTAMP=""

if command -v jq &>/dev/null; then
  TOOL_NAME=$(echo "$INPUT" | jq -r '.toolName // empty' 2>/dev/null || echo "")
  RESULT_TYPE=$(echo "$INPUT" | jq -r '.toolResult.resultType // "unknown"' 2>/dev/null || echo "unknown")
  TIMESTAMP=$(echo "$INPUT" | jq -r '.timestamp // 0' 2>/dev/null || echo "0")
fi

# Skip if no useful data
if [ -z "$TOOL_NAME" ]; then
  exit 0
fi

# Record to plugin database
if command -v sqlite3 &>/dev/null && [ -f "$PLUGIN_DB" ]; then
  sqlite3 "$PLUGIN_DB" \
    "INSERT INTO tool_outcomes (tool_name, result_type, timestamp)
     VALUES ('$(echo "$TOOL_NAME" | tr "'" "''")', '$(echo "$RESULT_TYPE" | tr "'" "''")', $TIMESTAMP);" 2>/dev/null || true
fi

exit 0
