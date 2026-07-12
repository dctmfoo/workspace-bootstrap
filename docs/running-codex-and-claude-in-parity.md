# Running OpenAI Codex CLI and Claude Code in parity on one codebase

*Patterns from 10+ repos and 5,000+ agent-co-authored commits — shipped iOS apps, enterprise Kubernetes delivery, data migrations, and ML POCs.*

Most teams pick one coding agent and hope. I run two — OpenAI Codex CLI and Claude Code — on the same repos, deliberately, because multi-model coverage catches what single-model blindness misses, and because customers ask "which one should *we* use?" and the only honest answer comes from running both. This guide is the operational playbook that makes that sane instead of chaotic.

## The core problem

A coding agent that contributes over weeks is not autocomplete; it's a teammate with severe amnesia and no employment contract. Concretely:

1. **Cold starts.** Session 47 knows nothing about sessions 1–46.
2. **Behavioral drift.** Codex reads `AGENTS.md`, Claude Code reads `CLAUDE.md`. If they say different things, you now maintain two engineering cultures.
3. **Unreviewed egress.** An agent that can push can leak — internal hostnames, customer identifiers, half-finished secrets handling — without malice, just momentum.

The pattern below addresses each mechanically. Nothing here relies on the agent "remembering to behave."

## 1. One contract, two filenames, zero drift

Both runtimes get the same operating contract:

```
AGENTS.md    # read by Codex CLI (and most other agent tools)
CLAUDE.md    # read by Claude Code
```

These are **byte-identical**, and a pre-commit hook enforces it:

```bash
#!/bin/sh
if ! cmp -s AGENTS.md CLAUDE.md; then
  echo "AGENTS.md and CLAUDE.md have diverged. Edit one, copy over the other." >&2
  exit 1
fi
```

That `cmp` is the whole trick. Discipline fails; `exit 1` doesn't. When I change a rule, I edit `AGENTS.md`, run `cp AGENTS.md CLAUDE.md`, and every agent in every runtime picks up the same rule on its next session.

What belongs in the contract (see [`templates/AGENTS.md.template`](../templates/AGENTS.md.template)):

- **Project facts** the agent will otherwise rediscover expensively every session (build commands, test commands, directory ownership).
- **Hard rules** — things that end a turn if violated (never push to X, never touch Y, cost caps for paid APIs).
- **A self-unblock protocol** — what the agent should try, in order, before stopping to ask (retry transients → substitute documented equivalents → research → log the assumption and proceed). This is what makes long unattended runs productive instead of stalling on the first ambiguity.
- **Session-journal discipline** — see next section.

## 2. Session journals: memory that survives the context window

Every working session writes a journal to `sessions/YYYY-MM-DD-HHMM-<slug>.md`: what was done, what was decided, and — most importantly — **"next step for a fresh agent."** The journal is written *for the next agent*, not for humans.

Two lifecycle hooks make this self-sustaining, and both runtimes get identical copies:

- **`SessionStart` → [`session-journal-pointer.sh`](../.claude/hooks/session-journal-pointer.sh)** injects a pointer to the newest journal (path + header preview, *not* full content — context budgets matter) so the agent orients itself before acting on your first prompt.
- **`Stop` → [`session-journal-nudge.sh`](../.claude/hooks/session-journal-nudge.sh)** checks whether the journal was touched this turn. If not, it blocks the stop **once** and reminds the agent to update it.

The nudge hook has two details worth stealing:

**Loop prevention by marker file.** A Stop hook that blocks can retrigger itself forever. The hook writes a `journal-nudge-pending` marker before blocking; if the marker already exists, it logs a warning and lets the session end. At most one nudge per stop cycle, guaranteed.

**THIN vs DETAILED mode.** If a governing plan/spec exists, the journal carries a `Live plan pointer` and each session appends *one line* (milestone + commit hash) — the plan document holds the narrative. With no governing doc, the journal itself is the canonical record. This stops journals from degenerating into either empty stubs or duplicated plans.

## 3. Mirrored hooks: the same lifecycle in both runtimes

Claude Code wires hooks in `.claude/settings.json`; Codex CLI in `.codex/hooks.json`. The events map cleanly (`SessionStart`, `PreToolUse`, `PostToolUse`, `Stop`), so I keep **one set of hook scripts** and two thin wiring files pointing at identical copies under `.claude/hooks/` and `.codex/hooks/`.

Rules that keep this maintainable:

- Hook scripts resolve the repo root themselves (`CLAUDE_PROJECT_DIR` if set, else `git rev-parse --show-toplevel`), so the same script runs unmodified in either runtime.
- Hooks **fail silent** on their own internal errors (never break the agent's turn for a broken nudge) but **fail loud** (`exit 2` / blocking) when the agent violated the contract.
- Anything hub-, CI-, or product-specific stays out of the shared scripts; those are per-repo additions.

## 4. The release-clean reviewer: a read-only gate on egress

The highest-stakes repos I run agents in are delivered to a customer's environment. Before anything is pushed to the delivery remote, a **reviewer subagent** scans the outgoing diff against a list of disallowed patterns — internal hostnames, personal paths, non-customer project names, credentials shapes, TODO-with-context leaks.

The reviewer is defined **once per runtime, in parity**:

- `.claude/agents/release-clean-reviewer.md` — a Claude Code subagent, read-only tools, explicit pattern list.
- `.codex/agents/release-clean-reviewer.toml` — the same policy as a Codex agent config (`sandbox_mode = "read-only"`).

Design choices that matter:

- **Read-only.** The reviewer can flag, never fix. Fixes go through the normal (governed) write path, so the gate itself can't be a leak vector.
- **The pattern list is data, not prose.** Each entry has an ID and a one-line rationale, so a finding is reportable ("blocked by rule L-07") and the list is reviewable in a diff.
- **Verdicts are binary.** `CLEAN` or `BLOCKED: <rule> <file:line>`. No "probably fine."

The same shape works for any egress gate: license compliance, PII scanning, "no generated files in src/".

## 5. What running both runtimes actually teaches you

Honest observations from parity-running both for a year — the kind of point of view you only earn by doing it:

- **Consolidate the tool surface.** In one agentic ops project I cut a 22-tool MCP surface to 10 intent-level tools and reliability went *up*. Agents pick correctly from a short menu of intents ("diagnose", "propose-fix") far more reliably than from a long menu of primitives. This holds for both runtimes.
- **Treat AI review comments as hypotheses.** When Codex reviews Claude's work (or vice versa), the review comment must be converted into a failing test before it's acted on — or explicitly rejected. Cross-model review is high-value precisely because the models disagree; unverified, those disagreements just generate churn.
- **CLI churn is real; adapt behind an interface.** Flag renames and output-format changes happen. Wrapping each CLI in a thin adapter (one place to fix `--flag` renames, output-schema capture, sandbox modes) turned breaking releases from an outage into a one-file patch.
- **Verification the agent can't game.** Byte-parity checks (`cmp`), golden fixtures, dual independent implementations of the same accounting — mechanical verification beats asking the agent "are you sure?" every time.

## Adopting this in your repo

1. Copy `.claude/`, `.codex/`, `templates/`, `scripts/` from this repo (see the [README quick start](../README.md)).
2. Write your `AGENTS.md` from the template; `cp AGENTS.md CLAUDE.md`; install the parity pre-commit.
3. `mkdir sessions/` and let the hooks enforce the journal discipline from session one.
4. Add a reviewer subagent only when you have a real egress boundary — start with the two hooks and the contract; they're 90% of the value.
