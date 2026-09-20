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
    local present = io.open(compilerModules .. "/nupp/compiler/hostreload.lua", "rb")
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

return M
