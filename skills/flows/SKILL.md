---
name: flows
description: Lists baton's agent-loop flows and helps choose one for a task; explains the settings (models and stances), how runs use a branch, and how to resume or stop. Use when the user asks which baton flow fits a task, or what baton can do.
---

# baton flows

Every flow runs as `/baton:<flow> "<task>" [flags]`, works on a run branch `baton/<run-id>` (your branch is untouched), commits each turn, and ends with a report on how to merge or drop the work. Shared flags: `--turns N`, `--minutes M`, `--check "<cmd>"`, `--no-early-stop`, `--in-place`, `--resume [run-id]`.

## Pick a flow

| Flow | What it does | Use it when |
|---|---|---|
| `flame-chase` | Two chasers with different models and stances alternate, fresh every turn; only the workspace passes between them | A long task where one agent's blind spots would compound |
| `cleanup-flame-chase` | flame-chase plus a cleaner every few turns, NEXT.md, squashed epochs | The same, over many turns |
| `ralph-loop` | Same task every round, fresh worker, only the repository carries over | Steady grinding on a task with a clear finish |
| `cleanup-ralph` | ralph-loop plus the cleaner | The same, over many turns |
| `stateful-ralph` | Same task every round, one persistent worker | Earlier reasoning matters between rounds |
| `continue-loop` | Task once, then "continue" | The simplest long run |
| `goal` | The task becomes the worker's own goal; it stops when it says the goal is met, with evidence | A measurable finish line, self-judged |
| `rlar` | Persistent actor; a fresh reviewer decides "done" and writes the next prompt | "Done" shouldn't be judged by the one who did it |
| `gen-idea` → `gen-plan` → `rlcr` | Idea draft → plan agreed by planner and fresh analyst → build with stop checks, a review every round and a final whole-change review | Larger features you want planned and reviewed |
| `fixed-interrupt` | Chasers alternate every k accepted experiments scored by your evaluator; a blind review picks the winner | Optimizing a measurable score |
| `parallel-chase` | A coordinator plans three different lanes; each lane chases in parallel; a shared leaderboard | The right approach isn't obvious |
| `parallel-chase-pr` | Three lanes propose; merged only when a clean evaluation improves the score | Score-driven work where nothing should land unmeasured |
| `recursive-lean-prover` | Lean 4 theorem → lemmas, prose audit, split, formalize in worktrees, wiki | Formal proofs in a Lake project |
| `author-flow` | Writes a new flow from your description; lands only after load, fake-world and critic gates | You want a loop baton doesn't have |

## Settings

Set them in `/plugin` → baton → configure, or in the baton rows of `/config`:

- chaser A: model `opus`, stance `builder` (defaults)
- chaser B: model `sonnet`, stance `skeptic`
- worker model `opus`, reviewer model `sonnet`, default turn budget 8

Stances: `builder`, `skeptic`, `simplifier`, `tester`. Models: `opus`, `sonnet`, `haiku`, `fable`.

## Before a long run

- Use a scratch repository or a clean working tree; baton refuses to start on uncommitted changes.
- Choose `acceptEdits` or `auto` permission mode so turns don't stop on prompts. Baton never turns on bypass permissions for you.
- Runs cost tokens in proportion to turns × agents. Start with a small `--turns`.
