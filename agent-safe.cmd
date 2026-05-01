@echo off
REM agent-safe.cmd — Drop this in your project root. Finds Git Bash and runs the CLI.
REM Usage: agent-safe adopt   OR   agent-safe start "task"
setlocal

REM Find Git Bash
set "BASH="
if exist "C:\Program Files\Git\bin\bash.exe" (
    set "BASH=C:\Program Files\Git\bin\bash.exe"
) else if exist "C:\Program Files (x86)\Git\bin\bash.exe" (
    set "BASH=C:\Program Files (x86)\Git\bin\bash.exe"
) else if defined GIT_INSTALL_ROOT (
    set "BASH=%GIT_INSTALL_ROOT%\bin\bash.exe"
) else (
    echo ERROR: Git Bash not found. Install Git for Windows: https://git-scm.com
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