---
name: protocol
description: Shared run protocol for every baton flow (configuration, setup, run branch, spawning turns, report blocks, commits, budget, failures, stopping, resume, stances, cleaning). Load it before running any baton flow, including flows written with /baton:author-flow.
user-invocable: false
---

# baton run protocol

You are the **orchestrator** of a baton flow. You don't do the task yourself. You start subagents, pass the baton between them, keep the books through the run script, and report at the end. A flow's own SKILL.md adds its roles, turn prompts and stop rules on top of this protocol; where the two differ, the flow wins.

## Economy

Every tool call you make re-reads your whole context, so keep them few:

- Bookkeeping goes through the run script, **one Bash call per step**: `sh "${CLAUDE_PLUGIN_ROOT}/scripts/baton.sh" <subcommand> ...`. Decide from what it prints. Don't add your own `git`, `date`, `cat` or log commands around it.
- Spawn only the agents the flow names. Don't add helper or verification agents of your own.
- Keep only report blocks and script output in your context. Don't read diffs, files or logs to second-guess the agents unless the flow tells you to.

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

1. Run this one call from the directory the user is in. Leave out the `check:`, `eval:` and `options:` lines you don't need; everything after `task:` is the TASK, verbatim:
   ```bash
   sh "${CLAUDE_PLUGIN_ROOT}/scripts/baton.sh" start <flow> --turns <N> [--minutes <M>] [--in-place] <<'BATON_END'
   check: <the --check command, verbatim>
   eval: <the --eval command, verbatim>
   options: <the flow's other flags as one JSON object>
   task:
   <TASK verbatim>
   BATON_END
   ```
   It checks that this is a git repository with a clean working tree, makes the run id (`<flow>-<YYYYMMDD-HHMMSS>`), the run directory `.baton/runs/<run-id>/` (kept out of git through `.git/info/exclude`, so the user's tree is untouched), the run branch `baton/<run-id>` (unless `--in-place`), `run.env`, `log.md` and `state.json` (with the TASK, which `--resume` rebuilds prompts from), plus `check.sh` and `eval.sh` that later calls run. The quoted heredoc keeps the TASK and the user's commands exactly as given. It prints `run_id`, `run_dir`, `branch` and `base`. If it prints `ERROR`, pass that line to the user and stop. Never stash, reset or discard the user's changes yourself. Work from the repository root from here on.
2. Tell the user in two lines at most: flow, branch, budget, and that `/baton:<flow> --resume <run-id>` continues the run if it's interrupted.

Only flows that say they keep state in `state.json`'s `extra` write that file again.

Any other branch the flow needs is named `baton/<run-id>-<suffix>` (never `baton/<run-id>/<suffix>`: git can't have both). Tags follow the same rule.

**Doc-only flows** (gen-idea, gen-plan, author-flow) run `start <flow> --doc-only`: no clean-tree check, no run branch, no commits. They only refuse to overwrite an existing output file unless `--force` is given.

## Spawning a turn

- Use the Agent tool with `subagent_type` `baton:<agent>` (`chaser-a`, `chaser-b`, `worker`, `reviewer`, `cleaner`, `coordinator`) and the `model` configured for that role. Use a short `description` such as `baton t3 chaser-b`.
- Every prompt starts with one header line: `BATON <flow> · turn <n>/<max> · role <role> · run <run-id>`, followed by the flow's template. Fill in the template's placeholders and send it as written; don't add advice, hints or rules of your own.
- **Fresh roles** get a new Agent call every turn and nothing from earlier turns except what the flow's template says.
- **Persistent roles** keep their session. On the first spawn give the agent the `name` `<run-id>-<role>`, and continue it later with SendMessage to that name. If SendMessage isn't available or the agent can't be reached, log it, then follow the flow's fallback: respawn it fresh with a short recap, or, in single-worker flows, play the role yourself in this session.
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

Flows may ask for extra lines in either block (for example `ready: yes`, `nominate: C2`). If a block is missing, treat the turn as `status: missing` with the agent's last line as the summary.

## After every work turn

One call does the commit, the check, the log line, the streaks and the budget:

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/baton.sh" turn <run_dir> t<n> <role> <status> <<'EOF'
<the report's summary line>
EOF
```

- `<status>` is the report's status, or `missing`.
- It stages everything and commits it as `baton(<flow>): t<n> <role>`; a turn that staged nothing is `empty`. The agent's summary stays out of the commit message: fresh agents read `git log`, and the summary is what the last agent *said*, which flows like flame-chase must not pass on. Summaries go only to `log.md`.
- If `check.sh` exists it runs it, logs its output to `check-t<n>.log`, and removes the untracked files the check itself created, so they don't land in the next commit. Agents see the result only if the flow says so.
- It prints the log line, the commit, a `streak:` line (how many turns in a row had this status, the status before that run, and how many in a row were `empty` or `changed`), `FAILED:` on the second `blocked` or `missing` in a row, and `budget:` ending in `continue` or `spent`. Every rule about consecutive turns or the budget is decided from these lines.
- Options: `-C <dir>` commits in another worktree, `-m "<message>"` replaces the commit message, `--no-commit` only logs (for flows that commit exact paths themselves). Labels other than `t<n>` are allowed, for example `r<r> lane-<i>`; streaks are counted per label family.

Review, cleaner and coordinator turns don't count against the budget unless the flow says so.

## Failed turns

A turn fails when the Agent call errors or returns nothing, or when the script prints `FAILED:`. A failed turn stops the run with that reason unless the flow says otherwise. Never retry the same turn more than once.

## Early stop

Unless `--no-early-stop` is set, a flow may stop before the budget when its own done-condition holds. Each flow defines that condition. It's a baton addition; the original flows run until their budget ends.

## Final report

When the run stops for any reason:

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/baton.sh" stop <run_dir> <finished|stopped|failed> "<reason>"
```

It logs the stop and prints the turns used, the run's commits, the last check result, and the exact commands to keep the work, drop it, or resume. Tell the user briefly: flow, turns used / budget, stop reason, those lines, and anything the flow adds. Don't merge into the user's branch, push, or delete branches yourself.

## Resume

```bash
sh "${CLAUDE_PLUGIN_ROOT}/scripts/baton.sh" resume <run-id> [--turns N] [--minutes M]
```

Without an id, pass `--flow <flow>` and it picks this flow's newest run that didn't finish or fail. It switches to the run branch (the tree must be clean), applies a new budget if given, and prints the last turns. Then read `state.json` for the TASK and `extra`. The next turn number is the last `t<n>` plus one, and the flow's rules give the next role (for alternating flows, the other role than the last line's). Persistent agents may be gone; if SendMessage to `<run-id>-<role>` fails, follow the flow's fallback.

## Safety

- Subagents never push, never touch remotes, never edit outside the repository (or the directory their prompt names), never edit `.baton/` unless their prompt gives them a path there, and never rewrite git history. Only you rewrite history, only on the run branch, and only where a flow says so.
- Long runs need edits and shell commands without a prompt each time. Suggest the user run in a scratch repository with `acceptEdits` or `auto` permission mode. Never switch to bypass permissions on the user's behalf.
- Keep every command's output small: logs go to files under the run directory, and you read only their tails.

## Stances

Chaser prompts carry the stance paragraph that matches the configured stance.

- **builder**: Push the task forward. Pick the most valuable missing piece and make it work end to end. Finish one thing rather than start three. Keep existing tests green and add tests for what you build.
- **skeptic**: Assume the current work is subtly wrong. Before adding anything, try to break what exists: run it, read it against the task, write the test that would fail. Fix the defects you find. Add new features only when what exists holds up.
- **simplifier**: Make the workspace smaller and clearer without losing behavior. Remove dead code and detours, merge duplicates, tighten names and structure. Then take the next small step on the task.
- **tester**: Turn the task into checks. Write or extend tests and scripts that show whether the task is done, run them, and fix what they reveal.

## Cleaning (cleanup flows only)

Flags: `--cleanup-turns K` (default 3), `--next-lines L` (default 10), `--work-paths "<paths>"` (default: the whole repository), `--repairs R` (default 2).

Every K work turns, after that turn's `turn` call:

1. Record the pre-clean commit: `git rev-parse HEAD` is `P`.
2. Spawn `baton:cleaner` fresh, with the worker model, named `<run-id>-cleaner-<k>`. Prompt: header, the TASK, the base commit, the work paths, and the NEXT.md line limit.
3. Commit and check it: `turn <run_dir> c<k> cleaner <status> -m "baton(<flow>): clean <k>"`.
4. Gate: if `NEXT.md` at the repository root is missing or longer than L lines (`wc -l < NEXT.md`), send the exact problem back to the same cleaner with SendMessage, then run step 3 again. Do this at most R times.
5. If the last `turn` call printed `check fail`, undo the cleaning with `git reset -q --hard <P> && echo "clean <k> reverted" >> <run_dir>/log.md`, and skip step 6.
6. Squash the epoch in one call: the epoch base is this run's latest squash commit, `git log -1 --format=%H --grep='^epoch [0-9]*: distilled tree$' <base>..HEAD`, or the run's base when that prints nothing. Then
   ```bash
   git tag baton/<run-id>-epoch-<k> && git reset -q --soft <epoch base> && git commit -q -m "epoch <k>: distilled tree"
   ```
   The tag is an archive of the full history that baton never deletes.

Cleaner turns don't count against `--turns`. Cleanup flows also stop when the `streak:` line shows 3 `empty` work turns in a row.
