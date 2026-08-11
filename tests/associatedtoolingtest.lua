-- What tooling says about a projection.
--
-- The written spelling is kept and its state is added, never substituted:
-- `Node.Value` and `Node` are not the same question, and answering the second
-- throws away which declaration the reader pointed at.
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
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

local function definition(path, line, column)
   return run(("cd '%s' && ./bin/nupp lsp definition --json '%s' %d %d")
      :format(ROOT, path, line, column))
end

local function rename(path, line, column, to)
   return run(("cd '%s' && ./bin/nupp lsp rename '%s' %d %d %s")
      :format(ROOT, path, line, column, to))
end

local function inspect(path, line, column)
   return run(("cd '%s' && ./bin/nupp lsp inspect --json '%s' %d %d")
      :format(ROOT, path, line, column))
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
   local path = os.tmpname() .. ".g.nupp"
   write(path, SOURCE)
   local out = inspect(path, 11, 44)
   os.remove(path)
   assert(out:find('"type":"Node.Value"', 1, true),
      "the written spelling was replaced:\n" .. out)
   assert(out:find('"associated":"resolves to Node"', 1, true),
      "the state was not reported:\n" .. out)
   -- line 4 is `associated type Value = self` on the interface
   assert(out:find('"line":4', 1, true),
      "definition did not land on the interface default:\n" .. out)
end

function M.anOpaqueProjectionReportsItsBound()
   local path = os.tmpname() .. ".g.nupp"
   write(path, table.concat({
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
   local out = inspect(path, 11, 44)
   os.remove(path)
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
   local path = os.tmpname() .. ".g.nupp"
   write(path, table.concat({
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
   local both = definition(path, 11, 55)
   local one = definition(path, 23, 46)
   os.remove(path)
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
   local path = os.tmpname() .. ".g.nupp"
   write(path, table.concat({
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
   local declaration = rename(path, 4, 21, "Element")
   local projection = rename(path, 12, 37, "Element")
   local alias = rename(path, 9, 10, "Renamed")
   os.remove(path)
   assertEq(declaration:find("cannot be renamed", 1, true) ~= nil, true,
      "an associated declaration was renameable:\n" .. declaration)
   assertEq(projection:find("cannot be renamed", 1, true) ~= nil, true,
      "an associated projection was renameable:\n" .. projection)
   -- and an ordinary nested alias is untouched by the refusal
   assert(alias:find("Renamed", 1, true), "a nested alias stopped being renameable:\n" .. alias)
end

return M
