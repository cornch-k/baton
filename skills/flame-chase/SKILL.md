---
name: flame-chase
description: Two chasers with different models and stances take turns on one task, each turn a fresh subagent, passing only the workspace, so every turn checks work it didn't write. Run with /baton:flame-chase "<task>".
argument-hint: "\"<task>\" [--turns N] [--minutes M] [--check \"cmd\"] [--no-early-stop] [--in-place] [--resume [run-id]]"
disable-model-invocation: true
---

# flame-chase

Arguments: $ARGUMENTS

Load the run protocol first (Skill tool → `baton:protocol`; if that fails, Read `${CLAUDE_PLUGIN_ROOT}/skills/protocol/SKILL.md`) and follow it. This file only adds what is specific to flame-chase.

## Idea

Two agents fail in different ways. Put them on the same task, let them take turns, and give each turn nothing but the workspace. Every turn starts by checking work the other agent wrote, so one agent's blind spots don't compound over a long run. Baton makes the two chasers differ by model and by stance (see the protocol's configuration).

## Roles

| Role | subagent_type | Model | Stance | Session |
|---|---|---|---|---|
| chaser-a | `baton:chaser-a` | chaser A model | chaser A stance | fresh every turn |
| chaser-b | `baton:chaser-b` | chaser B model | chaser B stance | fresh every turn |

Turn 1 is chaser-a; then they alternate. `state.next` holds whose turn is next.

## Turn prompt

```
BATON flame-chase · turn <n>/<max> · role <chaser-a|chaser-b> · run <run-id>

TASK:
<task, verbatim>

STANCE (<stance name>):
<stance paragraph from the protocol>

You start fresh. Nothing from earlier turns reaches you except the workspace: the files and the git history of branch <branch>. Orient from them, make the most valuable progress on the TASK you can this turn, and leave the workspace so the other chaser can continue cold.
```

Never add the other chaser's report, your own summary of earlier turns, check results, or hints. The workspace is the only handoff, and that is what makes this flow work.

## Stop

- The budget is used up, or a turn fails (protocol).
- Early stop, unless `--no-early-stop`: the last two turns, one by each chaser, both reported `status: done`, and the latest was `empty`.
