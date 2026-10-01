---
name: opencode-cli
description: Use when delegating work to subagents, dispatching OpenCode agents, running a cheaper outside model as a subagent, saving cost on subagent work, planning parallel agent execution, or managing agent worktrees (parent/child/daughter, merging, cleanup, context reuse). Holds the delegation matrix, the dispatch and worktree scripts, and the planning/worktree/parallel/context rules (Windows + PowerShell).
---

# OpenCode delegation

Claude plans, reviews and ships; a cheaper model on OpenCode executes routine work to save cost. Scripts are in `scripts/` next to this file. The defaults below are a starting point: if `local.md` exists next to this file, it holds this user's choices and overrides them. If it does not exist and the user wants to set this up, follow `docs/AGENT-SETUP.md` from the repo (or ask the user for it).

Statements here are written for OpenCode's CLI as seen in early 2026 and may differ in your version: check `opencode run --help` and `opencode debug agents` before relying on a flag or permission.

## Setup facts

- **CLI:** `dispatch.ps1` uses `$env:OPENCODE_CLI`, else `opencode` on PATH, else the OpenCode Desktop bundled CLI under `%LOCALAPPDATA%\Programs\@opencodedesktop\resources\`. The npm `opencode-ai` package may conflict with the desktop app's shared database; if you see database errors, use the bundled CLI.
- **Model:** `-Model provider/model`, else `$env:OPENCODE_MODEL`, else OpenCode's configured default. List with `opencode models`.
- **Useful `opencode run` flags:** `--model`, `--session`/`-s`, `--continue`/`-c`, `--fork`, `--agent`, `--format json`, `--file`/`-f`, `--title`, `--auto` (auto-approve anything not explicitly denied). The working directory is the process cwd. `opencode session list` shows sessions for the current project.
- **Permissions:** the default `build` agent typically allows everything, shell included, and `--auto` approves any `ask` rules. Nothing technically blocks push, deploy, `git stash` or reading secrets: only the prompt rules the script prepends do. The `plan` agent denies edits (`-ReadOnly` uses it). Subagent types such as `general` and `explore` may not nest further.
- **Measuring:** `opencode stats --days 0 --models --cost --json` and `opencode session export <id>` report tokens and cost per session; child sessions carry a `parentID`.

## Dispatching

Claude Code PowerShell tool, `run_in_background: true`; Claude is woken when the run exits.

```powershell
& "$env:USERPROFILE\.claude\skills\opencode-cli\scripts\dispatch.ps1" -Name <slug> -PromptFile <file> [-Worktree [-Base <branch>]] [-ReadOnly] [-Session <id>] [-Repo <path>] [-Model <provider/model>]
```

- Do not launch it through Bash `powershell -Command "..."`: Bash expands `$env:` first.
- The script attaches the prompt as a file, prepends rules for the mode (read-only, run with the `plan` agent / isolated worktree: commit on own branch / shared checkout: never commit; all modes: no `git stash`, no deleting others' files), retries once on an endpoint error with no result, and ends with a status line (`OK`, `exit N`, `FAILED`), `git status`/`diff --stat` and the agent's log tail (its final answer). Log: `%LOCALAPPDATA%\Temp\opencode-runs\<slug>.log`.
- Prompts need goal, owned files, contract and an acceptance command (the agent has none of Claude's context; its shell is PowerShell). Keep the acceptance command targeted: the one or two relevant test files or a typecheck, not a full suite. Tell the agent: no new tests unless the task names them, no test runs beyond the acceptance command. Say "grep for every occurrence of X" instead of listing files.
- Resume an agent with `-Session <id>` (e.g. review, then fix in the same chat). Snapshot `git diff --stat` before an edit run to compare after, and check `git diff --name-only` against the files it owned.
- Read a run's output to the end; the final summary is at the tail.

## Delegation matrix (default)

| Work | Goes to |
|---|---|
| Brainstorming, making plans | Opus (Agent tool, model opus) |
| Frontend / visual tasks | Sonnet subagent |
| All reviews | Sonnet subagent |
| Execution of everything else: backend, migrations, mechanical refactors, docs, changelogs, test fixes, debugging with a repro, fixes that came out of a review | cheap model via `dispatch.ps1` |
| Deep read-only investigation | cheap model, `-ReadOnly` |
| Quick lookups, greps | Haiku/Explore |
| Final pre-ship review and ship checklist | Claude main session |
| Auth, payments, prod data, infra, secrets, any production action; anything needing MCP, design or analytics tooling | Claude only |

Rules: delegate only if the task fits one self-contained prompt with an acceptance command. The cheap model never pushes, deploys or runs production actions; it commits only inside a dispatch-created `-Worktree`, never in a shared checkout, and Claude reviews before merging. Two failures, or edits outside owned files: Claude takes over. About one plan task per agent. Keep a short log of delegated tasks (rework, review effort) and stop delegating a category that costs more to review and fix than to do directly.

## Planning, worktree, parallel and context rules

**Hierarchy, max 3 levels.** Big task (more than ~3 files, or more than one wave, or more than one agent): create one parent worktree owning the feature branch, `scripts/new-feature-worktree.ps1 -Name <plan>` (`<repo>-worktrees\<plan>`, branch `feat/<plan>`). Children: `dispatch.ps1 -Name <plan>--<task> -Worktree` (branch `opencode/<plan>--<task>`, forks from the parent). Daughters: `<plan>--<task>--<sub>`, forking from the child. Git cannot hold both `x` and `x/y` as branches, hence `--`. The script refuses a fourth level and a new worktree with no resolvable base. Add a deeper level only when the level above is split in parallel across disjoint files and needs filesystem isolation; otherwise use in-worktree subagents. Small task: no parent; tiny edits on a clean checkout may use the shared checkout; read-only never gets a worktree.

**Merging and cleanup.** Bottom-up: daughters into child, children into parent in wave order, parent to main in one PR. A reviewer checks each branch diff first; Claude merges and runs tests after each merge. Then `scripts/cleanup-worktrees.ps1` (dry run; `-Apply` removes merged, clean ones deepest first; stale or unmerged need `-Force`). Remove the parent worktree by hand after the PR merges. If `git worktree remove` fails with Permission denied on Windows: delete the directory, `git worktree prune`, `git branch -D`.

**Plans carry an Execution design block** (lean: contracts, behaviour, test names): (1) big or small, parent worktree needed? (2) per-task read set and write set; write/write overlap means same agent or serial, write-then-read means a later wave or same agent; (3) agent count = widest wave after clustering tasks that share context, with a cap on concurrent agents (3 to 5 is a sensible start); (4) worktree levels needed and why; (5) waves and what runs concurrently; (6) model per task; (7) context plan. One owning task per shared contract; migrations strictly serial. Claude writes hotspot files (changelogs, status docs, lockfiles, generated files) at integration.

**Split or resume.** Discovery (reading files, learning contracts) is paid once per agent. Tasks touching the same files or concepts go to one agent, run in sequence, resumed with `-Session`. Split only when files are disjoint, context is separate and the parallel speedup is real. Use a fresh agent when the next task is another subsystem or the session has gone long or started forgetting. After one failure retry once in the same session with the error attached; a second failure goes to Claude.

**OpenCode's own subagents.** A lead agent can spawn OpenCode subagents inside its worktree. Claude still owns the worktree levels (the isolation boundary): tell the lead which subagents to spawn, which files each owns, that none may edit the same file, and that it verifies and summarizes. They share the lead's working directory. Count them toward the concurrency cap.

**Parallelism.** Frontend and backend work can run side by side in different directories. Start with few concurrent runs and watch for endpoint failures before raising the count. A fresh worktree needs its own dependency install (slow and large in monorepos), which is a reason to avoid needless worktrees.

## Not yet validated

Treat these as open questions and record what you find:

- How much review or rework the cheap model's diffs need on your real tasks. Judge by rework, not by whether runs complete.
- Whether the `plan` agent hard-blocks shell writes (its permissions deny `edit`; shell was not exhaustively tested).
- Whether resuming a session is actually cheaper than a fresh agent for your tasks (check with `opencode stats`).
- Not built: enforced deny rules for push, deploy, `git stash` and `.env` reads for `--auto` runs, a task-prompt template, a delegation log.

## Lessons log

Add problems that still need action here. Seed entries from the first users:

- The model endpoint can fail mid-run with a decode or transport error and end with no answer. The script retries once; if it still ends `FAILED`, resume with the same `-Name`/`-Worktree` plus `-Session <id>` (from `opencode session list`) and a short "you were cut off; orient with git status and continue" prompt.
- `git stash` is shared by every worktree. In one run an agent in its own worktree ran `git stash pop`, which applied an unrelated stash and then deleted the restored files. The script now prepends "never use git stash" to every run; put the same line in prompts for other agents, and check `git stash list` afterwards.
- A fix prompt that lists files by name can miss another file with the same issue. Ask for a repo-wide grep.
