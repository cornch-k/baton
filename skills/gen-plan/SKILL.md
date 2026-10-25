---
name: gen-plan
description: Phase 2 of plan-then-build. A planner that keeps its memory writes a plan; a fresh analyst reviews it each round until they agree. Run with /baton:gen-plan <idea-file-or-text>, then /baton:rlcr.
argument-hint: "<idea file or text> [--out docs/plan.md] [--rounds N] [--force]"
disable-model-invocation: true
---

# gen-plan

Arguments: $ARGUMENTS

Load the run protocol first (Skill tool → `baton:protocol`; if that fails, Read `${CLAUDE_PLUGIN_ROOT}/skills/protocol/SKILL.md`) and follow it. This is a **doc-only flow**: no run branch, no commits, and it may run on a dirty tree. This file only adds what is specific to gen-plan.

## Idea

The side that writes remembers; the side that reads does not. The planner keeps its session so revisions build on each other. The analyst starts fresh every round so it judges the plan as a stranger would.

## Flags

- INPUT: a path to an idea file (for example from `/baton:gen-idea`), or the idea as text.
- `--out <path>`: default `docs/plan.md`.
- `--rounds N`: maximum analyst rounds, default 3.
- `--force`: allow overwriting an existing output file.

## Roles

| Role | subagent_type | Model | Session |
|---|---|---|---|
| planner | `baton:worker` | worker model | persistent, named `<run-id>-planner` |
| analyst | `baton:reviewer` | reviewer model | fresh every round |

## Round

1. **Planner.** Round 1 (Agent call with `name`):
   ```
   BATON gen-plan · turn 1/<rounds> · role planner · run <run-id>

   INPUT:
   <the idea file's path and "read it first", or the idea text verbatim>

   Write a plan for this repository to <out>. Write no code and change no other file. Use these sections:
   - Goal
   - Context: the facts about this repository the plan relies on, with file references
   - Scope and non-goals
   - Steps: numbered; each with an acceptance check that a reviewer can run or read
   - Risks
   - Test plan
   - Decisions: each line "RESOLVED: <decision>" or "PENDING: <question> (options: ...)". Use PENDING only for what truly needs a human.
   You keep this session. A fresh analyst will review the plan and its objections will come back to you.
   ```
   Round n > 1 (SendMessage to `<run-id>-planner`): the header line, then "Revise <out> to answer these objections. Where you disagree, say why in the plan itself:" followed by the analyst's findings and `next_prompt`, verbatim.
2. **Analyst** (fresh):
   ```
   BATON gen-plan · turn <n>/<rounds> · role analyst · run <run-id>

   INPUT: <same as above>
   PLAN: <out>

   Review the plan against the INPUT and this repository. Object to anything wrong, missing, vague, untestable or risky; check that the Context matches the code. Return done: true only if you agree with the plan as written.
   Add the line "about_repo: yes|no": no if the plan isn't about this repository.
   ```

## Stop

- `about_repo: no`: stop and say the plan doesn't fit this repository.
- `done: true` and no `PENDING` line in the plan: finished. Tell the user to read `<out>`, then run `/baton:rlcr <out>`.
- `done: true` with `PENDING` lines: stop and show those questions to the user. They decide, edit the plan, then run `/baton:rlcr`.
- `--rounds` used up without agreement: stop and show the last objections.
- A failed turn (protocol).
