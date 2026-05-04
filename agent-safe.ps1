# agent-safe.ps1 — Drop this in your project root. Finds a POSIX shell and runs the CLI.
# Usage: agent-safe adopt   OR   agent-safe start "task"

$gitBash = $null
$useWsl = $false

# Check WSL first (best compatibility on Windows)
if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
    try {
        $null = & wsl.exe -e true 2>&1
        if ($LASTEXITCODE -eq 0) {
            $useWsl = $true
        }
    } catch {
        # WSL exists but no distribution installed
    }
}

$shScript = $null
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (Test-Path (Join-Path $scriptDir ".agent-safe-cli\agent-safe.sh")) {
    $shScript = Join-Path $scriptDir ".agent-safe-cli\agent-safe.sh"
} elseif (Test-Path (Join-Path $scriptDir "agent-safe.sh")) {
    $shScript = Join-Path $scriptDir "agent-safe.sh"
}

if ($useWsl -and $shScript) {
    # Convert Windows path to WSL path
    $wslPath = & wsl.exe -e wslpath "$shScript" 2>$null
    if ($wslPath) {
        & wsl.exe -e bash $wslPath @args
        exit $LASTEXITCODE
    }
}

# Fall back to Git Bash
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

# Check MSYS2
if (-not $gitBash -and (Test-Path "C:\msys64\usr\bin\bash.exe")) {
    $gitBash = "C:\msys64\usr\bin\bash.exe"
}

# Check Cygwin
if (-not $gitBash) {
    if (Test-Path "C:\cygwin64\bin\bash.exe") {
        $gitBash = "C:\cygwin64\bin\bash.exe"
    } elseif (Test-Path "C:\cygwin\bin\bash.exe") {
        $gitBash = "C:\cygwin\bin\bash.exe"
    }
}

if (-not $gitBash) {
    Write-Host "ERROR: No POSIX shell found. Install one of:" -ForegroundColor Red
    Write-Host "  - Git for Windows: https://git-scm.com" -ForegroundColor Yellow
    Write-Host "  - WSL: https://learn.microsoft.com/en-us/windows/wsl/install" -ForegroundColor Yellow
    Write-Host "  - MSYS2: https://www.msys2.org" -ForegroundColor Yellow
    Write-Host "  - Cygwin: https://www.cygwin.com" -ForegroundColor Yellow
    exit 1
}

if (-not $shScript) {
    Write-Host "ERROR: agent-safe.sh not found. Clone the CLI first:" -ForegroundColor Red
    Write-Host '  git clone https://github.com/alimudasirpcr/agent-safe-cli.git .agent-safe-cli' -ForegroundColor Yellow
    exit 1
}

$shUnix = $shScript -replace '\\', '/' -replace '^([A-Z]):', '/$1'
& $gitBash $shUnix @args