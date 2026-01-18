# Human-in-the-loop Ralph - runs one iteration
# Watch what Claude does, check the commit, run again
# Tip: Start here before going AFK. Build intuition for how the loop works.
#
# Expects in project root:
#   VISION.md  - End-state vision for the project
#   AGENTS.md  - Instructions for AI agents
#   .beads/    - Issue tracking database
#
# Uses beads + git history for context

if (-not (Test-Path "VISION.md")) {
    Write-Host "Error: VISION.md not found. Run 'ralph-init' to create project files."
    exit 1
}

if (-not (Test-Path "AGENTS.md")) {
    Write-Host "Error: AGENTS.md not found. Run 'ralph-init' to create project files."
    exit 1
}

if (-not (Test-Path "RAILS.md")) {
    Write-Host "Error: RAILS.md not found. Run 'ralph-init' to create project files."
    exit 1
}

if (-not (Test-Path "PROMPT.md")) {
    Write-Host "Error: PROMPT.md not found. Run 'ralph-init' to create project files."
    exit 1
}

$prompt = Get-Content -Path "PROMPT.md" -Raw

claude --dangerously-skip-permissions $prompt
