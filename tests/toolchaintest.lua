-- `scripts/toolchain` is what a clean machine runs before anything else works,
-- so what is checked here is the part that has to be right before a compiler is
-- ever invoked: that the pins say what the host build says, that a digest which
-- does not match stops the build, and that the cache is keyed by the toolchain
-- rather than shared across compilers.
--
-- Nothing here compiles anything. Building LuaJIT takes half a minute and proves
-- something the whole suite proves by running at all.

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local pipe = assert(io.popen("pwd"))
    HERE = pipe:read("*l") .. "/" .. HERE
    pipe:close()
end
local ROOT = HERE .. "/.."
local DRIVER = ROOT .. "/scripts/toolchain"

local M = {}

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function read(path)
    local file = assert(io.open(path, "rb"), path .. " is missing")
    local text = file:read("*a")
    file:close()
    return text
end

local function write(path, text)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

--- A directory as it can be spelled inside a colon-separated PATH.
---
--- A native Windows path cannot go in one: the shell splits `C:/x` into `C` and
--- `/x`, so the directory is never searched and whatever it was meant to shadow
--- wins instead. Which is what this suite is about, and what it was quietly
--- doing to itself -- the fake `cygpath` went unfound and the real one answered.
---
--- Rewritten here rather than asked of `cygpath`, in either process. Two
--- attempts went through one: this process is native on Windows and resolves a
--- different `cygpath` than the shell, and a command substitution in the shell
--- silently produced nothing, which emptied the entry and let the real
--- `cygpath` answer for the fake -- the failure both attempts were meant to fix,
--- reported identically each time.
---
--- A drive path has one spelling in a mount table that Git Bash gives `/c` for,
--- and these are temporary directories under it. Doing it by hand needs nothing
--- to be installed and answers the same on a machine with no `cygpath` at all.
local function forPath(directory)
    if package.config:sub(1, 1) ~= "\\" then
        return directory
    end
    local drive, rest = directory:match("^([A-Za-z]):(/.*)$")
    if drive == nil then
        return directory
    end

    return "/" .. drive:lower() .. rest
end

local function temporary()
    local path = os.tmpname()
    os.remove(path)
    assert(os.execute("mkdir -p " .. quote(path)) == 0)
    return path
end

--- Runs the driver with an environment, returning its exit status and output.
-- `PATH` is written for the shell to expand rather than quoted flat, so a value
-- can say `$PATH` and mean the one the shell already has. Lua's idea of it is
-- not usable here: on Windows this process is native, so `os.getenv("PATH")`
-- answers the semicolon-separated Windows spelling, and joining that with `:`
-- for a Git Bash command produced entries like `C` and `\Windows;C`. The shell
-- then had no `/usr/bin`, and the driver died on `dirname` before doing
-- anything this suite meant to test.
local function run(environment, arguments)
    local prefix = {}
    for name, value in pairs(environment) do
        if name == "PATH" then
            prefix[#prefix + 1] = name .. '="' .. value .. '"'
        else
            prefix[#prefix + 1] = name .. "=" .. quote(value)
        end
    end
    table.sort(prefix)
    local command = (
        "env %s %s %s 2>&1; echo \"__exit__:$?\""
    ):format(table.concat(prefix, " "), quote(DRIVER), arguments)
    local pipe = assert(io.popen(command))
    local output = pipe:read("*a")
    pipe:close()
    local status = tonumber(output:match("__exit__:(%d+)%s*$"))

    return status, (output:gsub("__exit__:%d+%s*$", ""))
end

local function pins()
    local text = read(ROOT .. "/scripts/toolchain.pins")
    local values = {}
    for name, value in text:gmatch("\n([A-Z0-9_]+)=([^\n]*)") do
        values[name] = (value:gsub("^'", ""):gsub("'$", ""))
    end

    return values
end

--- A compiler that answers `--version` and nothing else, for the cache key.
local function fakeCompiler(directory, name, version)
    local path = directory .. "/" .. name
    write(path, "#!/bin/sh\nprintf '%s\\n' " .. quote(version) .. "\n")
    assert(os.execute("chmod +x " .. quote(path)) == 0)
    return path
end

local function fakeWindowsUname(directory)
    local path = directory .. "/uname"
    write(path, [[#!/bin/sh
if [ "$1" = "-m" ]; then
   printf '%s\n' x86_64
else
   printf '%s\n' MINGW64_NT
fi
]])
    assert(os.execute("chmod +x " .. quote(path)) == 0)
end

local function fakeCygpath(directory)
    local path = directory .. "/cygpath"
    write(
        path,
        [[#!/bin/sh
case "$1" in
   -m) printf 'C:%s\n' "$2" ;;
   -u) printf '%s\n' "$NUPP_TEST_CYGPATH_U" ;;
   *) exit 2 ;;
esac
]]
    )
    assert(os.execute("chmod +x " .. quote(path)) == 0)
end

-- Every pinned source has a version and a digest, and the digest is what the
-- driver refuses a mismatch against. A pin with one and not the other would be
-- fetched and compiled without anything checking what arrived.
function M.everyPinHasAVersionAndADigest()
    local recorded = pins()
    for _, component in ipairs({"LUAJIT", "LUAROCKS", "LPEG",}) do
        local marker = component == "LUAJIT" and "REV" or "VERSION"
        assert(recorded[component .. "_" .. marker], component .. " has no version or revision")
        local digest = recorded[component .. "_SHA256"]
        assert(digest and #digest == 64, component .. " has no SHA-256, or one that is not 64 characters")
        assert(digest:match("^%x+$"), component .. "'s digest is not hexadecimal")
    end
end

-- Each of these is redistributed under a licence that asks its notice to travel
-- along, and the driver refuses to build a source whose notice has drifted. A
-- pin for which no notice exists would make that check unreachable.
function M.everyPinnedSourceHasANotice()
    for _, notice in ipairs({"LuaJIT-COPYRIGHT.txt", "LPeg-LICENSE.txt",}) do
        assert(io.open(ROOT .. "/host/notices/" .. notice, "rb"), "host/notices/" .. notice .. " is missing")
    end
end

-- GPU conformance uses the distribution-provided Lavapipe ICD. Keeping a
-- source-built software adapter here would make WGPU's test dependency the
-- largest remaining C++ build in the ordinary Nupp toolchain.
function M.softwareVulkanIsProvidedByCi()
    local driver = read(ROOT .. "/scripts/toolchain")
    local pinsFile = read(ROOT .. "/scripts/toolchain.pins")
    local workflow = read(ROOT .. "/.github/workflows/compiler.yml")
    local conformance = read(ROOT .. "/.github/scripts/test-gpu-conformance.sh")
    assert(not driver:find("swiftshader", 1, true), "the toolchain still source-builds SwiftShader")
    assert(not pinsFile:find("SWIFTSHADER", 1, true), "the removed SwiftShader source pin remains")
    assert(
        workflow:find("mesa-vulkan-drivers", 1, true),
        "GPU CI does not install a maintained software Vulkan adapter"
    )
    assert(conformance:find("NUPP_GPU_ICD", 1, true), "GPU conformance does not require CI to name its ICD")
end

-- A mirror that served something else is refused rather than compiled, and the
-- message says both digests so the reader can tell a stale pin from a bad
-- download.
function M.aWrongDigestRefusesToBuild()
    local directory = temporary()
    local archives = directory .. "/archives"
    assert(os.execute("mkdir -p " .. quote(archives)) == 0)
    local revision = pins().LUAJIT_REV
    write(archives .. "/LuaJIT-" .. revision .. ".tar.gz", "not an archive")

    local status, output = run(
        {NUPP_TOOLCHAIN_DIR = directory .. "/cache", NUPP_HOST_SOURCE_DIR = archives, PATH = "$PATH",},
        "luajit"
    )

    assert(status ~= 0, "a mismatched digest built anyway:\n" .. output)
    assert(
        output:find("expected " .. pins().LUAJIT_SHA256, 1, true),
        "the refusal does not say what was expected:\n" .. output
    )
end

-- Offline says which directory to put the archive in, because a builder with no
-- network has no way to discover that from a failed download.
function M.offlineNamesTheDirectoryToSupply()
    local directory = temporary()
    local status, output = run(
        {
            NUPP_TOOLCHAIN_DIR = directory .. "/cache",
            NUPP_HOST_SOURCE_DIR = directory .. "/empty",
            NUPP_HOST_OFFLINE = "1",
            PATH = "$PATH",
        },
        "luajit"
    )

    assert(status ~= 0, "an offline build with no archive succeeded:\n" .. output)
    assert(
        output:find("NUPP_HOST_SOURCE_DIR", 1, true),
        "the refusal does not say where to put the archive:\n" .. output
    )
end

-- Two compilers are two answers. A cache that ignored which one asked would hand
-- a GCC build back to a Clang one, and the failure would be a link error a long
-- way from the cause.
function M.thePrefixFollowsTheToolchain()
    local directory = temporary()
    local first = fakeCompiler(directory, "first-cc", "one")
    local second = fakeCompiler(directory, "second-cc", "two")
    local environment = {NUPP_TOOLCHAIN_DIR = directory .. "/cache", PATH = "$PATH",}

    environment.NUPP_CC = first
    environment.NUPP_CXX = first
    local status, one = run(environment, "--prefix")
    assert(status == 0, one)

    environment.NUPP_CC = second
    environment.NUPP_CXX = second
    local againStatus, two = run(environment, "--prefix")
    assert(againStatus == 0, two)

    assert(one ~= two, "two compilers shared one prefix: " .. one)
    assert(
        one:find(directory, 1, true) and two:find(directory, 1, true),
        "the prefix ignored NUPP_TOOLCHAIN_DIR: " .. one .. " and " .. two
    )

    environment.NUPP_CC = first
    environment.NUPP_CXX = first
    local repeatStatus, again = run(environment, "--prefix")
    assert(repeatStatus == 0, again)
    assert(again == one, "the same toolchain answered two prefixes")
end

function M.legacyNativeProviderComponentIsAbsent()
    local directory = temporary()
    local compiler = fakeCompiler(directory, "fake-cc", "fake")
    local status, output = run(
        {NUPP_TOOLCHAIN_DIR = directory .. "/cache", NUPP_CC = compiler, NUPP_CXX = compiler, PATH = "$PATH",},
        "native files"
    )

    assert(status ~= 0, "the removed native provider returned success:\n" .. output)
    assert(
        output:find("unknown component native", 1, true),
        "the refusal does not name the removed component:\n" .. output
    )
    local driver = read(ROOT .. "/scripts/toolchain")
    assert(not driver:find("build_native_library", 1, true), "the legacy provider builder remains in the toolchain")
    assert(
        not driver:find("provider_sources", 1, true),
        "the legacy provider feature registry remains in the toolchain"
    )
end

-- Resolve tools from the exact channel before considering ambient proxies.
-- A moving `stable` alias is not a fallback: even when it happens to report
-- the same version today, it is not a reproducible toolchain identity.
function M.rustupSelectsOnlyThePinnedToolchain()
    local driver = read(ROOT .. "/scripts/toolchain")
    assert(
        driver:find("rustup_toolchain=$expected", 1, true),
        "rustup does not select rust-toolchain.toml's exact channel"
    )
    assert(
        driver:find('RUSTUP_TOOLCHAIN="$rustup_toolchain"', 1, true),
        "rustup does not resolve tools from the selected exact channel"
    )
    assert(not driver:find("RUSTUP_TOOLCHAIN=stable", 1, true), "the moving stable alias remains a toolchain fallback")
end

-- Cargo gives a macOS cdylib an absolute install name beneath target-dir by
-- default. The Rust provider's target directory is a content cache; recording
-- it would make a linked consumer reach back into that cache after the dylib
-- had been staged or packaged elsewhere.
function M.macOSRustProviderUsesARelocatableInstallName()
    local driver = read(ROOT .. "/scripts/toolchain")
    assert(
        driver:find("[ \"$PLATFORM\" = darwin ] && cargo_action=rustc", 1, true),
        "the macOS Rust provider is not built through cargo rustc"
    )
    assert(
        driver:find("-install_name,@rpath/$filename", 1, true),
        "the macOS Rust provider records its content-cache path"
    )
end

-- The dependency builds use GNU make. Windows' hosted clang targets MSVC, so
-- LuaJIT's makefile asks it to link Unix spellings such as `-lm` as MSVC
-- libraries and the cold bootstrap stops. MinGW GCC is the compatible default;
-- explicitly naming clang still remains the caller's choice.
function M.windowsDefaultsToTheGnuCompilerPair()
    local directory = temporary()
    fakeWindowsUname(directory)
    fakeCygpath(directory)
    fakeCompiler(directory, "gcc", "gnu-c")
    fakeCompiler(directory, "g++", "gnu-cxx")
    fakeCompiler(directory, "clang", "msvc-c")
    fakeCompiler(directory, "clang++", "msvc-cxx")
    local environment = {NUPP_TOOLCHAIN_DIR = directory .. "/cache", PATH = forPath(directory) .. ":$PATH",}

    local status, automatic = run(environment, "--prefix")
    assert(status == 0, automatic)

    environment.NUPP_CC = "gcc"
    environment.NUPP_CXX = "g++"
    local gnuStatus, gnu = run(environment, "--prefix")
    assert(gnuStatus == 0, gnu)
    assert(automatic == gnu, "Windows did not select the MinGW compiler pair")

    environment.NUPP_CC = "clang"
    environment.NUPP_CXX = "clang++"
    local clangStatus, msvc = run(environment, "--prefix")
    assert(clangStatus == 0, msvc)
    assert(automatic ~= msvc, "Windows selected the MSVC-targeting clang pair")
end

-- Cargo owns the ordinary Rust executable's platform closure. The two static
-- relink routes still invoke a C linker and must spell that closure explicitly.
function M.windowsHostLinkersCarryPthread()
    local driver = read(ROOT .. "/scripts/toolchain")
    local packLinker = read(ROOT .. "/scripts/compiler-pack-link.c")
    assert(
        driver:match('windows%)%s+set %-%- "?%$@"? %-lpthread '),
        "the Windows application host linker does not link pthread"
    )
    assert(
        packLinker:match('#ifdef _WIN32%s+append%(&cursor, "%-lpthread"%);'),
        "the Windows compiler-pack host linker does not link pthread"
    )
end

-- Rustls reads the Windows root stores through CryptoAPI, and Rust std builds
-- child pipes with ntdll. Cargo records executable dependencies; both static
-- C-link routes record them themselves.
function M.windowsHostLinkersCarrySystemImports()
    local driver = read(ROOT .. "/scripts/toolchain")
    local packLinker = read(ROOT .. "/scripts/compiler-pack-link.c")
    assert(driver:find("-lcrypt32", 1, true), "the application host linker does not carry crypt32")
    assert(driver:find("-lntdll", 1, true), "the application host linker does not carry Rust std's ntdll dependency")
    assert(
        packLinker:match('append%(&cursor, "%-lcrypt32"%);'),
        "the Windows compiler-pack host linker does not link crypt32"
    )
    assert(
        packLinker:match('append%(&cursor, "%-lntdll"%);'),
        "the Windows compiler-pack host linker does not link Rust std's ntdll dependency"
    )
    assert(
        not driver:find("--allow-multiple-definition", 1, true),
        "the application host linker masks malformed archive composition"
    )
    assert(
        not packLinker:find("--allow-multiple-definition", 1, true),
        "the compiler-pack host linker masks malformed archive composition"
    )
end

-- Cargo derives both the DLL and its import-library descriptor from the Rust
-- library name. Staging the DLL under another basename leaves a successfully
-- linked consumer asking Windows for a file the SDK did not ship.
function M.windowsEmbeddingArtifactsShareTheCargoBasename()
    local driver = read(ROOT .. "/scripts/toolchain")
    local manifest = read(ROOT .. "/native/crates/host/Cargo.toml")
    assert(manifest:find('name = "nupp"', 1, true), "the host crate does not emit the public embedding basename")
    assert(driver:find("cargo_dynamic=nupp.dll", 1, true), "the staged Windows DLL does not keep Cargo's basename")
    assert(
        driver:find('RUST_EMBED_IMPORT_OUT="$out/target/release/libnupp.dll.a"', 1, true),
        "the staged Windows import library describes another DLL basename"
    )
    assert(
        not driver:find("nupp_native_host.dll", 1, true),
        "the Windows embedding SDK retains its private Cargo basename"
    )
end

-- The same static routes carry the macOS trust-store frameworks.
function M.macOSHostLinkersCarryTheSecurityFramework()
    local driver = read(ROOT .. "/scripts/toolchain")
    local packLinker = read(ROOT .. "/scripts/compiler-pack-link.c")
    local _, security = driver:gsub("%-framework Security", "")
    local _, foundation = driver:gsub("%-framework CoreFoundation", "")
    assert(security >= 1 and foundation >= 1, "not every macOS toolchain linker carries the trust-store frameworks")
    assert(
        packLinker:match('append%(&cursor, "Security"%);'),
        "the macOS compiler-pack host linker does not link Security.framework"
    )
    assert(
        packLinker:match('append%(&cursor, "CoreFoundation"%);'),
        "the macOS compiler-pack host linker does not link CoreFoundation"
    )
end

-- The Rust application archive now contains the exact-feature provider. Cargo
-- retains its named exports, and both static relink routes force-load that one
-- authoritative archive rather than assembling C objects and side archives.
function M.staticHostsForceLoadTheRustApplicationArchive()
    local driver = read(ROOT .. "/scripts/toolchain")
    local packer = read(ROOT .. "/scripts/compiler-pack")
    local packLinker = read(ROOT .. "/scripts/compiler-pack-link.c")
    assert(driver:find("-C link-dead-code", 1, true), "Cargo may discard exports reached only through LuaJIT FFI")
    assert(
        driver:find('stage_application_archive "$rust_application" "$out/libnupp-host.a"', 1, true),
        "the staged application host omits the sanitized Rust archive"
    )
    assert(
        driver:find("*.dlls[0-9]*.o", 1, true),
        "the Windows application archive retains Cargo-bundled import thunks"
    )
    assert(
        driver:find('-Wl,--whole-archive "$host_out/libnupp-host.a"', 1, true),
        "the ordinary static linker can discard the Rust application host"
    )
    assert(packer:find('cp "$host_dir/libnupp-host.a"', 1, true), "the compiler pack omits the Rust application host")
    assert(
        packLinker:find('host/lib/libnupp-host.a', 1, true),
        "the compiler-pack linker omits the Rust application host"
    )
    assert(
        packLinker:find('append(&cursor, "-Wl,--whole-archive")', 1, true),
        "the compiler-pack linker can discard the Rust application host"
    )
end

function M.networkAndTlsAreRustOnlyToolchainFeatures()
    local driver = read(ROOT .. "/scripts/toolchain")
    local packer = read(ROOT .. "/scripts/compiler-pack")
    local packLinker = read(ROOT .. "/scripts/compiler-pack-link.c")
    assert(
        driver:find('host_cargo_features="$host_cargo_features,native-net"', 1, true),
        "a network host does not select the Rust net crate"
    )
    assert(
        driver:find('host_cargo_features="$host_cargo_features,native-tls"', 1, true),
        "a TLS host does not select the Rust TLS crate"
    )
    for _, obsolete in ipairs({"libuv", "mbedtls"}) do
        assert(not driver:lower():find(obsolete, 1, true), "the toolchain still provisions " .. obsolete)
        assert(not packer:lower():find(obsolete, 1, true), "compiler packs still copy " .. obsolete)
        assert(not packLinker:lower():find(obsolete, 1, true), "compiler packs still link " .. obsolete)
    end
end

-- Release and compiler-pack jobs exercise a feature list outside the ordinary
-- toolchain driver. A removed host feature left there fails only after a clean
-- Linux or Windows release runner has provisioned the entire toolchain.
function M.releaseJobsRequestOnlyCurrentHostFeatures()
    for _, path in ipairs({
        ".github/scripts/build-compiler-pack-linux.sh",
        ".github/scripts/build-compiler-pack-windows.sh",
        ".github/workflows/release.yml",
    }) do
        local text = read(ROOT .. "/" .. path)
        assert(not text:find("lua-utf8", 1, true), path .. " still requests the removed lua-utf8 host feature")
    end
end

-- The large LLVM compiler-pack inputs are independently pinned, but release
-- builders must admit the same pre-fetched source directory as the rest of the
-- native toolchain when a release is reconstructed without a network.
function M.compilerPackBuildersAdmitPinnedOfflineSources()
    for _, path in ipairs({
        ".github/scripts/build-compiler-pack-linux.sh",
        ".github/scripts/build-compiler-pack-windows.sh",
    }) do
        local source = read(ROOT .. "/" .. path)
        assert(source:find("NUPP_HOST_SOURCE_DIR", 1, true), path .. " cannot read pre-fetched inputs")
        assert(source:find("NUPP_HOST_OFFLINE", 1, true), path .. " cannot forbid downloads")
        assert(
            source:find("offline compiler-pack build needs", 1, true),
            path .. " does not diagnose a missing offline input"
        )
    end
end

-- Clang accepts --ld-path only while linking. Generated AOT compilation uses
-- -Werror, so putting it among compile flags makes a valid installed pack fail
-- before its linker can run.
function M.linuxCompilerPackKeepsTheLinkerOutOfCompiles()
    local packer = read(ROOT .. "/scripts/compiler-pack")
    local compileFlags = assert(packer:match("compile_flags='(%[[^\n]+%])'"))
    local linkFlags = assert(packer:match("link_flags='(%[[^\n]+%])'"))
    assert(
        not compileFlags:find("--ld-path", 1, true),
        "the Linux pack gives linker selection to compile-only commands"
    )
    assert(linkFlags:find("--ld-path", 1, true), "the Linux pack does not select its bundled linker")
end

-- A path answered by Git Bash can be handed directly to the native compiler or
-- LuaJIT. Those processes do not understand its `/c/...` mount spelling.
function M.windowsAnswersNativePaths()
    local directory = temporary()
    fakeWindowsUname(directory)
    fakeCygpath(directory)
    fakeCompiler(directory, "gcc", "gnu-c")
    fakeCompiler(directory, "g++", "gnu-cxx")

    local status, prefix = run(
        {NUPP_TOOLCHAIN_DIR = directory .. "/cache", PATH = forPath(directory) .. ":$PATH",},
        "--prefix"
    )

    assert(status == 0, prefix)
    assert(prefix:match("^C:/"), "Windows answered an MSYS path: " .. prefix)
end

-- `native-rust` deliberately answers a drive-letter path for native compiler
-- arguments. That spelling cannot be inserted into Git Bash's colon-separated
-- PATH: its drive colon becomes a separator and the DLL is not found.
function M.windowsRustAbiSmokeConvertsTheDllSearchPath()
    local smoke = read(ROOT .. "/scripts/test-rust-abi")
    assert(
        smoke:find('SEARCH_DIRECTORY=$(cygpath -u "$DIRECTORY")', 1, true),
        "the Rust ABI smoke does not convert its native DLL directory for PATH"
    )
    assert(
        smoke:find('PATH="$SEARCH_DIRECTORY:$PATH"', 1, true),
        "the Rust ABI smoke inserts the drive-letter directory into PATH"
    )
end

-- The native spelling belongs in compiler arguments, but not in the colon-
-- separated PATH assembled by Git Bash. The selector converts that one use
-- back before looking for the staged interpreter.
function M.windowsNativeLuaJITPathIsConvertedForTheShellPath()
    local directory = temporary()
    local oldBin = directory .. "/old-bin"
    local staged = directory .. "/staged"
    local fakeRoot = directory .. "/root"
    assert(
        os.execute(
            ("mkdir -p %s %s %s"):format(quote(oldBin), quote(staged .. "/bin"), quote(fakeRoot .. "/scripts"))
        ) == 0
    )
    fakeWindowsUname(oldBin)
    fakeCygpath(oldBin)
    write(oldBin .. "/luajit", [[#!/bin/sh
echo 'LuaJIT 2.1.1'
]])
    write(staged .. "/bin/luajit", [[#!/bin/sh
echo 'LuaJIT 2.1.1784535650'
]])
    write(fakeRoot .. "/scripts/toolchain", [[#!/bin/sh
printf '%s\n' 'C:/staged'
]])
    assert(
        os.execute(
            "chmod +x " .. quote(
                oldBin .. "/luajit"
            ) .. " " .. quote(staged .. "/bin/luajit") .. " " .. quote(fakeRoot .. "/scripts/toolchain")
        ) == 0
    )

    local command = (
        'env PATH="%s:$PATH" NUPP_TEST_CYGPATH_U=%s sh -c %s'
    ):format(
        forPath(oldBin),
        quote(staged),
        quote(
            ". " .. quote(
                ROOT .. "/scripts/luajit.sh"
            ) .. "; if select_luajit " .. quote(fakeRoot) .. "; then command -v luajit; else exit 1; fi"
        )
    )
    local pipe = assert(io.popen(command))
    local selected = pipe:read("*a")
    pipe:close()
    -- Compared in one spelling. What is under test is whether the staged
    -- interpreter was reached at all: a drive path that went into PATH unconverted
    -- is split there, and then nothing is found and `command -v` answers with the
    -- old one or with nothing. Which spelling the answer comes back in is the
    -- selector's business and not this assertion's, and matching one of them by
    -- hand made a passing selection read as a split path.
    local wanted = forPath(staged) .. "/bin/luajit"
    assert(forPath((selected:gsub("%s+$", ""))) == wanted, ("selected %q, wanted %q"):format(selected, wanted))
end

-- `NUPP_NATIVE_CC` named the C compiler before the toolchain names were
-- unified. It keeps working, and the primary name wins.
function M.theOldCCompilerNameStillSelects()
    local directory = temporary()
    local named = fakeCompiler(directory, "named-cc", "named")
    local aliased = fakeCompiler(directory, "aliased-cc", "aliased")
    local environment = {NUPP_TOOLCHAIN_DIR = directory .. "/cache", PATH = "$PATH", NUPP_NATIVE_CC = aliased,}

    local status, viaAlias = run(environment, "--prefix")
    assert(status == 0, viaAlias)

    environment.NUPP_CC = named
    local primaryStatus, viaPrimary = run(environment, "--prefix")
    assert(primaryStatus == 0, viaPrimary)

    assert(viaAlias ~= viaPrimary, "the primary names did not win over the aliases: " .. viaAlias)
end

return M
