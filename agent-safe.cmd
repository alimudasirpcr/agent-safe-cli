@echo off
REM agent-safe.cmd — Drop this in your project root. Finds a POSIX shell and runs the CLI.
REM Usage: agent-safe adopt   OR   agent-safe start "task"
setlocal

REM Find POSIX shell: prefer WSL, then Git Bash, then MSYS2, then Cygwin
set "BASH="

REM Check WSL first (best compatibility on Windows)
where wsl.exe >nul 2>&1
if %errorlevel%==0 (
    REM Verify WSL has a working distribution
    wsl.exe -e true >nul 2>&1
    if %errorlevel%==0 (
        REM Find agent-safe.sh
        set "SH_SCRIPT="
        if exist "%~dp0.agent-safe-cli\agent-safe.sh" (
            set "SH_SCRIPT=%~dp0.agent-safe-cli\agent-safe.sh"
        ) else if exist "%~dp0agent-safe.sh" (
            set "SH_SCRIPT=%~dp0agent-safe.sh"
        )
        if defined SH_SCRIPT (
            REM Convert Windows path to WSL path
            for /f "usebackq delims=" %%p in (`wsl.exe -e wslpath "%SH_SCRIPT%"`) do set "SH_WSL=%%p"
            wsl.exe -e bash "%SH_WSL%" %*
            endlocal
            exit /b %errorlevel%
        )
    )
)

REM Fall back to Git Bash
if exist "C:\Program Files\Git\bin\bash.exe" (
    set "BASH=C:\Program Files\Git\bin\bash.exe"
) else if exist "C:\Program Files (x86)\Git\bin\bash.exe" (
    set "BASH=C:\Program Files (x86)\Git\bin\bash.exe"
) else if defined GIT_INSTALL_ROOT (
    set "BASH=%GIT_INSTALL_ROOT%\bin\bash.exe"
)

REM Check MSYS2
if not defined BASH (
    if exist "C:\msys64\usr\bin\bash.exe" (
        set "BASH=C:\msys64\usr\bin\bash.exe"
    )
)

REM Check Cygwin
if not defined BASH (
    if exist "C:\cygwin64\bin\bash.exe" (
        set "BASH=C:\cygwin64\bin\bash.exe"
    ) else if exist "C:\cygwin\bin\bash.exe" (
        set "BASH=C:\cygwin\bin\bash.exe"
    )
)

if not defined BASH (
    echo ERROR: No POSIX shell found. Install one of:
    echo   - Git for Windows: https://git-scm.com
    echo   - WSL: https://learn.microsoft.com/en-us/windows/wsl/install
    echo   - MSYS2: https://www.msys2.org
    echo   - Cygwin: https://www.cygwin.com
    exit /b 1
)

REM Find agent-safe.sh — check .agent-safe-cli/ in current dir, then PATH
set "SH_SCRIPT="
if exist "%~dp0.agent-safe-cli\agent-safe.sh" (
    set "SH_SCRIPT=%~dp0.agent-safe-cli\agent-safe.sh"
) else if exist "%~dp0agent-safe.sh" (
    set "SH_SCRIPT=%~dp0agent-safe.sh"
) else (
    echo ERROR: agent-safe.sh not found. Clone the CLI first:
    echo   git clone https://github.com/alimudasirpcr/agent-safe-cli.git .agent-safe-cli
    exit /b 1
)

REM Convert Windows path to Unix path for bash
set "SH_UNIX=%SH_SCRIPT:\=/%"
set "SH_UNIX=%SH_UNIX:C:=/c%"
set "SH_UNIX=%SH_UNIX:D:=/d%"
set "SH_UNIX=%SH_UNIX:E:=/e%"

"%BASH%" "%SH_UNIX%" %*

endlocal