-- Run from the repository root after ./bin/nupp build --target compiler.
-- luajit scripts/module-exports.lua [--write] FILE...
package.path = "build/?.lua;" .. package.path
local refactor = require("nupp.tools.moduleexports")
local write = false
for _, path in ipairs(arg) do
    if path == "--write" then
        write = true
    else
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        local result = refactor.plan(source)
        if result.edits then
            if write then
                file = assert(io.open(path, "wb"))
                file:write(result.source)
                file:close()
            end
            io.write((write and "converted" or "ready") .. "\t" .. path .. "\n")
        else
            io.write("review\t" .. path .. "\t" .. result.reason .. "\n")
        end
    end
end
