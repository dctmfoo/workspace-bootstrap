#!/bin/bash
# SessionStart hook: inject a pointer to the most recent session journal
# so a new / resumed agent knows where to continue from.
#
# Does NOT inject the journal's full content (context-budget conscious).
# Emits JSON with hookSpecificOutput.additionalContext; the agent reads the
# pointer on start and chooses to open the file itself.
#
# Runs unmodified under Claude Code (CLAUDE_PROJECT_DIR is set) and Codex CLI
# (falls back to the git toplevel).

set -e

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SESSIONS_DIR="$PROJECT_DIR/sessions"

mkdir -p "$SESSIONS_DIR"

# Find newest journal (any .md in sessions/ except README.md)
LATEST=""
for f in "$SESSIONS_DIR"/*.md; do
  [ -e "$f" ] || continue
  [ "$(basename "$f")" = "README.md" ] && continue
  if [ -z "$LATEST" ] || [ "$f" -nt "$LATEST" ]; then
    LATEST="$f"
  fi
done

if [ -z "$LATEST" ]; then
  MSG="No prior session journal found in $SESSIONS_DIR. Per the session-journal discipline in the agent operating contract (AGENTS.md / CLAUDE.md), create a new journal (YYYY-MM-DD-HHMM-<slug>.md) once the user's first message clarifies the session intent."
else
  REL=$(echo "$LATEST" | sed "s|^$PROJECT_DIR/||")
  # Read just the header (first ~20 lines) for a quick orient
  HEADER=$(head -n 20 "$LATEST" | sed 's/"/\\"/g' | awk 'BEGIN{ORS="\\n"} {print}')
  MSG="Most recent session journal: $REL. Read it first to understand where the previous session left off before acting on the user's prompt. If continuing the same work, append to that file; if starting unrelated work, create a fresh journal per the operating contract. Header preview:\\n$HEADER"
fi

# JSON escape the message safely via python (more robust than sed for arbitrary content)
if command -v python3 >/dev/null 2>&1; then
  ESCAPED=$(python3 -c "import sys,json; print(json.dumps(sys.argv[1]))" "$MSG")
elif command -v python >/dev/null 2>&1; then
  ESCAPED=$(python -c "import sys,json; print(json.dumps(sys.argv[1]))" "$MSG")
else
  # Fallback: rough escape. Safe for our controlled message strings (no exotic chars).
  ESCAPED=$(printf '%s' "$MSG" | sed 's/\\/\\\\/g; s/"/\\"/g')
  ESCAPED="\"$ESCAPED\""
fi

printf '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": %s}}\n' "$ESCAPED"
exit 0
