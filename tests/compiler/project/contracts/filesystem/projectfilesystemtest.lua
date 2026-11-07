local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local process = fixture.process
local fs = fixture.fs
local write = fixture.write
local read = fixture.read
local tempProject = fixture.tempProject
local remove = fixture.remove

local M = {}

function M.canonicalPathsFollowLinksAndKeepMissingOnesObservable()
    local dir = tempProject({["real/file.txt"] = "x\n"})
    local real = fs.canonical(dir .. "/real/file.txt")
    assert(real:sub(1, 1) == "/" or real:match("^%a:/"), "a canonical path is absolute: " .. real)
    assert(read(real) == "x\n", "the canonical path names the same file")
    testAssert.eq(fs.canonical(dir .. "/real/../real/./file.txt"), real, "dot segments are resolved")
    local missing = fs.canonical(dir .. "/real/absent.txt")
    testAssert.eq(missing, fs.absolute(dir .. "/real/absent.txt"), "a missing path keeps its absolute spelling")
    if jit.os ~= "Windows" then
        testAssert.eq(process.run({"ln", "-s", "real", dir .. "/link"}), 0)
        testAssert.eq(fs.canonical(dir .. "/link/file.txt"), real, "a symbolic link is followed")
        local _, printed = process.capture({"realpath", dir .. "/link/file.txt"})
        testAssert.eq(real, (printed:gsub("%s+$", "")), "the answer agrees with realpath")
        testAssert.eq(
            fs.canonical(dir .. "/link/absent.txt"),
            fs.absolute(dir .. "/link/absent.txt"),
            "a missing path behind a link keeps its spelling"
        )
    end
    remove(dir)
end

function M.lexicalRootsRemainAbsolute()
    testAssert.eq(fs.normalize("/"), "/", "the POSIX root survives normalization")
    testAssert.eq(fs.join("ignored", "/"), "/", "a joined POSIX root replaces its left side")
    testAssert.eq(fs.absolute("/"), "/", "the POSIX root does not become the working directory")
    testAssert.eq(fs.dirname("/file"), "/", "a file directly under the POSIX root has the root as its parent")
    testAssert.eq(fs.normalize("C:\\"), "C:/", "a drive root survives normalization")
    testAssert.eq(fs.join("ignored", "C:/"), "C:/", "a joined drive root replaces its left side")
    testAssert.eq(fs.absolute("C:/"), "C:/", "a drive root remains absolute")
    testAssert.eq(fs.dirname("C:/file"), "C:/", "a file directly under a drive root has that root as its parent")
end

function M.fileWalksStopAtSymbolicLinkCycles()
    if jit.os == "Windows" then
        return
    end
    local dir = tempProject({["root/value.txt"] = "value\n"})
    testAssert.eq(process.run({"ln", "-s", ".", dir .. "/root/again"}), 0, "the cycle is created")
    local listed = fs.listFiles(dir .. "/root")
    testAssert.eq(#listed, 1, "a link to an ancestor is not walked again")
    testAssert.eq(listed[1], dir .. "/root/value.txt", "the ordinary file remains visible")
    remove(dir)
end

function M.stagedWritesKeepTheDestinationAfterStreamFailures()
    local loaded = package.loaded["nupp.compiler.fs"]
    local open = io.open
    local dir = tempProject({output = "old\n"})
    local failureAt = "write"
    local ok, failure = pcall(function()
        io.open = function(path, mode)
            if mode ~= "wb" then
                return open(path, mode)
            end
            local closes = 0
            local stream = {}
            function stream:write()
                if failureAt == "write" then
                    return nil, "simulated write failure"
                end

                return self
            end

            function stream:close()
                closes = closes + 1
                if failureAt == "close" and closes == 1 then
                    return nil, "simulated close failure"
                end

                return true
            end

            return stream
        end
        package.loaded["nupp.compiler.fs"] = nil
        local isolated = require("nupp.compiler.fs")
        local wrote, reason = isolated.writeFile(dir .. "/output", "new\n")
        testAssert.eq(wrote, nil, "a failed stream write is reported")
        testAssert.eq(reason, "simulated write failure", "the write failure is retained")
        testAssert.eq(read(dir .. "/output"), "old\n", "a failed stream write publishes nothing")

        failureAt = "close"
        wrote, reason = isolated.writeFile(dir .. "/output", "new\n")
        testAssert.eq(wrote, nil, "a failed stream close is reported")
        testAssert.eq(reason, "simulated close failure", "the close failure is retained")
        testAssert.eq(read(dir .. "/output"), "old\n", "a failed stream close publishes nothing")
    end)
    io.open = open
    package.loaded["nupp.compiler.fs"] = loaded
    remove(dir)
    if not ok then
        error(failure, 0)
    end
end

return M
