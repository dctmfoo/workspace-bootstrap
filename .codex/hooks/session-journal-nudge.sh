#!/bin/bash
# Stop hook: nudge the agent to create/update the session journal.
#
# Algorithm (capped at 1 nudge per Stop cycle to prevent infinite loops):
#   1. Check sessions/ for the newest .md (excluding README.md).
#   2. If none exists AND no nudge-pending marker -> create marker, emit
#      "create a journal" reminder via stderr + exit 2 (Stop blocks, agent
#      sees reminder and creates the journal).
#   3. If none exists AND marker exists -> agent ignored previous nudge;
#      log warning, remove marker, exit 0 (session ends without journal).
#   4. If journal exists AND mtime within last 120s -> agent updated it
#      this turn; remove marker if present; exit 0.
#   5. If journal exists AND stale AND no marker -> create marker, emit
#      "update the journal" reminder via stderr + exit 2.
#   6. If journal exists AND stale AND marker exists -> agent ignored
#      previous nudge; log warning, remove marker, exit 0.
#
# The marker file ensures we nudge at most ONCE per Stop cycle. Neither
# runtime has built-in Stop-hook loop prevention, so the marker is mandatory.

set -e

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SESSIONS_DIR="$PROJECT_DIR/sessions"
STATE_DIR="$PROJECT_DIR/.claude/state"
MARKER="$STATE_DIR/journal-nudge-pending"

mkdir -p "$SESSIONS_DIR" "$STATE_DIR"

# Find newest journal (any .md in sessions/ except README.md)
LATEST=""
for f in "$SESSIONS_DIR"/*.md; do
  [ -e "$f" ] || continue
  [ "$(basename "$f")" = "README.md" ] && continue
  if [ -z "$LATEST" ] || [ "$f" -nt "$LATEST" ]; then
    LATEST="$f"
  fi
done

# Case 1: No journal exists
if [ -z "$LATEST" ]; then
  if [ -f "$MARKER" ]; then
    # Already nudged this cycle — agent ignored us. Don't loop.
    rm -f "$MARKER"
    echo "warning: session journal was not created after nudge; session ending without one." >&2
    exit 0
  fi
  touch "$MARKER"
  echo "SESSION-JOURNAL-REMINDER: No session journal exists at $SESSIONS_DIR. Per the session-journal discipline in the agent operating contract, create one (filename pattern: YYYY-MM-DD-HHMM-<slug>.md) before finishing this turn. Use templates/session-journal.md." >&2
  exit 2
fi

# Case 2: Journal exists — check freshness (Mac stat -f, Linux stat -c)
if stat -f %m "$LATEST" >/dev/null 2>&1; then
  MTIME=$(stat -f %m "$LATEST")
else
  MTIME=$(stat -c %Y "$LATEST")
fi
NOW=$(date +%s)
AGE=$(( NOW - MTIME ))

if [ "$AGE" -lt 120 ]; then
  # Fresh — agent updated this turn.
  [ -f "$MARKER" ] && rm -f "$MARKER"
  exit 0
fi

# Journal stale (>120s old)
if [ -f "$MARKER" ]; then
  rm -f "$MARKER"
  echo "warning: session journal $LATEST still stale after nudge (${AGE}s); session ending anyway." >&2
  exit 0
fi

touch "$MARKER"

# Detect journal mode: read the first non-empty line under "## Live plan pointer".
# THIN mode = pointer is set to a non-"none" value (any governing plan/spec/tracker).
# DETAILED mode = pointer is empty or literally "none" (case-insensitive).
PLAN_LINE=$(awk '
  /^## Live plan pointer[[:space:]]*$/ { flag = 1; next }
  flag && /^## / { exit }
  flag && NF { print; exit }
' "$LATEST" 2>/dev/null || true)

# Strip surrounding whitespace.
PLAN_LINE_TRIMMED=$(printf '%s' "$PLAN_LINE" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
PLAN_LINE_LC=$(printf '%s' "$PLAN_LINE_TRIMMED" | tr '[:upper:]' '[:lower:]')

if [ -z "$PLAN_LINE_TRIMMED" ] || [ "$PLAN_LINE_LC" = "none" ] || [ "$PLAN_LINE_LC" = "<none>" ]; then
  # DETAILED mode — no governing doc; journal is the canonical record.
  echo "SESSION-JOURNAL-REMINDER (DETAILED mode — Live plan pointer is 'none'): $LATEST was last touched ${AGE}s ago. Per the operating contract, update Milestones / Decisions / Files-touched / Next-step sections + the 'Last updated' timestamp before finishing this turn. If a plan/spec/tracker is in fact governing this session, set 'Live plan pointer' to that path and switch to THIN mode." >&2
else
  # THIN mode — governing doc exists; journal is a thin index.
  echo "SESSION-JOURNAL-REMINDER (THIN mode — Live plan pointer: ${PLAN_LINE_TRIMMED}): $LATEST was last touched ${AGE}s ago. Append a ONE-LINE milestone referencing the plan (section / decision id / phase / commit hash). Do NOT re-narrate plan content. Update 'Last updated' + 'Where we are now' + 'Next step for a fresh agent' as needed; let the governing doc carry the rest." >&2
fi
exit 2
