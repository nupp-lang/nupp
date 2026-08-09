-- What `--schema` promises against what `--json` actually writes.
--
-- A schema is a second description of something the code already describes, which
-- is the arrangement that always drifts. So every command that declares one is
-- run for real and its output validated against it. A field that goes away, or
-- changes type, or stops being written, fails here.
local json = require("cjson").new()
json.decode_array_with_array_mt(true)

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local p = assert(io.popen("pwd"))
   HERE = p:read("*l") .. "/" .. HERE
   p:close()
end
local NUPP = HERE .. "/../bin/nupp"

local M = {}

--- A JSON Schema validator covering exactly the keywords the schemas use:
--- type, properties, required, items, enum, and $ref into #/definitions.
--- Returns nil and the path of the first thing wrong.
local function validate(value, schema, root, path)
   root, path = root or schema, path or "$"
   local ref = schema["$ref"]
   if ref then
      local name = ref:match("^#/definitions/(.+)$")
      assert(name, "unsupported $ref " .. ref)
      local target = (root.definitions or {})[name]
      assert(target, "no definition named " .. name)
      return validate(value, target, root, path)
   end
   local wanted = schema.type
   if wanted then
      local actual
      if type(value) == "table" then
         -- cjson marks decoded arrays, which is the only way to tell an empty
         -- array from an empty object once it is a Lua table.
         actual = (getmetatable(value) == json.array_mt or #value > 0)
            and "array" or "object"
      elseif type(value) == "number" then
         actual = (value % 1 == 0) and "integer" or "number"
      else
         actual = type(value)
      end
      local fits = actual == wanted
         or (wanted == "number" and actual == "integer")
         or (wanted == "object" and actual == "array" and next(value) == nil)
      if not fits then
         return nil, ("%s: expected %s, got %s"):format(path, wanted, actual)
      end
   end
   if schema.enum then
      local found = false
      for _, allowed in ipairs(schema.enum) do
         if value == allowed then found = true end
      end
      if not found then
         return nil, ("%s: %s is not one of the listed values")
            :format(path, tostring(value))
      end
   end
   if wanted == "object" and schema.properties and type(value) == "table" then
      for _, name in ipairs(schema.required or {}) do
         if value[name] == nil then
            return nil, ("%s: missing required property %q"):format(path, name)
         end
      end
      for name, child in pairs(value) do
         local property = schema.properties[name]
         if property then
            local ok, err = validate(child, property, root, path .. "." .. name)
            if not ok then return nil, err end
         end
      end
   end
   if wanted == "array" and schema.items and type(value) == "table" then
      for index, item in ipairs(value) do
         local ok, err = validate(item, schema.items, root,
            ("%s[%d]"):format(path, index))
         if not ok then return nil, err end
      end
   end
   return true
end

local function capture(dir, argv)
   local prefix = dir and ("cd '" .. dir .. "' && ") or ""
   local pipe = assert(io.popen(prefix .. ("'%s' %s 2>/dev/null"):format(NUPP, argv)))
   local out = pipe:read("*a")
   pipe:close()
   return out
end

--- Runs a command twice: once for its schema, once for real output, and checks
--- the second against the first.
local function agrees(dir, argv)
   local schemaText = capture(dir, argv .. " --schema")
   local ok, schema = pcall(json.decode, schemaText)
   assert(ok and type(schema) == "table",
      argv .. " --schema did not produce a schema: " .. schemaText)
   local outputText = capture(dir, argv .. " --json")
   local decoded
   ok, decoded = pcall(json.decode, outputText)
   assert(ok, argv .. " --json did not produce JSON: " .. outputText)
   local valid, err = validate(decoded, schema)
   assert(valid, argv .. " --json does not match its own --schema: "
      .. tostring(err) .. "\noutput: " .. outputText)
   return decoded
end

local function tempProject(files)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   for name, text in pairs(files) do
      local file = assert(io.open(dir .. "/" .. name, "wb"))
      file:write(text)
      file:close()
   end
   return dir
end

local BAD = 'local x: number = "text"\nreturn x\n'
local UGLY = "local  y   =  1\nreturn y\n"
local GOOD = "local z: integer = 1\nreturn z\n"

function M.checkOutputMatchesItsSchema()
   local dir = tempProject({["nupp.lua"] = 'return {include = {"."}}\n',
      ["bad.nupp"] = BAD})
   local decoded = agrees(dir, "check bad.nupp")
   assert(#decoded.diagnostics == 1, "the diagnostic is reported")
   assert(decoded.diagnostics[1].docs,
      "and carries the reference anchor explain uses")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.buildOutputMatchesItsSchemaWhenItFailsAndWhenItDoesNot()
   local dir = tempProject({["nupp.lua"] = 'return {include = {"."}}\n',
      ["bad.nupp"] = BAD, ["good.nupp"] = GOOD})
   local failed = agrees(dir, "build bad.nupp")
   assert(failed.ok == false, "a build that reported an error is not ok")
   assert(#failed.written == 0, "and wrote nothing")

   local built = agrees(dir, "build good.nupp")
   assert(built.ok == true, "a build that worked says so")
   assert(#built.written == 1, "and names what it wrote: "
      .. table.concat(built.written, ", "))
   os.execute("rm -rf '" .. dir .. "'")
end

function M.fmtOutputMatchesItsSchemaAndSeparatesFailureFromUnformatted()
   local dir = tempProject({["nupp.lua"] = 'return {include = {"."}}\n',
      ["ugly.nupp"] = UGLY})
   local decoded = agrees(dir, "fmt ugly.nupp")
   assert(#decoded.unformatted == 1, "the unformatted file is listed")
   assert(#decoded.failed == 0, "and is not confused with a failure")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.lintsOutputMatchesItsSchema()
   local decoded = agrees(nil, "lints")
   assert(#decoded.lints > 0, "the lints are listed")
   for _, lint in ipairs(decoded.lints) do
      assert(lint.code and lint.name and lint.default,
         "each carries its code, name and default level")
   end
end

function M.tasksOutputMatchesItsSchema()
   local decoded = agrees(HERE .. "/..", "tasks")
   assert(#decoded.tasks > 0, "the tasks are listed")
end

function M.astOutputMatchesItsSchema()
   local dir = tempProject({["nupp.lua"] = 'return {include = {"."}}\n',
      ["good.nupp"] = GOOD})
   agrees(dir, "ast good.nupp")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.cleanOutputMatchesItsSchema()
   local dir = tempProject({["nupp.lua"] =
      'return {include = {"."}, build = {outDir = "out"}}\n'})
   local decoded = agrees(dir, "clean --dry-run")
   assert(decoded.dryRun == true, "a dry run says so")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.docOutputMatchesItsSchema()
   local dir = tempProject({["nupp.lua"] = 'return {include = {"."}}\n',
      ["good.nupp"] = "--- A point in the plane.\nglobal record Point\n"
         .. "    x: number\nend\n"})
   local decoded = agrees(dir, "doc markdown -o out/api.md")
   assert(decoded.format == "markdown", "the resolved format is reported")
   assert(#decoded.files > 0, "and every path it wrote")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.lspOperationsMatchTheirOwnSchemas()
   local dir = tempProject({["nupp.lua"] = 'return {include = {"."}}\n',
      ["lib.nupp"] = "local lib = {}\n\n--- Double a value.\n"
         .. "function lib.double(n: integer): integer\n    return n * 2\nend\n\n"
         .. "return lib\n",
      ["main.nupp"] = 'local lib = require("lib")\nreturn lib.double(21)\n'})
   -- Each operation carries its own grammar and so its own schema; the group
   -- has none of its own to give.
   agrees(dir, "lsp inspect lib.nupp 4 16")
   agrees(dir, "lsp definition main.nupp 2 12")
   agrees(dir, "lsp references lib.nupp 4 16")
   agrees(dir, "lsp symbols")
   agrees(dir, "lsp actions lib.nupp 4 16")
   local renamed = agrees(dir, "lsp rename lib.nupp 4 16 twice")
   assert(renamed.written == false, "rename previews by default")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.explainOutputMatchesItsSchema()
   local decoded = agrees(nil, "explain NUPP2119")
   assert(decoded.code == "NUPP2119", "the code is echoed")
   assert(decoded.docs, "and its reference given")
end

function M.everyCommandThatWritesJsonAlsoDescribesIt()
   -- The pairing is the point: a command that can be asked for JSON can always
   -- be asked what that JSON will look like.
   local cli = require("nupp.compiler.cli")
   for _, name in ipairs(cli.names()) do
      if name ~= "help" then
         local help = capture(nil, "help " .. name)
         if help:find("--json", 1, true) then
            assert(help:find("--schema", 1, true),
               name .. " offers --json without --schema")
         end
      end
   end
end

return M
