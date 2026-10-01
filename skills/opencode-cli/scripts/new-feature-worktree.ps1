<#
Create the PARENT worktree for a big task: owns the feature branch; children (dispatch -Worktree) branch off it.

  -Name   plan slug, no "--"  -> worktree <repo>-worktrees\<Name>, branch feat/<Name>
  -From   start point (default: origin/main if present, else main)
  -Repo   repo (default: the git repo of the current directory)
Prints the worktree path and branch. Children are then dispatched as -Name <Name>--<task> -Worktree (Base defaults to feat/<Name>).
Worktree root: $env:OPENCODE_WORKTREES, else <repo parent>\<repo name>-worktrees.
#>
param(
  [Parameter(Mandatory)][string]$Name,
  [string]$From,
  [string]$Repo
)
if ($Name -match '--') { throw 'plan name must not contain "--" (reserved for child/daughter levels)' }
if (-not $Repo) { $Repo = (git rev-parse --show-toplevel 2>$null) -replace '/', '\' }
if (-not $Repo -or -not (Test-Path $Repo)) { throw 'not inside a git repo; pass -Repo <path>' }
if (-not $From) {
  git -C $Repo fetch origin main 2>&1 | Out-Null
  $From = if (git -C $Repo rev-parse --verify --quiet origin/main) { 'origin/main' } else { 'main' }
}
$wtRoot = if ($env:OPENCODE_WORKTREES) { $env:OPENCODE_WORKTREES } else { Join-Path (Split-Path $Repo -Parent) ((Split-Path $Repo -Leaf) + '-worktrees') }
$dir = Join-Path $wtRoot $Name
if (Test-Path $dir) { throw "$dir already exists" }
git -C $Repo worktree add -b "feat/$Name" $dir $From 2>&1 | Out-Null
if (-not (Test-Path $dir)) { throw "worktree creation failed for $Name from $From" }
"parent worktree: $dir  branch: feat/$Name  from: $From"
