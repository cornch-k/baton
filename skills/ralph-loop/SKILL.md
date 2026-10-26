---
name: ralph-loop
description: Repeats the same task every round in a fresh worker subagent, so only the repository carries over between rounds. Run with /baton:ralph-loop "<task>". (For the variant that keeps one session, use /baton:stateful-ralph.)
argument-hint: "\"<task>\" [--turns N] [--minutes M] [--check \"cmd\"] [--no-early-stop] [--in-place] [--resume [run-id]]"
disable-model-invocation: true
---

# ralph-loop

Arguments: $ARGUMENTS

Load the run protocol first (Skill tool → `baton:protocol`; if that fails, Read `${CLAUDE_PLUGIN_ROOT}/skills/protocol/SKILL.md`) and follow it. This file only adds what is specific to ralph-loop.

## Idea

Give the same prompt again and again to an agent with no memory. Each round has to rediscover the state from the repository, which keeps the repository honest: whatever isn't in the files is forgotten. Anthropic's own `ralph-loop` plugin repeats the prompt inside one session; that is `/baton:stateful-ralph` here. This flow restarts fresh every round.

## Roles

| Role | subagent_type | Model | Session |
|---|---|---|---|
| worker | `baton:worker` | worker model | fresh every round |

## Turn prompt

The same every round, apart from the header:

```
BATON ralph-loop · turn <n>/<max> · role worker · run <run-id>

TASK:
<task, verbatim>

You start fresh. Only the workspace (files and git history of branch <branch>) carries over from earlier rounds. Orient from it, make the most valuable progress on the TASK you can this round, and leave the workspace ready for a cold start.
```

## Stop

- The budget is used up, or a turn fails (protocol).
- Early stop, unless `--no-early-stop`: the `streak:` line shows `done x2` or more and `empty x1` or more.
