#!/bin/sh
# Pre-commit check: the agent operating contract must be byte-identical in both
# runtime filenames. Codex CLI reads AGENTS.md; Claude Code reads CLAUDE.md.
# Discipline fails; exit 1 doesn't.
#
# Install:  cp scripts/check-contract-parity.sh .git/hooks/pre-commit
# (or call it from your existing pre-commit hook)

if [ -f AGENTS.md ] && [ -f CLAUDE.md ]; then
  if ! cmp -s AGENTS.md CLAUDE.md; then
    echo "AGENTS.md and CLAUDE.md have diverged." >&2
    echo "Edit one, then: cp AGENTS.md CLAUDE.md  (or the reverse)" >&2
    exit 1
  fi
fi
exit 0
