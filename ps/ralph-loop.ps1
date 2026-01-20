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

    # Run claude and capture output while monitoring for hanging errors
    # Claude CLI can throw unhandled promise rejections that hang the process
    $output = ""
    $iterationFailed = $false
    $tempFile = [System.IO.Path]::GetTempFileName()

    try {
        # Start claude as a background process so we can monitor and kill if needed
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = "claude"
        $pinfo.Arguments = "--dangerously-skip-permissions -p `"$($prompt -replace '"', '\"')`""
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $pinfo

        # Collect output asynchronously
        $outputBuilder = New-Object System.Text.StringBuilder
        $errorBuilder = New-Object System.Text.StringBuilder

        $outputEvent = Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -Action {
            if ($EventArgs.Data) {
                $Event.MessageData.AppendLine($EventArgs.Data)
                Write-Host $EventArgs.Data
            }
        } -MessageData $outputBuilder

        $errorEvent = Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action {
            if ($EventArgs.Data) {
                $Event.MessageData.AppendLine($EventArgs.Data)
                Write-Host $EventArgs.Data -ForegroundColor Red
            }
        } -MessageData $errorBuilder

        $process.Start() | Out-Null
        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()

        # Monitor for hanging error patterns
        while (-not $process.HasExited) {
            Start-Sleep -Milliseconds 500
            $currentOutput = $outputBuilder.ToString() + $errorBuilder.ToString()

            # Check for the specific hanging error
            if ($currentOutput -match "Error: No messages returned" -or
                ($currentOutput -match "promise rejected with the reason" -and $currentOutput -match "Error:")) {
                $hangMessage = "Detected hanging error. Killing Claude process..."
                Write-Host $hangMessage -ForegroundColor Yellow
                Add-Content -Path $LOG_FILE -Value $hangMessage
                $process.Kill()
                $iterationFailed = $true
                break
            }
        }

        # Wait for process to fully exit and clean up events
        $process.WaitForExit()
        Unregister-Event -SourceIdentifier $outputEvent.Name
        Unregister-Event -SourceIdentifier $errorEvent.Name

        $output = $outputBuilder.ToString() + $errorBuilder.ToString()
        $exitCode = $process.ExitCode

        if ($exitCode -ne 0 -and -not $iterationFailed) {
            $iterationFailed = $true
            $errorMessage = "Warning: Claude exited with code $exitCode"
            Write-Host $errorMessage -ForegroundColor Yellow
            Add-Content -Path $LOG_FILE -Value $errorMessage
        }
    }
    catch {
        $iterationFailed = $true
        $errorMessage = "Warning: Iteration $i failed with error: $_"
        Write-Host $errorMessage -ForegroundColor Yellow
        Add-Content -Path $LOG_FILE -Value $errorMessage
    }
    finally {
        if ($process -and -not $process.HasExited) {
            $process.Kill()
        }
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force
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
