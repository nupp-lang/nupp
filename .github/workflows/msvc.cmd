@echo off
rem Enters the 64-bit MSVC environment without naming an edition or a year,
rem which is what breaks when a runner image moves to the next one.
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo msvc.cmd: vswhere.exe is not installed 1>&2
    exit /b 1
)
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * ^
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 ^
    -property installationPath`) do set "VSPATH=%%i"
if "%VSPATH%"=="" (
    echo msvc.cmd: no Visual Studio with the C++ tools was found 1>&2
    exit /b 1
)
call "%VSPATH%\VC\Auxiliary\Build\vcvars64.bat"
