---
name: rlcr
description: Phase 3 of plan-then-build. A persistent builder builds a plan; after every turn, stop checks run and a fresh reviewer returns findings; once nothing is left, a whole-change code review must also come back clean. Run with /baton:rlcr [docs/plan.md].
argument-hint: "[plan path] [--rounds N] [--turns N] [--minutes M] [--check \"cmd\"] [--in-place] [--resume [run-id]]"
disable-model-invocation: true
---

# rlcr

Arguments: $ARGUMENTS

Load the run protocol first (Skill tool → `baton:protocol`; if that fails, Read `${CLAUDE_PLUGIN_ROOT}/skills/protocol/SKILL.md`) and follow it. This file only adds what is specific to rlcr.

## Idea

A Ralph loop with code review every round. The builder keeps its memory and hears the findings in the same session. The reviewer arrives with no memory, reads the repository and returns findings. "Done" needs both: the round reviewer finds nothing left, and a separate review of the whole change comes back clean.

## Flags

- Plan path: the first non-flag argument, default `docs/plan.md`. It must exist.
- `--rounds N`: maximum builder rounds, default 8. It also caps `--turns`.

## Setup additions

- If the plan file is the only uncommitted change, run `start rlcr --allow <plan path> ...`, then commit it on the run branch: `git add -- <plan path> && git commit -q -m "baton(rlcr): plan"`, and that commit is `plan_commit`. Otherwise `plan_commit` is the base. Store it in `state.extra.plan_commit`.
- If the plan has `PENDING:` lines, ask the user up to two of them with AskUserQuestion before building, and let them skip. Append the answers under a "Decisions (answered at build start)" heading in the plan and commit that change.

## Roles

| Role | subagent_type | Model | Session |
|---|---|---|---|
| builder | `baton:worker` | worker model | persistent, named `<run-id>-builder` |
| reviewer | `baton:reviewer` | reviewer model | fresh every round |
| final reviewer | `baton:reviewer` | reviewer model | fresh, once nothing is left |

## Round

1. **Builder.** Round 1 (Agent call with `name`):
   ```
   BATON rlcr · turn 1/<max> · role builder · run <run-id>

   PLAN: <plan path> (read it first; don't edit it)

   Build the plan, step by step, meeting each step's acceptance check. You keep this session. After each turn, stop checks run and a fresh reviewer with no memory reads the repository; its findings come back to you as your next message.
   ```
   Round n > 1 (SendMessage to `<run-id>-builder`): the header line, then "Stop checks failed:" with the failing gates (if any), then the reviewer's findings and `next_prompt`, verbatim.
2. **Turn call** (protocol): `turn <run_dir> t<n> builder <status>`.
3. **Stop checks**, in one call: `gates <run_dir> <plan path> <plan_commit>`. It prints pass or fail for each gate, at most three offending lines each (never a secret's value), and a last line `gates: all pass` or `gates: fail G..`. "Added lines" are those added since `plan_commit`:
   - G1: the turn's check passed, if `--check` was given.
   - G2: no conflict markers in the tree.
   - G3: no new stubs in added lines (TODO, FIXME, XXX, NotImplementedError, `unimplemented!`, `todo!(`).
   - G4: no newly skipped or disabled tests in added lines.
   - G5: nothing that looks like a secret in added lines (private keys, AWS, OpenAI-style and GitHub tokens).
   - G6: the builder didn't edit the plan since `plan_commit`.
4. **Reviewer** (fresh):
   ```
   BATON rlcr · turn <n>/<max> · role reviewer · run <run-id>

   PLAN: <plan path>
   CHANGES: `git log --oneline <base>..HEAD`; start from `git diff --stat <base>..HEAD`.
   WHAT THE BUILDER SAID: <its summary, changed and next lines>
   STOP CHECKS: <the gates output>

   List what is left: plan steps not done or not meeting their acceptance check, bugs, missing or hollow tests. done: true only if nothing is left.
   ```
5. If the reviewer returns `done: true` and every stop check passes, run the **final review** (fresh):
   ```
   BATON rlcr · final review · role reviewer · run <run-id>

   PLAN: <plan path>
   Review the whole change `git diff <base>..HEAD` against the plan: correctness, security, error handling, and tests that don't really test. Report only real defects. done: true if there are none.
   ```
   `done: true` here finishes the run as complete. Otherwise its findings go to the builder as the next round.

Fallback: if the builder can't be reached, respawn it fresh with the plan path plus the latest findings, and log it.

## Stop

- Complete: the round reviewer finds nothing left, every stop check passes, and the final review is clean.
- `--rounds` used up, the budget used up, or a failed turn (protocol).
