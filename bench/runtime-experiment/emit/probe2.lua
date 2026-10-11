local envMod = require("nupp.compiler.project.env")
local compile = require("nupp.tools.cli.compile")
local tree = compile.check(arg[1], envMod.new("."), {}, {})
local root = tree.root or tree
local function keys(t) local ks = {} for k, v in pairs(t) do ks[#ks+1] = k .. "=" .. (type(v) == "table" and (v.tag or v.kind or "table") or tostring(v)) end table.sort(ks) return table.concat(ks, " ") end
for _, s in ipairs(root.blocks[1].stats) do
  if s.kind == "recordDecl" then for _, e in ipairs(s.entries) do if e.kind == "inlineMethod" then
    local fb = e.body
    print("method", e.name.value or e.name.text, "funcbody keys:", keys(fb))
    print("  rets[1]:", fb.rets and keys(fb.rets[1]))
    print("  params[1]:", keys(fb.params[1]))
    print("  params[1].type:", fb.params[1].type and keys(fb.params[1].type))
    print("  body stats[1]:", keys(fb.body.stats[1]))
  end end end
  if s.kind == "localFuncStmt" and (s.name.value or s.name.text) == "total" then
    local fb = s.body
    print("total rets[1]:", fb.rets and keys(fb.rets[1]))
    print("total params[1].type:", keys(fb.params[1].type))
    print("total localFuncStmt keys:", keys(s))
  end
end
for _, s in ipairs(root.blocks[1].stats) do
  if s.kind == "localFuncStmt" and (s.name.value or s.name.text) == "total" then
    local st = s.body.signatureType
    print("signatureType keys:", keys(st))
    for k, v in pairs(st) do if type(v) == "table" and (k == "params" or k == "rets" or k == "returns" or k == "args") then for i, t in ipairs(v) do print("  ", k, i, type(t) == "table" and (t.tag or t.kind) or tostring(t), type(t)=="table" and t.name or "") end end end
  end
end
