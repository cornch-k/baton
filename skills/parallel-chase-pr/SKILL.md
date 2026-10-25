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
2. Score the integration branch: evaluate it in a clean worktree (see Evaluate below) and store `integration_score`.
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

1. Commit each lane in its own directory, and append one protocol log line per lane to `log.md`, starting `r<r> lane-<i>` instead of `t<n>`. Log every evaluation, merge and rejection there too, one line each.
2. Each lane that reported `ready: yes` proposes its head commit. A newer proposal from the same lane replaces its older one.
3. **Evaluate** every proposal, one at a time:
   ```bash
   git worktree add -q --detach .baton/runs/<run-id>/eval-wt <sha>
   ( cd .baton/runs/<run-id>/eval-wt && <eval> ) > .baton/runs/<run-id>/eval-<lane>-<sha7>.log 2>&1; echo "exit=$?"
   git worktree remove --force .baton/runs/<run-id>/eval-wt
   ```
   Write a receipt `receipts/<lane>-<sha7>.json` with lane, commit, score, command, exit code, the log's `shasum -a 256`, and the time.
4. Reject a proposal if its evaluation failed, if it touches paths outside `--paths` (`git diff --name-only baton/<run-id>...<sha>`), or if its score doesn't beat `integration_score`.
5. Take the single best remaining proposal and merge it into the integration branch: `git merge --no-ff -q -m "baton(parallel-chase-pr): merge lane-<i> <sha7> (<score>)" <sha>`. If the merge conflicts, run `git merge --abort` and reject it as "conflicts with integration".
6. Evaluate the merged integration head the same way. If it doesn't beat the old `integration_score`, undo the merge with `git reset -q --hard HEAD~1` and reject the proposal. Otherwise update `integration_score`.
7. At most one merge per round. Rejected and unmerged lanes hear why in their next prompt.
8. A lane whose two turns in a row failed is held.

## Stop

- `--rounds` or `--minutes` used up, or every lane is held.

## Final report additions

Each merge with its lane, commit and score, the integration score from start to end, the rejected proposals with reasons, and the lane branches. Remove the lane worktrees with `git worktree remove <dir>` and keep their branches.
