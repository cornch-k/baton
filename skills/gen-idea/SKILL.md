---
name: gen-idea
description: Phase 1 of plan-then-build. Turns a loose idea into a draft file with a main direction and alternatives, checked against the repository. Writes no code. Run with /baton:gen-idea "<idea>", then /baton:gen-plan, then /baton:rlcr.
argument-hint: "\"<idea>\" [--out ideas/<slug>.md] [--directions N] [--force]"
disable-model-invocation: true
---

# gen-idea

Arguments: $ARGUMENTS

Load the run protocol first (Skill tool → `baton:protocol`; if that fails, Read `${CLAUDE_PLUGIN_ROOT}/skills/protocol/SKILL.md`) and follow it. This is a **doc-only flow**: no run branch, no commits, and it may run on a dirty tree. This file only adds what is specific to gen-idea.

## Flags

- `--out <path>`: default `ideas/<slug>.md`, where `<slug>` is a short kebab-case name you derive from the idea.
- `--directions N`: how many directions to explore, default 5.
- `--force`: allow overwriting an existing output file.

## Roles

| Role | subagent_type | Model | Session |
|---|---|---|---|
| drafter | `baton:worker` | worker model | one turn, named `<run-id>-drafter` (kept only for one repair) |

## Turn prompt

```
BATON gen-idea · turn 1/1 · role drafter · run <run-id>

IDEA:
<task, verbatim>

Turn this loose idea into a draft. Write no code and change no file other than <out>.
Explore <N> directions. Check each against this repository (read only what each direction depends on). Then write <out> with these sections:
1. Idea: the idea restated in two or three sentences.
2. Main direction: what, why, and how it fits this repository, with file references.
3. Alternatives: each direction you didn't pick, with its trade-off against the main one.
4. Open questions: decisions a human should make.
5. Risks.
Report status: done when the file is written.
```

## After the turn

1. If `<out>` doesn't exist, send the drafter one repair message saying so. If it still doesn't exist, stop as failed.
2. Compare `git status --porcelain` with what it showed before the run. If the drafter changed any other file, list those files to the user rather than reverting them, since the tree may have been dirty before.
3. Report the path and tell the user to read and edit it, then run `/baton:gen-plan <out>`.
