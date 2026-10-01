# Agent setup guide

You are Claude Code, and the user wants the `opencode-cli` skill set up for their machine and preferences. Follow this guide. Do not assume answers: inspect the environment first, then ask only what you cannot determine. Never print secrets (API keys, tokens) you encounter.

## 1. Inspect the environment (no questions yet)

Run and note the results:

- OS and shell: `$PSVersionTable.PSVersion`, `git --version`. The scripts need Windows PowerShell 5.1+ and git.
- OpenCode: `Get-Command opencode`, else check `%LOCALAPPDATA%\Programs\@opencodedesktop\resources\opencode-cli.exe`. Then `opencode --version` and `opencode models` (the model list is the options for the question below).
- Skill install: whether `%USERPROFILE%\.claude\skills\opencode-cli\` exists (if not, run `install.ps1` from the repo).
- The target repo: `git rev-parse --show-toplevel`, default branch, whether it has `AGENTS.md`/`CLAUDE.md`, its test and typecheck commands, and whether it is a monorepo with heavy installs (worktrees duplicate them).
- Existing `~/.claude/CLAUDE.md` content that already routes subagents or sets a testing policy (do not overwrite; merge).

## 2. Ask the user (AskUserQuestion, batch related questions)

1. **Model:** which model from `opencode models` should do routine execution? Which, if any, should be the free/fallback option?
2. **Roles:** which Claude model for planning, frontend, reviews, and final pre-ship review? Offer the default matrix in `SKILL.md` and ask what to change.
3. **Off-limits for the cheap model:** which areas stay Claude-only (auth, payments, production data, infra, secrets, anything else)?
4. **Worktrees:** where should they live (default `<repo parent>\<repo name>-worktrees`)? Is the default "worktree per edit task, tiny-edit exception" acceptable?
5. **Concurrency:** how many parallel agents (3 to 5 is a sensible start)? Any rate limit or plan limit to respect?
6. **Review and merge:** should Claude merge reviewed branches itself, or leave merging to the user? One PR per plan?
7. **Testing policy:** targeted tests only, or full suites? Anything agents must never run (slow or destructive commands)?
8. **Commit rules:** may the cheap model commit inside its dispatch-created worktree? Required commit message style?

Skip any question the environment already answered. Prefer fewer questions.

## 3. Write the customisation

- `~/.claude/skills/opencode-cli/local.md`: the user's answers as short bullets (model, roles, off-limits list, worktree root, concurrency cap, merge policy, test commands, commit style, the known paths and CLI location). `SKILL.md` says this file overrides its defaults. Do not edit the shipped `SKILL.md` for personal choices, so updates stay clean.
- `~/.claude/CLAUDE.md`: add or merge `docs/claude-md-snippet.md`, edited to the user's roles. Keep it short and point to the skill.
- Environment variables only if needed: `OPENCODE_MODEL`, `OPENCODE_CLI`, `OPENCODE_WORKTREES` (set persistently with `setx`, and tell the user a new shell is needed).
- Do not write absolute personal paths into the shipped repo files.

## 4. Verify, honestly

- Run one cheap read-only dispatch (`-ReadOnly`, a question about the repo) in the background and confirm you are woken, the status line says `OK`, and the answer is at the log tail.
- Optionally one tiny edit task with `-Worktree` on a scratch branch, then clean up with `cleanup-worktrees.ps1`.
- Report what worked, what failed, and what remains unverified. Add any problem that still needs action to the skill's Lessons log.

## 5. Tell the user how to use it

One short paragraph: Claude plans, the cheap model executes in worktrees, Claude reviews and merges; how to ask for a delegated task; that `--auto` cannot technically block push or deploys, so diffs must be reviewed before merging.
