## Subagent delegation (OpenCode)

Routine execution goes to OpenCode running a cheaper model, not Claude subagents, to save cost. Before delegating, load the `opencode-cli` skill (`~/.claude/skills/opencode-cli/SKILL.md`): it has the matrix, dispatch and worktree scripts, and the planning, worktree, parallel and context rules.

- **Opus** (Agent tool, model opus): brainstorming and making plans.
- **Sonnet subagent:** frontend tasks and all reviews. **Haiku/Explore:** quick lookups.
- **OpenCode** (`dispatch.ps1`): execution of everything else, including fixes from reviews, and deep read-only investigation.
- **Claude main session:** final pre-ship review and the ship checklist. **Claude only:** auth, payments, prod data, infra, secrets, any production action, anything needing MCP tools.
- **Always:** delegate only tasks that fit one self-contained prompt with an acceptance command; the cheap model never pushes or runs prod actions and commits only in a dispatch-created worktree; Claude reviews before merging; two failures means Claude takes over. Add any problem that still needs action to the skill's Lessons log.
