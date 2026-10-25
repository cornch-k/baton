---
name: protocol
description: Shared run protocol for every baton flow (configuration, setup, run branch, spawning turns, report blocks, commits, budget, failures, stopping, resume, stances, cleaning). Load it before running any baton flow, including flows written with /baton:author-flow.
user-invocable: false
---

# baton run protocol

You are the **orchestrator** of a baton flow. You don't do the task yourself. You start subagents, pass the baton between them, commit their work, keep the budget, and report at the end. A flow's own SKILL.md adds its roles, turn prompts and stop rules on top of this protocol; where the two differ, the flow wins.

## Configuration

Values come from the plugin's settings (`/plugin` → baton → configure, or the baton rows in `/config`). If a value below still reads like `${…}`, use the default.

| Setting | Value | Default |
|---|---|---|
| chaser A model | ${user_config.chaser_a_model} | opus |
| chaser A stance | ${user_config.chaser_a_stance} | builder |
| chaser B model | ${user_config.chaser_b_model} | sonnet |
| chaser B stance | ${user_config.chaser_b_stance} | skeptic |
| worker model | ${user_config.worker_model} | opus |
| reviewer model | ${user_config.reviewer_model} | sonnet |
| default turn budget | ${user_config.default_turns} | 8 |

Models are passed as the Agent tool's `model` parameter (`opus`, `sonnet`, `haiku`, `fable`). Two chasers with different models *and* different stances is how baton gets the "two agents fail differently" effect without mixing vendors.

## Arguments

Everything in the argument string that isn't a flag is the TASK. Keep it verbatim; never paraphrase it in prompts. Flags shared by all flows:

| Flag | Meaning |
|---|---|
| `--turns N` | work-turn budget (default: the configured default turn budget) |
| `--minutes M` | wall-clock budget, optional |
| `--check "<cmd>"` | command run after each work turn; the result is logged |
| `--no-early-stop` | ignore the flow's early-stop rule and run to the budget, as the original flows do |
| `--in-place` | work on the current branch instead of a run branch |
| `--resume [run-id]` | continue a stopped run |

Flows add their own flags. If the TASK is empty and you aren't resuming, ask the user for it in one question and stop.

## Setup

1. The directory must be a git repository: `git rev-parse --show-toplevel`. If it isn't, tell the user to run `git init` and make a first commit, then stop. Work from the repository root.
2. The working tree must be clean: `git status --porcelain` prints nothing. If it doesn't, tell the user to commit or stash, then stop. Never stash, reset or discard their changes yourself.
3. Run id: `<flow>-<YYYYMMDD-HHMMSS>` from `date +%Y%m%d-%H%M%S`.
4. Run directory and exclude, with Bash (file-editing tools are refused inside `.git/`):
   ```bash
   mkdir -p .baton/runs/<run-id> && { grep -qxF '.baton/' .git/info/exclude 2>/dev/null || echo '.baton/' >> .git/info/exclude; }
   ```
   Use `.git/info/exclude`, not `.gitignore`, so the user's tree stays untouched. Doc-only flows run this step too.
5. Branch: unless `--in-place`, `git switch -c baton/<run-id>`. Any other branch the flow needs is named `baton/<run-id>-<suffix>` (never `baton/<run-id>/<suffix>`: git can't have both). Tags follow the same rule.
6. Write `.baton/runs/<run-id>/state.json`:
   ```json
   {"flow": "", "run_id": "", "task": "", "branch": "", "start_branch": "", "base": "<sha>",
    "started_epoch": 0, "budget": {"turns": 8, "minutes": null}, "options": {},
    "turn": 0, "next": "", "status": "running", "stop_reason": null,
    "agents": {}, "extra": {}}
   ```
   and `log.md` with one header line. `task` holds the TASK verbatim, because `--resume` rebuilds prompts from it.
7. Tell the user in two lines at most: flow, branch, budget, and that `/baton:<flow> --resume <run-id>` continues the run if it's interrupted.

**Doc-only flows** (gen-idea, gen-plan, author-flow) skip steps 2 and 5 and make no commits. They only refuse to overwrite an existing output file unless `--force` is given.

## Spawning a turn

- Use the Agent tool with `subagent_type` `baton:<agent>` (`chaser-a`, `chaser-b`, `worker`, `reviewer`, `cleaner`, `coordinator`) and the `model` configured for that role. Use a short `description` such as `baton t3 chaser-b`.
- Every prompt starts with one header line: `BATON <flow> · turn <n>/<max> · role <role> · run <run-id>`, followed by the flow's template.
- **Fresh roles** get a new Agent call every turn and nothing from earlier turns except what the flow's template says.
- **Persistent roles** keep their session. On the first spawn give the agent a `name` of `<run-id>-<role>` and record it in `state.agents` (`{"<role>": "<name>"}`) right away. Continue it later with SendMessage to that name. If SendMessage isn't available or the agent can't be reached, log it, then follow the flow's fallback: respawn it fresh with a short recap, or, in single-worker flows, play the role yourself in this session.
- Wait for the subagent to finish. Don't poll, don't read its transcript, and don't work on the task meanwhile. Start several subagents in one message only where the flow says roles run in parallel.

## Report blocks

Every working agent ends its final message with:

```
BATON-REPORT
status: progress | done | blocked
summary: <one line: what changed this turn>
changed: <comma-separated paths, or none>
next: <one line: the most valuable next step>
```

Reviewers end with:

```
BATON-VERDICT
done: true | false
findings:
- <one per line, most important first, or "none">
next_prompt: |
  <the exact instructions the worker gets next; empty when done>
```

Flows may ask for extra lines in either block (for example `ready: yes`, `nominate: C2`). If a block is missing, treat the turn as `status: progress` with the agent's last line as the summary, and log its status as `missing`.

Keep only these blocks in your context. Don't read full diffs or files to second-guess the agents unless the flow tells you to: judging the work is the agents' job, and your context has to last the whole run.

## After every work turn

1. **Commit** (unless the flow says otherwise):
   ```bash
   git add -A && { git diff --cached --quiet && echo EMPTY || git commit -q -m "baton(<flow>): t<n> <role>"; }
   ```
   A turn that staged nothing is `empty`. Keep the agent's summary out of the commit message: fresh agents read `git log`, and the summary is what the last agent *said*, which flows like flame-chase must not pass on. Summaries go to `log.md`.
2. **Check**: if `--check` was given, run it with its output kept out of your context, and remove only the untracked files the check itself created (caches, build output), so they don't land in the next commit:
   ```bash
   git ls-files --others --exclude-standard > .baton/runs/<run-id>/pre-check.txt
   ( <cmd> ) > .baton/runs/<run-id>/check-t<n>.log 2>&1; echo "exit=$?"
   git ls-files --others --exclude-standard | grep -vxFf .baton/runs/<run-id>/pre-check.txt | while IFS= read -r f; do rm -f -- "$f"; done
   ```
   Record pass or fail. Agents see the result only if the flow says so.
3. **Log**: append `t<n> · <role> · <progress|done|blocked|missing> · <empty|changed> · <pass|fail|-> · <summary>` to `log.md`. Every rule about consecutive turns (early stop, failed turns, three empty turns in a row) is decided by reading the last lines of `log.md`, so write this line before deciding anything.
4. **State**: update `turn`, `next` (the role that acts next), `agents` and `extra` in `state.json`.
5. **Budget**: stop when `turn >= budget.turns`, or when `--minutes` is set and `$(date +%s) - started_epoch >= minutes*60`. Review, cleaner and coordinator turns don't count unless the flow says so.

## Failed turns

A turn fails when the Agent call errors or returns nothing, or when it is the second `missing` or the second `blocked` in a row in `log.md`. A failed turn stops the run with that reason unless the flow says otherwise. Never retry the same turn more than once.

## Early stop

Unless `--no-early-stop` is set, a flow may stop before the budget when its own done-condition holds. Each flow defines that condition. It's a baton addition; the original flows run until their budget ends.

## Final report

When the run stops for any reason, set `state.status` to `finished`, `stopped` or `failed`, record `stop_reason`, and tell the user briefly:

- flow, turns used / budget, stop reason
- the branch and its commits: `git log --oneline <base>..HEAD | head -20`
- the last check result, if any
- to keep the work: `git switch <start_branch> && git merge baton/<run-id>`
- to drop it after switching away: `git branch -D baton/<run-id>`
- to continue: `/baton:<flow> --resume <run-id>`

Don't merge into the user's branch, push, or delete branches yourself.

## Resume

`--resume` without an id picks the newest `.baton/runs/*/state.json` for this flow whose status is `running` or `stopped`. Switch to its branch (the tree must be clean), restore budget, turn, next, agents and extra, read `log.md`, and continue with `next`. A new `--turns` given with `--resume` replaces the stored budget. Persistent agents may be gone; if SendMessage to a stored name fails, follow the flow's fallback.

## Safety

- Subagents never push, never touch remotes, never edit outside the repository (or the directory their prompt names), never edit `.baton/` unless their prompt gives them a path there, and never rewrite git history. Only you rewrite history, only on the run branch, and only where a flow says so.
- Long runs need edits and shell commands without a prompt each time. Suggest the user run in a scratch repository with `acceptEdits` or `auto` permission mode. Never switch to bypass permissions on the user's behalf.
- Keep every command's output small: send logs to files under the run directory and read only their tails.

## Stances

Chaser prompts carry the stance paragraph that matches the configured stance.

- **builder**: Push the task forward. Pick the most valuable missing piece and make it work end to end. Finish one thing rather than start three. Keep existing tests green and add tests for what you build.
- **skeptic**: Assume the current work is subtly wrong. Before adding anything, try to break what exists: run it, read it against the task, write the test that would fail. Fix the defects you find. Add new features only when what exists holds up.
- **simplifier**: Make the workspace smaller and clearer without losing behavior. Remove dead code and detours, merge duplicates, tighten names and structure. Then take the next small step on the task.
- **tester**: Turn the task into checks. Write or extend tests and scripts that show whether the task is done, run them, and fix what they reveal.

## Cleaning (cleanup flows only)

Flags: `--cleanup-turns K` (default 3), `--next-lines L` (default 10), `--work-paths "<paths>"` (default: the whole repository), `--repairs R` (default 2).

Every K work turns, after that turn's commit:

1. Record the pre-clean commit `P = git rev-parse HEAD`.
2. Spawn `baton:cleaner` fresh, with the worker model, named `<run-id>-cleaner-<k>`. Prompt: header, the TASK, the base commit, the work paths, and the NEXT.md line limit.
3. Commit its changes as `baton(<flow>): clean <k>`.
4. Gate: if `NEXT.md` at the repository root is missing or longer than L lines, send the exact problem back to the same cleaner with SendMessage, then commit again. Do this at most R times.
5. If `--check` is set, run it. If it fails, undo the cleaning with `git reset -q --hard P`, log `clean <k> reverted`, and skip step 6.
6. Squash the epoch: tag the current head `baton/<run-id>-epoch-<k>` (an archive baton never deletes), then `git reset -q --soft <epoch_base> && git commit -q -m "epoch <k>: distilled tree"`. The first `epoch_base` is the run's base commit; afterwards it's the latest squash commit. Store it in `state.extra.epoch_base`.

Cleaner turns don't count against `--turns`. Cleanup flows also stop after 3 consecutive `empty` work turns.
