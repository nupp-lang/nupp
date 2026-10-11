local envMod = require("nupp.compiler.project.env")
local compile = require("nupp.tools.cli.compile")
local path = arg[1]
local env = envMod.new(arg[2] or ".")
local collected = {}
local tree, source = compile.check(path, env, {}, collected)
for _, d in ipairs(collected) do local ks = {} for k, v in pairs(d) do if type(v) ~= "table" then ks[#ks+1] = k .. "=" .. tostring(v) end end io.stderr:write(table.concat(ks, " "), "\n") end
assert(tree, "check failed")
local function tyname(t)
  if type(t) ~= "table" then return tostring(t) end
  local parts = {tostring(t.tag)}
  if t.name then parts[#parts+1] = "name=" .. tostring(t.name) end
  if t.value ~= nil then parts[#parts+1] = "value=" .. tostring(t.value) end
  if t.element then parts[#parts+1] = "element=" .. tyname(t.element) end
  if t.key then parts[#parts+1] = "key=" .. tyname(t.key) end
  if t.base then parts[#parts+1] = "base=" .. tyname(t.base) end
  return table.concat(parts, " ")
end
local seen = {}
local function walk(node, depth)
  if type(node) ~= "table" or seen[node] then return end
  seen[node] = true
  if node.kind and node.inferredType and not seen[node.kind .. tyname(node.inferredType)] then
    seen[node.kind .. tyname(node.inferredType)] = true
    print(node.kind, "=>", tyname(node.inferredType))
  end
  for k, v in pairs(node) do
    if k ~= "inferredType" and k ~= "resolvedType" and k ~= "parent" and type(v) == "table" then walk(v, depth + 1) end
  end
end
walk(tree, 0)
print("--- keys on a number literal:")
local function find(node, kind) if type(node) ~= "table" then return nil end if node.kind == kind then return node end for k, v in pairs(node) do if k ~= "parent" and type(v) == "table" then local r = find(v, kind) if r then return r end end end end
local num = find(tree, "number"); local keys = {} for k in pairs(num) do keys[#keys+1] = k end table.sort(keys) print(table.concat(keys, " "))
local rec = find(tree, "recordDecl"); print("recordDecl resolvedType:", tyname(rec.resolvedType)); if rec.resolvedType and rec.resolvedType.byname then for k, v in pairs(rec.resolvedType.byname) do print("  field", k, tyname(v)) end end
local nm = find(tree, "name"); print("name token:", nm.token and nm.token.value or nm.token and nm.token.text, "symbol keys:", (function() local ks={} for k in pairs(nm) do ks[#ks+1]=k end table.sort(ks) return table.concat(ks," ") end)())
