---
name: author-flow
description: Writes a new baton flow from a plain-language description. A writer drafts a spec and the flow; it lands as a project skill only after it loads, terminates in three fake worlds, and passes a critic that never saw it written. Run with /baton:author-flow "<description>".
argument-hint: "\"<description of the flow>\" [--name kebab-name] [--repairs N] [--force]"
disable-model-invocation: true
---

# author-flow

Arguments: $ARGUMENTS

Load the run protocol first (Skill tool → `baton:protocol`; if that fails, Read `${CLAUDE_PLUGIN_ROOT}/skills/protocol/SKILL.md`) and follow it. This is a **doc-only flow**: no run branch, no commits. This file only adds what is specific to author-flow.

## Idea

Describe a loop in words and get a flow you can run. The draft lands only after three different checks pass: it loads, it ends in every fake world, and a critic that never saw it being written approves it. Each check catches a different failure.

## Flags

- `--name <kebab-name>`: the flow's name. If omitted, the writer proposes one.
- `--repairs N`: how many times a refusal goes back to the writer, default 3.
- `--force`: allow replacing an existing `.claude/skills/<name>/`.

Paths: the draft lives in `.baton/runs/<run-id>/draft/<name>/SKILL.md`; the flow lands in `.claude/skills/<name>/SKILL.md` of this project.

## Roles

| Role | subagent_type | Model | Session |
|---|---|---|---|
| writer | `baton:worker` | worker model | persistent, named `<run-id>-writer` |
| termination checker | `baton:reviewer` | reviewer model | fresh per check |
| critic | `baton:reviewer` | reviewer model | fresh per check |

## Steps

1. **Spec and draft.** Spawn the writer (Agent call with `name`):
   ```
   BATON author-flow · turn 1 · role writer · run <run-id>

   DESCRIPTION:
   <task, verbatim>

   You may write only under .baton/runs/<run-id>/. First write spec.md there: purpose, roles (which baton agent: chaser-a, chaser-b, worker, reviewer, cleaner, coordinator; which model setting; fresh or persistent), turn order, exactly what each role sees (the handoff), stop conditions, budget, and flags.
   Then write the flow to .baton/runs/<run-id>/draft/<name>/SKILL.md, following the conventions of baton's own flows; read ${CLAUDE_PLUGIN_ROOT}/skills/flame-chase/SKILL.md and ${CLAUDE_PLUGIN_ROOT}/skills/rlar/SKILL.md as examples:
   - frontmatter first: name (= <name>), description, argument-hint, disable-model-invocation: true. It will land as a project skill, so it runs as /<name>, not /baton:<name>.
   - "Arguments: \$ARGUMENTS", then "Load the run protocol first (Skill tool → baton:protocol)"
   - a roles table using only baton:chaser-a, baton:chaser-b, baton:worker, baton:reviewer, baton:cleaner, baton:coordinator
   - the exact turn prompt templates
   - stop conditions that always include the budget, failed turns, and what happens when agents never report done, report done at once, or return nothing.
   You keep this session; refusals from the checks will come back to you word for word.
   ```
2. **Gate 1: load.** Check it yourself:
   - The first line is `---`, the frontmatter parses, `name` is kebab-case and equals the directory name, `description` isn't empty, and `disable-model-invocation: true` is set.
   - The body mentions `baton:protocol`, and every `baton:` agent it names is one of the six above.
   - Build a throwaway plugin and validate it:
     ```bash
     G=.baton/runs/<run-id>/gate-plugin
     mkdir -p "$G/.claude-plugin" "$G/skills" && printf '{"name":"baton-gate","version":"0.0.0"}\n' > "$G/.claude-plugin/plugin.json"
     cp -R .baton/runs/<run-id>/draft/<name> "$G/skills/" && claude plugin validate "$G" 2>&1 | tail -20
     ```
     It must report `Validation passed` (warnings are fine).
3. **Gate 2: fake worlds** (fresh termination checker):
   ```
   BATON author-flow · gate 2 · role reviewer · run <run-id>

   Read the flow at .baton/runs/<run-id>/draft/<name>/SKILL.md and the protocol it loads (${CLAUDE_PLUGIN_ROOT}/skills/protocol/SKILL.md).
   Trace the flow turn by turn, with its default budget, in three fake worlds:
   W1: every agent always reports status: progress and never done.
   W2: every agent reports status: done on its first turn and changes nothing.
   W3: every agent returns nothing at all (no report block).
   For each world, list the turns until the flow stops and the stop reason. done: true only if the flow stops in all three worlds within its budget with a sensible outcome.
   ```
   This check is traced by a model, not executed; say so in the final report.
4. **Gate 3: critic** (fresh):
   ```
   BATON author-flow · gate 3 · role reviewer · run <run-id>

   DESCRIPTION: <task, verbatim>
   Read the flow at .baton/runs/<run-id>/draft/<name>/SKILL.md cold. Is it sound for the description? Are roles and handoffs clear, is independence real where the flow claims it, is it consistent with the baton protocol, and is it free of unsafe instructions (pushing, bypass permissions, deleting outside the repository, rewriting the user's history)? done: true to approve; otherwise list the reasons to refuse.
   ```
5. **Repair.** A failure at any gate goes to the writer by SendMessage, word for word, with "Repair the draft." Then run the gates again from Gate 1. Do this at most `--repairs` times.
6. **Land.** When all three gates pass, copy the draft to `.claude/skills/<name>/SKILL.md`. Refuse to overwrite an existing one unless `--force` is set. Delete `gate-plugin/`.

## Stop

- Landed: tell the user the flow runs as `/<name>`, and to run `/reload-skills` if it doesn't show up yet. Mention that Gate 2 was a traced check.
- Repairs used up: stop, show the last refusal, and leave the draft in the run directory for the user to decide.
- A failed turn (protocol).
