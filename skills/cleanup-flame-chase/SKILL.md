---
name: cleanup-flame-chase
description: flame-chase plus a cleaner working between the two chasers. Every few turns it distills the workspace, writes a short NEXT.md, and squashes the epoch into one commit (old history kept in a tag). Run with /baton:cleanup-flame-chase "<task>".
argument-hint: "\"<task>\" [--cleanup-turns K] [--next-lines L] [--work-paths \"paths\"] [--repairs R] [--turns N] [--minutes M] [--check \"cmd\"] [--no-early-stop] [--in-place] [--resume [run-id]]"
disable-model-invocation: true
---

# cleanup-flame-chase

Arguments: $ARGUMENTS

Load the run protocol first (Skill tool → `baton:protocol`; if that fails, Read `${CLAUDE_PLUGIN_ROOT}/skills/protocol/SKILL.md`) and follow it, including its **Cleaning** section. Then Read `${CLAUDE_SKILL_DIR}/../flame-chase/SKILL.md` and run exactly that flow (roles, turn prompt, stop rules), with these changes:

- The flow name in headers and commit messages is `cleanup-flame-chase`.
- Add one line to the end of each chaser's turn prompt: `If NEXT.md exists at the repository root, read it first: a cleaner wrote it after distilling the workspace.`
- Every `--cleanup-turns` work turns, run the protocol's Cleaning steps. The cleaner is not a chaser and doesn't change whose turn is next.
- Also stop after 3 consecutive `empty` work turns.

## Why

In a long chase, each chaser leaves traces of its own approach. The cleaner sits between them, keeps the tree to the work that matters, and leaves a short NEXT.md, so each fresh chaser spends its turn on the task instead of on archaeology. NEXT.md is part of the tree, so the "workspace is the only handoff" rule still holds.
