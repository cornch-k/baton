---
name: rlcr
description: Phase 3 of plan-then-build. A persistent builder builds a plan; after every turn, stop checks run and a fresh reviewer verifies the last review's findings and what changed since; when nothing is left, one whole-change review by a different model must also come back clean. Run with /baton:rlcr [docs/plan.md].
argument-hint: "[plan path] [--rounds N] [--minutes M] [--check \"cmd\"] [--in-place] [--resume [run-id]]"
disable-model-invocation: true
---

# rlcr

Arguments: $ARGUMENTS

Load the run protocol first (Skill tool → `baton:protocol`; if that fails, Read `${CLAUDE_PLUGIN_ROOT}/skills/protocol/SKILL.md`) and follow it. This file only adds what is specific to rlcr.

## Idea

A Ralph loop with code review every round. The builder keeps its memory and hears the findings in the same session. The reviewer arrives with no memory, re-verifies the last review's findings, checks what changed since, and returns findings. "Done" needs both: a round reviewer that finds nothing left, and one whole-change review by a different model that comes back clean. A round costs the builder's turn, one `turn` call and one reviewer; nothing is reviewed twice unless it changed.

## Flags

- Plan path: the first non-flag argument, default `docs/plan.md`, relative to the repository root. It must exist. In the `start` call the TASK is the plan path on one line; there is no other TASK, so never ask the user for one.
- `--rounds N`: builder rounds, default 8. Pass it to `start` as `--turns N`; that number is `<max>` in every header and the only budget. `--turns` means the same thing; if both are given, the smaller wins.

## Setup

In this order, before anything else:

1. Read the plan. If it has `PENDING:` lines, ask the user up to two of them with AskUserQuestion (they may skip) and append the answers under a "Decisions (answered at build start)" heading at the end of the plan.
2. `start rlcr --allow <plan path> --turns <N> ...` (protocol), with the plan path as the `task:`. `--allow` lets the plan be the only uncommitted file and, if it is new or modified, commits it on the run branch as `baton(rlcr): plan`. The gates find that commit themselves (else they use the base); nothing is stored and no git command of your own is needed.

## Roles

| Role | subagent_type | Model | Session |
|---|---|---|---|
| builder | `baton:worker` | worker model | persistent, named `<run-id>-builder` |
| reviewer | `baton:reviewer` | reviewer model | fresh every round |
| final reviewer | `baton:reviewer` | **worker model**, so the two reviews don't share a model's blind spots | fresh, at most twice per run |

## Round

1. **Builder.** Round 1 (Agent call with `name`):
   ```
   BATON rlcr · turn 1/<max> · role builder · run <run-id>

   PLAN: <plan path> (read it first; never edit it)
   CHECK: <the --check command> (runs after each of your turns; keep it passing)

   Build the plan in step order. Each turn: finish as many whole steps as you can verify (run each step's acceptance check, keep tests green), then stop and report; don't start a step you can't finish this turn. A PENDING: line with no decision: take the simplest option and say which in your report. You keep this session: after each turn, stop checks run and a fresh reviewer reads what changed; its instructions arrive as your next message. If an instruction is wrong, don't follow it: add `disputed: <the instruction> — <your evidence>` to your report. `status: done` means every step meets its acceptance check.
   ```
   Leave the CHECK line out when there is no `--check`.
   Round n > 1 (SendMessage to `<run-id>-builder`): the header line; then, only if a gate failed and isn't waived, `STOP CHECKS FAILED:` with those gates' lines from the `turn` output, verbatim; then the reviewer's `next_prompt`, verbatim (if it is empty: `Fix the stop checks above.`). Don't send the findings list as well: `next_prompt` already holds what matters, and the builder's context is the scarce resource.
2. **Turn and stop checks** in one call: `turn <run_dir> t<n> builder <status> --gates <plan path>`. After the usual lines it prints the gates, each `pass` or `fail` with at most three offending `path:line: content` lines (never a secret's value; G1 adds the check command and the log's last lines), and a last line `gates: all pass` or `gates: fail G..`. "Added lines" are those added since the plan commit:
   - G1: the turn's check passed, if `--check` was given.
   - G2: no conflict markers in added lines.
   - G3: no new stubs in added lines (`TODO`, `FIXME`, `XXX` as words, `raise NotImplementedError`, `unimplemented!(`, `todo!(`).
   - G4: no newly skipped or focused tests in added lines (pytest/unittest skip, `it.skip(`/`.only(`, `xit(`, `@Disabled`, `@Ignore`, `#[ignore]`, `t.Skip(`).
   - G5: nothing that looks like a secret in added lines (private keys, AWS, OpenAI/Anthropic-style and GitHub tokens).
   - G6: the plan wasn't edited since the plan commit.
   If the `budget:` line says `spent`, this round's review still runs (and the final review if it says done), and no builder round follows.
3. **Reviewer** (fresh):
   ```
   BATON rlcr · turn <n>/<max> · role reviewer · run <run-id>

   PLAN: <plan path>
   CHANGE: this round `git diff <last reviewed commit>..HEAD`; the whole run `git diff --stat <base>..HEAD`.
   CHECK: <the --check command> (this round: pass|fail)
   STOP CHECKS: <the failing gates' lines, or "all pass">
   BUILDER'S CLAIM (verify, don't trust): <its summary and changed lines>
   LAST REVIEW: steps_ok: <its steps_ok>; findings: <its findings, verbatim>
   BUILDER DISPUTES: <its disputed lines, or "none">

   First re-verify each finding of the last review and settle each dispute (drop a finding the builder refutes). Then check the plan steps this round's change touches against their acceptance checks; re-check a step in steps_ok only if the change touches it. Out of scope: the plan's non-goals, PENDING lines without a decision, style, and pre-existing problems the plan doesn't name. A stop-check hit that is a false positive: say so with `gate_ok: G<k>`. done: true only when every plan step is in steps_ok (yours or inherited) and nothing material is left. Add to your verdict, after done:, `steps_ok: <every step verified so far, comma-separated>` and `gate_ok: <gates, or none>`.
   ```
   With no `--check`, the CHECK line reads `CHECK: none given. Find and run the project's tests; if you can't run them, say so and don't return done: true.` In round 1, LAST REVIEW is `none`. `<last reviewed commit>` is HEAD when the previous reviewer ran: the commit printed by the previous round's `turn` call (the base in round 1; if that turn was `empty`, the last commit before it).
4. **Verdict.** Use the last `BATON-VERDICT` block in the reviewer's message. If it is missing, or says `done: false` with findings `none` and an empty `next_prompt`, spawn the reviewer once more; a second unusable verdict stops the run as `failed`. `done: true` with findings other than `none` counts as `done: false` with those findings as the `next_prompt`. A gate the verdict lists under `gate_ok` counts as passed for this round; G1 and G6 can't be waived.
5. **Final review**, when the verdict is `done: true` and every gate passes or is waived. Fresh `baton:reviewer` with the worker model:
   ```
   BATON rlcr · final review · role reviewer · run <run-id>

   PLAN: <plan path>
   CHECK: <the --check command, or "none given: find and run the project's tests">

   The round reviewer passed this change; assume it missed something. Review `git diff <base>..HEAD` against the plan: correctness, security, error handling, and tests that don't really test. Run the tests, and try one input per plan step that the tests don't cover. Report only real defects. done: true if there are none.
   ```
   `done: true` finishes the run as complete. Otherwise, if the budget is spent, stop the run as `stopped` with its findings as the reason; else its `next_prompt` goes to the builder as the next round (the header line, `FINAL REVIEW FOUND:`, then the `next_prompt` verbatim) and that round's reviewer runs as usual. A second final review gets the first's findings verbatim after the PLAN line, as `EARLIER FINDINGS:`, and checks only whether they are fixed and whether the fixes broke anything. There is no third: after two final reviews, a round verdict of `done: true` with gates passing finishes the run.

Fallback: a SendMessage error or a `missing` builder report means the builder can't be reached. Respawn it fresh once, named `<run-id>-builder-r<n>`, with the round-1 prompt plus `RESUMING: earlier turns are in git log; continue from the first step that doesn't meet its check.` and the latest `next_prompt`; send later messages there, and mention it in the final report. Never do the builder's work in this session.

## Stop

- `finished`: a round verdict `done: true`, every gate passed or waived, and the final review clean (or already run twice).
- `stopped`: `--rounds` or `--minutes` spent (after that round's review), or a stall: the `streak:` line shows `empty x2` and the new findings repeat the last round's. Put both sides (the finding and the builder's dispute) in the reason.
- `failed`: a failed turn (protocol), or two unusable verdicts in a row.
- `--no-early-stop` has no effect in rlcr.

In the final report, say whether the run had a `--check`; without one, the only tests run were those the reviewers chose.

## Resume

After `resume` (protocol), the plan path is the `task:` line it prints, and the builder session is gone: spawn the builder as in the fallback (named `<run-id>-builder-r<n>`), with the next turn number from the last `t<n>` line. That round's reviewer gets `LAST REVIEW: none` and HEAD at resume as the last reviewed commit.
