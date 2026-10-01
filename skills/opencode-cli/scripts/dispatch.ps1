<#
Dispatch one task to OpenCode headlessly. Launch from Claude Code's PowerShell tool with run_in_background
so Claude is woken when the run exits. (Do NOT launch via Bash `powershell -Command "..."`: Bash expands $env:* first.)

  -Name       short slug; names the log, session title and (if -Worktree) the branch
  -Prompt     self-contained task prompt (OpenCode has none of Claude's context)
  -PromptFile path to a prompt file (preferred for long prompts)
  -Repo       repo to work in (default: the git repo of the current directory)
  -Worktree   isolate in <repo>-worktrees\<Name> on branch opencode/<Name>.
              Use when the task EDITS files and may overlap other running agents or your own edits.
              Skip for read-only investigation, or a single edit agent touching files nothing else touches.
  -Base       branch to fork a new -Worktree from. Defaults to the parent implied by -Name (<plan>--<task> forks from
              feat/<plan>; <plan>--<task>--<sub> from opencode/<plan>--<task>); otherwise required
  -ReadOnly   review/investigation: runs the `plan` agent and rules forbid edits
  -Session    continue an earlier OpenCode session id (follow-up on the same agent)
  -Retries    re-run when the endpoint errors with no result (default 1)
  -Model      provider/model; default $env:OPENCODE_MODEL, else OpenCode's own configured default

Environment overrides: OPENCODE_CLI (path to the CLI), OPENCODE_MODEL, OPENCODE_WORKTREES (worktree root;
default <repo parent>\<repo name>-worktrees), OPENCODE_RUNS (log dir; default %LOCALAPPDATA%\Temp\opencode-runs).

The prompt is delivered as an attached file (-f), so there is no argv length or quoting limit.
Output ends with a status line, git summary, and the tail of the agent's log (its final answer).
#>
param(
  [Parameter(Mandatory)][string]$Name,
  [string]$Prompt,
  [string]$PromptFile,
  [string]$Repo,
  [switch]$Worktree,
  [string]$Base,
  [switch]$ReadOnly,
  [string]$Session,
  [int]$Retries = 1,
  [string]$Model = $env:OPENCODE_MODEL
)
$ErrorActionPreference = 'Continue'
if ($PromptFile) { $Prompt = Get-Content -Raw $PromptFile }
if (-not $Prompt) { throw 'need -Prompt or -PromptFile' }

if (-not $Repo) { $Repo = (git rev-parse --show-toplevel 2>$null) -replace '/', '\' }
if (-not $Repo -or -not (Test-Path $Repo)) { throw 'not inside a git repo; pass -Repo <path>' }
$wtRoot = if ($env:OPENCODE_WORKTREES) { $env:OPENCODE_WORKTREES } else { Join-Path (Split-Path $Repo -Parent) ((Split-Path $Repo -Leaf) + '-worktrees') }

$cli = $env:OPENCODE_CLI
if (-not $cli) { $c = Get-Command opencode -ErrorAction SilentlyContinue; if ($c) { $cli = $c.Source } }
if (-not $cli) { $cli = "$env:LOCALAPPDATA\Programs\@opencodedesktop\resources\opencode-cli.exe" }
if (-not (Test-Path $cli)) { throw 'OpenCode CLI not found; set $env:OPENCODE_CLI or put `opencode` on PATH' }

$logDir = if ($env:OPENCODE_RUNS) { $env:OPENCODE_RUNS } else { Join-Path $env:LOCALAPPDATA 'Temp\opencode-runs' }
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir "$Name.log"
$taskFile = Join-Path $logDir "$Name.task.md"

$dir = $Repo
if ($Worktree) {
  $dir = Join-Path $wtRoot $Name
  # Levels: <plan>--<task> (child) and <plan>--<task>--<sub> (daughter); the parent worktree is feat/<plan>. Max 3 levels.
  $segs = ($Name -split '--').Count
  if ($segs -gt 3) { throw 'max depth is parent -> child -> daughter (at most 2 "--" in -Name); redesign the plan instead' }
  if (-not $Base -and $segs -gt 1) {
    $stem = $Name.Substring(0, $Name.LastIndexOf('--'))
    $Base = @("opencode/$stem", "feat/$stem") | Where-Object { git -C $Repo rev-parse --verify --quiet "refs/heads/$_" } | Select-Object -First 1
  }
  if (-not (Test-Path $dir)) {
    if (-not $Base) { throw '-Worktree needs -Base <integration branch or commit>. Never branch off main or whatever the shared checkout has checked out.' }
    git -C $Repo worktree add -b "opencode/$Name" $dir $Base 2>&1 | Out-Null
    if (-not (Test-Path $dir)) { throw "worktree creation failed for $Name from $Base" }
  }
}
elseif (-not $ReadOnly) {
  $dirty = git -C $dir status --porcelain
  if ($dirty) { "WARNING: $dir already has uncommitted changes; agent edits will mix with them. Consider -Worktree.`n" }
}

$rules = if ($ReadOnly) {
  'READ-ONLY: do not edit, create or delete any file; run no state-changing commands.'
} elseif ($Worktree) {
  # isolated worktree: committing on its own branch is allowed (Claude reviews before merge)
  'You are on your own isolated branch. Commit your work here with conventional messages, staging explicit paths only (never git add -A or .). Never push, force-push, skip hooks, change git config, or touch main. Never run deploys, cloud CLIs, infrastructure tools, or other production actions.'
} else {
  'Shared checkout: never commit or push; leave changes uncommitted. Do not touch main. Never run deploys, cloud CLIs, infrastructure tools, or other production actions.'
}
@"
Repo rules: read AGENTS.md first if the repo has one. $rules
Your shell is Windows PowerShell 5.1 (no /dev/null, head, grep; use Select-String, Select-Object -First, 2>`$null). Prefer your Read/Grep/Glob tools over shell for searching.
Never use git stash (the stash list is shared by every worktree) and never delete, restore or revert files you did not create or change yourself.
Add no new tests unless one would fail without the intended behavior. Keep changes minimal and match surrounding code.
Finish with a short summary: files changed, what you did, anything unverified.

TASK:
$Prompt
"@ | Set-Content -Encoding utf8 $taskFile

Push-Location $dir
$cliArgs = @('run', '--auto', '--title', $Name, '-f', $taskFile)
if ($Model) { $cliArgs += @('--model', $Model) }
if ($ReadOnly) { $cliArgs += @('--agent', 'plan') }  # plan agent denies edits; stronger than a prompt rule alone
if ($Session) { $cliArgs += @('--session', $Session) }

$attempt = 0
do {
  $attempt++
  # stringify so PowerShell does not wrap stderr lines as ErrorRecords (which sets a false failure)
  & $cli @cliArgs 'Do the task described in the attached file.' 2>&1 | ForEach-Object { "$_" } | Out-File -Encoding utf8 $log
  $code = $LASTEXITCODE
  $text = Get-Content -Raw $log
  $endpointError = $text -match 'Error:.*(Decode error|Transport|socket connection was closed|rate limit|ECONN|ETIMEDOUT|fetch failed|5\d\d)'
  $lastLines = (Get-Content $log -Tail 8) -join "`n"
  $noResult = $endpointError -and ($lastLines -notmatch '\S{40,}')
  if ($noResult -and $attempt -le $Retries) { "retrying after endpoint error (attempt $attempt)"; Start-Sleep 10 }
} while ($noResult -and $attempt -le $Retries)

$status = if ($noResult) { 'FAILED: endpoint error, no result' } elseif ($code -ne 0) { "exit $code" } else { 'OK' }
"`n=== opencode $status | attempts $attempt | dir $dir | log $log ==="
git status --short
git diff --stat
"`n--- agent log tail ---"
Get-Content $log -Tail 60
Pop-Location
exit $(if ($noResult) { 2 } else { $code })
