# Initialize a project for Ralph loops
# Creates VISION.md and AGENTS.md templates

Write-Host "Initializing Ralph project files..."

if (Test-Path "VISION.md") {
    Write-Host "VISION.md already exists, skipping."
} else {
    @"
# Project Vision

## What We're Building

<!-- Describe the end state. What does "done" look like? -->

## Core Features

<!-- List the key capabilities -->

-

## Non-Goals

<!-- What are we explicitly NOT building? -->

-

## Success Criteria

<!-- How do we know we're done? -->

-
"@ | Set-Content -Path "VISION.md" -Encoding UTF8
    Write-Host "Created VISION.md"
}

if (Test-Path "AGENTS.md") {
    Write-Host "AGENTS.md already exists, skipping."
} else {
    @"
# Agent Instructions

## Project Overview

<!-- Brief description of the project -->

## Tech Stack

<!-- Languages, frameworks, key dependencies -->

-

## Quality Gates

Run these before every commit:

``````bash
# Example for Rust:
# cargo fmt && cargo clippy && cargo test

# Example for Node:
# npm run lint && npm run test

# Update with your project's commands:

``````

## Issue Tracking

This project uses beads for issue tracking. Issues marked **Backlog** are ignored - only work on ready issues.

``````bash
bd ready                          # Find available work
bd show <id>                      # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>                     # Complete work
bd create "description"           # Create new issue
``````

## Code Conventions

<!-- Project-specific patterns, naming, structure -->

-

## Important Files

<!-- Key files an agent should know about -->

-
"@ | Set-Content -Path "AGENTS.md" -Encoding UTF8
    Write-Host "Created AGENTS.md"
}

if (Test-Path "RAILS.md") {
    Write-Host "RAILS.md already exists, skipping."
} else {
    @"
# RAILS - Guardrails & Lessons Learned

Mistakes we don't repeat. Keep entries short.

---

<!-- Example entry:

## GIT-001: Review before ``git clean``

Never run ``git clean -fd`` without first checking for non-temp untracked files. Use ``git clean -n`` to preview.

-->
"@ | Set-Content -Path "RAILS.md" -Encoding UTF8
    Write-Host "Created RAILS.md"
}

if (Test-Path "PROMPT.md") {
    Write-Host "PROMPT.md already exists, skipping."
} else {
    @"
@VISION.md @AGENTS.md @RAILS.md

You are an autonomous coding agent working on this project.
Read VISION.md to understand what we're building.
Read AGENTS.md for workflow instructions.
Read RAILS.md for project-specific guardrails and lessons learned.

1. Run 'bd ready' to find available issues. Ignore Backlog issues.
2. Run 'git log --oneline -10' to see recent work.
3. Pick the HARDEST, highest-priority issue. Evaluate the issues yourself; don't just pick the first one.
4. Run 'bd show <id>' to understand the issue, then 'bd update <id> --status in_progress' to claim it.
5. Implement the task. Check RAILS.md for relevant warnings before making changes.
6. Run quality gates (check AGENTS.md for project-specific commands).
   - If tests fail, fix them before proceeding. DO NOT commit broken code.
   - If you cannot fix tests, leave issue in_progress and create a new blocking issue with 'bd create'.
7. For UI changes: visually verify the implementation works as expected.
8. Only after tests pass: commit your changes with a descriptive message.
9. IF there are any instructions in AGENTS.md about documenting breaking changes against a production deployment, MAKE SURE TO DOCUMENT THEM SUCH THAT MIGRATIONS CAN BE SCRIPTED AND EASILY EXECUTED IN THE FUTURE.
10. If you made a significant mistake (repeated twice or major time sink), add an entry to RAILS.md.
11. Run 'bd close <id>' to mark complete.

CRITICAL: ONLY DO ONE TASK. Keep CI green. Every commit must pass all tests.
"@ | Set-Content -Path "PROMPT.md" -Encoding UTF8
    Write-Host "Created PROMPT.md"
}

# Check for beads
if (-not (Test-Path ".beads")) {
    Write-Host ""
    Write-Host "Note: No .beads/ directory found."
    Write-Host "Run 'bd init' to set up issue tracking."
}

Write-Host ""
Write-Host "Done. Edit VISION.md, AGENTS.md, RAILS.md, and PROMPT.md, then run:"
Write-Host "  ralph-once   # Human-in-the-loop (one iteration)"
Write-Host "  ralph-loop N # AFK mode (N iterations)"
