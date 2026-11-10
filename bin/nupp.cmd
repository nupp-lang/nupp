@echo off
rem Starts this checkout's `nupp` launcher from cmd.exe and CreateProcess.
rem
rem `bin\nupp` is a POSIX shell script, and Windows can start neither it nor
rem any file without an executable extension. This runs it under Git Bash, the
rem shell the toolchain is provisioned with, so `nupp` on PATH resolves here
rem for a project task's argv and for a program that spawns a checkout's
rem launcher by path.
rem
rem NUPP_BASH names the bash.exe to use. Otherwise the one beside the Git on
rem PATH is used. A bare `bash` is never searched for: on Windows that is the
rem WSL launcher, which would run the script inside Linux.
setlocal
set "NUPP_CMD_BASH=%NUPP_BASH%"
if defined NUPP_CMD_BASH goto run
for /f "delims=" %%G in ('where git.exe 2^>nul') do (
    if exist "%%~dpG..\bin\bash.exe" (
        set "NUPP_CMD_BASH=%%~dpG..\bin\bash.exe"
        goto run
    )
)
echo nupp: no Git Bash found; install Git for Windows or set NUPP_BASH to its bash.exe 1>&2
exit /b 1

:run
"%NUPP_CMD_BASH%" "%~dp0nupp" %*
exit /b %ERRORLEVEL%
