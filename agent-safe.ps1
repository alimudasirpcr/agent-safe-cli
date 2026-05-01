# agent-safe.ps1 — Drop this in your project root. Finds Git Bash and runs the CLI.
# Usage: agent-safe adopt   OR   agent-safe start "task"

$gitBash = $null
if (Test-Path "C:\Program Files\Git\bin\bash.exe") {
    $gitBash = "C:\Program Files\Git\bin\bash.exe"
} elseif (Test-Path "C:\Program Files (x86)\Git\bin\bash.exe") {
    $gitBash = "C:\Program Files (x86)\Git\bin\bash.exe"
} elseif ($env:GIT_INSTALL_ROOT) {
    $gitBash = Join-Path $env:GIT_INSTALL_ROOT "bin\bash.exe"
} elseif (Get-Command bash -ErrorAction SilentlyContinue) {
    $found = (Get-Command bash).Source
    if ($found -notmatch "WindowsApps") { $gitBash = $found }
}

if (-not $gitBash) {
    Write-Host "ERROR: Git Bash not found. Install Git for Windows: https://git-scm.com" -ForegroundColor Red
    exit 1
}

$shScript = $null
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (Test-Path (Join-Path $scriptDir ".agent-safe-cli\agent-safe.sh")) {
    $shScript = Join-Path $scriptDir ".agent-safe-cli\agent-safe.sh"
} elseif (Test-Path (Join-Path $scriptDir "agent-safe.sh")) {
    $shScript = Join-Path $scriptDir "agent-safe.sh"
}

if (-not $shScript) {
    Write-Host "ERROR: agent-safe.sh not found. Clone the CLI first:" -ForegroundColor Red
    Write-Host '  git clone https://github.com/alimudasirpcr/agent-safe-cli.git .agent-safe-cli' -ForegroundColor Yellow
    exit 1
}

$shUnix = $shScript -replace '\', '/' -replace '^([A-Z]):', '/$1'
& $gitBash $shUnix @args