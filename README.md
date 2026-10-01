# Claude Code + OpenCode delegation

A Claude Code skill that lets Claude act as the planner and quality gate while a cheaper model, run through [OpenCode](https://opencode.ai) from the command line, does the routine execution in isolated git worktrees. The goal is lower Claude spend without giving up review: Claude plans, reviews and ships; the cheaper model writes the code.

It is an experiment, not a guarantee of savings. It was developed on Windows with PowerShell 5.1 and works with any model OpenCode can run. Details can differ between OpenCode versions; the skill tells Claude to check flags and permissions on your install, and lists what is still unvalidated.

## What you get

- **`dispatch.ps1`**: runs one task headlessly through `opencode run`. Attaches the prompt as a file, optionally creates an isolated worktree, prepends safety rules, retries once on endpoint errors, and prints a status line, the git diff summary and the agent's final answer. Run it in Claude Code's PowerShell tool with `run_in_background: true` and Claude is woken when it exits.
- **`new-feature-worktree.ps1`**: creates the parent worktree that owns a feature branch for a large task.
- **`cleanup-worktrees.ps1`**: dry-run-by-default sweep of finished child and daughter worktrees.
- **`SKILL.md`**: the rules Claude follows: who does what (planning, frontend, reviews, execution, ship), when to use a worktree, how to plan parallel work, when to resume an agent instead of splitting.
- **`docs/AGENT-SETUP.md`**: a guide Claude follows to inspect your machine, ask you the right questions, and write your customisation.

## Requirements

- Claude Code, git, Windows PowerShell 5.1 or newer
- OpenCode with at least one provider and model configured (`opencode models` lists them). The OpenCode Desktop app bundles a CLI; the script finds it, or put `opencode` on your PATH.

## Set up (recommended: let Claude do it)

```powershell
git clone <this repo>
cd opencode-claude-delegation
.\install.ps1
```

Then open Claude Code in the repo you want to delegate in and say:

> Read `~/.claude/skills/opencode-cli/docs/AGENT-SETUP.md` and set up OpenCode delegation for me.

Claude will inspect your environment (shell, git, OpenCode install, available models, your existing `CLAUDE.md`), ask you which model to use, which roles go to which Claude model, what must stay Claude-only, where worktrees live, how many agents may run in parallel, and your testing and merge rules. It then writes your answers to `~/.claude/skills/opencode-cli/local.md` (which overrides the skill's defaults, so updating the repo never clobbers your choices), merges a short routing section into your `~/.claude/CLAUDE.md`, and runs a harmless read-only dispatch to check it works.

### Manual setup

1. Run `install.ps1`.
2. Add [`docs/claude-md-snippet.md`](docs/claude-md-snippet.md) to your `CLAUDE.md` and edit the roles.
3. Choose a model: `-Model provider/model`, `$env:OPENCODE_MODEL`, or OpenCode's configured default.

## Use

Ask Claude to delegate, or run it yourself from the repo you want changed:

```powershell
& "$env:USERPROFILE\.claude\skills\opencode-cli\scripts\dispatch.ps1" -Name fix-login-docs -PromptFile task.md -Worktree -Base main
```

- `-ReadOnly` runs OpenCode's `plan` agent for reviews and investigation.
- `-Worktree` creates `<repo>-worktrees\<Name>` on branch `opencode/<Name>`; the agent may commit there, never push.
- `-Session <id>` resumes an earlier run so a fix continues the same chat as the review.
- Big plans: `new-feature-worktree.ps1 -Name <plan>` makes a parent `feat/<plan>`; dispatch children as `<plan>--<task>`, merge bottom-up, then run `cleanup-worktrees.ps1`.

Environment overrides: `OPENCODE_CLI`, `OPENCODE_MODEL`, `OPENCODE_WORKTREES`, `OPENCODE_RUNS`.

## Safety

`--auto` approves everything OpenCode does not explicitly deny, and nothing technically blocks `git push`, deploys, `git stash` or reading `.env` files. Only the rules prepended to each prompt do. They are a guardrail, not a guarantee, and one real run misused `git stash pop` (see the lessons log). Treat this as a tool for repos you trust: review every diff before merging, keep secrets out of the working tree, and do not expose production credentials to the agent. Enforced deny rules are not built yet.

## Layout

```
skills/opencode-cli/       the skill (SKILL.md + scripts/), installed to ~/.claude/skills/
docs/AGENT-SETUP.md        guide Claude follows to customise for you
docs/claude-md-snippet.md  routing rules for CLAUDE.md
install.ps1                copies the skill (and the setup guide) into ~/.claude/skills
```

## License

MIT
