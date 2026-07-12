# workspace-bootstrap

**An agent-governance scaffold for running OpenAI Codex CLI and Claude Code side-by-side, in parity, on one codebase.**

I've used this pattern across 10+ production and personal repos (5,000+ agent-co-authored commits): iOS apps shipped to the App Store, enterprise Kubernetes delivery pipelines, data-migration toolchains, and ML fine-tuning POCs. It solves the problems that show up the moment coding agents become long-lived contributors instead of one-shot autocomplete:

- **Agents forget.** Every new session starts cold. → *Session journals* + a `SessionStart` hook that points the agent at where the last session left off.
- **Agents drift.** Two different agent runtimes (Codex, Claude Code) develop two different behaviors. → *One operating contract* (`AGENTS.md` ≡ `CLAUDE.md`, byte-identical, enforced by a pre-commit check) and *mirrored lifecycle hooks* in `.codex/` and `.claude/`.
- **Agents leak.** An agent with repo access can push something that shouldn't leave the building. → A *read-only reviewer subagent*, defined once per runtime, that gates pushes against a list of disallowed patterns.

📖 **Start with the guide: [Running Codex CLI and Claude Code in parity](docs/running-codex-and-claude-in-parity.md)**

## What's in the box

```
templates/
  AGENTS.md.template          # the operating contract (copy to AGENTS.md, symlink/copy to CLAUDE.md)
  session-journal.md          # journal template referenced by the contract
.claude/
  settings.json               # hook wiring for Claude Code
  hooks/                      # SessionStart pointer + Stop nudge
  agents/release-clean-reviewer.md    # read-only push gate (Claude Code subagent)
.codex/
  hooks.json                  # the same lifecycle, wired for Codex CLI
  hooks/                      # identical scripts
  agents/release-clean-reviewer.toml  # the same reviewer (Codex agent config)
scripts/
  check-contract-parity.sh    # pre-commit: AGENTS.md and CLAUDE.md must be byte-identical
```

## Quick start

```bash
# from your repo root
cp -R <this-repo>/.claude <this-repo>/.codex .
cp <this-repo>/templates/AGENTS.md.template AGENTS.md
cp AGENTS.md CLAUDE.md
mkdir -p sessions
cp <this-repo>/scripts/check-contract-parity.sh .git/hooks/pre-commit  # or call it from your existing hook
```

Then edit `AGENTS.md` (project facts, verification commands, hard rules), copy it over `CLAUDE.md`, and start a session in either tool. The hooks do the rest:

1. **SessionStart** — the agent is told which session journal to read before acting.
2. **Stop** — if the agent is ending its turn without creating/updating the journal, the hook blocks once and reminds it (with a marker file so it can never loop).
3. **Pre-push (optional)** — the reviewer subagent scans the outgoing diff for disallowed patterns before anything leaves the repo.

## Why byte-identical contracts?

Codex CLI reads `AGENTS.md`; Claude Code reads `CLAUDE.md`. The instant those files diverge, your two runtimes have different rules and you'll debug "why did the agent do that" twice. Keeping them byte-identical (enforced mechanically, not by discipline) means one place to change behavior for every agent that touches the repo.

## License

MIT
