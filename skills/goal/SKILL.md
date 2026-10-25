---
name: goal
description: Hands the task to one persistent worker as its own goal; it keeps working until it says the goal is met, with evidence. No independent judge (use /baton:rlar for that). Run with /baton:goal "<goal>".
argument-hint: "\"<goal>\" [--turns N] [--minutes M] [--check \"cmd\"] [--in-place] [--resume [run-id]]"
disable-model-invocation: true
---

# goal

Arguments: $ARGUMENTS

Load the run protocol first (Skill tool → `baton:protocol`; if that fails, Read `${CLAUDE_PLUGIN_ROOT}/skills/protocol/SKILL.md`) and follow it. This file only adds what is specific to goal.

## Idea

Make the task the agent's own goal and let it judge when the goal is met. It works best for goals with a measurable finish line ("bench under 200 ms", "all tests in tests/api pass"). The worker judges its own work; when "is it done?" shouldn't be answered by the one who did it, use `/baton:rlar`.

## Roles

| Role | subagent_type | Model | Session |
|---|---|---|---|
| worker | `baton:worker` | worker model | persistent, named `<run-id>-worker` |

## Turn prompts

Round 1 (Agent call with `name`):

```
BATON goal · turn 1/<max> · role worker · run <run-id>

YOUR GOAL:
<task, verbatim>

This is your own goal. Keep working on it across turns: profile, change, measure, repeat. Measure; don't guess. When the goal is met, report status: done and put the evidence in the summary (the command you ran and its result).
```

Round n > 1 (SendMessage to `<run-id>-worker`):

```
BATON goal · turn <n>/<max> · role worker · run <run-id>

Keep going toward your goal. If it is met, report status: done with the evidence.
```

Fallback: if the worker can't be reached, play the worker yourself in this session for the remaining rounds and say so in the log.

## Stop

- The worker reports `status: done`. Put its evidence line in the final report, and say plainly that it is the worker's own judgment.
- The budget is used up, or a turn fails (protocol).
