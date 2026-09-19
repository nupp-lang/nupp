-- End-to-end gates for the artifacts scripts/toolchain hands to C consumers.

local test = require("assert")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local pipe = assert(io.popen("pwd"))
    HERE = pipe:read("*l") .. "/" .. HERE
    pipe:close()
end
local ROOT = HERE .. "/.."
local FEATURES = "lpeg,native-compression,native-files,native-gpu,native-net,native-process,native-tls,workers"

local M = {}

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function run(command)
    local pipe = assert(io.popen(command .. " 2>&1; printf '\n__status__:%s' $?"))
    local output = pipe:read("*a")
    pipe:close()
    local status = tonumber(output:match("__status__:(%d+)%s*$"))

    return status, output:gsub("\n__status__:%d+%s*$", "")
end

local function write(path, bytes)
    local file = assert(io.open(path, "wb"))
    file:write(bytes)
    file:close()
end

local function temporary()
    local path = os.tmpname()
    os.remove(path)
    assert(os.execute("mkdir -p " .. quote(path)) == 0)
    return path
end

local cachedSdk

local function sdk()
    if cachedSdk then
        return cachedSdk
    end
    local status, output = run(("cd %s && ./scripts/toolchain host-library %s"):format(quote(ROOT), FEATURES))
    if status ~= 0 then
        test.skip("the Rust embedding SDK could not be built: " .. output)
    end
    cachedSdk = assert(output:match("([^\r\n]+)%s*$"), "toolchain named no SDK")

    return cachedSdk
end

local function fixture(directory)
    local component = directory .. "/fixture.nuppc"
    write(
        component,
        [[-- NUPP-COMPONENT 1
return {
  format = 1,
  hostAbi = 1,
  install = function()
    return {
      exports = {["game.answer"] = function(value) return value + 1 end},
      start = function() end,
    }
  end,
}
]]
    )

    return component
end

local function compiler()
    return os.getenv("NUPP_CC") or "cc"
end

local function platformLibraries(library)
    local file = assert(io.open(library .. "/link.json", "rb"))
    local manifest = require("testjson").decode(file:read("*a"))
    file:close()
    local flags = assert(manifest.staticLinkFlags, "the SDK must advertise its static system dependencies")
    local arguments = {}
    for _, flag in ipairs(flags) do
        arguments[#arguments + 1] = quote(flag)
    end
    return table.concat(arguments, " ")
end

function M.staticSdkLinksAndRunsFromC()
    local directory, library = temporary(), sdk()
    local executable = directory .. "/embed"
    if jit.os == "Windows" then
        executable = executable .. ".exe"
    end
    local status, output = run(
        (
            "%s -std=c11 -I%s %s %s %s -o %s"
        ):format(
            quote(compiler()),
            quote(library),
            quote(ROOT .. "/host/examples/embed.c"),
            quote(library .. "/libnupp.a"),
            platformLibraries(library),
            quote(executable)
        )
    )
    assert(status == 0, output)
    status, output = run(quote(executable) .. " " .. quote(fixture(directory)))
    assert(status == 0, output)
    assert(output:find("game.answer(41) = 42", 1, true), output)
end

function M.dynamicSdkLinksAndRunsFromC()
    local directory, library = temporary(), sdk()
    local executable = directory .. "/embed-dynamic"
    local link, environment
    if jit.os == "Windows" then
        executable = executable .. ".exe"
        link = quote(library .. "/libnupp.dll.a")
        environment = "PATH=" .. quote(library) .. ':"$PATH" '
    else
        link = "-L" .. quote(library) .. " -lnupp -Wl,-rpath," .. quote(library)
        environment = ""
    end
    local status, output = run(
        (
            "%s -std=c11 -I%s %s %s -o %s"
        ):format(quote(compiler()), quote(library), quote(ROOT .. "/host/examples/embed.c"), link, quote(executable))
    )
    assert(status == 0, output)
    status, output = run(environment .. quote(executable) .. " " .. quote(fixture(directory)))
    assert(status == 0, output)
    assert(output:find("game.answer(41) = 42", 1, true), output)
    if jit.os == "OSX" then
        status, output = run("otool -L " .. quote(library .. "/libnupp.dylib"))
        assert(status == 0, output)
        assert(
            not output:lower():find("luajit", 1, true),
            "the staged embedding library retains a LuaJIT cache dependency:\n" .. output
        )
    end
end

function M.staticApplicationHostLinksAndRuns()
    local directory = temporary()
    local executable = directory .. "/nupp"
    if jit.os == "Windows" then
        executable = executable .. ".exe"
    end
    local status, output = run(
        ("cd %s && ./scripts/toolchain host-link %s %s %s"):format(quote(ROOT), FEATURES, quote(executable), "--")
    )
    assert(status == 0, output)
    local source = directory .. "/fixture.lua"
    write(
        source,
        [[
assert(__nuppHost.hostFeatures.lpeg)
assert(__nuppHost.hostFeatures["native-net"])
assert(require("lpeg").P("x"):match("x") == 2)
local ffi = require("ffi")
ffi.cdef([=[
unsigned int nuppNativeAbiVersion(void);
void *nupp_rust_worker_channel_new(void);
]=])
assert(ffi.C.nuppNativeAbiVersion() == 2)
assert(ffi.C.nupp_rust_worker_channel_new ~= nil)
]]
    )
    status, output = run(quote(executable) .. " " .. quote(source))
    if status ~= 0 and jit.os == "Windows" then
        local function peImports(path)
            local importStatus, importOutput = run("objdump -p " .. quote(path))
            local imports = {}
            for name in importOutput:gmatch("DLL Name:%s*([^\r\n]+)") do
                imports[#imports + 1] = name
            end
            table.sort(imports)

            return importStatus, table.concat(imports, ", ")
        end

        local importStatus, imports = peImports(executable)
        local hostStatus, hostOutput = run(("cd %s && ./scripts/toolchain host %s"):format(quote(ROOT), FEATURES))
        local knownHost = hostOutput:match("([^\r\n]+)%s*$")
        local knownImportStatus, knownImports = peImports(knownHost or "")
        local hostDirectory = knownHost and knownHost:gsub("[/\\][^/\\]+$", "") or ""
        local archiveStatus, archiveOutput = run("ar t " .. quote(hostDirectory .. "/libnupp-host.a"))
        local archiveImports = {}
        for member in archiveOutput:gmatch("[^\r\n]+") do
            if member:lower():find("dll", 1, true) then
                archiveImports[#archiveImports + 1] = member
            end
        end
        output = (
            "shell status %s; PE import scan status %s; imports: %s\n"
            .. "known host status %s; import scan status %s; imports: %s\n"
            .. "sanitized archive scan status %s; remaining DLL members: %s\n%s"
        ):format(
            tostring(status),
            tostring(importStatus),
            imports,
            tostring(hostStatus),
            tostring(knownImportStatus),
            knownImports,
            tostring(archiveStatus),
            table.concat(archiveImports, ", "),
            output
        )
    end
    assert(status == 0, output)
end

-- The C driver for the reload gate below. It edits the entry itself rather than
-- waiting on a watcher, so what the case proves is the boundary and not a
-- filesystem race: one member taken before the edit, called again after the poll
-- that committed it.
local RELOAD_DRIVER = [[
#include "nupp.h"
#include <stdio.h>

static int report(const char *what, nupp_status status, nupp_error *error) {
    if (status == NUPP_STATUS_OK) return 0;
    fprintf(stderr, "%s: %s\n", what, error ? nupp_error_message(error) : "unknown error");
    nupp_error_free(error);
    return 1;
}

static void write_entry(const char *path, int value) {
    FILE *file = fopen(path, "wb");
    if (!file) return;
    fprintf(file, "local function update(): integer\n    return %d\nend\n\nreturn {update = update}\n", value);
    fclose(file);
}

int main(int argc, char **argv) {
    nupp_runtime *runtime = NULL;
    nupp_reload *reload = NULL;
    nupp_handle *update = NULL;
    nupp_error *error = NULL;
    nupp_config config;
    nupp_reload_config reloading;
    nupp_value result = {0};
    size_t count = 0;
    uint32_t verdict = 0;
    uint64_t generation = 0;
    nupp_status status;
    char entry[2048];

    if (argc != 4) {
        fprintf(stderr, "usage: %s COMPILER_DIR PROJECT_DIR ENTRY\n", argv[0]);
        return 2;
    }
    snprintf(entry, sizeof entry, "%s/%s", argv[2], argv[3]);
    write_entry(entry, 41);
    nupp_config_init(&config);
    status = nupp_runtime_new(&config, &runtime, &error);
    if (report("runtime", status, error)) return 1;
    nupp_reload_config_init(&reloading);
    reloading.compiler_path = argv[1];
    reloading.root = argv[2];
    reloading.entry = argv[3];
    error = NULL;
    status = nupp_reload_open(runtime, &reloading, &reload, &error);
    if (report("open", status, error)) return 1;
    error = NULL;
    status = nupp_reload_find(runtime, reload, "update", &update, &error);
    if (report("find", status, error)) return 1;
    error = NULL;
    status = nupp_call(runtime, update, NULL, 0, &result, 1, &count, &error);
    if (report("call", status, error)) return 1;
    printf("before = %.0f\n", result.number);

    write_entry(entry, 42);
    error = NULL;
    status = nupp_reload_poll(runtime, reload, &verdict, &generation, &error);
    if (report("poll", status, error)) return 1;
    printf("verdict = %u generation = %llu\n", verdict, (unsigned long long)generation);
    if (nupp_reload_message(reload)) printf("message = %s\n", nupp_reload_message(reload));
    error = NULL;
    status = nupp_call(runtime, update, NULL, 0, &result, 1, &count, &error);
    if (report("recall", status, error)) return 1;
    printf("after = %.0f\n", result.number);

    error = NULL;
    status = nupp_reload_close(runtime, reload, 1, &error);
    if (report("close", status, error)) return 1;
    nupp_reload_free(reload);
    error = NULL;
    nupp_handle_release(runtime, update, &error);
    nupp_error_free(error);
    error = NULL;
    status = nupp_runtime_shutdown(runtime, &error);
    if (report("shutdown", status, error)) return 1;
    nupp_runtime_free(runtime);
    return 0;
}
]]

function M.hotReloadCommitsAnEditThroughTheCApi()
    local compilerModules = ROOT .. "/build"
    local present = io.open(compilerModules .. "/nupp/compiler/hostreload.lua", "rb")
    if not present then
        test.skip("hot reload needs the compiler's Lua modules under build/")
    end
    present:close()
    local directory, library = temporary(), sdk()
    local project = directory .. "/project"
    assert(os.execute("mkdir -p " .. quote(project)) == 0)
    local source = directory .. "/reload.c"
    write(source, RELOAD_DRIVER)
    local executable = directory .. "/reload"
    if jit.os == "Windows" then
        executable = executable .. ".exe"
    end
    local status, output = run(
        ("%s -std=c11 -I%s %s %s %s -o %s"):format(
            quote(compiler()),
            quote(library),
            quote(source),
            quote(library .. "/libnupp.a"),
            platformLibraries(library),
            quote(executable)
        )
    )
    assert(status == 0, output)
    status, output = run(
        ("%s %s %s main.nupp"):format(quote(executable), quote(compilerModules), quote(project))
    )
    assert(status == 0, output)
    assert(output:find("before = 41", 1, true), output)
    assert(output:find("verdict = 1 generation = 2", 1, true), output)
    assert(output:find("after = 42", 1, true), output)

    -- The published example drives the same surface but waits on a person between
    -- polls, so it is compiled rather than run: what would rot in it is the API it
    -- spells, and that is what compiling catches.
    status, output = run(
        ("%s -std=c11 -I%s -c %s -o %s"):format(
            quote(compiler()),
            quote(library),
            quote(ROOT .. "/host/examples/reload.c"),
            quote(directory .. "/reload-example.o")
        )
    )
    assert(status == 0, output)
end

return M
