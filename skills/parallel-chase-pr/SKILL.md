---
name: parallel-chase-pr
description: Three lanes, each a flame chase on its own branch and worktree, propose candidates; a candidate is merged into the integration branch only when a fresh evaluation shows it improves the score. No reviewer, the measurement decides. Run with /baton:parallel-chase-pr "<task>" --eval "<cmd>".
argument-hint: "\"<task>\" --eval \"<cmd>\" [--goal max|min] [--rounds N] [--paths \"globs\"] [--minutes M] [--resume [run-id]]"
disable-model-invocation: true
---

# parallel-chase-pr

Arguments: $ARGUMENTS

Load the run protocol first (Skill tool → `baton:protocol`; if that fails, Read `${CLAUDE_PLUGIN_ROOT}/skills/protocol/SKILL.md`) and follow it. This file only adds what is specific to parallel-chase-pr.

## Idea

Like parallel-chase, but no lane writes the shared tree directly. Lanes propose; the integration branch takes a change only when a measurement on a clean checkout says it is better. Proposals are local merge candidates, not GitHub pull requests: nothing is pushed.

## Flags

- `--eval "<cmd>"` (required) and `--goal max|min` (default `max`): same contract as fixed-interrupt (exit 0, number on the last line).
- `--rounds N`: default 4. It replaces `--turns`.
- `--paths "<glob>,<glob>"`: optional. A candidate whose diff touches files outside these globs is rejected.
- `--in-place` isn't supported.

If `--eval` is missing, ask the user for it and stop.

## Setup additions

1. The run branch `baton/<run-id>` is the **integration branch**. The main checkout stays on it.
2. Pass the evaluator as the `eval:` line of `start` (protocol), then score the integration branch on a clean checkout: `eval <run_dir> integration-0 --sha HEAD`. Store the score as `integration_score`.
3. **Coordinator** (fresh, `baton:coordinator`, worker model): header, TASK, evaluator and goal. Parse `BATON-LANES`.
4. Every lane, including lane 1, gets its own worktree and branch:
   ```bash
   git worktree add -q .baton/runs/<run-id>/lanes/lane-<i> -b baton/<run-id>-lane-<i>
   ```
5. Each lane alternates chaser-a and chaser-b, starting with chaser-a.

## Round

Spawn the current chaser of every active lane in one message:

```
BATON parallel-chase-pr · round <r>/<rounds> · lane <i> (<lane name>) · role <chaser> · run <run-id>

TASK:
<task, verbatim>

YOUR LANE'S APPROACH:
<approach>

STANCE (<stance name>):
<stance paragraph>

WORK ONLY INSIDE: <absolute lane directory>. cd there first.
INTEGRATION: branch baton/<run-id>, score <integration_score> (goal: <max|min>). Evaluator: `<eval>`.
<if the integration branch changed since this lane last merged it: "The integration branch moved. Start by running `git merge baton/<run-id>` in your lane and resolving any conflicts; this merge is the one git operation you may run.">
<if this lane's last candidate was rejected: "Your last candidate was rejected: <reason>.">

You start fresh; your lane's workspace is the only handoff. When your lane has a change you expect to beat the integration score, add "ready: yes" inside your BATON-REPORT. Only a measured improvement gets merged.
```

## After each round

1. In one Bash call, run the protocol's `turn` once per lane, with label `"r<r> lane-<i>"` and `-C <lane dir>`. Log every merge and rejection to `log.md` too, one line each (evaluations log themselves).
2. Each lane that reported `ready: yes` proposes its head commit. A newer proposal from the same lane replaces its older one.
3. **Evaluate** every proposal on a clean checkout, one after another, in one Bash call:
   ```bash
   sh "${CLAUDE_PLUGIN_ROOT}/scripts/baton.sh" eval <run_dir> lane-<i>-<sha7> --sha <sha> --beat <integration_score> --goal <goal>
   ```
   It checks the commit out in a temporary worktree, runs `eval.sh` there, removes the worktree, and writes the receipt `receipts/lane-<i>-<sha7>.json` (commit, score, exit code, the evaluator's and the log's sha256, time).
4. Reject a proposal if its evaluation was rejected, if it touches paths outside `--paths` (`git diff --name-only baton/<run-id>...<sha>`), or if it doesn't beat `integration_score` (`beats ...: no`).
5. Take the single best remaining proposal and merge it into the integration branch: `git merge --no-ff -q -m "baton(parallel-chase-pr): merge lane-<i> <sha7> (<score>)" <sha>`. If the merge conflicts, run `git merge --abort` and reject it as "conflicts with integration".
6. Evaluate the merged integration head the same way (`eval <run_dir> integration-<r> --sha HEAD --beat <integration_score> --goal <goal>`). If it doesn't beat the old score, undo the merge with `git reset -q --hard HEAD~1` and reject the proposal. Otherwise update `integration_score`.
7. At most one merge per round. Rejected and unmerged lanes hear why in their next prompt.
8. A lane whose two turns in a row failed is held.

## Stop

- `--rounds` or `--minutes` used up, or every lane is held.

## Final report additions

Each merge with its lane, commit and score, the integration score from start to end, the rejected proposals with reasons, and the lane branches. Remove the lane worktrees with `git worktree remove <dir>` and keep their branches.
