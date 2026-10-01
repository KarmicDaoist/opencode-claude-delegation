<#
Sweep dispatch-created child/daughter worktrees (branches opencode/*), deepest first. Dry run by default.
Parent of opencode/<plan>--<task>--<sub> is opencode/<plan>--<task>; parent of opencode/<plan>--<task> is
opencode/<plan> or feat/<plan> (first that exists). Branches without "--" need -Base.

  -Base           fallback parent for branches without "--" (e.g. opencode/<name> from a single dispatch)
  -Repo           repo (default: the git repo of the current directory)
  -OlderThanDays  also flag worktrees untouched this long (default 7)
  -Apply          remove worktrees whose branch is fully merged into its parent (and clean)
  -Force          also remove stale unmerged/dirty ones (their commits are lost)
Parent feature worktrees (feat/<plan>) are never removed here; remove them by hand after the PR merges.
Worktree root: $env:OPENCODE_WORKTREES, else <repo parent>\<repo name>-worktrees.
#>
param(
  [string]$Base,
  [string]$Repo,
  [int]$OlderThanDays = 7,
  [switch]$Apply,
  [switch]$Force
)
if (-not $Repo) { $Repo = (git rev-parse --show-toplevel 2>$null) -replace '/', '\' }
if (-not $Repo -or -not (Test-Path $Repo)) { throw 'not inside a git repo; pass -Repo <path>' }
$root = if ($env:OPENCODE_WORKTREES) { $env:OPENCODE_WORKTREES } else { Join-Path (Split-Path $Repo -Parent) ((Split-Path $Repo -Leaf) + '-worktrees') }
function Test-Branch($b) { git -C $Repo rev-parse --verify --quiet "refs/heads/$b" | Out-Null; $LASTEXITCODE -eq 0 }

$items = @()
$raw = git -C $Repo worktree list --porcelain | Out-String
foreach ($block in ($raw -split "`r?`n`r?`n")) {
  if ($block -notmatch 'worktree (.+)') { continue }
  $path = $Matches[1].Trim() -replace '/', '\'
  if ($block -notmatch 'branch refs/heads/(opencode/\S+)') { continue }
  if (-not ($path -like "$root\*")) { continue }
  $branch = $Matches[1]
  $short = $branch -replace '^opencode/', ''
  $i = $short.LastIndexOf('--')
  $parent = $Base
  if ($i -gt 0) {
    $stem = $short.Substring(0, $i)
    $parent = @("opencode/$stem", "feat/$stem") | Where-Object { Test-Branch $_ } | Select-Object -First 1
  }
  $items += [pscustomobject]@{ Path = $path; Branch = $branch; Parent = $parent; Depth = ([regex]::Matches($short, '--')).Count }
}

foreach ($it in ($items | Sort-Object Depth -Descending)) {
  if (-not $it.Parent) { "{0,-50} no parent resolved (pass -Base) -> keep" -f $it.Branch; continue }
  git -C $Repo merge-base --is-ancestor $it.Branch $it.Parent
  $merged = ($LASTEXITCODE -eq 0)
  $dirty = [bool](git -C $it.Path status --porcelain)
  $age = if (Test-Path $it.Path) { ((Get-Date) - (Get-Item $it.Path).LastWriteTime).Days } else { 999 }
  $stale = $age -ge $OlderThanDays
  $removable = ($merged -and -not $dirty) -or ($stale -and $Force)
  "{0,-50} parent={1} merged={2} dirty={3} age={4}d -> {5}" -f $it.Branch, $it.Parent, $merged, $dirty, $age, $(if ($removable) { 'REMOVABLE' } elseif ($stale) { 'stale (needs -Force)' } else { 'keep' })

  if ($Apply -and $removable) {
    git -C $Repo worktree remove --force $it.Path 2>$null
    if (Test-Path $it.Path) {
      Remove-Item -Recurse -Force $it.Path -ErrorAction SilentlyContinue   # Windows can hold the dir
      git -C $Repo worktree prune
    }
    git -C $Repo branch $(if ($merged) { '-d' } else { '-D' }) $it.Branch | Out-Null
    "  removed $($it.Path) and $($it.Branch)"
  }
}
