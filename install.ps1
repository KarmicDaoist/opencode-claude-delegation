# Copies the skill into your Claude Code skills folder (re-run to update; your local.md is kept).
$src = Join-Path $PSScriptRoot 'skills\opencode-cli'
$dst = Join-Path $env:USERPROFILE '.claude\skills\opencode-cli'
New-Item -ItemType Directory -Force "$dst\docs" | Out-Null
Copy-Item "$src\*" $dst -Recurse -Force
Copy-Item (Join-Path $PSScriptRoot 'docs\*') "$dst\docs" -Force
"Installed to $dst"
"Next: open Claude Code in your repo and ask it to read $dst\docs\AGENT-SETUP.md and set up delegation."
