-- The JIT's emitter: guest bytecode lowered to CLIF by
-- `nupp.compiler.clif.guest` and run just in time by the glue
-- (`nupp-vm native jit`) against a fake frame, each answer compared with the
-- interpreter's for the same function and arguments; and what the emitter
-- refuses. The glue is `nupp-vm` built with its code generator, which
-- `scripts/vm-cli glue` builds into the shared target directory and names.
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."
local FIXTURES = "tests/fixtures/nativejit"

local guest = require("nupp.compiler.clif.guest")
local project = require("nupp.tools.vm.project")

local M = {}

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function capture(command)
    local pipe = assert(io.popen(command .. " 2>&1; echo __exit__:$?"))
    local output = pipe:read("*a")
    pipe:close()
    local status = tonumber(output:match("__exit__:(%d+)%s*$"))
    return status, (output:gsub("__exit__:%d+%s*$", ""))
end

-- A runtime's answer: its standard output alone, since the runner reports
-- timings and the JIT its decisions on standard error, which is kept for a
-- failure's message.
local function answer(command)
    local errors = os.tmpname()
    local status, output = capture("( " .. command .. " 2>" .. quote(errors) .. " )")
    local file = io.open(errors, "rb")
    local reported = file and file:read("*a") or ""
    if file then
        file:close()
    end
    os.remove(errors)
    return status, output, reported
end

local glue = nil

local function glueTool()
    if not glue then
        local status, output = capture(("cd %s && python3 scripts/vm-cli glue"):format(quote(ROOT)))
        assert(status == 0, "scripts/vm-cli glue failed: " .. output)
        glue = assert(output:match("([^\r\n]+)%s*$"), "scripts/vm-cli glue named no tool")
    end
    return glue
end

local function tempDirectory()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. quote(dir)) == 0)
    return dir
end

local function write(path, text)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local function read(path)
    local file = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = file:read("*a")
    file:close()
    return text
end

local layoutFn = nil

local function layouts()
    if not layoutFn then
        local path = tempDirectory() .. "/layouts.json"
        local status, output = capture(("%s native layouts %s"):format(quote(glueTool()), quote(path)))
        assert(status == 0, "native layouts failed: " .. output)
        local measured = guest.layoutsFrom(read(path))
        -- The glue adds the context's interpreter pointer when it drives the
        -- emitter; the glue's layout table does not list it, and it is the
        -- context's first word.
        layoutFn = function(field)
            if field == "interp" then
                return 0
            end
            return measured(field)
        end
    end
    return layoutFn
end

-- The corpus image, emitted once: the path it is written to for the
-- interpreter, and its functions by name as the glue describes them to the
-- emitter (`nupp-vm native describe`), which is the text the JIT hands over.
local corpus = nil

local function corpusImage()
    if not corpus then
        local image = project.emit(ROOT, "corpus", "", FIXTURES)
        local path = tempDirectory() .. "/corpus.image"
        write(path, image)
        local status, described = capture(("%s native describe %s"):format(quote(glueTool()), quote(path)))
        assert(status == 0, "native describe failed: " .. described)
        corpus = {path = path, functions = guest.functions(described)}
    end
    return corpus
end

local function functionNamed(name)
    local functions = corpusImage().functions
    local text = functions["corpus." .. name] or functions[name]
    if not text then
        local names = {}
        for known in pairs(functions) do
            names[#names + 1] = known
        end
        table.sort(names)
        error("the corpus has no function " .. name .. "; it has " .. table.concat(names, " "), 2)
    end
    return guest.parse(text)
end

-- The interpreter's answer: the glue runtime running the image.
local function interpret(name, args)
    local words = {}
    for index, arg in ipairs(args) do
        words[index] = quote(arg)
    end
    local status, output, reported = answer(("NO_JIT=1 %s run %s corpus %s %s"):format(
        quote(glueTool()), quote(corpusImage().path), quote(name), table.concat(words, " ")))
    assert(status == 0, ("interpreter %s(%s): %s%s"):format(name, table.concat(args, ", "), output, reported))
    return (output:match("^([^\r\n]*)"))
end

-- A runtime with the code generator and the native core, which drives guest
-- entries: `scripts/vm-cli runtime --link` builds it and the emitter image
-- is emitted from these sources, so the whole JIT path runs from the tree.
local jit = nil

local function jitRuntime()
    if not jit then
        local status, output = capture(("cd %s && python3 scripts/vm-cli runtime --link"):format(quote(ROOT)))
        assert(status == 0, "scripts/vm-cli runtime --link failed: " .. output)
        local runtime = assert(output:match("([^\r\n]+)%s*$"), "scripts/vm-cli runtime named no runtime")
        local extras = "nupp.compiler.hostservices,nupp.compiler.fs,nupp.compiler.project.projectconfig,"
            .. "nupp.compiler.project.store,nupp.compiler.project.fingerprint,nupp.compiler.hash,"
            .. "nupp.compiler.project.preludecache,nupp.runtime.provider.nativeprocess,"
            .. "nupp.runtime.provider.nativepath,nupp.runtime.provider.nativefiles"
        local image = tempDirectory() .. "/guest.image"
        write(image, project.emit(ROOT, "nupp.compiler.clif.guest", extras, "src"))
        jit = {runtime = runtime, image = image}
    end
    return jit
end

-- The answer of the JIT runtime in guest mode: every function compiled at
-- its first entry, on the compiler thread or in line, under the scheduler or
-- a plain call.
local function compiledRun(name, args, background, tasks)
    local words = {}
    for index, arg in ipairs(args) do
        words[index] = quote(arg)
    end
    local runtime = jitRuntime()
    local status, output, reported = answer(("NUPP_JIT_IMAGE=%s JIT_FRAME_THRESHOLD=1 JIT_BACKGROUND=%d %s run %s corpus %s %s %s"):format(
        quote(runtime.image), background and 1 or 0, quote(runtime.runtime), quote(corpusImage().path), quote(name),
        table.concat(words, " "), tasks and "--tasks" or ""))
    assert(status == 0, ("guest %s(%s): %s%s"):format(name, table.concat(args, ", "), output, reported))
    return (output:match("^([^\r\n]*)"))
end

local compiled = {}

-- The CLIF of a function with its harness, written once per function.
local function compiledFile(name)
    if not compiled[name] then
        local fn = functionNamed(name)
        local clif, reason = guest.emit(fn, layouts(), {nested = 0})
        assert(clif, name .. ": the emitter refused it: " .. tostring(reason))
        local path = tempDirectory() .. "/" .. name .. ".clif"
        write(path, guest.harness(fn, clif, layouts()))
        compiled[name] = {path = path, fid = fn.fid}
    end
    return compiled[name]
end

-- The compiled answer, as the harness's f64 or i64 word.
local function run(name, args, asWord)
    local entry = compiledFile(name)
    local words = {}
    for index, arg in ipairs(args) do
        words[index] = quote(arg)
    end
    local harness = (asWord and "word_" or "run_") .. tostring(entry.fid)
    local status, output = capture(("%s native jit %s %s %s"):format(
        quote(glueTool()), quote(entry.path), quote(harness), table.concat(words, " ")))
    assert(status == 0, ("compiled %s(%s): %s"):format(name, table.concat(args, ", "), output))
    return (output:gsub("%s+$", ""))
end

local TRUE = "9221964661971222528"
local FALSE = "9221683186994511872"

-- {function, arguments}: numbers compared as numbers, booleans as words.
local NUMERIC = {
    {"sum", {0}}, {"sum", {100}}, {"sum", {1000}},
    {"collatz", {27}}, {"collatz", {1}}, {"collatz", {97}},
    {"nested", {10}}, {"nested", {0}}, {"nested", {25}},
    {"clamp", {0.5, 0, 1}}, {"clamp", {-3.25, 0, 1}}, {"clamp", {7, 0, 1}},
    {"mean", {1, 2}}, {"mean", {-1, 0}},
    {"floorMod", {7, 3}}, {"floorMod", {-7, 3}}, {"floorMod", {7, -3}}, {"floorMod", {5.5, 2}},
    {"scaled", {2}}, {"scaled", {0}},
    {"countdown", {5}}, {"countdown", {0}},
    {"firstSquareAbove", {50}}, {"firstSquareAbove", {0}},
}

local BOOLEAN = {
    {"between", {5, 1, 10}}, {"between", {0, 1, 10}}, {"between", {10, 1, 10}},
    {"same", {1, 1}}, {"same", {1, 2}}, {"same", {0, -0}},
    {"differ", {1, 1}}, {"differ", {1, 2}},
}

function M.numericFunctionsAnswerAsTheInterpreterDoes()
    for _, case in ipairs(NUMERIC) do
        local name, args = case[1], case[2]
        local expected = tonumber(interpret(name, args))
        local got = tonumber(run(name, args, false))
        local label = ("%s(%s)"):format(name, table.concat(args, ", "))
        assert(expected ~= nil, label .. ": the interpreter answered no number")
        assert(got == expected, label .. ": interpreter " .. tostring(expected) .. ", compiled " .. tostring(got))
    end
end

function M.booleanFunctionsAnswerAsTheInterpreterDoes()
    for _, case in ipairs(BOOLEAN) do
        local name, args = case[1], case[2]
        local expected = interpret(name, args)
        local got = run(name, args, true)
        local label = ("%s(%s)"):format(name, table.concat(args, ", "))
        local want = expected == "true" and TRUE or (expected == "false" and FALSE or nil)
        assert(want, label .. ": the interpreter answered " .. expected)
        assert(got == want, label .. ": interpreter " .. expected .. ", compiled word " .. got)
    end
end

-- Every corpus function, called as the runner calls it: through the frame
-- driver, with calls nested natively where the callee has an entry and
-- handed to the interpreter where it does not.
local GUEST = {
    {"sum", {1000}}, {"collatz", {97}}, {"nested", {25}}, {"clamp", {7, 0, 1}}, {"between", {5, 1, 10}},
    {"mean", {1, 2}}, {"floorMod", {-7, 3}}, {"scaled", {2}}, {"same", {1, 2}}, {"differ", {1, 2}},
    {"countdown", {5}}, {"firstSquareAbove", {50}},
    {"fibonacci", {20}}, {"viaHelper", {100}}, {"viaClosure", {50}}, {"viaBuiltin", {100}},
    {"concatLoop", {10}}, {"tableSum", {100}}, {"multi", {7}}, {"varargs", {4}}, {"depth", {300}},
    {"fields", {1000}},
}

function M.theJitRuntimeAnswersAsTheInterpreterDoesInGuestMode()
    for _, case in ipairs(GUEST) do
        local name, args = case[1], case[2]
        local expected = interpret(name, args)
        local label = ("%s(%s)"):format(name, table.concat(args, ", "))
        local inline = compiledRun(name, args, false, false)
        assert(inline == expected, label .. ": in line, plain call: interpreter " .. expected .. ", compiled " .. inline)
        local scheduled = compiledRun(name, args, true, true)
        assert(scheduled == expected, label .. ": compiler thread, scheduled: interpreter " .. expected .. ", compiled " .. scheduled)
    end
end

function M.theEmitterRefusesVectorCodeAndJumpTables()
    local fn = guest.parse(table.concat({
        "function switched 0 1 4 1 v:v",
        "  table 0 0 1",
        "  IUnbox 0 1",
        "  Switch 0 0",
        "  RetNil",
        "  RetNil",
        "end",
    }, "\n"))
    local clif, reason = guest.emit(fn, layouts(), {nested = 0})
    assert(clif == nil and reason:find("Switch"), "a jump table was accepted: " .. tostring(reason))
    local vectors = guest.parse("function vectors 0 1 4 1 v:v\n  VAdd 0 0 0\n  RetNil\nend\n")
    clif, reason = guest.emit(vectors, layouts(), {nested = 0})
    assert(clif == nil and reason:find("VAdd"), "vector code was accepted: " .. tostring(reason))
end

function M.livenessFollowsTheOpcodeTable()
    local fn = functionNamed("clamp")
    local live = guest.liveness(fn)
    -- The parameters are live at entry, in the value class.
    local atEntry = live.liveAt(0)
    for r = 1, fn.nparams do
        assert(atEntry[r], "parameter " .. r .. " is not live at pc 0")
    end
    -- Nothing is live after the last return.
    local last = #fn.code - 1
    assert(fn.code[last + 1].name:match("^Ret"), "the function ends with a return")
end

return M
