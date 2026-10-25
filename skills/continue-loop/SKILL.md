---
name: continue-loop
description: Gives the task once to a persistent worker, then sends only "continue" each round. Run with /baton:continue-loop "<task>".
argument-hint: "\"<task>\" [--turns N] [--minutes M] [--check \"cmd\"] [--no-early-stop] [--in-place] [--resume [run-id]]"
disable-model-invocation: true
---

# continue-loop

Arguments: $ARGUMENTS

Load the run protocol first (Skill tool → `baton:protocol`; if that fails, Read `${CLAUDE_PLUGIN_ROOT}/skills/protocol/SKILL.md`) and follow it. This file only adds what is specific to continue-loop.

## Idea

The simplest long run: state the task once, then keep saying "continue". The worker decides what to do next from its own memory and the repository.

## Roles

| Role | subagent_type | Model | Session |
|---|---|---|---|
| worker | `baton:worker` | worker model | persistent, named `<run-id>-worker` |

## Turn prompts

Round 1 (Agent call with `name`):

```
BATON continue-loop · turn 1/<max> · role worker · run <run-id>

TASK:
<task, verbatim>

You keep this session. After this turn you will only be told "continue". End every turn with your BATON-REPORT.
```

Round n > 1 (SendMessage to `<run-id>-worker`), exactly:

```
continue
```

Fallback: if the worker can't be reached, play the worker yourself in this session for the remaining rounds and say so in the log.

## Stop

- The budget is used up, or a turn fails (protocol).
- Early stop, unless `--no-early-stop`: two consecutive rounds reported `status: done`, and the latest was `empty`.
