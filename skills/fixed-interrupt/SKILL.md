---
name: fixed-interrupt
description: Two chasers alternate in tenures of k accepted experiments, scored by a trusted evaluator command the orchestrator runs; at the end a blind reviewer (identities and scores hidden) picks the winner. For tasks with a measurable score. Run with /baton:fixed-interrupt "<task>" --eval "<cmd>".
argument-hint: "\"<task>\" --eval \"<cmd>\" [--goal max|min] [--k N] [--review-reserve M] [--turns N] [--minutes M] [--in-place] [--resume [run-id]]"
disable-model-invocation: true
---

# fixed-interrupt

Arguments: $ARGUMENTS

Load the run protocol first (Skill tool → `baton:protocol`; if that fails, Read `${CLAUDE_PLUGIN_ROOT}/skills/protocol/SKILL.md`) and follow it. This file only adds what is specific to fixed-interrupt.

## Idea

Alternate on a fixed schedule instead of every turn: one chaser holds the tree for k accepted experiments, then the other takes over. Only the trusted evaluator decides what counts as an accepted experiment, and the final choice comes from a blind review by the side that didn't write the latest accepted candidate.

## Flags

- `--eval "<cmd>"` (required): run from the repository root, exit code 0, and print the score as a number on the last line of stdout. A run that exits non-zero or prints no number is rejected.
- `--goal max|min`: whether a higher or a lower score is better. Default `max`.
- `--k N`: accepted experiments per tenure, default 5.
- `--review-reserve M`: with `--minutes`, stop starting turns when fewer than M minutes are left, so the review has time. Default 15.

If `--eval` is missing, ask the user for it and stop.

## Roles

| Role | subagent_type | Model | Stance | Session |
|---|---|---|---|---|
| chaser-a | `baton:chaser-a` | chaser A model | chaser A stance | fresh every turn |
| chaser-b | `baton:chaser-b` | chaser B model | chaser B stance | fresh every turn |
| blind reviewer | `baton:reviewer` | the model of the chaser *opposite* the author of the latest accepted candidate | none | fresh, once |

chaser-a holds the first tenure. Pass the evaluator as the `eval:` line of `start` and `{"goal": ..., "k": ...}` as its `options:` line (protocol); together they are the run's contract. Keep in `state.extra`: `holder`, `accepted_in_tenure`, `candidates` (list of `{label, commit, author, score}`) and `best`; write it only when a candidate is accepted or the tenure changes.

## Turn prompt

```
BATON fixed-interrupt · turn <n>/<max> · role <holder> · run <run-id>

TASK:
<task, verbatim>

STANCE (<stance name>):
<stance paragraph>

CONTRACT: the trusted evaluator is `<eval>` (goal: <max|min>). You may run it while you work, but only the orchestrator's run after your turn counts.
STATUS: accepted this tenure <a>/<k> · best so far <score or "none"> · last submission: <accepted with <score> | rejected: <one-line reason> | none>

You start fresh; the workspace is the only handoff. Make one experiment: one coherent change you expect to improve the score. Leave it in the workspace and report.
```

## After each turn

1. Commit and evaluate in one call, with a neutral commit message (the blind reviewer reads commit messages, so no role in it):
   ```bash
   sh "${CLAUDE_PLUGIN_ROOT}/scripts/baton.sh" turn <run_dir> t<n> <holder> <status> -m "baton(fixed-interrupt): t<n>" <<'EOF'
   <summary>
   EOF
   sh "${CLAUDE_PLUGIN_ROOT}/scripts/baton.sh" eval <run_dir> t<n> --beat <best or none> --goal <goal>
   ```
   Skip the `eval` line when the turn was `empty`: an empty turn is not a submission.
2. `eval` printed a score: the submission is accepted. Add candidate `C<i>` with this commit, its author and score, update `best` when it beats it, and add one to `accepted_in_tenure`. `rejected (...)`: the reason and the two log lines it printed are `last_result` for the next prompt.
3. When `accepted_in_tenure` reaches k, hand the tenure to the other chaser and reset the count.

## Blind review

When the budget ends (turns, or minutes minus the reserve):

- With fewer than two accepted candidates, the winner is the only candidate, or there is none.
- Otherwise spawn the blind reviewer once, with this prompt:
  ```
  BATON fixed-interrupt · blind review · role reviewer · run <run-id>

  TASK:
  <task, verbatim>

  CANDIDATES: <labels in shuffled order, each with its commit sha>
  Inspect each with `git show --stat <sha>` and `git diff <base> <sha>`. Don't run the evaluator and don't look for scores; judge which candidate best does the TASK.
  Add the line "nominate: <one label from the list>" or "nominate: none".
  ```
  The reviewer may only nominate an existing candidate. `none`, a missing line, or an unknown label keeps the standing candidate (the best score). There is no retry.
- Create the branch `baton/<run-id>-winner` at the winner's commit, and write `review.json` and `result.json` in the run directory.

## Final report additions

A table of the candidates with commit, author and score, the nominee, the winner, and the winner branch.
