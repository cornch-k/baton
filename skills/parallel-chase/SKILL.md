---
name: parallel-chase
description: A coordinator plans three different lanes once; each lane runs its own flame chase in parallel. Lane 1 writes the run branch, lanes 2 and 3 work in their own worktrees, and a single-writer leaderboard feeds the best score into every fresh lane prompt. Run with /baton:parallel-chase "<task>".
argument-hint: "\"<task>\" [--eval \"<cmd>\"] [--goal max|min] [--rounds N] [--minutes M] [--check \"cmd\"] [--no-early-stop] [--resume [run-id]]"
disable-model-invocation: true
---

# parallel-chase

Arguments: $ARGUMENTS

Load the run protocol first (Skill tool → `baton:protocol`; if that fails, Read `${CLAUDE_PLUGIN_ROOT}/skills/protocol/SKILL.md`) and follow it. This file only adds what is specific to parallel-chase.

## Idea

When the right approach isn't obvious, try three at once. A coordinator plans three genuinely different lanes, and each lane is a small flame chase of its own. Lanes don't share a tree; they share only a leaderboard and one-line insights.

## Flags

- `--rounds N`: rounds, where one round is one turn in every active lane. Default 4. It replaces `--turns`.
- `--eval "<cmd>"` and `--goal max|min`: optional. With them, each lane is scored after every round (same contract as fixed-interrupt: exit 0, number on the last line).
- `--in-place` isn't supported: lane 1 always uses the run branch.

## Setup additions

1. **Coordinator** (fresh, `baton:coordinator`, worker model): header, TASK verbatim, and the evaluator if given. Parse its `BATON-LANES` block into `state.extra.lanes`.
2. Lane 1 works in the main checkout on `baton/<run-id>`. For lanes 2 and 3:
   ```bash
   git worktree add -q .baton/runs/<run-id>/lanes/lane-<i> -b baton/<run-id>-lane-<i>
   ```
3. Each lane alternates chaser-a and chaser-b, starting with chaser-a. Track `next`, `fails` and `held` per lane.

## Round

Spawn the current chaser of every active lane **in one message**, so the lanes run in parallel:

```
BATON parallel-chase · round <r>/<rounds> · lane <i> (<lane name>) · role <chaser> · run <run-id>

TASK:
<task, verbatim>

YOUR LANE'S APPROACH:
<the coordinator's approach for this lane>

STANCE (<stance name>):
<stance paragraph>

WORK ONLY INSIDE: <absolute path of this lane's directory>. cd there first.
LEADERBOARD: <"best so far: lane-<j> with <score>" or "no scores yet">
FROM OTHER LANES: <up to 3 "share:" lines other lanes reported last round, or "nothing">

You start fresh; this lane's workspace is the only handoff. Make the most valuable progress for your lane's approach this turn. Inside your BATON-REPORT you may add "share: <one line other lanes should know>" and "deliverable_ready: yes" when your lane has a complete solution.
```

After all lanes return:

1. In one Bash call, run the protocol's `turn` once per lane, with label `"r<r> lane-<i>"` and `-C <lane dir>` for lanes 2 and 3.
2. With `--eval`, in one Bash call, run `eval <run_dir> r<r>-lane-<i> -C <lane dir>` for each lane, one after another (not in parallel). Then update `leaderboard.json` in the run directory; you are its only writer.
3. A lane whose two turns in a row failed is held: it gets no more turns.

## Stop

- `--rounds` or `--minutes` used up.
- Every lane is held.
- Early stop, unless `--no-early-stop`: every active lane reported `deliverable_ready: yes` or `status: done` in the same round.

## Final report additions

The leaderboard, each lane's approach and branch (lane 1 is `baton/<run-id>`), and which lane looks best and why, in one line. Remove the lane worktrees with `git worktree remove <dir>` but keep their branches, so the user can merge the winner.
