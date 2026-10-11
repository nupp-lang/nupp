-- Writes a corpus of paths with the shipped normaliser's answers, so the
-- prototype runtime is checked against the implementation it is replacing.
-- Run as `nupp run corpus.lua OUT.tsv` from this directory.
local pathtext = require("nupp.io.path.pathtext")
local out = assert(io.open(arg[1], "w"))
local seed = 12345
local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n + 1 end
local names = {"src", "nupp", "compiler", "a", "lib", "tests", "very-long-component-name", "x", "build", "docs", ".", "..", "..", "", "file.nupp", "README.md", "node_modules", "pkg"}
local lines = 0
local function emit(path, windows)
    -- Verbatim Windows paths are answered by the wrapper, not the kernel.
    if windows and (path:sub(1, 4) == "\\\\?\\" or path:sub(1, 4) == "\\\\.\\") then return end
    local answer = pathtext.normalize(path, windows)
    out:write(path, "\t", windows and "1" or "0", "\t", answer, "\n")
    lines = lines + 1
end
for _ = 1, 400 do
    local n = rnd(8)
    local parts = {}
    for i = 1, n do parts[i] = names[rnd(#names)] end
    local sep = "/"
    local body = table.concat(parts, sep)
    local root = ({"", "/", "//", "./", "../"})[rnd(5)]
    local tail = ({"", "/", "/."})[rnd(3)]
    emit(root .. body .. tail, false)
    local wsep = rnd(2) == 1 and "\\" or "/"
    local wroot = ({"", "C:\\", "C:/", "\\\\server\\share\\", "\\", "\\\\?\\C:\\", "d:"})[rnd(7)]
    emit(wroot .. table.concat(parts, wsep) .. tail, true)
end
-- Edge cases.
for _, p in ipairs({"", ".", "..", "/", "//", "///", "/..", "/../..", "a/..", "a/../..", "./a", "a/./b", "a//b", "a/b/", "..//..", "C:", "C:\\", "C:/..", "\\\\server\\share", "\\\\server\\share\\..\\x", "\\\\?\\C:\\a\\..\\b"}) do emit(p, false); emit(p, true) end
out:close()
io.stderr:write(lines, " cases\n")
