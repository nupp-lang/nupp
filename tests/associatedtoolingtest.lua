-- What tooling says about a projection.
--
-- The written spelling is kept and its state is added, never substituted:
-- `Node.Value` and `Node` are not the same question, and answering the second
-- throws away which declaration the reader pointed at.
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
-- Absolute, because the commands below are run from the sample's own project
-- rather than from here, and a relative path stops naming this checkout the
-- moment the working directory moves.
if not HERE:match("^/") and not HERE:match("^%a:[/\\]") then
   local pipe = assert(io.popen("pwd"))
   HERE = pipe:read("*l") .. "/" .. HERE
   pipe:close()
end
local ROOT = HERE .. "/.."

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function write(path, text)
   local handle = assert(io.open(path, "w"))
   handle:write(text)
   handle:close()
end

local function run(command)
   local pipe = assert(io.popen(command .. " 2>&1"))
   local out = pipe:read("*a")
   pipe:close()
   return out
end

-- A project holding one file: the sample the case is about.
--
-- These questions are asked of a project, and a rename is asked of every file in
-- it. Asked in this repository -- which is what running the command here meant,
-- whatever directory the sample was written to -- the one rename that succeeds
-- reads a thousand source files to find nothing, and takes twenty-four seconds
-- to say what it says in a third of one here.
--
-- `.g.nupp` because these samples bind names they never use, which is a fragment
-- rather than a program and not what the strict floor is for.
local function project(source)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   write(dir .. "/nupp.lua", 'return {include = {"."}}\n')
   write(dir .. "/sample.g.nupp", source)
   return dir
end

local function remove(dir)
   os.execute("rm -rf '" .. dir .. "'")
end

local function definition(dir, line, column)
   return run(("cd '%s' && '%s/bin/nupp' lsp definition --json sample.g.nupp %d %d")
      :format(dir, ROOT, line, column))
end

local function rename(dir, line, column, to)
   return run(("cd '%s' && '%s/bin/nupp' lsp rename sample.g.nupp %d %d %s")
      :format(dir, ROOT, line, column, to))
end

local function inspect(dir, line, column)
   return run(("cd '%s' && '%s/bin/nupp' lsp inspect --json sample.g.nupp %d %d")
      :format(dir, ROOT, line, column))
end

local SOURCE = table.concat({
   "local m = {}",
   "",
   "interface m.Holds",
   "    associated type Value = self",
   "end",
   "",
   "record m.Node is m.Holds",
   "    tag: string",
   "end",
   "",
   "local function itself(n: m.Node): m.Node.Value",
   "    return n",
   "end",
   "",
   "return m, itself",
}, "\n") .. "\n"

local M = {}

-- The regression that proves provenance and normalization both reach tooling
-- without being conflated: definition lands on the interface that wrote the
-- default, while the concrete projection reports what it resolves to.
function M.aCopiedDefaultKeepsItsSiteAndReportsItsAnswer()
   local dir = project(SOURCE)
   local out = inspect(dir, 11, 44)
   remove(dir)
   assert(out:find('"type":"Node.Value"', 1, true),
      "the written spelling was replaced:\n" .. out)
   assert(out:find('"associated":"resolves to Node"', 1, true),
      "the state was not reported:\n" .. out)
   -- line 4 is `associated type Value = self` on the interface
   assert(out:find('"line":4', 1, true),
      "definition did not land on the interface default:\n" .. out)
end

function M.anOpaqueProjectionReportsItsBound()
   local dir = project(table.concat({
      "local m = {}",
      "",
      "interface m.Named",
      "    name: string",
      "end",
      "",
      "interface m.Holds",
      "    associated type Value is m.Named",
      "end",
      "",
      "local function opaque<T is m.Holds>(v: T.Value): T.Value",
      "    return v",
      "end",
      "",
      "return m, opaque",
   }, "\n") .. "\n")
   local out = inspect(dir, 11, 44)
   remove(dir)
   assert(out:find('"associated":"opaque with bound Named"', 1, true),
      "an opaque projection did not report its bound:\n" .. out)
   -- and the definition is the requirement that states it
   assert(out:find('"line":8', 1, true),
      "definition did not land on the requirement:\n" .. out)
end

-- Two independent contracts stating one name are two places to be, and none of them
-- is the deciding one. A diamond is one, because requirements deduplicate by
-- identity before they reach tooling.
function M.everyContributingDeclarationIsOffered()
   local dir = project(table.concat({
      "local m = {}",
      "",
      "interface m.Left",
      "    associated type Item",
      "end",
      "",
      "interface m.Right",
      "    associated type Item",
      "end",
      "",
      "local function coalesced<T is m.Left & m.Right>(x: T.Item): T.Item",
      "    return x",
      "end",
      "",
      "interface m.Top",
      "    associated type Leaf",
      "end",
      "interface m.A is m.Top",
      "end",
      "interface m.B is m.Top",
      "end",
      "local function diamond<T is m.A & m.B>(x: T.Leaf): T.Leaf",
      "    return x",
      "end",
      "",
      "return m, coalesced, diamond",
   }, "\n") .. "\n")
   local both = definition(dir, 11, 55)
   local one = definition(dir, 23, 46)
   remove(dir)
   assert(both:find('"definitions"', 1, true),
      "two contracts did not offer two declarations:\n" .. both)
   assert(both:find('"line":4', 1, true) and both:find('"line":8', 1, true),
      "the two contracts were not both offered:\n" .. both)
   assert(not one:find('"definitions"', 1, true),
      "a diamond offered more than one declaration:\n" .. one)
end

-- References group by spelling, and an associated name means something only against
-- the contract stating it. Refusing is the safe half until that is identity-based.
function M.associatedNamesAreNotRenameableYet()
   local dir = project(table.concat({
      "local m = {}",
      "",
      "interface m.Holds",
      "    associated type Item",
      "end",
      "",
      "record m.Node is m.Holds",
      "    associated type Item = string",
      "    type Alias = integer",
      "end",
      "",
      "local function use(x: m.Node.Item, y: m.Node.Alias): integer",
      "    return y",
      "end",
      "",
      "return m, use",
   }, "\n") .. "\n")
   local declaration = rename(dir, 4, 21, "Element")
   local projection = rename(dir, 12, 37, "Element")
   local alias = rename(dir, 9, 10, "Renamed")
   remove(dir)
   assertEq(declaration:find("cannot be renamed", 1, true) ~= nil, true,
      "an associated declaration was renameable:\n" .. declaration)
   assertEq(projection:find("cannot be renamed", 1, true) ~= nil, true,
      "an associated projection was renameable:\n" .. projection)
   -- and an ordinary nested alias is untouched by the refusal
   assert(alias:find("Renamed", 1, true), "a nested alias stopped being renameable:\n" .. alias)
end

return M
