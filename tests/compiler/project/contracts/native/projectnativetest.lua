local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local process = fixture.process
local nativeStage = fixture.nativeStage
local fs = fixture.fs
local compilerEnv = fixture.compilerEnv
local tempProject = fixture.tempProject
local remove = fixture.remove

local M = {}

function M.subprocessPreservesEmptyArguments()
    local dir = tempProject({["argv.lua"] = [[io.write(#arg, "|", arg[1], "|", arg[2])]],})
    local status, output = process.capture({"luajit", dir .. "/argv.lua", "", "tail"})
    remove(dir)
    testAssert.eq(status, 0, output)
    testAssert.eq(output, "2||tail", "an empty argv entry reaches the child process")
end

function M.nativeFacilitiesSharingAProviderBuildAsOneUnion()
    local originalCapture, originalCopy = process.capture, fs.copyFile
    local originalCompilerRoot = compilerEnv.compilerRoot
    local calls, copies = {}, {}
    -- The driver answers with the path it built, which is the last line it
    -- writes; anything before that is progress.
    process.capture = function(argv)
        calls[#calls + 1] = argv
        return 0, "/built/libnupp_native.dylib\n"
    end
    fs.copyFile = function(source, destination)
        copies[#copies + 1] = {source, destination}
        return true
    end
    compilerEnv.compilerRoot = function()
        return "."
    end
    local ok, outputs, problem = pcall(nativeStage.build, ".", "out", {["native.path"] = true, ["native.uuid"] = true,})
    process.capture, fs.copyFile = originalCapture, originalCopy
    compilerEnv.compilerRoot = originalCompilerRoot
    assert(ok, outputs)
    assert(outputs, problem)
    testAssert.eq(#calls, 1, "one provider union is built once")
    testAssert.eq(#copies, 2, "the shared library and path runtime are staged")
    local command = "\n" .. table.concat(calls[1], "\n") .. "\n"
    assert(command:find("\nnative%-rust\nfilesystem,uuid\n"), "path and UUID select one sorted Rust feature union")
    testAssert.eq(copies[1][1], "/built/libnupp_native.dylib", "the Rust provider union has one source artifact")
    assert(copies[1][2]:find("out/lib/nupp_native", 1, true), "the Rust provider union keeps its stable sidecar name")
end

function M.gpuOverrideSelectsAHostWithTheProviderLinked()
    local originalCapture = process.capture
    local originalCompilerRoot = compilerEnv.compilerRoot
    local calls = {}
    process.capture = function(argv)
        calls[#calls + 1] = argv
        return 0, "/built/nupp-host\n"
    end
    compilerEnv.compilerRoot = function()
        return "."
    end
    local ok, problem = pcall(function()
        for _, enabled in ipairs({false, true}) do
            local effects = nativeStage.resolve({}, {gpu = enabled})
            local host, err = nativeStage.hostStub(".", "out", {stub = "nupp"}, effects)
            testAssert.eq(host, "/built/nupp-host", err)
        end
    end)
    process.capture = originalCapture
    compilerEnv.compilerRoot = originalCompilerRoot
    assert(ok, problem)
    testAssert.eq(#calls, 2, "each feature union selects its own host")
    testAssert.eq(calls[1][#calls[1]], "", "GPU is absent when disabled")
    testAssert.eq(calls[2][#calls[2]], "native-gpu", "forcing GPU changes the host build and cache key")
end

function M.nativeFacilityCanSelectItsProviderDriver()
    local originalCapture, originalCopy = process.capture, fs.copyFile
    local originalCompilerRoot = compilerEnv.compilerRoot
    local calls, copies = {}, {}
    process.capture = function(argv)
        calls[#calls + 1] = argv
        return 0, "/built/libnupp_native.dylib\n"
    end
    fs.copyFile = function(source, destination)
        copies[#copies + 1] = {source, destination}
        return true
    end
    compilerEnv.compilerRoot = function()
        return "."
    end
    local ok, outputs, problem = pcall(nativeStage.build, ".", "out", {["native.gpu"] = true,})
    process.capture, fs.copyFile = originalCapture, originalCopy
    compilerEnv.compilerRoot = originalCompilerRoot
    assert(ok, outputs)
    assert(outputs, problem)
    testAssert.eq(#calls, 1, "the facility selects one provider build")
    local command = "\n" .. table.concat(calls[1], "\n") .. "\n"
    assert(command:find("\nnative%-rust\n"), "the feature's provider driver is passed to the toolchain")
    assert(command:find("\ngpu\n", 1, true), "the selected driver receives the provider feature union")
    testAssert.eq(copies[1][1], "/built/libnupp_native.dylib")
    assert(copies[1][2]:find("out/lib/nupp_native", 1, true), "the Rust provider has an independent sidecar name")
end

function M.aTargetKeepsTheRuntimeModuleItAlreadyBuilt()
    local originalCopy = fs.copyFile
    local originalCompilerRoot = compilerEnv.compilerRoot
    local copies = {}
    fs.copyFile = function(source, destination)
        copies[#copies + 1] = {source, destination}
        return true
    end
    compilerEnv.compilerRoot = function()
        return "/compiler"
    end
    local output = "/project/out/nupp/suspension.lua"
    local ok, outputs, problem = pcall(nativeStage.build, "/project", "out", {['runtime.suspension'] = true}, nil, {
        [output] = true
    })
    fs.copyFile = originalCopy
    compilerEnv.compilerRoot = originalCompilerRoot
    assert(ok, outputs)
    assert(outputs, problem)
    testAssert.eq(#copies, 0, "native staging preserves the target's generated runtime")
    assert(outputs[output], "the preserved runtime remains a staged output")

    copies = {}
    fs.copyFile = function(source, destination)
        copies[#copies + 1] = {source, destination}
        return true
    end
    compilerEnv.compilerRoot = function()
        return "/compiler"
    end
    ok, outputs, problem = pcall(nativeStage.build, "/project", "out", {['runtime.suspension'] = true})
    fs.copyFile = originalCopy
    compilerEnv.compilerRoot = originalCompilerRoot
    assert(ok, outputs)
    assert(outputs, problem)
    testAssert.eq(#copies, 1, "an application still receives the compiler runtime")
    testAssert.eq(copies[1][1], "/compiler/build/nupp/suspension.lua")
    testAssert.eq(copies[1][2], output)
end

return M
