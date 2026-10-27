---
name: rlar
description: Ralph loop with agentic review. A persistent actor works; after every turn a fresh reviewer that never saw the work reads the repository, decides whether the task is done, and writes the actor's next prompt. Run with /baton:rlar "<task>".
argument-hint: "\"<task>\" [--turns N] [--minutes M] [--check \"cmd\"] [--in-place] [--resume [run-id]]"
disable-model-invocation: true
---

# rlar

Arguments: $ARGUMENTS

Load the run protocol first (Skill tool → `baton:protocol`; if that fails, Read `${CLAUDE_PLUGIN_ROOT}/skills/protocol/SKILL.md`) and follow it. This file only adds what is specific to rlar.

## Idea

"Is it done?" shouldn't be answered by the agent that did the work. The actor keeps its memory; the reviewer starts fresh every time, sees only the task, what the actor said, and the repository, and its review becomes the actor's next prompt.

## Roles

| Role | subagent_type | Model | Session |
|---|---|---|---|
| actor | `baton:worker` | worker model | persistent, named `<run-id>-actor` |
| reviewer | `baton:reviewer` | reviewer model | fresh every round |

`--turns` counts actor turns. Reviews don't count.

## Round

1. **Actor.** Round 1 (Agent call with `name`):
   ```
   BATON rlar · turn 1/<max> · role actor · run <run-id>

   TASK:
   <task, verbatim>

   You keep this session. After each of your turns, a fresh reviewer who never saw you work reads the repository and decides whether the TASK is done. If it isn't, its instructions become your next message.
   ```
   Round n > 1 (SendMessage to `<run-id>-actor`): the header line, then the reviewer's `next_prompt`, verbatim.
2. **Turn call** (protocol): `turn <run_dir> t<n> actor <status>`.
3. **Reviewer** (fresh):
   ```
   BATON rlar · turn <n>/<max> · role reviewer · run <run-id>

   TASK:
   <task, verbatim>

   WHAT THE ACTOR SAID THIS TURN (verify, don't trust):
   <the actor's summary and changed lines>

   COMMITS THIS RUN: `git log --oneline <base>..HEAD`; start from `git diff --stat <base>..HEAD`.
   <if --check: "Check command: <cmd> (last result: <pass|fail from the turn call>)">

   Decide whether the TASK is completely done in the repository as it is now. If it isn't, write next_prompt: the exact instructions for the actor's next turn.
   ```
4. `done: true` stops the run as finished. Otherwise go to the next round.

Fallback: if the actor can't be reached, respawn it fresh with the TASK plus the latest `next_prompt` and log it.

## Stop

- The reviewer returns `done: true`.
- The budget is used up, or a turn fails (protocol).
