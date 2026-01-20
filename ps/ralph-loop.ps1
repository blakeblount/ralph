# AFK Ralph - runs multiple iterations autonomously
# Usage: ralph-loop.ps1 <iterations>
# Run in Docker sandbox: docker sandbox run claude ralph-loop 20
#
# Expects in project root:
#   VISION.md  - End-state vision for the project
#   AGENTS.md  - Instructions for AI agents
#   .beads/    - Issue tracking database
#
# Tips applied:
# - Start conservative (10-20 iterations) before scaling
# - Each commit must pass all tests (Keep CI Green)
# - Completion promise for explicit "done" signal

param(
    [Parameter(Position=0)]
    [int]$Iterations
)

$ErrorActionPreference = "Stop"

# Track Claude process globally for cleanup
$script:ClaudeProcess = $null

# Kill a process and all its descendants
function Stop-ProcessTree {
    param([int]$ParentId)

    # Find all child processes
    $children = Get-CimInstance Win32_Process -Filter "ParentProcessId = $ParentId" -ErrorAction SilentlyContinue
    foreach ($child in $children) {
        Stop-ProcessTree -ParentId $child.ProcessId
    }

    # Kill the parent
    Stop-Process -Id $ParentId -Force -ErrorAction SilentlyContinue
}

# Cleanup function to kill orphaned Claude processes
function Stop-ClaudeProcess {
    if ($script:ClaudeProcess -and -not $script:ClaudeProcess.HasExited) {
        Write-Host "Cleaning up Claude process tree..." -ForegroundColor Yellow
        try {
            Stop-ProcessTree -ParentId $script:ClaudeProcess.Id
            $script:ClaudeProcess.WaitForExit(5000)
        } catch {
            # Process may have already exited
        }
    }
}

# Register cleanup for Ctrl+C and script exit
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action { Stop-ClaudeProcess }
trap {
    Stop-ClaudeProcess
    break
}

if (-not $Iterations -or $Iterations -le 0) {
    Write-Host "Usage: ralph-loop.ps1 <iterations>"
    Write-Host ""
    Write-Host "Tip: Start with 10-20 iterations to understand token consumption."
    Write-Host "     A 50-iteration loop can cost `$50-100+ on large codebases."
    exit 1
}

# Check for required files
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

$basePrompt = Get-Content -Path "PROMPT.md" -Raw

# Safety guardrail
$MAX_SAFE_ITERATIONS = 50
if ($Iterations -gt $MAX_SAFE_ITERATIONS) {
    Write-Host "Warning: $Iterations iterations exceeds safe limit of $MAX_SAFE_ITERATIONS."
    $confirm = Read-Host "Are you sure? (y/N)"
    if ($confirm -ne "y") {
        exit 1
    }
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LOG_FILE = "ralph-log-$timestamp.txt"
$startMessage = "Starting Ralph loop at $(Get-Date)"
Write-Host $startMessage
Add-Content -Path $LOG_FILE -Value $startMessage
$maxMessage = "Max iterations: $Iterations"
Write-Host $maxMessage
Add-Content -Path $LOG_FILE -Value $maxMessage

# Build full prompt: base prompt + loop-specific completion signal
$loopSuffix = @"

LOOP MODE INSTRUCTIONS:
- You are running in a loop. Each iteration should complete exactly ONE task.
- Ignore Backlog issues entirely - treat them as invisible.
- After completing one task, simply end your response. Do NOT output <promise>COMPLETE</promise>.
- ONLY output <promise>COMPLETE</promise> if 'bd ready' shows zero ready issues at the START of your run.
- The loop controller will call you again for the next task.
"@

$prompt = $basePrompt + $loopSuffix

$consecutiveFailures = 0
$MAX_CONSECUTIVE_FAILURES = 3

for ($i = 1; $i -le $Iterations; $i++) {
    Write-Host ""
    Add-Content -Path $LOG_FILE -Value ""
    $iterMessage = "=== Iteration $i of $Iterations ==="
    Write-Host $iterMessage
    Add-Content -Path $LOG_FILE -Value $iterMessage

    # Use temp file to capture output while monitoring in real-time
    $tempOutput = [System.IO.Path]::GetTempFileName()
    $tempPrompt = [System.IO.Path]::GetTempFileName()
    $iterationFailed = $false

    try {
        # Write prompt to temp file to avoid escaping issues
        Set-Content -Path $tempPrompt -Value $prompt -NoNewline

        # Call node directly with claude-code CLI, bypassing the .ps1 wrapper
        $claudeCli = "$env:APPDATA\npm\node_modules\@anthropic-ai\claude-code\cli.js"
        $script:ClaudeProcess = Start-Process -FilePath "node.exe" `
            -ArgumentList $claudeCli, "--dangerously-skip-permissions", "-p", $tempPrompt `
            -RedirectStandardOutput $tempOutput `
            -RedirectStandardError "$tempOutput.err" `
            -NoNewWindow -PassThru

        # Monitor for hanging errors while Claude runs (check every 30 seconds like zsh)
        while (-not $script:ClaudeProcess.HasExited) {
            # Check if error pattern appeared in output
            if (Test-Path $tempOutput) {
                $currentOutput = Get-Content -Path $tempOutput -Raw -ErrorAction SilentlyContinue
                if ($currentOutput -match "Error: No messages returned|promise rejected with the reason|processTicksAndRejections") {
                    Write-Host "Detected hanging error - killing Claude process tree..." -ForegroundColor Yellow
                    Add-Content -Path $LOG_FILE -Value "Detected hanging error - killing Claude process tree..."
                    Stop-ProcessTree -ParentId $script:ClaudeProcess.Id
                    $iterationFailed = $true
                    break
                }
            }
            Start-Sleep -Seconds 30
        }

        # Wait for process to fully exit
        $script:ClaudeProcess.WaitForExit()
        $exitCode = $script:ClaudeProcess.ExitCode

        # Debug: show exit code info
        if ($null -eq $exitCode) {
            Write-Host "[Debug] Exit code: null" -ForegroundColor Cyan
        } else {
            Write-Host "[Debug] Exit code: $exitCode" -ForegroundColor Cyan
        }

        # Read and display output
        $output = ""
        if (Test-Path $tempOutput) {
            $output = Get-Content -Path $tempOutput -Raw -ErrorAction SilentlyContinue
            if ($output) { Write-Host $output }
        }
        if (Test-Path "$tempOutput.err") {
            $stderrOutput = Get-Content -Path "$tempOutput.err" -Raw -ErrorAction SilentlyContinue
            if ($stderrOutput) {
                Write-Host $stderrOutput -ForegroundColor Yellow
                $output += $stderrOutput
            }
        }

        # Check exit code - treat null/empty/0 as success
        if ($null -ne $exitCode -and $exitCode -ne 0 -and -not $iterationFailed) {
            $iterationFailed = $true
            $errorMessage = "Warning: Claude exited with code $exitCode"
            Write-Host $errorMessage -ForegroundColor Yellow
            Add-Content -Path $LOG_FILE -Value $errorMessage
        }

        # Final check for error patterns (in case they appeared at the end)
        if (-not $iterationFailed -and $output -match "Error: No messages returned|promise rejected with the reason") {
            $errorMessage = "Detected error pattern in output"
            Write-Host $errorMessage -ForegroundColor Yellow
            Add-Content -Path $LOG_FILE -Value $errorMessage
            $iterationFailed = $true
        }
    }
    catch {
        $iterationFailed = $true
        $errorMessage = "Warning: Iteration $i failed with error: $_"
        Write-Host $errorMessage -ForegroundColor Yellow
        Add-Content -Path $LOG_FILE -Value $errorMessage
        $output = ""
        Stop-ClaudeProcess
    }
    finally {
        $script:ClaudeProcess = $null
        if (Test-Path $tempOutput) {
            Remove-Item $tempOutput -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path "$tempOutput.err") {
            Remove-Item "$tempOutput.err" -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $tempPrompt) {
            Remove-Item $tempPrompt -Force -ErrorAction SilentlyContinue
        }
    }

    # Append to log file
    Add-Content -Path $LOG_FILE -Value $output

    # Track consecutive failures
    if ($iterationFailed) {
        $consecutiveFailures++
        if ($consecutiveFailures -ge $MAX_CONSECUTIVE_FAILURES) {
            $abortMessage = "Aborting: $MAX_CONSECUTIVE_FAILURES consecutive failures. Check logs for details."
            Write-Host $abortMessage -ForegroundColor Red
            Add-Content -Path $LOG_FILE -Value $abortMessage
            exit 1
        }
        $retryMessage = "Continuing to next iteration... ($consecutiveFailures/$MAX_CONSECUTIVE_FAILURES consecutive failures)"
        Write-Host $retryMessage -ForegroundColor Yellow
        Add-Content -Path $LOG_FILE -Value $retryMessage
        # Brief pause before retry to avoid hammering on transient errors
        Start-Sleep -Seconds 2
        continue
    }

    # Reset consecutive failure counter on success
    $consecutiveFailures = 0

    if ($output -match "<promise>COMPLETE</promise>") {
        Write-Host ""
        Add-Content -Path $LOG_FILE -Value ""
        $completeMessage = "All issues complete after $i iterations."
        Write-Host $completeMessage
        Add-Content -Path $LOG_FILE -Value $completeMessage
        exit 0
    }
}

Write-Host ""
Add-Content -Path $LOG_FILE -Value ""
$doneMessage = "Completed $Iterations iterations."
Write-Host $doneMessage
Add-Content -Path $LOG_FILE -Value $doneMessage
$remainingMessage = "Run 'bd ready' to check remaining work."
Write-Host $remainingMessage
Add-Content -Path $LOG_FILE -Value $remainingMessage
