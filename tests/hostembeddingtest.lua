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
    -- The worker shim's Rust half is reached through a table, not by name, so
    -- the library exports none of it.
    local exports
    if jit.os == "OSX" then
        exports = "nm -gU " .. quote(library .. "/libnupp.dylib")
    elseif jit.os == "Linux" then
        exports = "nm -D --defined-only " .. quote(library .. "/libnupp.so")
    end
    if exports then
        status, output = run(exports)
        assert(status == 0 and output:find("nupp_runtime_new", 1, true), output)
        assert(not output:find("nupp_rust_", 1, true), "the embedding library exports worker internals:\n" .. output)
    end
    if jit.os == "OSX" then
        status, output = run("otool -L " .. quote(library .. "/libnupp.dylib"))
        assert(status == 0, output)
        assert(
            not output:lower():find("luajit", 1, true),
            "the staged embedding library retains a LuaJIT cache dependency:\n" .. output
        )
    end
end

-- A standalone program links the way `nupp build` links one: lld, in process,
-- against the link kit for this machine.
function M.staticApplicationHostLinksFromAKitAndRuns()
    local directory = temporary()
    local executable = directory .. "/nupp"
    if jit.os == "Windows" then
        executable = executable .. ".exe"
    end
    local aotllvm = require("nupp.tools.build.aotllvm")
    local available, why = aotllvm.selected()
    assert(available == true, why)
    local status, output = run(("cd %s && ./scripts/toolchain kit %s"):format(quote(ROOT), FEATURES))
    assert(status == 0, output)
    local kit = assert(output:match("([^\r\n]+)%s*$"), "toolchain named no kit")
    local linkErr = aotllvm.linkStandalone(kit, executable, {}, {})
    assert(linkErr == nil, linkErr)
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
int nupp_luaopen_workers(void *state);
]=])
assert(ffi.C.nuppNativeAbiVersion() == 2)
assert(ffi.C.nupp_luaopen_workers ~= nil)
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

    /* Shut down with the session still open: a runtime releases what it rooted
     * for a session the host never closed. */
    error = NULL;
    nupp_handle_release(runtime, update, &error);
    nupp_error_free(error);
    error = NULL;
    status = nupp_runtime_shutdown(runtime, &error);
    if (report("shutdown", status, error)) return 1;
    nupp_reload_free(reload);
    nupp_runtime_free(runtime);
    printf("shut down with the session open\n");
    return 0;
}
]]

function M.hotReloadCommitsAnEditThroughTheCApi()
    local compilerModules = ROOT .. "/build"
    local present = io.open(compilerModules .. "/nupp/tools/hostreload.lua", "rb")
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
    assert(output:find("shut down with the session open", 1, true), output)

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

-- A runtime attached to a host's state shuts down without closing that state, so
-- a session it left open must still be closed by the shutdown: the session latch
-- lives in the state, and a later runtime there would otherwise be told a
-- session is already open.
local REOPEN_DRIVER = [[
#include "nupp.h"
#include <stdio.h>

static int report(const char *what, nupp_status status, nupp_error *error) {
    if (status == NUPP_STATUS_OK) return 0;
    fprintf(stderr, "%s: %s\n", what, error ? nupp_error_message(error) : "unknown error");
    nupp_error_free(error);
    return 1;
}

static int open_attached(nupp_runtime *owner, char **argv, nupp_runtime **runtime,
    nupp_reload **reload, const char *what) {
    nupp_config config;
    nupp_reload_config reloading;
    nupp_error *error = NULL;
    nupp_config_init(&config);
    config.flags = 0;
    if (report("attach", nupp_runtime_attach(nupp_runtime_lua_state(owner), &config,
            runtime, &error), error)) return 1;
    nupp_reload_config_init(&reloading);
    reloading.compiler_path = argv[1];
    reloading.root = argv[2];
    reloading.entry = argv[3];
    error = NULL;
    return report(what, nupp_reload_open(*runtime, &reloading, reload, &error), error);
}

int main(int argc, char **argv) {
    nupp_runtime *owner = NULL, *first = NULL, *second = NULL;
    nupp_reload *reload = NULL;
    nupp_error *error = NULL;
    FILE *entry;
    char path[2048];

    if (argc != 4) return 2;
    snprintf(path, sizeof path, "%s/%s", argv[2], argv[3]);
    entry = fopen(path, "wb");
    if (!entry) return 2;
    fputs("local function update(): integer\n    return 1\nend\n\nreturn {update = update}\n", entry);
    fclose(entry);
    if (report("runtime", nupp_runtime_new(NULL, &owner, &error), error)) return 1;
    if (open_attached(owner, argv, &first, &reload, "first open")) return 1;
    error = NULL;
    if (report("first shutdown", nupp_runtime_shutdown(first, &error), error)) return 1;
    nupp_reload_free(reload);
    nupp_runtime_free(first);
    if (open_attached(owner, argv, &second, &reload, "second open")) return 1;
    printf("reopened\n");
    error = NULL;
    nupp_reload_close(second, reload, 1, &error);
    nupp_error_free(error);
    nupp_reload_free(reload);
    nupp_runtime_free(second);
    nupp_runtime_free(owner);
    return 0;
}
]]

function M.anAttachedShutdownClosesTheSessionItLeftOpen()
    local compilerModules = ROOT .. "/build"
    local present = io.open(compilerModules .. "/nupp/tools/hostreload.lua", "rb")
    if not present then
        test.skip("hot reload needs the compiler's Lua modules under build/")
    end
    present:close()
    local directory, library = temporary(), sdk()
    local project = directory .. "/project"
    assert(os.execute("mkdir -p " .. quote(project)) == 0)
    local source = directory .. "/reopen.c"
    write(source, REOPEN_DRIVER)
    local executable = directory .. "/reopen"
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
    assert(status == 0 and output:find("reopened", 1, true), output)
end

-- The plan's own acceptance case, in C: a loaded component, a callable retained
-- across the edit, an update prepared away from the safe point and applied at one,
-- and module state that outlives the commit.
local ATTACH_DRIVER = [[
#include "nupp.h"
#include <stdio.h>
#include <stdlib.h>

static int failed = 0;

static int report(const char *what, nupp_status status, nupp_error *error) {
    if (status == NUPP_STATUS_OK) return 0;
    fprintf(stderr, "%s: %s\n", what, error ? nupp_error_message(error) : "unknown error");
    nupp_error_free(error);
    failed = 1;
    return 1;
}

static unsigned char *read_all(const char *path, size_t *length) {
    FILE *file = fopen(path, "rb");
    long end;
    unsigned char *bytes;
    if (!file) return NULL;
    if (fseek(file, 0, SEEK_END) != 0 || (end = ftell(file)) < 0) { fclose(file); return NULL; }
    fseek(file, 0, SEEK_SET);
    bytes = (unsigned char *)malloc((size_t)end);
    if (!bytes || fread(bytes, 1, (size_t)end, file) != (size_t)end) { free(bytes); fclose(file); return NULL; }
    fclose(file);
    *length = (size_t)end;
    return bytes;
}

/* The whole module each time: an edit a reload accepts changes a body, and the
 * structural variant adds a module-level binding, which it does not. */
static void write_source(const char *path, int increment, int structural) {
    FILE *file = fopen(path, "wb");
    fprintf(file, "module game\n\nlocal game = {}\n\nlocal calls: integer = 0\n\n");
    if (structural) fprintf(file, "local added: integer = 7\n\n");
    fprintf(file, "function game.answer(value: number): number\n    calls = calls + 1\n    return value + %d\nend\n\n", increment);
    fprintf(file, "function game.calls(): number\n    return calls\nend\n\nexport = game\n");
    fclose(file);
}

static double call(nupp_runtime *runtime, nupp_handle *callable, double value, int pass) {
    nupp_value argument = {0};
    nupp_value result = {0};
    nupp_error *error = NULL;
    size_t count = 0;
    argument.kind = NUPP_VALUE_NUMBER;
    argument.number = value;
    if (report("call", nupp_call(runtime, callable, pass ? &argument : NULL, pass ? 1 : 0,
            &result, 1, &count, &error), error)) {
        return -1.0;
    }
    return count == 1 && result.kind == NUPP_VALUE_NUMBER ? result.number : -1.0;
}

int main(int argc, char **argv) {
    nupp_runtime *runtime = NULL;
    nupp_component *component = NULL;
    nupp_reload *reload = NULL;
    nupp_handle *answer = NULL;
    nupp_handle *calls = NULL;
    nupp_error *error = NULL;
    nupp_config config;
    nupp_reload_config reloading;
    uint32_t verdict = 0;
    uint64_t generation = 0;
    size_t length = 0;
    unsigned char *bytes;
    char source[2048];

    if (argc != 5) { fprintf(stderr, "usage: attach COMPILER PROJECT SOURCE COMPONENT\n"); return 2; }
    snprintf(source, sizeof source, "%s", argv[3]);
    bytes = read_all(argv[4], &length);
    if (!bytes) { fprintf(stderr, "cannot read %s\n", argv[4]); return 2; }

    nupp_config_init(&config);
    if (report("runtime", nupp_runtime_new(&config, &runtime, &error), error)) return 1;
    error = NULL;
    if (report("load", nupp_component_load(runtime, bytes, length, argv[4], &component, &error), error)) return 1;
    error = NULL;
    if (report("answer", nupp_export_find(runtime, component, "game.answer", &answer, &error), error)) return 1;
    error = NULL;
    if (report("calls", nupp_export_find(runtime, component, "game.calls", &calls, &error), error)) return 1;

    printf("before = %.0f\n", call(runtime, answer, 41.0, 1));
    printf("calls before = %.0f\n", call(runtime, calls, 0.0, 0));

    nupp_reload_config_init(&reloading);
    reloading.compiler_path = argv[1];
    reloading.root = argv[2];
    error = NULL;
    if (report("attach", nupp_reload_attach(runtime, &reloading, &reload, &error), error)) return 1;

    write_source(source, 5, 0);
    error = NULL;
    if (report("prepare", nupp_reload_prepare(runtime, reload, &verdict, &generation, &error), error)) return 1;
    printf("prepared verdict = %u generation = %llu\n", verdict, (unsigned long long)generation);
    printf("during = %.0f\n", call(runtime, answer, 41.0, 1));

    error = NULL;
    if (report("apply", nupp_reload_apply(runtime, reload, &verdict, &generation, &error), error)) return 1;
    printf("applied verdict = %u generation = %llu\n", verdict, (unsigned long long)generation);
    printf("after = %.0f\n", call(runtime, answer, 41.0, 1));
    printf("calls after = %.0f\n", call(runtime, calls, 0.0, 0));

    error = NULL;
    if (report("reapply", nupp_reload_apply(runtime, reload, &verdict, &generation, &error), error)) return 1;
    printf("reapplied verdict = %u generation = %llu\n", verdict, (unsigned long long)generation);

    /* A second prepare replaces the first: the newer edit is the one the program
     * is about to be asked for. */
    write_source(source, 6, 0);
    error = NULL;
    if (report("prepare-again", nupp_reload_prepare(runtime, reload, &verdict, &generation, &error), error)) return 1;
    printf("first staged verdict = %u\n", verdict);
    write_source(source, 7, 0);
    error = NULL;
    if (report("prepare-newer", nupp_reload_prepare(runtime, reload, &verdict, &generation, &error), error)) return 1;
    error = NULL;
    if (report("apply-newer", nupp_reload_apply(runtime, reload, &verdict, &generation, &error), error)) return 1;
    printf("superseded = %.0f\n", call(runtime, answer, 41.0, 1));

    /* An edit that does not check leaves the running generation alone. */
    {
        FILE *broken = fopen(source, "wb");
        fprintf(broken, "module game\n\nlocal game = {}\n\nlocal calls: integer = 0\n\n"
            "function game.answer(value: number): number\n    calls = calls + 1\n    return \"seven\"\nend\n\n"
            "function game.calls(): number\n    return calls\nend\n\nexport = game\n");
        fclose(broken);
    }
    error = NULL;
    if (report("rejected", nupp_reload_poll(runtime, reload, &verdict, &generation, &error), error)) return 1;
    printf("rejected verdict = %u generation = %llu\n", verdict, (unsigned long long)generation);
    if (nupp_reload_message(reload)) printf("rejected message = %s\n", nupp_reload_message(reload));
    printf("rejected keeps = %.0f\n", call(runtime, answer, 41.0, 1));

    write_source(source, 7, 1);
    error = NULL;
    if (report("structural", nupp_reload_poll(runtime, reload, &verdict, &generation, &error), error)) return 1;
    printf("structural verdict = %u generation = %llu\n", verdict, (unsigned long long)generation);
    if (nupp_reload_message(reload)) printf("structural message = %s\n", nupp_reload_message(reload));
    printf("still = %.0f\n", call(runtime, answer, 41.0, 1));

    error = NULL;
    if (report("close", nupp_reload_close(runtime, reload, 1, &error), error)) return 1;
    /* A closed session answers rather than acting. */
    error = NULL;
    if (nupp_reload_prepare(runtime, reload, &verdict, &generation, &error) == NUPP_STATUS_OK) {
        fprintf(stderr, "a closed session still prepared\n");
        failed = 1;
    }
    printf("closed says = %s\n", error ? nupp_error_message(error) : "nothing");
    nupp_error_free(error);
    nupp_reload_free(reload);
    error = NULL;
    nupp_handle_release(runtime, answer, &error);
    nupp_error_free(error);
    error = NULL;
    nupp_handle_release(runtime, calls, &error);
    nupp_error_free(error);
    nupp_component_release(component);
    error = NULL;
    if (report("shutdown", nupp_runtime_shutdown(runtime, &error), error)) return 1;
    nupp_runtime_free(runtime);
    free(bytes);
    return failed;
}
]]

local RELOAD_COMPONENT_MANIFEST = [[
return {
    include = {"src"},
    build = {
        kind = "component",
        description = "A component built for development hot reload",
        entries = {"game"},
        exports = {"game.answer", "game.calls"},
        reload = true,
    },
}
]]

local RELOAD_COMPONENT_SOURCE = [[
module game

local game = {}

local calls: integer = 0

function game.answer(value: number): number
    calls = calls + 1
    return value + 1
end

function game.calls(): number
    return calls
end

export = game
]]

function M.hotReloadAttachesToALoadedComponent()
    local compilerModules = ROOT .. "/build"
    local present = io.open(compilerModules .. "/nupp/tools/hostreload.lua", "rb")
    if not present then
        test.skip("hot reload needs the compiler's Lua modules under build/")
    end
    present:close()
    local directory, library = temporary(), sdk()
    local project = directory .. "/project"
    assert(os.execute("mkdir -p " .. quote(project .. "/src")) == 0)
    write(project .. "/nupp.lua", RELOAD_COMPONENT_MANIFEST)
    write(project .. "/src/game.nupp", RELOAD_COMPONENT_SOURCE)
    local status, output = run(
        ("cd %s && %s build"):format(quote(project), quote(ROOT .. "/bin/nupp"))
    )
    assert(status == 0, output)
    local component = project .. "/build/component.nuppc"
    assert(io.open(component, "rb"), "the reload target writes a component: " .. output)

    local source = directory .. "/attach.c"
    write(source, ATTACH_DRIVER)
    local executable = directory .. "/attach"
    if jit.os == "Windows" then
        executable = executable .. ".exe"
    end
    status, output = run(
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
        ("%s %s %s %s %s"):format(
            quote(executable),
            quote(compilerModules),
            quote(project),
            quote(project .. "/src/game.nupp"),
            quote(component)
        )
    )
    assert(status == 0, output)
    -- Applied, and only where the host asked for it.
    assert(output:find("before = 42", 1, true), output)
    assert(output:find("prepared verdict = 4 generation = 1", 1, true), output)
    assert(output:find("during = 42", 1, true), output)
    assert(output:find("applied verdict = 1 generation = 2", 1, true), output)
    assert(output:find("after = 46", 1, true), output)
    -- The captured counter kept counting across the commit.
    assert(output:find("calls before = 1", 1, true), output)
    assert(output:find("calls after = 3", 1, true), output)
    -- Nothing was left staged, and a structural edit stays out of the process.
    assert(output:find("reapplied verdict = 0", 1, true), output)
    assert(output:find("superseded = 48", 1, true), output)
    assert(output:find("rejected verdict = 2 generation = 3", 1, true), output)
    assert(output:find("rejected keeps = 48", 1, true), output)
    assert(output:find("structural verdict = 3 generation = 3", 1, true), output)
    assert(output:find("NUPP5001", 1, true), output)
    assert(output:find("still = 48", 1, true), output)
    assert(output:find("closed says = ", 1, true), output)
end

-- One export, called from C through the static SDK, that hands naga a SPIR-V
-- module it panics on. The provider catches the panic at its export and answers
-- a status, the export raises it, and nupp_call reports it: the host lives on to
-- make another call. A machine with no adapter has nothing to show.
local PANIC_COMPONENT = [[-- NUPP-COMPONENT 1
return {
  format = 1,
  hostAbi = 1,
  install = function()
    local ffi = require("ffi")
    ffi.cdef("int32_t nuppNativeGpuContextCreate(uint64_t *);"
      .. "int32_t nuppNativeGpuKernelCreate(uint64_t, const uint8_t *, size_t, const char *, size_t,"
      .. " uint32_t, uint32_t, uint64_t, uint32_t, uint32_t, uint32_t, uint64_t *);"
      .. "const char *nuppNativeLastError(void);")
    local function kernel(spirv)
      local context = ffi.new("uint64_t[1]")
      local status = ffi.C.nuppNativeGpuContextCreate(context)
      if status == 8 then
        return "unavailable"
      end
      assert(status == 0, ffi.string(ffi.C.nuppNativeLastError()))
      local output = ffi.new("uint64_t[1]")
      status = ffi.C.nuppNativeGpuKernelCreate(context[0], spirv, #spirv, "main", 4, 1, 1, 16, 64, 1, 1, output)
      error(("status %d: %s"):format(status, ffi.string(ffi.C.nuppNativeLastError())))
    end
    return {exports = {["gpu.kernel"] = kernel, ["gpu.after"] = function() return "alive" end}, start = function() end}
  end,
}
]]

local PANIC_DRIVER = [[
#include "nupp.h"
#include <stdio.h>
#include <stdlib.h>

static unsigned char *read_all(const char *path, size_t *length) {
    FILE *file = fopen(path, "rb");
    long end;
    unsigned char *bytes;
    if (!file || fseek(file, 0, SEEK_END) != 0 || (end = ftell(file)) < 0 || fseek(file, 0, SEEK_SET) != 0) return NULL;
    bytes = (unsigned char *)malloc((size_t)end + 1);
    if (!bytes || fread(bytes, 1, (size_t)end, file) != (size_t)end) return NULL;
    fclose(file);
    *length = (size_t)end;
    return bytes;
}

static void print_value(const char *label, const nupp_value *value) {
    printf("%s = %.*s\n", label, (int)value->length, value->data ? (const char *)value->data : "");
}

int main(int argc, char **argv) {
    nupp_runtime *runtime = NULL;
    nupp_component *component = NULL;
    nupp_handle *kernel = NULL, *after = NULL;
    nupp_error *error = NULL;
    nupp_value argument = {0}, result = {0};
    size_t count = 0, length = 0, spirv_length = 0;
    unsigned char *bytes, *spirv;
    nupp_status status;

    if (argc != 3 || !(bytes = read_all(argv[1], &length)) || !(spirv = read_all(argv[2], &spirv_length))) return 2;
    if (nupp_runtime_new(NULL, &runtime, &error) != NUPP_STATUS_OK) return 1;
    if (nupp_component_load(runtime, bytes, length, argv[1], &component, &error) != NUPP_STATUS_OK) return 1;
    if (nupp_export_find(runtime, component, "gpu.kernel", &kernel, &error) != NUPP_STATUS_OK) return 1;
    if (nupp_export_find(runtime, component, "gpu.after", &after, &error) != NUPP_STATUS_OK) return 1;
    argument.kind = NUPP_VALUE_BYTES;
    argument.data = spirv;
    argument.length = spirv_length;
    status = nupp_call(runtime, kernel, &argument, 1, &result, 1, &count, &error);
    if (status == NUPP_STATUS_OK) {
        print_value("kernel", &result);
        nupp_value_release(runtime, &result, NULL);
    } else {
        printf("kernel status = %d\nkernel message = %s\n", (int)status, error ? nupp_error_message(error) : "");
        nupp_error_free(error);
    }
    error = NULL;
    if (nupp_call(runtime, after, NULL, 0, &result, 1, &count, &error) != NUPP_STATUS_OK) return 1;
    print_value("after", &result);
    nupp_value_release(runtime, &result, NULL);
    nupp_handle_release(runtime, kernel, NULL);
    nupp_handle_release(runtime, after, NULL);
    nupp_component_release(component);
    nupp_runtime_shutdown(runtime, NULL);
    nupp_runtime_free(runtime);
    return 0;
}
]]

function M.aNativePanicUnderACallAnswersAStatus()
    local directory, library = temporary(), sdk()
    local component = directory .. "/panic.nuppc"
    write(component, PANIC_COMPONENT)
    local source = directory .. "/panic.c"
    write(source, PANIC_DRIVER)
    local executable = directory .. "/panic"
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
        ("%s %s %s"):format(
            quote(executable),
            quote(component),
            quote(ROOT .. "/native/crates/native/testdata/naga-panic.spv")
        )
    )
    assert(status == 0, output)
    if output:find("kernel = unavailable", 1, true) then
        test.skip("no GPU adapter to hand the malformed module to")
    end
    assert(output:find("kernel status = 3", 1, true), output)
    assert(output:find("status 5: native provider panicked", 1, true), output)
    assert(output:find("after = alive", 1, true), output)
end

-- The symbols host/include/nupp.exports names for FEATURES: every `always`
-- section and every section naming one of them. The LuaJIT version symbol is
-- the one entry spelled by its macro, since its name moves with the pin.
local function committedExports()
    local enabled = {always = true}
    for feature in FEATURES:gmatch("[^,]+") do
        enabled[feature] = true
    end
    local file = assert(io.open(ROOT .. "/host/include/nupp.exports", "rb"))
    local names, applies = {}, false
    for line in file:lines() do
        line = line:match("^%s*(.-)%s*$")
        local section = line:match("^%[(.*)%]$")
        if section then
            applies = false
            for feature in section:gmatch("%S+") do
                applies = applies or enabled[feature] == true
            end
        elseif applies and line ~= "" and not line:find("^#") then
            names[line] = true
        end
    end
    file:close()
    return names
end

-- The dynamic library exports exactly the committed list: the embedding API,
-- the native provider, and LuaJIT's C API, which a host using the state
-- nupp_runtime_lua_state returns, or a compiled module, finds by name.
function M.theDynamicSdkExportsTheCommittedList()
    local exports
    if jit.os == "OSX" then
        exports = "nm -gU " .. quote(sdk() .. "/libnupp.dylib")
    elseif jit.os == "Linux" then
        exports = "nm -D --defined-only " .. quote(sdk() .. "/libnupp.so")
    else
        test.skip("reads the export table with nm")
    end
    local status, output = run(exports)
    assert(status == 0, output)
    local expected, found, unexpected = committedExports(), {}, {}
    for name in output:gmatch("%S+%s+%a%s+_?([%w_]+)") do
        if name:find("^luaJIT_version_") then
            found.LUAJIT_VERSION_SYM = true
        elseif expected[name] then
            found[name] = true
        elseif not name:find("^_") then
            -- Objective-C class records the GPU backend registers begin with
            -- an underscore of their own; nothing else may appear.
            unexpected[#unexpected + 1] = name
        end
    end
    local missing = {}
    for name in pairs(expected) do
        if not found[name] then
            missing[#missing + 1] = name
        end
    end
    table.sort(missing)
    table.sort(unexpected)
    assert(#missing == 0, "the dynamic SDK does not export: " .. table.concat(missing, ", "))
    assert(#unexpected == 0, "the dynamic SDK exports what the list does not name: " .. table.concat(unexpected, ", "))
end

local AOT_COMPONENT_MANIFEST = [[
return {
    include = {"src"},
    build = {
        kind = "component",
        description = "A component whose export is a compiled Lua builder",
        entries = {"game"},
        exports = {"game.label"},
        aot = "require",
    },
}
]]

local AOT_COMPONENT_SOURCE = [[
module game

@aot
local function label(flag: boolean): string
    return flag and "compiled" or "fallback"
end

export = {label = label}
]]

local AOT_DRIVER = [[
#include "nupp.h"
#include <stdio.h>
#include <stdlib.h>

static int report(const char *what, nupp_status status, nupp_error *error) {
    if (status == NUPP_STATUS_OK) return 0;
    fprintf(stderr, "%s: %s\n", what, error ? nupp_error_message(error) : "unknown error");
    nupp_error_free(error);
    return 1;
}

static unsigned char *read_all(const char *path, size_t *length) {
    FILE *file = fopen(path, "rb");
    long end;
    unsigned char *bytes;
    if (!file || fseek(file, 0, SEEK_END) != 0 || (end = ftell(file)) < 0 || fseek(file, 0, SEEK_SET) != 0) return NULL;
    bytes = (unsigned char *)malloc((size_t)end + 1);
    if (!bytes || fread(bytes, 1, (size_t)end, file) != (size_t)end) return NULL;
    fclose(file);
    *length = (size_t)end;
    return bytes;
}

int main(int argc, char **argv) {
    nupp_runtime *runtime = NULL;
    nupp_component *component = NULL;
    nupp_handle *label = NULL;
    nupp_error *error = NULL;
    nupp_value argument = {0}, result = {0};
    size_t count = 0, length = 0;
    unsigned char *bytes;

    if (argc != 2 || !(bytes = read_all(argv[1], &length))) return 2;
    if (report("runtime", nupp_runtime_new(NULL, &runtime, &error), error)) return 1;
    if (report("load", nupp_component_load(runtime, bytes, length, argv[1], &component, &error), error)) return 1;
    if (report("find", nupp_export_find(runtime, component, "game.label", &label, &error), error)) return 1;
    argument.kind = NUPP_VALUE_BOOLEAN;
    argument.boolean = 1;
    if (report("call", nupp_call(runtime, label, &argument, 1, &result, 1, &count, &error), error)) return 1;
    printf("game.label(true) = %.*s\n", (int)result.length, result.data ? (const char *)result.data : "");
    nupp_value_release(runtime, &result, NULL);
    nupp_handle_release(runtime, label, NULL);
    nupp_component_release(component);
    nupp_runtime_shutdown(runtime, NULL);
    nupp_runtime_free(runtime);
    free(bytes);
    return 0;
}
]]

-- ER-013: a component whose export is a compiled Lua builder, loaded by a host
-- linking the dynamic SDK. The compiled module's registrar finds the Lua API
-- in the process, which it could not while libnupp kept that API to itself:
-- nuppAotRuntime answered null and the component failed at load.
function M.anAotComponentLoadsThroughTheDynamicSdk()
    if jit.os == "Windows" then
        test.skip("links against the dynamic SDK the Unix way")
    end
    local directory, library = temporary(), sdk()
    local project = directory .. "/project"
    assert(os.execute("mkdir -p " .. quote(project .. "/src")) == 0)
    write(project .. "/nupp.lua", AOT_COMPONENT_MANIFEST)
    write(project .. "/src/game.nupp", AOT_COMPONENT_SOURCE)
    local status, output = run(("cd %s && %s build"):format(quote(project), quote(ROOT .. "/bin/nupp")))
    assert(status == 0, output)
    local source = directory .. "/aot.c"
    write(source, AOT_DRIVER)
    local executable = directory .. "/aot"
    status, output = run(
        ("%s -std=c11 -I%s %s -L%s -lnupp -Wl,-rpath,%s -o %s"):format(
            quote(compiler()),
            quote(library),
            quote(source),
            quote(library),
            quote(library),
            quote(executable)
        )
    )
    assert(status == 0, output)
    -- The compiled library travels with the component, and the component looks
    -- for it from where it runs.
    status, output = run(("cd %s && %s component.nuppc"):format(quote(project .. "/build"), quote(executable)))
    assert(status == 0, output)
    assert(output:find("game.label(true) = compiled", 1, true), output)
end

local POLL_COMPONENT_MANIFEST = [[
return {
    include = {"src"},
    build = {
        kind = "component",
        description = "A component with a readiness source only a poll advances",
        entries = {"clock"},
        exports = {"clock.fired", "clock.arm"},
    },
}
]]

-- A timer as a readiness source: armed for a number of ticks, it counts one
-- down on each pass and fires when none are left. Nothing but a poll runs it.
local POLL_COMPONENT_SOURCE = [[
module clock

local suspension = require("nupp.suspension")

local remaining: integer = 0
local count: integer = 0

suspension.source("clock.timer", 10, function(): integer
    if remaining == 0 then
        return 0
    end
    remaining = remaining - 1
    if remaining == 0 then
        count = count + 1
        return 1
    end
    return 0
end)

export function arm(ticks: integer): nil
    remaining = ticks
end

export function fired(): integer
    return count
end
]]

local POLL_DRIVER = [[
#include "nupp.h"
#include <stdio.h>
#include <stdlib.h>

static unsigned char *read_all(const char *path, size_t *length) {
    FILE *file = fopen(path, "rb");
    long end;
    unsigned char *bytes;
    if (!file || fseek(file, 0, SEEK_END) != 0 || (end = ftell(file)) < 0 || fseek(file, 0, SEEK_SET) != 0) return NULL;
    bytes = (unsigned char *)malloc((size_t)end + 1);
    if (!bytes || fread(bytes, 1, (size_t)end, file) != (size_t)end) return NULL;
    fclose(file);
    *length = (size_t)end;
    return bytes;
}

static double fired(nupp_runtime *runtime, nupp_handle *handle) {
    nupp_value result = {0};
    size_t count = 0;
    if (nupp_call(runtime, handle, NULL, 0, &result, 1, &count, NULL) != NUPP_STATUS_OK) return -1;
    return result.number;
}

int main(int argc, char **argv) {
    nupp_runtime *runtime = NULL;
    nupp_component *component = NULL;
    nupp_handle *arm = NULL, *fire = NULL;
    nupp_error *error = NULL;
    nupp_value ticks = {0}, result = {0};
    size_t count = 0, length = 0;
    unsigned char *bytes;
    int pass;

    if (argc != 2 || !(bytes = read_all(argv[1], &length))) return 2;
    if (nupp_runtime_new(NULL, &runtime, &error) != NUPP_STATUS_OK) return 1;
    /* Nothing has loaded nupp.suspension yet, so there is nothing to drive. */
    if (nupp_runtime_poll(runtime, &error) != NUPP_STATUS_OK) return 1;
    if (nupp_component_load(runtime, bytes, length, argv[1], &component, &error) != NUPP_STATUS_OK) return 1;
    if (nupp_export_find(runtime, component, "clock.arm", &arm, &error) != NUPP_STATUS_OK) return 1;
    if (nupp_export_find(runtime, component, "clock.fired", &fire, &error) != NUPP_STATUS_OK) return 1;
    ticks.kind = NUPP_VALUE_NUMBER;
    ticks.number = 3;
    if (nupp_call(runtime, arm, &ticks, 1, &result, 1, &count, &error) != NUPP_STATUS_OK) return 1;
    printf("armed fired = %.0f\n", fired(runtime, fire));
    for (pass = 1; pass <= 3; ++pass) {
        if (nupp_runtime_poll(runtime, &error) != NUPP_STATUS_OK) {
            fprintf(stderr, "poll: %s\n", error ? nupp_error_message(error) : "");
            return 1;
        }
        printf("pass %d fired = %.0f\n", pass, fired(runtime, fire));
    }
    nupp_handle_release(runtime, arm, NULL);
    nupp_handle_release(runtime, fire, NULL);
    nupp_component_release(component);
    nupp_runtime_shutdown(runtime, NULL);
    nupp_runtime_free(runtime);
    free(bytes);
    return 0;
}
]]

-- D-28: a host that owns its event loop advances the state's readiness sources
-- by calling nupp_runtime_poll, one non-blocking pass each time.
function M.aRuntimePollAdvancesATimerSource()
    local directory, library = temporary(), sdk()
    local project = directory .. "/project"
    assert(os.execute("mkdir -p " .. quote(project .. "/src")) == 0)
    write(project .. "/nupp.lua", POLL_COMPONENT_MANIFEST)
    write(project .. "/src/clock.nupp", POLL_COMPONENT_SOURCE)
    local status, output = run(("cd %s && %s build"):format(quote(project), quote(ROOT .. "/bin/nupp")))
    assert(status == 0, output)
    local source = directory .. "/poll.c"
    write(source, POLL_DRIVER)
    local executable = directory .. "/poll"
    if jit.os == "Windows" then
        executable = executable .. ".exe"
    end
    status, output = run(
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
    status, output = run(quote(executable) .. " " .. quote(project .. "/build/component.nuppc"))
    assert(status == 0, output)
    assert(output:find("armed fired = 0", 1, true), output)
    assert(output:find("pass 2 fired = 0", 1, true), output)
    assert(output:find("pass 3 fired = 1", 1, true), output)
end

return M
