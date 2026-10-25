---
name: recursive-lean-prover
description: Proves a Lean 4 theorem by recursion. Each lemma is planned and proved in prose, audited step by step by a fresh reviewer, split into child lemmas when needed, then formalized in its own git worktree and accepted only when the build passes with no sorry and a fresh reviewer reruns it. Accepted lemmas go into a Markdown wiki. Run with /baton:recursive-lean-prover "<theorem>".
argument-hint: "\"theorem name : statement\" | --file <path> --name <theorem> [--max-depth D] [--max-children C] [--revisions R] [--build \"cmd\"] [--parallel P] [--turns N] [--minutes M] [--resume [run-id]]"
disable-model-invocation: true
---

# recursive-lean-prover

Arguments: $ARGUMENTS

Load the run protocol first (Skill tool → `baton:protocol`; if that fails, Read `${CLAUDE_PLUGIN_ROOT}/skills/protocol/SKILL.md`) and follow it. This file only adds what is specific to recursive-lean-prover.

## Prerequisites

- `lake --version` works, and the repository is a Lake project (`lakefile.lean` or `lakefile.toml` at the root). If not, stop and tell the user to install Lean through elan (https://github.com/leanprover/elan) and run this from a Lake project.
- The root theorem: either a full statement in the arguments (`theorem name : ...`), or `--file <path> --name <theorem>` pointing at an existing statement.

## Flags

- `--max-depth D`: how deep lemmas may split, default 3.
- `--max-children C`: at most C child lemmas per split, default 4.
- `--revisions R`: revisions per lemma, for prose and for the formal proof each, default 3.
- `--build "<cmd>"`: the build command, default `lake build`.
- `--parallel P`: at most P lemma workers at once, default 3. At most 2 builds ever run at the same time, because Lean builds are heavy.
- `--turns N`: the budget counts worker turns, default 40.

## Layout

- `lemmas/INDEX.md`: one line per accepted lemma (name, statement, Lean file).
- `lemmas/drafts/<id>.md`: work in progress. `lemmas/<id>.md`: accepted lemmas (statement, prose proof, Lean file, dependencies).
- Lean proofs go in a `Baton/` folder inside the project's default library (the worker picks the path from the lakefile and records it in `state.extra`).
- `state.extra.tree`: nodes `{id, name, statement, parent, depth, status, children, worker, branch, worktree}` with status `planned | proving | split | formalizing | accepted | refused`.

## Roles

| Role | subagent_type | Model | Session |
|---|---|---|---|
| prover (one per lemma) | `baton:worker` | worker model | persistent per lemma, named `<run-id>-<id>` |
| auditor | `baton:reviewer` | reviewer model | fresh per check |

## The loop for one lemma X

1. **Prose.** Spawn X's prover (Agent call with `name`):
   ```
   BATON recursive-lean-prover · lemma <id> (depth <d>) · role prover · run <run-id>

   STATEMENT (Lean, exact; never change it):
   <statement>

   ACCEPTED LEMMAS YOU MAY USE: see lemmas/INDEX.md.
   Write lemmas/drafts/<id>.md: the statement, a plan, and a prose proof as numbered steps, each step small enough to check on its own. If the proof is too big for one lemma, report status: blocked with summary "split".
   ```
2. **Audit** (fresh auditor): "Audit the prose proof in lemmas/drafts/<id>.md step by step against its statement. Report the FIRST invalid step (number and why) as the only finding, or done: true if every step is valid and the proof shows exactly the statement, not a weaker one."
3. **Revise**: send the first invalid step, verbatim, to X's prover with "Revise the proof." Repeat up to `--revisions` times.
4. **Split**: if the proof is still invalid, or the prover reported "split", and depth < `--max-depth`:
   - Ask X's prover for at most `--max-children` child lemmas, as exact Lean statements, from which X follows, plus the prose of how X follows. Write them into the draft.
   - A fresh auditor checks: "Does the statement follow from these children, as argued? First invalid step, or done: true." A failure counts as a revision.
   - Run the same loop for every child. Siblings run in parallel, up to `--parallel` workers at once, spawned in one message.
   - At max depth, the lemma is **refused**. A refused child refuses its parent unless the parent's prover finds another split within its revisions.
5. **Formalize**, once there are no children or all children are accepted:
   ```bash
   git worktree add -q .baton/runs/<run-id>/wt/<id> -b baton/<run-id>-<id>
   ```
   (branched from the run branch, which already contains the accepted children). Then SendMessage to X's prover: "Formalize the accepted prose proof in Lean, working only inside <worktree>. Copy the statement exactly. No `sorry`, `admit`, new `axiom`, or options that switch off checking. Use accepted lemmas by importing their files."
6. **Comparator.** Run it yourself in the worktree:
   - the build: `( cd <worktree> && <build> ) > .baton/runs/<run-id>/build-<id>.log 2>&1; echo "exit=$?"`, which must exit 0;
   - `git -C <worktree> diff baton/<run-id> -U0 | grep -E '^\+.*\b(sorry|admit|axiom)\b'` finds nothing;
   - the theorem line in the Lean file matches the planned statement, whitespace aside.
   On failure, send the last 30 lines of the log to the prover ("Fix the formal proof."), up to `--revisions` times. After that the lemma is refused.
7. **Rerun** (fresh auditor): "In <worktree>, rerun `<build>` yourself, and check that the Lean statement of <name> is exactly the planned one and not weakened, and that nothing is assumed without proof. done: true to accept."
8. **Accept**: `git merge --no-ff -q baton/<run-id>-<id>` into the run branch, `git worktree remove <worktree>`, move the draft to `lemmas/<id>.md`, add its line to `lemmas/INDEX.md`, and commit `baton(lean): accept <name>`. Lemmas waiting on it may now go on.

## Stop

- The root theorem is accepted: finished, "proved".
- The root theorem is refused: finished, "refused". Report the deepest refused lemma and its last invalid step.
- The budget is used up, or a turn fails (protocol).

## Final report additions

The lemma tree (name, status, depth), the wiki path, and the Lean file of the root proof. Remove any leftover worktrees but keep their branches.
