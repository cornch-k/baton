---
name: cleanup-ralph
description: ralph-loop plus a cleaner that, every few turns, distills the workspace, writes a short NEXT.md, and squashes the epoch into one commit (old history kept in a tag). Run with /baton:cleanup-ralph "<task>".
argument-hint: "\"<task>\" [--cleanup-turns K] [--next-lines L] [--work-paths \"paths\"] [--repairs R] [--turns N] [--minutes M] [--check \"cmd\"] [--no-early-stop] [--in-place] [--resume [run-id]]"
disable-model-invocation: true
---

# cleanup-ralph

Arguments: $ARGUMENTS

Load the run protocol first (Skill tool → `baton:protocol`; if that fails, Read `${CLAUDE_PLUGIN_ROOT}/skills/protocol/SKILL.md`) and follow it, including its **Cleaning** section. Then Read `${CLAUDE_SKILL_DIR}/../ralph-loop/SKILL.md` and run exactly that flow (roles, turn prompt, stop rules), with these changes:

- The flow name in headers and commit messages is `cleanup-ralph`.
- Add one line to the end of the worker's turn prompt: `If NEXT.md exists at the repository root, read it first: a cleaner wrote it after distilling the workspace.`
- Every `--cleanup-turns` work turns, run the protocol's Cleaning steps.
- Also stop after 3 consecutive `empty` work turns.

## Why

Long fresh-session loops pile up strays: scratch files, dead experiments, half-abandoned approaches. Each fresh turn then spends its budget rediscovering them. A periodic cleaner keeps the tree small and leaves a ten-line pointer to what's next, while the full history stays reachable through the epoch tags.
