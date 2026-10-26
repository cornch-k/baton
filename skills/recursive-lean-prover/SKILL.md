---
name: recursive-lean-prover
description: Proves a Lean 4 theorem by recursion. Each lemma is first tried directly in Lean; one that doesn't go through is proved in prose, audited step by step by a fresh reviewer, split into child lemmas when needed, then formalized in its own git worktree. A lemma is accepted only when Lean itself confirms the exact planned statement with no sorry or extra axioms. Accepted lemmas go into a Markdown wiki. Run with /baton:recursive-lean-prover "<theorem>".
argument-hint: "\"theorem name <binders> : statement\" | --file <path> --name <theorem> [--prose-first] [--max-depth D] [--max-children C] [--revisions R] [--parallel P] [--turns N] [--minutes M] [--resume [run-id]]"
disable-model-invocation: true
---

# recursive-lean-prover

Arguments: $ARGUMENTS

Load the run protocol first (Skill tool → `baton:protocol`; if that fails, Read `${CLAUDE_PLUGIN_ROOT}/skills/protocol/SKILL.md`) and follow it. This file only adds what is specific to recursive-lean-prover, and overrides the protocol's commit step: this flow always stages exact paths, never `git add -A`, because several lemmas are in flight at once.

## What Lean is trusted for

Three facts decide acceptance, and all three come from Lean, never from an agent's word. Because they are mechanical, no reviewer re-runs them:

1. `lake build <Module>` succeeds for the lemma's own module. A plain `lake build` is **not** enough: it only builds what the library root imports, so a new file would never be checked.
2. A check file elaborates `example : <planned statement> := by exact @<formal name>`. This fails (exit code 1) when the proved theorem is weaker or different.
3. `#print axioms <formal name>` lists only `propext`, `Classical.choice` and `Quot.sound`, or says it depends on no axioms. A `sorry` shows up as `sorryAx` and a made-up axiom shows up by its name. The build alone doesn't catch either: a `sorry` is only a warning and the build still exits 0.

## Prerequisites (setup)

1. `lake --version` works and the repository root has `lakefile.toml` or `lakefile.lean`. If not, stop and tell the user to install Lean through elan (`brew install elan-init`, or https://github.com/leanprover/elan) and run this from a Lake project.
2. Find the default library: its name `<Lib>` (from `defaultTargets` / `[[lean_lib]] name`) and its source directory (`<Lib>/` at the root unless `srcDir` says otherwise). Record both in `state.extra.lib`.
3. `lake build` must pass on the base commit (log to `build-base.log`). This also warms the build cache. If the project depends on packages (for example Mathlib), they must already be fetched in this checkout; tell the user to run `lake exe cache get` first if the build tries to compile Mathlib.
4. `.lake/` must be ignored by git (`git check-ignore -q .lake`). If it isn't, stop and tell the user to add `/.lake` to `.gitignore`.

## The root statement

Input is either a statement in the arguments (`theorem name <binders> : <type>`), or `--file <path> --name <theorem>` pointing at an existing declaration (usually ending in `sorry`).

1. Pick the run tag `T` = the run id's time part (`HHMMSS`).
2. Write the root's **closed statement**: move every binder before the colon into a leading `∀`, keeping implicit and instance binders as they are (`theorem foo (n : Nat) {m : Nat} : P n m` → `∀ (n : Nat) {m : Nat}, P n m`).
3. Write the **preamble** as two lists: the `imports` (modules that define the statement's names) and the `opens` (namespaces it uses unqualified). For `--file`, take them from that file. Store both in `state.extra.preamble`. Lean requires every `import` before anything else, so every file this flow writes starts with all its imports, then the opens.
4. Verify the closed statement with Lean before anything else, by writing `.baton/runs/<run-id>/checks/root-stmt.lean`:
   - with `--file`: first `lake build <module of that file>`; then the file is `import <module of that file>`, the other preamble imports, the opens, and `example : <closed statement> := by exact @<name>`;
   - with a text statement: the preamble imports, the opens, then `theorem baton_stmt_probe <binders> : <type> := sorry` exactly as given, then `example : <closed statement> := by exact @baton_stmt_probe`.

   Run `lake env lean <file>`. It must exit 0. Otherwise fix the closed statement (two tries), then stop and ask the user to restate the theorem.

## Naming

- Node ids: the root is `root`; the k-th child of node `x` is `x_k` (for example `root_2_1`).
- Formal name of node `x`: `baton_<T>_<x>`. These names never collide with the user's code or with other runs.
- Module of node `x`: `<Lib>.Baton.R<T>.<x>`, file `<lib dir>/Baton/R<T>/<x>.lean`.
- Every lemma records its closed statement verbatim. The statement is never edited after the lemma is planned.

## Layout

- `lemmas/INDEX.md`: one line per accepted lemma: id, formal name, closed statement, Lean file.
- `lemmas/drafts/<x>.md` is work in progress; `lemmas/<x>.md` is an accepted lemma (statement, prose proof, Lean file, children it uses).
- `state.extra.tree`: nodes `{id, statement, parent, depth, status, children, worker, branch, worktree}`, with status `prose | split | formalizing | accepted | refused`.

## Flags

- `--prose-first`: skip the direct attempt (step 0) and always start from prose, as the original flow does.
- `--max-depth D` (default 3), `--max-children C` (default 4), `--revisions R` for prose and for formal proofs each (default 3).
- `--parallel P`: at most P lemma workers at once (default 3). Run at most 2 Lean processes of your own at the same time.
- `--turns N`: the budget counts prover turns (default 40). Log each one with `turn <run_dir> t<n> prover-<x> <status> --no-commit` (protocol); its `budget:` line decides.

## Roles

| Role | subagent_type | Model | Session |
|---|---|---|---|
| prover, one per lemma | `baton:worker` | worker model | persistent per lemma, named `<run-id>-<x>` |
| auditor | `baton:reviewer` | reviewer model | fresh per check |

## The loop for one lemma x

x's prover is spawned once, at its first step, with an Agent call named `<run-id>-<x>` and this opening; every later step is a SendMessage to it:

```
BATON recursive-lean-prover · lemma <x> (depth <d>) · role prover · run <run-id>

STATEMENT (Lean, closed form; never change it):
<statement>
PREAMBLE: imports <imports>; opens <opens>
ACCEPTED LEMMAS YOU MAY USE: lemmas/INDEX.md (use them by their formal names).
```

0. **Direct attempt** (unless `--prose-first`). Lean is the judge, so a lemma it accepts needs no prose and no audit. Create x's worktree as in step 5, but on the branch `baton/<run-id>-<x>-direct`, and ask x's prover:
   ```
   Try to prove the statement directly in Lean. <the formalize instructions from step 5>
   If it doesn't go through after a few honest tries, stop and report status: blocked with summary "needs prose". Don't fight it: a prose proof and a split come next.
   ```
   Run the comparator (step 6). A pass goes straight to Accept (step 7, merging the `-direct` branch), and x's wiki page says "proved directly in Lean". One failure goes back to the prover with the log tail ("Fix the formal proof."). A second failure or "needs prose" ends the attempt: `git worktree remove --force <worktree>`, keep the branch as a record, and go on to step 1 with the same prover.
1. **Prose.** Ask x's prover:
   ```
   Write lemmas/drafts/<x>.md: the statement, a short plan, and a prose proof as numbered steps, each small enough to check on its own. Write no Lean yet.
   If the statement has independent parts (a conjunction, several cases) or needs facts that deserve their own proof, report status: blocked with summary "split" instead of a proof.
   ```
   Commit only the draft: `git add lemmas/drafts/<x>.md && git commit -q -m "baton(lean): draft <x>"`.
2. **Audit** (fresh auditor): "Audit the prose proof in lemmas/drafts/<x>.md step by step against its statement. Report the FIRST invalid step (number and why) as the only finding, or done: true if every step is valid and the proof shows exactly the statement, not a weaker one."
3. **Revise**: send the first invalid step, verbatim, to x's prover with "Revise the proof in the draft." Repeat up to `--revisions` times.
4. **Split**: when the prover reported "split", or the proof is still invalid after the revisions, and depth < `--max-depth`:
   - Ask x's prover for at most `--max-children` child lemmas as closed Lean statements (ids `x_1`, `x_2`, ...), plus the prose of how x follows from them. They go into x's draft.
   - A fresh auditor checks "x follows from these children, as argued": first invalid step, or done: true. A failure counts as a revision of x.
   - Run this same loop for every child. Siblings run in parallel, up to `--parallel` workers, spawned in one message.
   - At max depth the lemma is **refused**. A refused child refuses its parent, unless the parent's prover finds another split within its revisions.
5. **Formalize**, when x has no children or all of them are accepted:
   ```bash
   git worktree add -q .baton/runs/<run-id>/wt/<x> -b baton/<run-id>-<x>
   [ -d .lake/packages ] && mkdir -p .baton/runs/<run-id>/wt/<x>/.lake && ln -s "$PWD/.lake/packages" .baton/runs/<run-id>/wt/<x>/.lake/packages
   ```
   The worktree starts from the run branch, so it already contains the accepted children. The symlink shares fetched packages such as Mathlib instead of downloading them again.

   Then SendMessage to x's prover:
   ```
   Formalize lemma <x> in Lean, working only inside <absolute worktree path>.
   Write <lib dir>/Baton/R<T>/<x>.lean containing, in this order: the preamble imports and `import <Lib>.Baton.R<T>.<child>` for each child you use (all imports first), the preamble opens, then a top-level (no namespace) declaration
     theorem baton_<T>_<x> : <statement, verbatim> := ...
   No sorry, admit, new axiom, or option that switches off checking. Check it with `lake build <Lib>.Baton.R<T>.<x>` in that directory.
   ```
6. **Comparator.** Run it yourself in one Bash call, with the run directory as an absolute path `<R>`. The check file is written from the planned statement, so it matches it by construction:
   ```bash
   ( cd <worktree> && mkdir -p <R>/checks &&
   cat > <R>/checks/<x>.lean <<'LEAN'
   import <Lib>.Baton.R<T>.<x>
   <the preamble opens>
   example : <statement, verbatim> := by exact @baton_<T>_<x>
   #print axioms baton_<T>_<x>
   LEAN
   lake build <Lib>.Baton.R<T>.<x> > <R>/build-<x>.log 2>&1; echo "build exit=$?"
   lake env lean <R>/checks/<x>.lean > <R>/check-<x>.log 2>&1; echo "check exit=$?"; tail -3 <R>/check-<x>.log
   L=<R>/check-<x>.log
   if grep -q "does not depend on any axioms" "$L"; then echo "AXIOMS OK"
   elif A=$(grep -o "depends on axioms: \[.*\]" "$L"); then
     BAD=$(echo "$A" | sed 's/.*\[\(.*\)\]/\1/' | tr ',' '\n' | tr -d ' ' | grep -vxE 'propext|Classical\.choice|Quot\.sound')
     [ -z "$BAD" ] && echo "AXIOMS OK" || echo "AXIOMS BAD: $BAD"
   else echo "AXIOMS MISSING"; fi )
   ```
   The last part decides the axioms mechanically, never by eye: it prints `AXIOMS OK` only when the axioms line exists and names nothing outside the three standard axioms.
   It passes only if both exit codes are 0 and the line above printed `AXIOMS OK`. A `sorry` anywhere below the lemma, children included, shows up here as `sorryAx` even though the build and the `example` both exit 0. On failure, send the last 30 lines of the failing log to the prover ("Fix the formal proof."), up to `--revisions` times; after that the lemma is refused.
7. **Accept**:
   ```bash
   git merge --no-ff -q -m "baton(lean): accept <x>" <x's branch>
   git worktree remove --force <worktree>
   ```
   Then write `lemmas/<x>.md` (the draft moved there, or for a direct proof: the statement, the Lean file and "proved directly in Lean"), append its line to `lemmas/INDEX.md`, and commit exactly those paths (and the draft's removal). The parent may now formalize once all its children are accepted.

## Stop

- The root is accepted: finished, "proved".
- The root is refused: finished, "refused". Report the deepest refused lemma and its last invalid step or Lean error.
- The budget is used up, or a turn fails (protocol).

## Final report additions

The lemma tree (id, status, depth), the root's formal name and Lean file, the wiki path, and the exact command that re-checks the root: `lake build <Lib>.Baton.R<T>.root && lake env lean .baton/runs/<run-id>/checks/root.lean`. Remove leftover worktrees with `git worktree remove --force`, but keep their branches.
