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
local function run(environment, arguments, driver)
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
    ):format(table.concat(prefix, " "), quote(driver or DRIVER), arguments)
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

-- Where a source comes from is the pin's to say. The driver used to spell four of
-- the URLs out again beside the pins that named them, so editing a pin's URL moved
-- nothing and the two could disagree about where a source lives.
function M.theDriverFetchesOnlyFromThePins()
    local driver = read(ROOT .. "/scripts/toolchain")
    local url = driver:match("https?://[^%s\"']+")
    assert(url == nil, "scripts/toolchain names a URL of its own: " .. tostring(url))
end

--- A rockspec read the way LuaRocks reads one: as a chunk run in an empty table.
local function rockspec(path)
    local fields = {}
    local chunk = assert(loadfile(path))
    setfenv(chunk, fields)
    chunk()
    return fields
end

-- The documentation rocks are bundled into the release binary, and they were
-- pinned by name and version alone: whatever the rock server, or the Git tag its
-- rockspec named, held on the day was what `dist` shipped. Each is now installed
-- from a rockspec in this tree naming one archive and the digest LuaRocks checks
-- before unpacking it, and nothing is resolved from a server for them.
function M.everyBundledRockIsPinnedToAnArchiveDigest()
    local manifest = dofile(ROOT .. "/nupp.lua")
    local seen = 0
    for name, dependency in pairs(manifest.dependencies) do
        if dependency.kind == "luarocks" then
            seen = seen + 1
            local path = dependency.rockspec
            assert(
                type(path) == "string" and path:match("^rocks/[^/]+%.rockspec$"),
                name .. " is not pinned by a rockspec in rocks/"
            )
            assert(dependency.version == nil and dependency.server == nil, name .. " asks a rock server for itself")
            assert(dependency.rockDependencies == false, name .. " lets LuaRocks resolve its dependencies from a server")
            local source = rockspec(ROOT .. "/" .. path).source
            assert(source.url:match("^https://"), path .. " fetches over something other than HTTPS: " .. source.url)
            assert(source.tag == nil and source.branch == nil, path .. " names a movable Git ref")
            assert(source.url:match("%.tar%.gz$") or source.url:match("%.zip$"), path .. " does not name an archive")
            assert(
                type(source.md5) == "string" and #source.md5 == 32 and source.md5:match("^%x+$"),
                path .. " has no digest for LuaRocks to check"
            )
        end
    end
    assert(seen >= 5, "the manifest lost its documentation rocks")

    -- The LPeg rock is built from the archive the native LPeg is, which the pins
    -- file holds to a SHA-256.
    local recorded = pins()
    local lpeg = rockspec(ROOT .. "/" .. manifest.dependencies.lunamark_lpeg.rockspec).source.url
    assert(lpeg == recorded.LPEG_URL:gsub("%${LPEG_VERSION}", recorded.LPEG_VERSION), lpeg)

    -- A step that installs one of them by name first leaves the build nothing to
    -- check, since an installed version is taken as it is.
    local pages = read(ROOT .. "/.github/workflows/pages.yml")
    assert(not pages:find("install lpeg", 1, true), "the Pages build installs LPeg from a rock server")
end

-- A pin written out a second time somewhere that cannot read the pins file. Each
-- of these agreed only because whoever bumped the pin remembered it: the profiler
-- labels a trace from any other LuaJIT unsupported, the notice every archive
-- carries names what was pinned, and llvm-sys is the C API the code generator is
-- compiled against, `231` for LLVM 23.1.
function M.handCopiedPinsAgreeWithThePinsFile()
    local recorded = pins()
    local trace = read(ROOT .. "/src/nupp/profile/trace.nupp")
    assert(
        trace:find('trace.PINNED_LUAJIT_REVISION = "' .. recorded.LUAJIT_REV .. '"', 1, true),
        "src/nupp/profile/trace.nupp names a LuaJIT revision other than LUAJIT_REV"
    )

    local notice = read(ROOT .. "/host/NOTICE.md")
    assert(
        notice:find("| `" .. recorded.LUAJIT_REV .. "` |", 1, true),
        "host/NOTICE.md names a LuaJIT revision other than LUAJIT_REV"
    )
    assert(
        notice:find("| `" .. recorded.LPEG_VERSION .. "` |", 1, true),
        "host/NOTICE.md names an LPeg version other than LPEG_VERSION"
    )

    local major, minor = recorded.LLVM_VERSION:match("^(%d+)%.(%d+)%.")
    local manifest = read(ROOT .. "/native/crates/codegen/Cargo.toml")
    local bound = manifest:match('llvm%-sys = { version = "=(%d+)%.')
    assert(
        bound == major .. minor,
        ("llvm-sys is pinned to the %s C API and LLVM_VERSION is %s"):format(tostring(bound), recorded.LLVM_VERSION)
    )
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

-- A checkout copy whose LPeg pin names an archive this suite made, fetched by a
-- `curl` that answers from a table of hosts and logs each URL it was asked for.
-- The origin never answers, as it did not for run 36447903992; what each mirror
-- serves is the case's to say.
local function lpegFromMirrors(serves)
    local directory = temporary()
    local root = directory .. "/root"
    local bin = directory .. "/bin"
    local staging = directory .. "/staging/lpeg-9.9.9"
    for _, path in ipairs({root .. "/scripts/patches", root .. "/host/notices", bin, staging, directory .. "/served"}) do
        assert(os.execute("mkdir -p " .. quote(path)) == 0)
    end
    local licence = "Copyright 2007-2023 Lua.org, PUC-Rio.\nPermission is hereby granted\n"
        .. "THE SOFTWARE IS PROVIDED\n"
    write(root .. "/host/notices/LPeg-LICENSE.txt", licence)
    write(staging .. "/lptree.c", "/* fixture marker */\n")
    write(staging .. "/lpeg.html", licence)
    local tarball = directory .. "/lpeg-9.9.9.tar.gz"
    assert(os.execute("tar czf " .. quote(tarball) .. " -C " .. quote(directory .. "/staging") .. " lpeg-9.9.9") == 0)
    local digestCommand = "{ shasum -a 256 2>/dev/null || sha256sum; } < " .. quote(tarball) .. " | cut -c1-64"
    local pipe = assert(io.popen("sh -c " .. quote(digestCommand)))
    local digest = pipe:read("*l")
    pipe:close()
    assert(digest and #digest == 64, "cannot digest the fixture archive")

    local pinsText = read(ROOT .. "/scripts/toolchain.pins")
        :gsub("\nLPEG_VERSION=[^\n]*", "\nLPEG_VERSION=9.9.9")
        :gsub("\nLPEG_SHA256=[^\n]*", "\nLPEG_SHA256=" .. digest)
        :gsub("\nLPEG_URL=[^\n]*", "\nLPEG_URL='https://origin.invalid/lpeg-${LPEG_VERSION}.tar.gz'")
        :gsub(
            "\nLPEG_MIRRORS=[^\n]*",
            "\nLPEG_MIRRORS='https://first.invalid/lpeg-${LPEG_VERSION}.tar.gz "
                .. "https://second.invalid/lpeg-${LPEG_VERSION}.tar.gz'"
        )
    local driver = root .. "/scripts/toolchain"
    write(driver, read(DRIVER))
    write(root .. "/scripts/toolchain.pins", pinsText)
    write(root .. "/scripts/patches/luajit-irt-size.patch", read(ROOT .. "/scripts/patches/luajit-irt-size.patch"))
    for host, what in pairs(serves) do
        write(directory .. "/served/" .. host, what == "archive" and read(tarball) or what)
    end
    write(
        bin .. "/curl",
        [[#!/bin/sh
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) destination=$2; shift ;;
        -*) ;;
        *) url=$1 ;;
    esac
    shift
done
printf '%s\n' "$url" >> "$NUPP_TEST_SERVED/log"
host=${url#https://}
host=${host%%/*}
[ -f "$NUPP_TEST_SERVED/$host" ] || { echo "curl: (6) Could not resolve host: $host" >&2; exit 6; }
cp "$NUPP_TEST_SERVED/$host" "$destination"
]]
    )
    assert(os.execute("chmod +x " .. quote(driver) .. " " .. quote(bin .. "/curl")) == 0)
    local compiler = fakeCompiler(directory, "fake-cc", "fixed")
    local status, output = run(
        {
            NUPP_TOOLCHAIN_DIR = directory .. "/cache",
            NUPP_CC = compiler,
            NUPP_CXX = compiler,
            NUPP_TEST_SERVED = directory .. "/served",
            PATH = forPath(bin) .. ":$PATH",
        },
        "lpeg-source",
        driver
    )
    local log = io.open(directory .. "/served/log", "rb")
    local asked = log and log:read("*a") or ""
    if log then
        log:close()
    end

    return status, output, asked, digest, directory
end

-- The origin being down is not the archive being unavailable. Each mirror is
-- asked in turn and held to the same digest: the first answers with other bytes
-- and is refused, and the second, which has the pinned archive, is what is used.
function M.anUnreachableOriginFallsBackToAMirrorWithTheSameDigest()
    local status, output, asked, _, directory = lpegFromMirrors({
        ["first.invalid"] = "a page that is not the archive",
        ["second.invalid"] = "archive",
    })
    assert(status == 0, "no mirror was used when the origin was down:\n" .. output)
    assert(
        asked == "https://origin.invalid/lpeg-9.9.9.tar.gz\n"
            .. "https://first.invalid/lpeg-9.9.9.tar.gz\n"
            .. "https://second.invalid/lpeg-9.9.9.tar.gz\n",
        "the origin and mirrors were not asked in order:\n" .. asked
    )
    assert(output:find("refusing to cache or compile it; trying https://second.invalid", 1, true), output)
    assert(output:find("/sources/lpeg-9.9.9", 1, true), "the tree was not printed:\n" .. output)
    os.execute("rm -rf " .. quote(directory))
end

-- A mirror is a place to look and nothing else. When every one of them serves
-- something other than the pinned archive, the build stops rather than taking the
-- last answer, and says what it expected.
function M.mirrorsThatServeOtherBytesAreRefused()
    local status, output, asked, digest, directory = lpegFromMirrors({
        ["first.invalid"] = "a page that is not the archive",
        ["second.invalid"] = "another page that is not the archive",
    })
    assert(status ~= 0, "a mirror's wrong bytes were used:\n" .. output)
    assert(output:find("expected " .. digest, 1, true), "the refusal does not say what was expected:\n" .. output)
    assert(select(2, asked:gsub("\n", "")) == 3, "not every mirror was tried:\n" .. asked)
    local cached = io.open(directory .. "/cache/archives/lpeg-9.9.9.tar.gz", "rb")
    assert(cached == nil, "a refused download was left in the archive cache")
    os.execute("rm -rf " .. quote(directory))
end

-- A finished LuaJIT is checked against the receipt its install left, not believed
-- for its marker: one damaged afterwards was handed to every command, which the
-- kernel killed before it printed anything. Offline and with nothing supplied, the
-- rebuild this asks for stops at the archive, which is how the case sees it asked.
function M.aDamagedCachedLuajitIsBuiltAgain()
    local directory = temporary()
    local environment = {
        NUPP_TOOLCHAIN_DIR = directory .. "/cache",
        NUPP_HOST_SOURCE_DIR = directory .. "/empty",
        NUPP_HOST_OFFLINE = "1",
        PATH = "$PATH",
    }
    local _, prefix = run(environment, "--prefix")
    local out = assert(prefix:match("([^\n]+)%s*$")) .. "/luajit"
    assert(os.execute("mkdir -p " .. quote(out .. "/bin")) == 0)
    write(out .. "/bin/luajit", "an interpreter once\n")
    write(out .. "/.complete", "done\n")
    write(out .. "/.nupp-runtime-patch", "the receipt of some other interpreter\n")

    local status, output = run(environment, "luajit")
    assert(status ~= 0, "a damaged LuaJIT was handed out as the built one:\n" .. output)
    assert(output:find("not what was installed", 1, true), "the damage was not reported:\n" .. output)
    os.execute("rm -rf " .. quote(directory))
end

-- A tree named outright is checked for being the pinned LLVM as well as for being
-- whole. CI names whichever restored tree it finds first, and one left from before
-- a pin bump was linked as though it were the pinned one.
function M.aNamedLlvmTreeOfAnotherVersionIsRefused()
    local directory = temporary()
    local function tree(name, version)
        local prefix = directory .. "/" .. name
        assert(os.execute("mkdir -p " .. quote(prefix .. "/bin") .. " " .. quote(prefix .. "/lib")) == 0)
        fakeCompiler(prefix .. "/bin", "llvm-config", version)
        for _, library in ipairs({"lldCommon", "lldMachO", "lldELF", "lldCOFF", "lldMinGW", "lldWasm"}) do
            write(prefix .. "/lib/lib" .. library .. ".a", "")
        end
        assert(os.execute("mkdir -p " .. quote(prefix .. "/include/llvm/Config")) == 0)
        write(
            prefix .. "/include/llvm/Config/llvm-config.h",
            '#define LLVM_VERSION_MAJOR 1\n#define LLVM_VERSION_STRING "' .. version .. '"\n'
        )
        return prefix
    end

    local environment = {NUPP_TOOLCHAIN_DIR = directory .. "/cache", PATH = "$PATH",}
    environment.NUPP_LLVM_PREFIX = tree("pinned", pins().LLVM_VERSION)
    local status, output = run(environment, "llvm")
    assert(status == 0, "the pinned version was refused:\n" .. output)

    environment.NUPP_LLVM_PREFIX = tree("stale", "1.0.0")
    status, output = run(environment, "llvm")
    assert(status ~= 0, "a tree of another LLVM was used as the pinned one:\n" .. output)
    assert(
        output:find("which is LLVM 1.0.0, not the pinned " .. pins().LLVM_VERSION, 1, true),
        "the refusal does not say which versions disagree:\n" .. output
    )
    os.execute("rm -rf " .. quote(directory))
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

-- A release archive is published by digest, so its bytes are its files' names,
-- contents and executable bits: not the clock, the user, the umask, or the
-- extended attributes and AppleDouble files macOS tar adds. The release job
-- packs through the driver rather than calling tar itself.
function M.releaseArchivesCarryOnlyNamesContentsAndModes()
    local directory = temporary()
    local tree = directory .. "/tree"
    assert(os.execute("mkdir -p " .. quote(tree .. "/notices")) == 0)
    write(tree .. "/nupp", "#!/bin/sh\n")
    write(tree .. "/notices/NOTICE.md", "notice\n")
    assert(os.execute("chmod 755 " .. quote(tree .. "/nupp")) == 0)
    local first = directory .. "/first.tar.gz"
    local status, output = run({}, "archive " .. quote(tree) .. " " .. quote(first))
    assert(status == 0, output)
    assert(
        os.execute(
            "touch " .. quote(tree .. "/nupp") .. " && chmod 700 " .. quote(tree .. "/nupp")
                .. " && chmod 600 " .. quote(tree .. "/notices/NOTICE.md")
        ) == 0
    )
    local second = directory .. "/second.tar.gz"
    status, output = run({TZ = "Asia/Tokyo"}, "archive " .. quote(tree) .. " " .. quote(second))
    assert(status == 0, output)
    assert(read(first) == read(second), "the same files archived twice differ")
    local workflow = read(ROOT .. "/.github/workflows/release.yml")
    assert(not workflow:find("tar -czf", 1, true), "the release job archives with tar directly")
end

-- ld64 hashes the debug map's object paths and the output's leaf name into
-- LC_UUID, and rustc re-signs an executable under that leaf. The target
-- directory reaches all three -- the leaf is Cargo's hashed deps/ name -- so a
-- provider or host linked in a second checkout differed from the first in its
-- UUID and signature and nowhere else.
function M.macOSRustLinksDoNotRecordTheTargetDirectory()
    local driver = read(ROOT .. "/scripts/toolchain")
    local _, prefixes = driver:gsub("link%-arg=%-Wl,%-oso_prefix,%$out/target/", "")
    assert(prefixes == 3, "the provider, host and embedding links each strip the target directory: " .. prefixes)
    assert(
        driver:find("link-arg=-Wl,-final_output,nupp-host-rust", 1, true),
        "the host's UUID is hashed from Cargo's per-directory deps/ name"
    )
    assert(
        driver:find("codesign --force --sign - --identifier nupp-host-rust", 1, true),
        "the host keeps rustc's signature under Cargo's per-directory deps/ name"
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

-- Cargo owns the ordinary Rust executable's platform closure. The static relink
-- route still invokes a C linker and must spell that closure explicitly.
function M.windowsHostLinkersCarryPthread()
    local driver = read(ROOT .. "/scripts/toolchain")
    local systemFlags = assert(driver:match("host_system_flags%(%) {%s*(.-)\n}"))
    local windowsFlags = assert(systemFlags:match("windows%)(.-);;"))
    assert(windowsFlags:find("-lpthread", 1, true), "the Windows application host linker does not link pthread")
    assert(driver:find('$(host_system_flags "$features")', 1, true), "the application linker omits its system flags")
end

-- Rustls reads the Windows root stores through CryptoAPI, and Rust std builds
-- child pipes with ntdll. Cargo records executable dependencies; the static
-- C-link route records them itself.
function M.windowsHostLinkersCarrySystemImports()
    local driver = read(ROOT .. "/scripts/toolchain")
    assert(driver:find("-lcrypt32", 1, true), "the application host linker does not carry crypt32")
    assert(driver:find("-lntdll", 1, true), "the application host linker does not carry Rust std's ntdll dependency")
    assert(
        not driver:find("--allow-multiple-definition", 1, true),
        "the application host linker masks malformed archive composition"
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

-- The same static route carries the macOS trust-store frameworks.
function M.macOSHostLinkersCarryTheSecurityFramework()
    local driver = read(ROOT .. "/scripts/toolchain")
    local _, security = driver:gsub("%-framework Security", "")
    local _, foundation = driver:gsub("%-framework CoreFoundation", "")
    assert(security >= 1 and foundation >= 1, "not every macOS toolchain linker carries the trust-store frameworks")
end

-- The Rust application archive now contains the exact-feature provider. Cargo
-- retains its named exports. Windows selects one-codegen-unit Rust surfaces
-- normally so it does not force-load flattened std/import objects; other hosts
-- retain the authoritative archive directly.
function M.staticHostsRetainTheRustApplicationArchive()
    local cargo = read(ROOT .. "/Cargo.toml")
    local driver = read(ROOT .. "/scripts/toolchain")
    local companionCopy = assert(driver:find('cp "$source" "$imports_archive"', 1, true))
    local sanitize = assert(driver:find('"$archive_tool" d "$destination" "@$imports_native"', 1, true))
    local importMemberCase = "*.dlls[0-9]*.o|*.dllh.o|*.dllt.o"
    local importMemberCases = 0
    local importMemberPosition = 1
    while true do
        local position = driver:find(importMemberCase, importMemberPosition, true)
        if not position then
            break
        end
        importMemberCases = importMemberCases + 1
        importMemberPosition = position + #importMemberCase
    end
    assert(driver:find("-C link-dead-code", 1, true), "Cargo may discard exports reached only through LuaJIT FFI")
    assert(companionCopy < sanitize, "the import companion is not preserved before archive sanitization")
    assert(
        driver:find('"$rust_application" "$out/libnupp-host.a" "$out/libnupp-host-imports.a"', 1, true),
        "the staged application host omits the sanitized Rust archive"
    )
    assert(
        importMemberCases == 2,
        "the Windows application archive does not remove and verify the complete GNU import-member union"
    )
    assert(
        driver:find('"$archive_tool" d "$destination" "@$imports_native"', 1, true),
        "Windows import members are not removed in one response-file rewrite"
    )
    assert(driver:find("tr -d '\\r'", 1, true), "Windows archive listings are not normalized before member matching")
    assert(
        driver:find('die "the staged Windows application archive retains import member $member"', 1, true),
        "the staged Windows archive does not verify that every import member was removed"
    )
    assert(
        driver:find('[ "$PLATFORM" != windows ] || [ -f "$out/libnupp-host-imports.a" ]', 1, true),
        "a completed Windows host cache can omit its import companion"
    )

    local function hasOneCodegenUnit(package)
        local profile = "%[profile%.release%.package%." .. package:gsub("%-", "%%-") .. "%]"
        return cargo:match(profile .. "%s+codegen%-units%s*=%s*1")
    end

    assert(
        hasOneCodegenUnit("nupp-native") and hasOneCodegenUnit("nupp-native-host"),
        "the ordinary Windows host archive can split name-resolved Rust exports across codegen units"
    )
    local windowsHost = assert(
        driver:find('set -- "$CC" -v -o "$probe.exe" "$probe-aot.o" "$out/libnupp-runtime.a"', 1, true)
    )
    assert(
        driver:find('-lws2_32 -ldbghelp -lole32 -lshell32 -lbcrypt -lcrypt32 -lntdll', 1, true),
        "the Windows system flags omit canonical imports"
    )
    local systemImports = assert(driver:find('$(host_system_flags "$features")', windowsHost, true))
    local hostImports = assert(driver:find('set -- "$@" "$out/lib/libnupp-host-imports.a"', systemImports, true))
    assert(
        windowsHost < systemImports and systemImports < hostImports,
        "the Windows import companion can preempt MinGW's canonical system imports"
    )
    assert(
        driver:find('-lkernel32 -lsecur32 -lncrypt', 1, true),
        "the import companion can preempt canonical kernel, security, or cryptography imports"
    )
    assert(
        not driver:find('--whole-archive "$out/lib/libnupp-host-imports.a"', 1, true),
        "the Windows link kit explicitly force-loads Rust std's import companion"
    )
end

function M.networkAndTlsAreRustOnlyToolchainFeatures()
    local driver = read(ROOT .. "/scripts/toolchain")
    assert(
        driver:find('host_cargo_features="$host_cargo_features,native-net"', 1, true),
        "a network host does not select the Rust net crate"
    )
    assert(
        driver:find('host_cargo_features="$host_cargo_features,native-tls"', 1, true),
        "a TLS host does not select the Rust TLS crate"
    )
    assert(
        driver:find('host_cargo_features="$host_cargo_features,native-compression"', 1, true),
        "a compression host does not select the Rust compression crate"
    )
    for _, obsolete in ipairs({"libuv", "mbedtls"}) do
        assert(not driver:lower():find(obsolete, 1, true), "the toolchain still provisions " .. obsolete)
    end
end

function M.gpuHostSelectionReachesTheProviderAndAdvertisedCapability()
    local driver = read(ROOT .. "/scripts/toolchain")
    local cargo = read(ROOT .. "/native/crates/host/Cargo.toml")
    local runtime = read(ROOT .. "/native/crates/host/src/lua.rs")
    assert(
        driver:find('native-gpu|gpu) host_cargo_features="$host_cargo_features,native-gpu"', 1, true),
        "the host driver must accept and forward the GPU feature"
    )
    assert(
        cargo:find('native-gpu = ["nupp-native/gpu"]', 1, true),
        "the host feature must enable the native GPU provider"
    )
    assert(
        runtime:find('self.add_feature(c"native-gpu")?', 1, true),
        "the packaged host must advertise its GPU capability"
    )
end

function M.deletedCHostDoesNotContributeCacheInputs()
    local driver = read(ROOT .. "/scripts/toolchain")
    assert(not driver:find("host/c", 1, true), "the deleted C host still contributes toolchain cache inputs")
    assert(driver:find("embedding_headers_digest", 1, true), "the staged public embedding headers have no content key")
end

-- Release jobs exercise a feature list outside the ordinary
-- toolchain driver. A removed host feature left there fails only after a clean
-- Linux or Windows release runner has provisioned the entire toolchain.
function M.releaseJobsRequestOnlyCurrentHostFeatures()
    for _, path in ipairs({".github/workflows/release.yml"}) do
        local text = read(ROOT .. "/" .. path)
        assert(not text:find("lua-utf8", 1, true), path .. " still requests the removed lua-utf8 host feature")
    end
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

-- Test a checkout copy: changing patch bytes must change both the native prefix
-- and the source fingerprint used by host artifacts, without rebuilding C.
function M.luaJitPatchContentChangesNativeAndHostKeys()
    local directory = temporary()
    local root = directory .. "/root"
    assert(os.execute("mkdir -p " .. quote(root .. "/scripts/patches")) == 0)
    local driver = root .. "/scripts/toolchain"
    write(driver, read(DRIVER))
    write(root .. "/scripts/toolchain.pins", read(ROOT .. "/scripts/toolchain.pins"))
    local patch = root .. "/scripts/patches/luajit.patch"
    write(patch, read(ROOT .. "/scripts/patches/luajit.patch"))
    local hostProbe = root .. "/scripts/host-key"
    local text = read(DRIVER)
    local entry = assert(text:find("# --- entry", 1, true))
    write(hostProbe, text:sub(1, entry - 1) .. '\nrust_sources_digest\n')
    assert(os.execute("chmod +x " .. quote(driver) .. " " .. quote(hostProbe)) == 0)
    local compiler = fakeCompiler(directory, "fake-cc", "fixed")
    local env = {NUPP_TOOLCHAIN_DIR = directory .. "/cache", NUPP_CC = compiler, NUPP_CXX = compiler, PATH = "$PATH"}
    local status, prefix = run(env, "--prefix", driver)
    assert(status == 0, prefix)
    local hostStatus, host = run(env, "", hostProbe)
    assert(hostStatus == 0, host)
    write(patch, read(patch) .. "\n# Distinct patch content for cache invalidation.\n")
    local newStatus, newPrefix = run(env, "--prefix", driver)
    assert(newStatus == 0, newPrefix)
    local newHostStatus, newHost = run(env, "", hostProbe)
    assert(newHostStatus == 0, newHost)
    assert(prefix ~= newPrefix, "changed LuaJIT patch reused the native prefix")
    assert(host ~= newHost, "changed LuaJIT patch reused the host source fingerprint")
end

function M.luaJitBuildPatchesOnlyItsPrivateSourceCopy()
    local directory = temporary()
    local root = directory .. "/root"
    local source = directory .. "/cache/sources/LuaJIT-" .. pins().LUAJIT_REV
    assert(
        os.execute(
            "mkdir -p " .. quote(
                root .. "/scripts/patches"
            ) .. " " .. quote(root .. "/host/notices") .. " " .. quote(source .. "/src")
        ) == 0
    )
    local driver = root .. "/scripts/toolchain"
    write(driver, read(DRIVER))
    write(root .. "/scripts/toolchain.pins", read(ROOT .. "/scripts/toolchain.pins"))
    write(root .. "/scripts/patches/luajit.patch", read(ROOT .. "/scripts/patches/luajit.patch"))
    local notice = read(ROOT .. "/host/notices/LuaJIT-COPYRIGHT.txt")
    write(root .. "/host/notices/LuaJIT-COPYRIGHT.txt", notice)
    write(source .. "/COPYRIGHT", notice)
    write(source .. "/src/lj_arch.h", "/* fixture source marker */\n")
    local header = "#define irt_is64(t)\t\t((IRT_IS64 >> irt_type(t)) & 1)\n"
        .. "#define irt_is64orfp(t)\t\t(((IRT_IS64|(1u<<IRT_FLOAT))>>irt_type(t)) & 1)\n\n"
        .. "#define irt_size(t)\t\t(lj_ir_type_size[irt_t((t))])\n\n"
        .. "LJ_DATA const uint8_t lj_ir_type_size[];\n\n"
    write(source .. "/src/lj_ir.h", header)
    -- The loop-entry hunk's context, at the line it names.
    write(
        source .. "/src/vm_arm64.dasc",
        string.rep("\n", 3938)
            .. "    if (op == BC_FORI) {\n"
            .. "      |  csel PC, RC, PC, hi\n"
            .. "    } else if (op == BC_JFORI) {\n"
            .. "      |  ldrh RCw, [RC, #-4+OFS_RD]\n"
            .. "      |  bls =>BC_JLOOP\n"
            .. "    } else if (op == BC_IFORL) {\n"
    )
    local make = directory .. "/fake-make"
    write(
        make,
        [[#!/bin/sh
set -eu
mode=build
while [ "$#" -gt 0 ]; do
    case "$1" in
        -C) tree=$2; shift ;;
        PREFIX=*) prefix=${1#PREFIX=} ;;
        clean|install) mode=$1 ;;
    esac
    shift
done
[ "$tree" != "$NUPP_TEST_SHARED_SOURCE" ]
grep -F 'lj_ir_type_size[irt_type((t))]' "$tree/src/lj_ir.h" >/dev/null
printf 'private\n' > "$tree/private-build-marker"
if [ "$mode" = build ]; then
    : > "$tree/src/libluajit.a"
fi
if [ "$mode" = install ]; then
    mkdir -p "$prefix/bin" "$prefix/lib" "$prefix/include/luajit-2.1"
    printf '#!/bin/sh\necho LuaJIT 2.1.1784535650\n' > "$prefix/bin/luajit"
    chmod +x "$prefix/bin/luajit"
fi
]]
    )
    write(directory .. "/uname", "#!/bin/sh\nif [ \"$1\" = -m ]; then echo x86_64; else echo Linux; fi\n")
    assert(os.execute("chmod +x " .. quote(driver) .. " " .. quote(make) .. " " .. quote(directory .. "/uname")) == 0)
    local compiler = fakeCompiler(directory, "fake-cc", "fixed")
    local status, output = run(
        {
            NUPP_TOOLCHAIN_DIR = directory .. "/cache",
            NUPP_CC = compiler,
            NUPP_CXX = compiler,
            MAKE = make,
            NUPP_TEST_SHARED_SOURCE = source,
            PATH = forPath(directory) .. ":$PATH"
        },
        "luajit",
        driver
    )
    assert(status == 0, output)
    assert(read(source .. "/src/lj_ir.h") == header, "the shared verified source was patched")
    assert(not io.open(source .. "/private-build-marker", "rb"), "make wrote into the shared verified source")
end

-- `known` is what the launcher hands the selector as its second argument: nil for
-- nothing, "finished" for the staged directory with its completion marker, and
-- "unfinished" for the directory without one.
local function luaJitSelection(architecture, stagedExists, patched, replaceBinary, known)
    local directory = temporary()
    local current = directory .. "/current"
    local staged = directory .. "/staged"
    local root = directory .. "/root"
    assert(
        os.execute(
            "mkdir -p " .. quote(current) .. " " .. quote(staged .. "/bin") .. " " .. quote(root .. "/scripts")
        ) == 0
    )
    write(
        current .. "/uname",
        "#!/bin/sh\nif [ \"$1\" = -m ]; then echo " .. quote(architecture) .. "; else echo Linux; fi\n"
    )
    write(current .. "/luajit", "#!/bin/sh\necho 'LuaJIT 2.1.9999999999'\n")
    if patched then
        assert(os.execute("mkdir -p " .. quote(root .. "/scripts/patches")) == 0)
        local patch = root .. "/scripts/patches/luajit.patch"
        write(patch, read(ROOT .. "/scripts/patches/luajit.patch"))
        local receipt = directory .. "/.nupp-runtime-patch"
        assert(
            os.execute(
                "{ cksum < " .. quote(
                    patch
                ) .. "; cksum < " .. quote(current .. "/luajit") .. "; } > " .. quote(receipt)
            ) == 0
        )
        if replaceBinary then
            write(current .. "/luajit", "#!/bin/sh\necho 'LuaJIT 2.1.9999999999 replacement'\n")
        end
    end
    local marker = directory .. "/provisioned"
    write(
        root .. "/scripts/toolchain",
        "#!/bin/sh\nprintf requested > " .. quote(marker) .. "\nprintf '%s\\n' " .. quote(forPath(staged)) .. "\n"
    )
    if stagedExists then
        write(staged .. "/bin/luajit", "#!/bin/sh\necho 'LuaJIT 2.1.1784535650'\n")
        assert(os.execute("chmod +x " .. quote(staged .. "/bin/luajit")) == 0)
    end
    if known == "finished" then
        write(staged .. "/.complete", "done\n")
    end
    local knownArgument = known and " " .. quote(forPath(staged)) or ""
    assert(
        os.execute(
            "chmod +x " .. quote(
                current .. "/uname"
            ) .. " " .. quote(current .. "/luajit") .. " " .. quote(root .. "/scripts/toolchain")
        ) == 0
    )
    local command = (
        'env PATH="%s:$PATH" sh -c %s 2>&1'
    ):format(
        forPath(current),
        quote(
            '. ' .. quote(
                ROOT .. '/scripts/luajit.sh'
            ) .. '; if select_luajit ' .. quote(
                root
            ) .. knownArgument .. '; then command -v luajit; else echo SELECT_FAILED; fi'
        )
    )
    local pipe = assert(io.popen(command))
    local selected = pipe:read("*a")
    pipe:close()
    local handle = io.open(marker, "rb")
    local provisioned = handle ~= nil
    if handle then
        handle:close()
    end

    return selected:gsub("%s+$", ""), provisioned, current, staged
end

function M.arm64SelectsPatchedLuaJitEvenWhenPathIsNewer()
    for _, architecture in ipairs({"arm64", "aarch64"}) do
        local selected, provisioned, _, staged = luaJitSelection(architecture, true)
        assert(provisioned, "ARM64 trusted an unverified PATH LuaJIT")
        assert(forPath(selected) == forPath(staged) .. "/bin/luajit", selected)
    end
end

function M.otherArchitecturesKeepUsablePathLuaJit()
    local selected, provisioned, current = luaJitSelection("x86_64", true)
    assert(not provisioned, "x86_64 needlessly replaced a usable PATH LuaJIT")
    assert(forPath(selected) == forPath(current) .. "/luajit", selected)
end

function M.arm64DoesNotFallBackWhenStagedLuaJitIsMissing()
    local selected, provisioned = luaJitSelection("arm64", false)
    assert(provisioned and selected:find("SELECT_FAILED", 1, true), selected)
end

function M.arm64KeepsAnAlreadyVerifiedPatchedInterpreter()
    local selected, provisioned, current = luaJitSelection("arm64", true, true)
    assert(not provisioned, "a patched interpreter was rebuilt for a changed AOT compiler")
    assert(forPath(selected) == forPath(current) .. "/luajit", selected)
end

-- The launcher has already asked the toolchain for its prefix, and the staged
-- interpreter under it is the answer a second question would get. Asking anyway
-- cost every top-level command about seventy milliseconds.
function M.aFinishedStagedLuaJitTheCallerNamedIsTakenWithoutAskingAgain()
    local selected, provisioned, _, staged = luaJitSelection("arm64", true, false, false, "finished")
    assert(not provisioned, "the selector asked the toolchain for a directory it was handed")
    assert(forPath(selected) == forPath(staged) .. "/bin/luajit", selected)
end

-- A directory without its completion marker is one a build has not finished, and
-- only the toolchain can say what to do about that.
function M.anUnfinishedStagedLuaJitStillAsksTheToolchain()
    local selected, provisioned, _, staged = luaJitSelection("arm64", true, false, false, "unfinished")
    assert(provisioned, "the selector trusted a staged directory with no completion marker")
    assert(forPath(selected) == forPath(staged) .. "/bin/luajit", selected)
end

function M.arm64DoesNotTrustAReplacedPatchedInterpreter()
    local selected, provisioned, _, staged = luaJitSelection("arm64", true, true, true)
    assert(provisioned, "a replaced interpreter retained the old patch receipt")
    assert(forPath(selected) == forPath(staged) .. "/bin/luajit", selected)
end


-- A run that finds another holding a lock says so, and whose it is, on standard
-- error whether or not that is a terminal. It used to sleep in silence for up to
-- half an hour -- the fifteen-minute stalls three cold runs showed with nothing
-- to explain them -- and when it did learn to speak, it spoke only to a
-- terminal, which a test suite's or an agent's standard error is not.
--
-- The lock functions are taken out of the driver and run on their own: no
-- component is quick enough to hold a lock for the grace this waits out, and
-- the waiting is theirs alone.
function M.aRunWaitingOnALockSaysWhoHoldsIt()
    local driver = read(DRIVER)
    local functions = {}
    for _, name in ipairs({"release_lock", "say_waiting", "take_lock"}) do
        local body = driver:match("\n(" .. name .. "%(%) {[^\n]*})\n")
            or driver:match("\n(" .. name .. "%(%) {\n.-\n})\n")
        assert(body, "scripts/toolchain has no " .. name .. " function")
        functions[#functions + 1] = body
    end
    local directory = temporary()
    local script = directory .. "/wait.sh"
    write(
        script,
        table.concat({
            "set -eu",
            "note() { printf 'toolchain: %s\\n' \"$*\" >&2; }",
            "LOCK=",
            table.concat(functions, "\n"),
            "CACHE=" .. quote(directory .. "/cache"),
            "mkdir -p \"$CACHE/.lock-demo\"",
            "sleep 5 &",
            "holder=$!",
            "printf '%s\\n' \"$holder\" > \"$CACHE/.lock-demo/pid\"",
            "echo \"holder:$holder\"",
            "take_lock demo \"$CACHE/never\"",
            "echo took",
            "",
        }, "\n")
    )
    local pipe = assert(io.popen("sh " .. quote(script) .. " 2>&1"))
    local output = pipe:read("*a")
    pipe:close()
    local holder = assert(output:match("holder:(%d+)"), output)
    assert(output:find("took", 1, true), "the lock was never taken once its holder exited:\n" .. output)
    assert(
        output:find("toolchain: waiting for demo, which pid " .. holder .. " is building (3s so far)", 1, true),
        "a wait on a live holder said nothing:\n" .. output
    )
    os.execute("rm -rf " .. quote(directory))
end

return M
