$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$pythonPath = Join-Path $projectRoot ".venv\Scripts\python.exe"
$backendPath = Join-Path $projectRoot "backend"
$frontendPath = Join-Path $projectRoot "frontend"

if (-not (Test-Path -LiteralPath $pythonPath)) {
    throw "Python environment is missing. Follow the setup steps in README.md first."
}

$backendProcess = Start-Process -FilePath $pythonPath -ArgumentList @(
    "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "8000", "--reload"
) -WorkingDirectory $backendPath -WindowStyle Hidden -PassThru

$frontendProcess = Start-Process -FilePath "npm.cmd" -ArgumentList @(
    "run", "dev"
) -WorkingDirectory $frontendPath -WindowStyle Hidden -PassThru

@{
    backendPid = $backendProcess.Id
    frontendPid = $frontendProcess.Id
    startedAt = (Get-Date).ToString("o")
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $projectRoot ".run-pids.json")

Write-Host "InnerWave is starting..."
Write-Host "App:     http://localhost:3000"
Write-Host "API docs: http://localhost:8000/docs"
