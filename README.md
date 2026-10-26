# Baton

Agent relay loops for Claude Code. Fresh subagents with different models and stances pass the baton through your repository: flame chase, ralph loops, reviewed loops, plan-then-build, scored parallel lanes, a recursive Lean prover, and a flow author.

[한국어 README](README.ko.md)

## Why

Some work goes better when no single agent carries it alone:

- **Fresh sessions keep the repository honest.** If the next agent starts with no memory, whatever isn't in the files is gone, so the files have to be good.
- **Different agents fail differently.** When each turn starts by checking work someone else wrote, one agent's blind spots don't compound.
- **"Done" shouldn't be judged by the one who did the work.** A reviewer that never saw the work being done reads what is actually there.

Tools such as [Humanize](https://github.com/humanfia/humanize) get that diversity by mixing vendors (Claude, Codex, ...). Baton stays inside Claude Code and gets it from **subagents that differ in both model and stance**: by default chaser A is Opus with a *builder* stance and chaser B is Sonnet with a *skeptic* stance. Both are configurable.

## Install

```text
/plugin marketplace add cornch-k/baton
/plugin install baton@baton
```

To try a local checkout without installing:

```bash
claude --plugin-dir /path/to/baton
```

## Flows

| Command | What it does |
|---|---|
| `/baton:flame-chase "<task>"` | Two chasers (different model and stance) alternate, each turn a fresh subagent; only the workspace passes between them |
| `/baton:cleanup-flame-chase "<task>"` | flame-chase plus a cleaner every few turns: strays removed, a short `NEXT.md`, each epoch squashed into one commit, old history kept in a tag |
| `/baton:ralph-loop "<task>"` | The same task every round in a fresh worker; only the repository carries over |
| `/baton:cleanup-ralph "<task>"` | ralph-loop plus the cleaner |
| `/baton:stateful-ralph "<task>"` | The same task every round in one persistent worker session |
| `/baton:continue-loop "<task>"` | Task once, then "continue" |
| `/baton:goal "<goal>"` | The task becomes the worker's own goal; it stops when it says the goal is met, with evidence |
| `/baton:rlar "<task>"` | A persistent actor works; a fresh reviewer decides "done" and writes the actor's next prompt |
| `/baton:gen-idea "<idea>"` | Idea → a draft with a main direction and alternatives, checked against the repository; no code |
| `/baton:gen-plan <idea>` | A planner that remembers and a fresh analyst agree on `docs/plan.md` |
| `/baton:rlcr [docs/plan.md]` | Build the plan: stop checks every turn, a fresh review every round, a clean whole-change review to finish |
| `/baton:fixed-interrupt "<task>" --eval "<cmd>"` | Chasers alternate every k accepted experiments scored by your evaluator; a blind reviewer picks the winner |
| `/baton:parallel-chase "<task>"` | A coordinator plans three different lanes; each lane chases in parallel, with a shared leaderboard |
| `/baton:parallel-chase-pr "<task>" --eval "<cmd>"` | Three lanes propose; a change merges only when a clean evaluation improves the score |
| `/baton:recursive-lean-prover "<theorem>"` | Lean 4 theorem → lemmas. Each lemma is tried directly in Lean first; only one that doesn't go through gets a prose proof, a step-by-step audit and a split. Formalized in worktrees, recorded in a wiki. A lemma is accepted only when Lean confirms the exact planned statement and `#print axioms` shows no `sorryAx` or extra axiom. Needs a Lake project and Lean via elan (`brew install elan-init`) |
| `/baton:author-flow "<description>"` | Writes a new flow; it lands only after a load check, a fake-world termination check and a critic |

`/baton:flows` lists them and helps you pick one.

Shared flags: `--turns N`, `--minutes M`, `--check "<cmd>"`, `--no-early-stop`, `--in-place`, `--resume [run-id]`.

## How a run works

1. Baton needs a git repository with a clean working tree. It creates a run branch `baton/<flow>-<timestamp>`; your branch is untouched.
2. The main session is the **orchestrator**. It spawns each turn's subagent and passes only what the flow allows (often nothing but the workspace). After every turn, one call to `scripts/baton.sh` commits, runs your check, logs the turn and checks the budget.
3. Agents end each turn with a short `BATON-REPORT` (or a reviewer's `BATON-VERDICT`). The orchestrator keeps only those blocks, so its own context lasts.
4. State lives in `.baton/runs/<run-id>/` (listed in `.git/info/exclude`, so it never enters your tree): `state.json`, `log.md`, check and evaluator logs.
5. At the end you get the stop reason, the commits, and the exact commands to merge or drop the branch, or to resume.

Baton never pushes, never merges into your branch, and never turns on bypass permissions. For long runs, use a scratch repository and the `acceptEdits` or `auto` permission mode.

## Cost

Each turn is a fresh agent that re-reads the workspace. That is the design, and it is what a run pays for. Baton keeps everything around it small:

- Working agents carry six tools (Read, Write, Edit, Bash, Glob, Grep) instead of every tool and MCP server in your session. Their fixed context per request drops from 33k–50k tokens to about 9k, and an agent sends dozens of requests per turn. They have no web or MCP tools; `curl` through Bash still works.
- The orchestrator's bookkeeping is one script call per turn, so it doesn't spend a model round trip on each of commit, check, log and budget.
- Lean lemmas are tried directly in Lean before any prose, audit or split, and Lean's mechanical checks aren't re-run by a reviewer.

Measured on the same two-turn flame chase, 0.2.0 used 59–67% fewer subagent input tokens than 0.1.1 (37% fewer overall) and finished in 65–68 s instead of 85 s.

The biggest dials are yours. Chaser A and the worker default to Opus; setting them to `sonnet` costs much less. Start with a small `--turns`; early stop is on by default.

## Settings

`/plugin` → baton → configure, or the baton rows in `/config`:

| Setting | Default | Options |
|---|---|---|
| Chaser A model / stance | `opus` / `builder` | `opus`, `sonnet`, `haiku`, `fable` / `builder`, `skeptic`, `simplifier`, `tester` |
| Chaser B model / stance | `sonnet` / `skeptic` | same |
| Worker model | `opus` | same models |
| Reviewer model | `sonnet` | same models |
| Default turn budget | `8` | 1–200 |

## Differences from the original flows

- Agents are Claude Code subagents, not separate CLI sessions or vendors; diversity comes from model plus stance.
- Most flows stop early when their own done-condition holds (`--no-early-stop` restores "run to the budget").
- `parallel-chase-pr` proposes local merge candidates instead of opening GitHub pull requests.
- `author-flow`'s termination gate is traced by a reviewer model rather than executed against fake agents.
- `rlcr` runs six stop checks of its own (check command, conflict markers, new stubs, skipped tests, secrets, plan untouched).

## Credits

The flow designs are inspired by [Humanfia's flows](https://humanfia.ai/flows/), [Humanize](https://github.com/humanfia/humanize) and PolyArch/humanize. Baton is an independent re-implementation and contains no code or prompt text from those projects. It is not affiliated with Humanfia or PolyArch. See [NOTICE](NOTICE).

## License

[Apache-2.0](LICENSE)
