---
name: continual-learning
description: Guide for implementing continual learning in AI coding agents — hooks, memory files, reflection patterns, and session persistence. Use when setting up learning infrastructure for agents.
---

# Continual Learning for AI Coding Agents

## Core Concept

Continual learning enables AI coding agents to improve across sessions by capturing corrections, reflecting on patterns, and persisting knowledge. Instead of starting each session from scratch, agents build on accumulated experience.

```
Experience → Capture → Reflect → Persist → Apply
```

## The Learning Loop

### 1. Capture (During Session)

Track corrections, tool outcomes, and user feedback as they happen:
- User corrections: "no, use X not Y", "actually...", "that's wrong"
- Tool failures: repeated failures on the same tool indicate a pattern
- Successful patterns: approaches that worked well

### 2. Reflect (Session End)

At session end, synthesize raw observations into actionable learnings:
- Abstract the general principle (not just the specific instance)
- Determine scope: project-specific or global?
- Check for conflicts with existing rules

### 3. Persist (To Storage)

Store learnings in one or more of:
- **SQLite database** (`~/.copilot/continual-learning.db`) — structured, queryable
- **Memory file** (`.github/memory/learnings.md`) — human-readable, version-controlled
- **Agent memory tools** (`store_memory`, `sql` session store) — agent-native persistence

### 4. Apply (Next Session)

On session start, load accumulated context:
- Query session store for recent project history
- Read persisted learnings from database
- Surface memory file content
- Agent starts with full context of past work

## Implementation Patterns

### Hook-Based (Infrastructure Layer)

Install the `continual-learning` hook set for automatic capture and reflection:

```bash
cp -r hooks/continual-learning .github/hooks/
chmod +x .github/hooks/continual-learning/scripts/*.sh
```

This provides:
- `sessionStart` → loads past learnings
- `postToolUse` → tracks tool outcomes
- `sessionEnd` → reflects and persists

### Agent-Native (Intelligence Layer)

Use the agent's built-in memory tools for higher-quality learnings:

```
# Using the store_memory tool
store_memory(
  subject="error handling",
  fact="This project uses Result<T> pattern, not exceptions",
  category="general"
)
```

```sql
-- Using the SQL session database
INSERT INTO session_state (key, value)
VALUES ('learned_pattern', 'Always use async/await for Azure SDK calls');
```

### Memory File Pattern

Create a living knowledge base the agent reads on startup:

```markdown
# .github/memory/learnings.md

## Conventions
- Use `DefaultAzureCredential` for all Azure auth
- Prefer `create_or_update_*` for idempotent operations

## Common Mistakes
- Don't use `azure-ai-inference` for Foundry agents — use `azure-ai-projects`
- The `search()` parameter is `semantic_configuration_name`, not `semantic_configuration`

## Preferences
- User prefers concise commit messages (50 char limit)
- Always run tests before committing
```

### The Diary Pattern (Advanced)

For deeper reflection across multiple sessions:

1. **Log sessions** — Save session summaries with decisions, challenges, outcomes
2. **Cross-reference** — Identify patterns across sessions (recurring mistakes, preferences)
3. **Synthesize** — Convert patterns into rules
4. **Prune** — Remove redundant or outdated learnings

## Best Practices

1. **Start simple** — Begin with the hook set, add agent-native memory later
2. **Be specific** — "Use `semantic_configuration_name=`" is better than "use the right parameter"
3. **Scope learnings** — Mark whether something is project-specific or global
4. **Prune regularly** — Outdated learnings cause more harm than no learnings
5. **Don't log secrets** — Only store tool names, result types, and abstract patterns
6. **Compound over time** — Small improvements per session create exponential gains
