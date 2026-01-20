# Ralph Clean - kills orphaned Claude processes
# Usage: ralph-clean.ps1

$processes = Get-Process -Name "claude" -ErrorAction SilentlyContinue

if (-not $processes) {
    Write-Host "No orphaned Claude processes found." -ForegroundColor Green
    exit 0
}

Write-Host "Found $($processes.Count) Claude process(es):" -ForegroundColor Yellow
$processes | ForEach-Object {
    Write-Host "  PID $($_.Id) - Started: $($_.StartTime) - CPU: $([math]::Round($_.CPU, 2))s"
}

Write-Host ""
$processes | ForEach-Object {
    Write-Host "Killing PID $($_.Id)..." -ForegroundColor Yellow
    Stop-Process $_ -Force
}

Write-Host "Done." -ForegroundColor Green
