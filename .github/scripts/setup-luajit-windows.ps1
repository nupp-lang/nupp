$ErrorActionPreference = "Stop"

# Keep the VM and its one test dependency identical to the POSIX jobs. LuaJIT
# publishes rolling source releases, not official Windows binaries.
$luajitCommit = "1edc3e52b67eaf6ce5f809be8e17d6862594b8bc"
$cjsonCommit = "5ce46a80b10ef9d380a45c9e6cff9ecffbe71ebb"
$luarocksCommit = "3421bedc2ce2b64e79530bb97497531b014899a8"
# The compiler parses its own doc comments with `nupp.peg`, which resolves
# native LPeg, so the module has to exist before the first build rather than
# arriving later with what `nupp doc` renders with.
$lpegVersion = "1.1.0-2"
$toolRoot = Join-Path $env:RUNNER_TEMP "nupp-ci-tools"
$luajitRoot = Join-Path $toolRoot "luajit"
$cjsonRoot = Join-Path $toolRoot "lua-cjson"
$cjsonBuild = Join-Path $toolRoot "cjson-build"
$luarocksRoot = Join-Path $toolRoot "luarocks"
$luarocksInstall = Join-Path $toolRoot "luarocks-install"

git clone --filter=blob:none https://github.com/LuaJIT/LuaJIT.git $luajitRoot
git -C $luajitRoot checkout --detach $luajitCommit

$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
$visualStudio = & $vswhere -latest -products * -property installationPath
if (-not $visualStudio) {
    throw "Visual Studio is unavailable"
}
$developerShell = Join-Path $visualStudio "Common7\Tools\VsDevCmd.bat"
$buildLuaJit = Join-Path $toolRoot "build-luajit.cmd"
@"
@call "$developerShell" -arch=x64 -host_arch=x64
@if errorlevel 1 exit /b %errorlevel%
@cd /d "$luajitRoot\src"
@call msvcbuild.bat
"@ | Set-Content -Encoding ascii $buildLuaJit
& cmd.exe /d /c $buildLuaJit
if ($LASTEXITCODE -ne 0) {
    throw "LuaJIT failed to build"
}
# LuaJIT's MSVC build names its import library `lua51.lib`; LuaRocks derives
# `luajit.lib` from the interpreter filename. The copied import library still
# records `lua51.dll` internally and only gives LuaRocks the name it probes.
Copy-Item (Join-Path $luajitRoot "src\lua51.lib") (Join-Path $luajitRoot "src\luajit.lib")

git clone --filter=blob:none https://github.com/openresty/lua-cjson.git $cjsonRoot
git -C $cjsonRoot checkout --detach $cjsonCommit
# lua-cjson still aliases snprintf for the pre-UCRT MSVC runtime. Current
# runners provide the standard function, where the alias is a hard error.
$cjsonCMake = Join-Path $cjsonRoot "CMakeLists.txt"
(Get-Content $cjsonCMake) |
    Where-Object { $_ -ne "    add_definitions(-Dsnprintf=_snprintf)" } |
    Set-Content -Encoding utf8 $cjsonCMake
cmake -S $cjsonRoot -B $cjsonBuild -A x64 `
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5" `
    "-DLUA_INCLUDE_DIR:PATH=$luajitRoot\src" `
    "-DLUA_LIBRARY:FILEPATH=$luajitRoot\src\lua51.lib"
cmake --build $cjsonBuild --config Release --parallel 2

$moduleRoot = Join-Path $env:GITHUB_WORKSPACE ".rocks\lib\lua\5.1"
New-Item -ItemType Directory -Force $moduleRoot | Out-Null
Copy-Item (Join-Path $cjsonBuild "Release\cjson.dll") (Join-Path $moduleRoot "cjson.dll")

git clone --filter=blob:none https://github.com/luarocks/luarocks.git $luarocksRoot
git -C $luarocksRoot checkout --detach $luarocksCommit
$installLuaRocks = Join-Path $toolRoot "install-luarocks.cmd"
@"
@call "$developerShell" -arch=x64 -host_arch=x64
@if errorlevel 1 exit /b %errorlevel%
@cd /d "$luarocksRoot"
@call install.bat /P "$luarocksInstall" /TREE "$env:GITHUB_WORKSPACE\.rocks" /CONFIG "$luarocksInstall" /LV 5.1 /INC "$luajitRoot\src" /LIB "$luajitRoot\src" /BIN "$luajitRoot\src" /Q /F /NOREG /NOADMIN /FORCECONFIG
"@ | Set-Content -Encoding ascii $installLuaRocks
& cmd.exe /d /c $installLuaRocks
if ($LASTEXITCODE -ne 0) {
    throw "LuaRocks failed to install"
}

# LuaRocks compiles LPeg from source, so this one runs in the developer shell
# too rather than in the PowerShell the workflow starts.
$installLpeg = Join-Path $toolRoot "install-lpeg.cmd"
@"
@call "$developerShell" -arch=x64 -host_arch=x64
@if errorlevel 1 exit /b %errorlevel%
@call "$luarocksInstall\luarocks.bat" install lpeg $lpegVersion
"@ | Set-Content -Encoding ascii $installLpeg
& cmd.exe /d /c $installLpeg
if ($LASTEXITCODE -ne 0) {
    throw "LPeg failed to install"
}

$luaJitBin = Join-Path $luajitRoot "src"
$gitBash = (Get-Command bash.exe).Source
$gitSh = Join-Path (Split-Path $gitBash) "sh.exe"
$luaPath = ($luajitRoot -replace "\\", "/") + "/src/?.lua;;"
$luaCPath = ($moduleRoot -replace "\\", "/") + "/?.dll;;"
$luaJitBin | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append
$luarocksInstall | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append
"LUA_PATH=$luaPath" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
"LUA_CPATH=$luaCPath" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
"NUPP_LUAROCKS=$luarocksInstall\luarocks.bat" |
    Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
"NUPP_CI_BASH=$gitBash" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
"NUPP_CI_SH=$gitSh" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append

$env:LUA_PATH = $luaPath
$env:LUA_CPATH = $luaCPath
& (Join-Path $luaJitBin "luajit.exe") -e 'require("cjson"); require("lpeg"); assert((nil ?? 1) == 1)'
if ($LASTEXITCODE -ne 0) {
    throw "the CI LuaJIT toolchain cannot load lua-cjson, LPeg or Nupp syntax"
}
& (Join-Path $luarocksInstall "luarocks.bat") --version
if ($LASTEXITCODE -ne 0) {
    throw "the CI LuaRocks installation cannot run"
}
