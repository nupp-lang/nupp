-- Temporary source migration helper. Run from a built Nupp checkout:
-- ./bin/nupp run scripts/migrate-construction.lua --tracked
-- Default: report only. --stdout prints one converted file; --write applies edits.
-- This prepares syntax edits, not a proof of equivalent call resolution.
package.path = "build/?.lua;" .. package.path
local parser = require("nupp.compiler.syntax.parser")
local cst = require("nupp.compiler.syntax.cst")

local M = {}

-- Ignore only the construction wrapper. A changed expression grouping is refused.
local function shape(node, out)
    if cst.isToken(node) then
        out[#out + 1] = node.kind .. ":" .. #node.text .. ":" .. node.text
    elseif node.kind == "newExpr" then
        shape(node.call, out)
    else
        out[#out + 1] = "(" .. node.kind
        for _, child in ipairs(node) do
            shape(child, out)
        end
        out[#out + 1] = ")"
    end

    return out
end

function M.plan(source, filename)
    local before = parser.parse(source, filename)
    if #before.errors > 0 then
        return nil, before.errors[1]
    end
    local edits, review = {}, {}
    local constructors, records, structs = 0, 0, 0

    local function visit(node)
        if cst.isToken(node) then
            if node.text == "__call" then
                review[#review + 1] = node.line
            end
            return
        end
        if node.kind == "newExpr" then
            local token = assert(cst.firstToken(node))
            assert(token.text == "new")
            local finish = token.offset + #token.text
            -- Consume horizontal whitespace only. Keep comments and line endings.
            while source:sub(finish, finish):match("[ \t]") do
                finish = finish + 1
            end
            edits[#edits + 1] = {offset = token.offset, length = finish - token.offset, line = token.line}
        elseif node.kind == "constructorDecl" then
            constructors = constructors + 1
        elseif node.kind == "recordDecl" then
            records = records + (node.declKind == "record" and 1 or 0)
            structs = structs + (node.declKind == "struct" and 1 or 0)
        end
        for _, child in ipairs(node) do
            visit(child)
        end
    end

    visit(before.root)
    table.sort(edits, function(a, b)
        return a.offset > b.offset
    end)
    local output = source
    for _, edit in ipairs(edits) do
        output = output:sub(1, edit.offset - 1) .. output:sub(edit.offset + edit.length)
    end
    local after = parser.parse(output, filename)
    if #after.errors > 0 then
        return nil, after.errors[1]
    end
    if table.concat(shape(before.root, {}), "\0") ~= table.concat(shape(after.root, {}), "\0") then
        return nil, {msg = "removing new changes expression grouping; migrate this file manually"}
    end

    return {
        source = source,
        output = output,
        edits = edits,
        review = review,
        constructors = constructors,
        records = records,
        structs = structs,
    }
end

if ... == "library" then
    return M
end

local function main()
    local write, check, stdout, tracked = false, false, false, false
    local paths, exclusions = {}, {}
    local positional = false
    for _, value in ipairs(arg) do
        if not positional and value == "--" then
            positional = true
        elseif not positional and value == "--write" then
            write = true
        elseif not positional and value == "--check" then
            check = true
        elseif not positional and value == "--stdout" then
            stdout = true
        elseif not positional and value == "--tracked" then
            tracked = true
        elseif not positional and value:match("^%-%-exclude=.+$") then
            exclusions[#exclusions + 1] = value:sub(11)
        elseif not positional and (value == "--help" or value == "-h") then
            io.write(
                [=[Usage: ./bin/nupp run scripts/migrate-construction.lua [OPTIONS] [--] FILE.nupp...
  --tracked  Include tracked .nupp files in the current Git checkout.
  --exclude=PATH  Skip this exact file (repeat for known invalid fixtures).
  --stdout   Print converted source for exactly one file; do not write.
  --write    Apply edits after every input passes parsing and grouping checks.
  --check    Do not write; exit 1 if construction keywords remain.
  --help     Show this help.

Default: inventory only. Exit 2 on invalid input; no files are written if any
input fails preflight. Strings, comments, .lua fixtures, and Markdown are not
migrated. __call locations are review candidates, not diagnosed conflicts.
Run --write only after the compiler supports callable construction and the
bootstrap pin permits the new source. Recheck names, overloads, and behavior
afterward: this tool proves syntax preservation, not semantic equivalence.
]=]
            )
            return 0
        elseif not positional and value:sub(1, 1) == "-" then
            error("unknown option: " .. value, 0)
        else
            paths[#paths + 1] = value
        end
    end
    if (write and check) or (write and stdout) or (check and stdout) then
        error("choose only one of --write, --check, and --stdout", 0)
    end
    if tracked then
        local pipe = assert(io.popen("git ls-files --stage -z -- '*.nupp'", "r"))
        local listing = pipe:read("*a")
        local ok = pipe:close()
        if not ok then
            error("could not list tracked files", 0)
        end
        for entry in listing:gmatch("([^%z]+)%z") do
            local mode, stage, path = entry:match("^(%d+) %x+ (%d+)\t(.*)$")
            if not path or stage ~= "0" or mode == "120000" then
                error("tracked input is unmerged or a symlink: " .. entry, 0)
            end
            paths[#paths + 1] = path
        end
    end
    if #paths == 0 then
        error("supply .nupp files or --tracked; use --help for usage", 0)
    end
    local fs = require("nupp.compiler.fs")
    local excluded = {}
    for _, path in ipairs(exclusions) do
        excluded[fs.canonical(path)] = true
    end
    local seen, plans, failed = {}, {}, false
    local total, changed, reviews = 0, 0, 0
    for _, path in ipairs(paths) do
        if not path:match("%.nupp$") then
            error("only .nupp source files are accepted: " .. path, 0)
        end
        local identity = fs.canonical(path)
        if not seen[identity] and not excluded[identity] then
            seen[identity] = true
            local source, problem = fs.readFile(path)
            local plan
            if source then
                plan, problem = M.plan(source, path)
            end
            if not plan then
                failed = true
                local line = type(problem) == "table" and problem.line or 0
                local message = type(problem) == "table" and problem.msg or problem
                io.stderr:write(("%s:%s: %s\n"):format(path, line or 0, message or "cannot read file"))
            else
                plan.path = path
                plans[#plans + 1] = plan
                total = total + #plan.edits
                changed = changed + (#plan.edits > 0 and 1 or 0)
                reviews = reviews + #plan.review
            end
        end
    end
    if failed and (write or stdout) then
        return 2
    end
    if stdout then
        if #plans ~= 1 then
            error("--stdout needs exactly one distinct file", 0)
        end
        io.write(plans[1].output)
        return 0
    end
    if write then
        -- Recheck the entire batch before touching the first file.
        for _, plan in ipairs(plans) do
            if fs.readFile(plan.path) ~= plan.source then
                error("input changed during preflight: " .. plan.path, 0)
            end
        end
    end
    for _, plan in ipairs(plans) do
        if #plan.edits > 0 then
            if write then
                if fs.readFile(plan.path) ~= plan.source then
                    error("input changed during write: " .. plan.path .. "; earlier files may be converted", 0)
                end
                local ok, problem = fs.writeFile(plan.path, plan.output)
                if not ok then
                    error(tostring(problem) .. "; earlier files may be converted", 0)
                end
            end
            io.write(("%s\t%d\t%s\n"):format(write and "converted" or "ready", #plan.edits, plan.path))
        end
        for _, line in ipairs(plan.review) do
            io.write(("review\t%s:%d\t__call surface; classify declaration versus instance\n"):format(plan.path, line))
        end
    end
    io.write(
        (
            "%d constructions in %d files; %d files parsed; %d __call review locations\n"
        ):format(total, changed, #plans, reviews)
    )

    return failed and 2 or check and total > 0 and 1 or 0
end

local ok, code = pcall(main)
if not ok then
    io.stderr:write(tostring(code), "\n")
    os.exit(2)
end
os.exit(code)
