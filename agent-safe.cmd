@echo off
REM agent-safe.cmd — Windows wrapper that finds Git Bash and runs agent-safe.sh
REM Works from both PowerShell and CMD. Put this on PATH alongside agent-safe.sh.

setlocal

REM Find Git Bash
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

REM Find the directory where this .cmd file lives
set "SCRIPT_DIR=%~dp0"

REM Run agent-safe.sh with all arguments passed through
"%BASH%" "%SCRIPT_DIR%agent-safe.sh" %*

endlocal