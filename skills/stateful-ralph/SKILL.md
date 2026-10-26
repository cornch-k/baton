---
name: stateful-ralph
description: Repeats the same task every round in one persistent worker session that remembers earlier rounds. Run with /baton:stateful-ralph "<task>".
argument-hint: "\"<task>\" [--turns N] [--minutes M] [--check \"cmd\"] [--no-early-stop] [--in-place] [--resume [run-id]]"
disable-model-invocation: true
---

# stateful-ralph

Arguments: $ARGUMENTS

Load the run protocol first (Skill tool → `baton:protocol`; if that fails, Read `${CLAUDE_PLUGIN_ROOT}/skills/protocol/SKILL.md`) and follow it. This file only adds what is specific to stateful-ralph.

## Idea

Like ralph-loop, but the worker keeps its session, so it remembers what it tried. It's faster on tasks where earlier reasoning matters, at the cost of the worker's context filling up and drifting.

## Roles

| Role | subagent_type | Model | Session |
|---|---|---|---|
| worker | `baton:worker` | worker model | persistent, named `<run-id>-worker` |

## Turn prompts

Round 1 (Agent call with `name`):

```
BATON stateful-ralph · turn 1/<max> · role worker · run <run-id>

TASK:
<task, verbatim>

You keep this session across rounds. Each round you will get the same TASK again. Make the most valuable progress you can this round and report.
```

Round n > 1 (SendMessage to `<run-id>-worker`):

```
BATON stateful-ralph · turn <n>/<max> · role worker · run <run-id>

Round <n>. Same TASK:
<task, verbatim>

Continue from where you are. Check what is still missing before you add anything.
```

Fallback: if the worker can't be reached, play the worker yourself in this session for the remaining rounds and say so in the log.

## Stop

- The budget is used up, or a turn fails (protocol).
- Early stop, unless `--no-early-stop`: the `streak:` line shows `done x2` or more and `empty x1` or more.
