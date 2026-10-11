-- A module-graph emitter for real compiler modules: every module is a chunk
-- function whose top-level locals are its own (cells when captured), every
-- function is a closure, every call is dynamic, library functions are
-- builtins, and multiple results travel through `RetN`. Run as
--   nupp run emitmod.lua ROOT entry.module.name [extra.module.names...]
-- from a directory whose nupp.lua includes ROOT's sources.
local envMod = require("nupp.compiler.project.env")
local compile = require("nupp.tools.cli.compile")

local root = assert(arg[1], "project root")
local entryName = assert(arg[2], "entry module name")
local env = envMod.new(root)

local out = {}
local assignedNames = {}
local function emit(s) out[#out + 1] = s end
local function tokText(tok) return tok.value ~= nil and tok.value or tok.text end
local function tyTag(t) return type(t) == "table" and t.tag or "?" end

-- Shapes ---------------------------------------------------------------------
local shapes, shapeOrder = {}, {}
local function slotTy(t)
    local tag = tyTag(t)
    if tag == "number" or tag == "integer" then return "num" end
    if tag == "string" then return "str" end
    if tag == "boolean" then return "bool" end
    if tag == "nominal" and shapes[t.name] then return "rec:" .. shapes[t.name].id end
    if tag == "literal" then return slotTy(t.base) end
    return "any"
end
local function declareShape(node)
    -- An interface has no runtime identity: no shape, erased casts, field access by name.
    if node.declKind == "interface" then return nil end
    local name = tokText(node.name)
    if shapes[name] then return shapes[name] end
    local shape = {id = #shapeOrder, name = name, slots = {}, slotIndex = {}, node = node}
    shapes[name] = shape
    shapeOrder[#shapeOrder + 1] = shape
    local nominal = node.resolvedType
    for _, entry in ipairs(node.entries) do
        if entry.kind == "fieldDecl" then
            local fname = tokText(entry.name)
            shape.slotIndex[fname] = #shape.slots
            shape.slots[#shape.slots + 1] = {name = fname, ty = slotTy(nominal and nominal.byname and nominal.byname[fname])}
        end
    end
    return shape
end
-- A table constructor the checker types as a closed set of named fields gets
-- a shape of its own, shared by every constructor with the same field set:
-- the plan's structural object, slots by offset at the constructor and
-- by name, through a per-site cache, everywhere it is read.
local function structShape(ty)
    if tyTag(ty) ~= "shape" or type(ty.fields) ~= "table" or #ty.fields == 0 then return nil end
    local names = {}
    for i, field in ipairs(ty.fields) do names[i] = type(field) == "table" and field.name or tostring(field) end
    local name = "struct:" .. table.concat(names, ",")
    if shapes[name] then return shapes[name] end
    local shape = {id = #shapeOrder, name = name, slots = {}, slotIndex = {}}
    shapes[name] = shape
    shapeOrder[#shapeOrder + 1] = shape
    for _, fname in ipairs(names) do
        shape.slotIndex[fname] = #shape.slots
        shape.slots[#shape.slots + 1] = {name = fname, ty = slotTy(ty.byname and ty.byname[fname])}
    end
    return shape
end
local function shapeOf(ty)
    if tyTag(ty) == "nominal" then return shapes[ty.name] or shapes[(ty.name or ""):match("([%w_]+)$") or ""] end
end

-- Functions --------------------------------------------------------------------
local functions = {}
local Fn = {}
Fn.__index = Fn
local function newFn(name, parent)
    local f = setmetatable({name = name, consts = {}, constIndex = {}, code = {}, nregs = 1, nfregs = 0, scopes = {{}}, nparams = 0, upvals = {}, upvalIndex = {}, captured = {}, parent = parent, breaks = {}, yields = {}, tables = {}}, Fn)
    functions[#functions + 1] = f
    f.id = #functions - 1
    return f
end
function Fn:const(kind, value)
    local key = kind .. "\0" .. tostring(value)
    if self.constIndex[key] then return self.constIndex[key] end
    self.consts[#self.consts + 1] = {kind = kind, value = value}
    self.constIndex[key] = #self.consts - 1
    return #self.consts - 1
end
function Fn:op(...) self.code[#self.code + 1] = {...}; return #self.code end
function Fn:patch(at, ...) self.code[at] = {...} end
local function nodeLine(node)
    if type(node) ~= "table" then return nil end
    if node.line then return node.line end
    for _, c in ipairs(node) do local l = nodeLine(c); if l then return l end end
    if node.token then return node.token.line end
    return nil
end
function Fn:reg() local r = self.nregs; self.nregs = r + 1; self.maxRegs = math.max(self.maxRegs or 0, self.nregs); if r > 250 then error("register pressure in " .. self.name .. " at statement " .. tostring(self.curStmt and self.curStmt.kind) .. " line " .. tostring(nodeLine(self.curStmt)) .. " declTop " .. tostring(self.declTop)) end; return r end
function Fn:freg() local r = self.nfregs; self.nfregs = r + 1; self.maxFregs = math.max(self.maxFregs or 0, self.nfregs); if r > 250 then error("float register pressure in " .. self.name) end; return r end
-- Declared registers persist; temporaries are reclaimed after each statement
-- down to the highest declared register (`declTop`, `fdeclTop`).
function Fn:declare(name, class)
    if self.captured[name] then
        local r = self:reg()
        self.declTop = math.max(self.declTop or 0, r + 1)
        self.scopes[#self.scopes][name] = {reg = r, class = "v", cell = true}
        return r, true
    end
    local r = (class == "f" or class == "i") and self:freg() or self:reg()
    if class == "f" or class == "i" then self.fdeclTop = math.max(self.fdeclTop or 0, r + 1) else self.declTop = math.max(self.declTop or 0, r + 1) end
    self.scopes[#self.scopes][name] = {reg = r, class = class or "v"}
    return r
end
function Fn:lookup(name)
    for i = #self.scopes, 1, -1 do local r = self.scopes[i][name]; if r then return r.reg, r.class, r.cell end end
end
-- The function id a name is bound to, when it names a `local function` the
-- module never assigns to: the call can then name its callee.
-- The scope entry a name resolves to, through the enclosing functions.
function Fn:binding(name)
    for i = #self.scopes, 1, -1 do local e = self.scopes[i][name]; if e then return e end end
    if self.parent then return self.parent:binding(name) end
end
function Fn:knownFid(name)
    for i = #self.scopes, 1, -1 do local e = self.scopes[i][name]; if e then return e.fid end end
    if self.parent then return self.parent:knownFid(name) end
end
function Fn:upvalue(name)
    if self.upvalIndex[name] then return self.upvalIndex[name] end
    if not self.parent then return nil end
    local preg, _, pcell = self.parent:lookup(name)
    local source
    if preg then
        assert(pcell, "captured local " .. name .. " is not a cell in " .. self.parent.name)
        source = {kind = "local", reg = preg}
    else
        local pi = self.parent:upvalue(name)
        if not pi then return nil end
        source = {kind = "upval", index = pi}
    end
    self.upvals[#self.upvals + 1] = source
    self.upvalIndex[name] = #self.upvals - 1
    return #self.upvals - 1
end
-- A scope remembers the declared high-water marks at entry, so leaving it
-- frees its locals' registers for what follows.
function Fn:push() self.scopes[#self.scopes + 1] = {["\0top"] = {self.declTop or 0, self.fdeclTop or 0}} end
function Fn:pop() local top = self.scopes[#self.scopes]["\0top"]; self.scopes[#self.scopes] = nil; if top then self.declTop, self.fdeclTop = top[1], top[2] end end
function Fn:here() return #self.code end
function Fn:offset(from, to) return to - from end

local BUILTINS = {}
for _, n in ipairs({"pairs", "ipairs", "next", "type", "tostring", "tonumber", "error", "assert", "select", "print", "rawequal", "rawget", "rawset", "setmetatable", "getmetatable", "unpack"}) do BUILTINS[n] = true end
local LIBS = {string = true, table = true, math = true}

local function isNumeric(t)
    local tag = tyTag(t)
    if tag == "number" or tag == "integer" then return true end
    if tag == "literal" then return isNumeric(t.base) end
    return false
end
local function isInteger(t)
    local tag = tyTag(t)
    if tag == "integer" then return true end
    if tag == "literal" then return isInteger(t.base) end
    return false
end
local function isIntegerish(n)
    if n.kind == "paren" then return isIntegerish(n.expr) end
    if n.kind == "number" then local text = tokText(n.token); local v = tonumber(text); return v ~= nil and v == math.floor(v) and not text:find("[%.eE]") and not text:find("^0[xX]") end
    return isInteger(n.inferredType)
end

local function coerce(f, reg, class, want, dst)
    if class == want then
        if dst and dst ~= reg then f:op(want == "f" and "FMov" or want == "i" and "IMov" or "Move", dst, reg) return dst end
        return reg
    end
    if want == "v" then
        dst = dst or f:reg()
        if class == "i" then local t = f:freg(); f:op("IToF", t, reg); f:op("FBox", dst, t) else f:op("FBox", dst, reg) end
        return dst
    end
    if want == "f" then
        dst = dst or f:freg()
        if class == "i" then f:op("IToF", dst, reg) else f:op("FUnbox", dst, reg) end
        return dst
    end
    dst = dst or f:freg()
    if class == "f" then f:op("FToI", dst, reg) else f:op("IUnbox", dst, reg) end
    return dst
end

local expr, block, stmt, stmtReclaim, defineFunction, markCaptures, callInto, emitClosure
local function exprAs(f, node, want, dst) local r, c = expr(f, node, nil, want); return coerce(f, r, c, want, dst) end

-- A call with results landing at `dst..`: eight registers are reserved above
-- the base so a callee's extra results have somewhere to go.
callInto = function(f, node, dst, extraSelf)
    local base = dst
    local nargs = 0
    local args = node.args and node.args.exprs or {}
    local argRegs = {}
    if extraSelf then nargs = nargs + 1; argRegs[1] = extraSelf end
    local spread
    for i, a in ipairs(args) do if a.kind == "vararg" and i == #args then spread = a else nargs = nargs + 1; argRegs[nargs] = a end end
    -- Only the arguments are reserved: a callee's extra results land above
    -- the top, which nothing holds live, inside the frame's nine-word slack.
    while f.nregs < base + nargs + 1 do f:reg() end
    for i, a in ipairs(argRegs) do
        if type(a) == "number" then f:op("Move", base + i, a) else exprAs(f, a, "v", base + i) end
    end
    -- A trailing `...` spreads this frame's own varargs, flagged by 128 on
    -- the count; the runtime copies them from below the header.
    if spread then assert(f.vararg, "... outside a vararg function"); return base, nargs + 128 end
    return base, nargs
end

-- A call's window is reserved above every register in use, so the callee
-- and receiver values evaluated first are not clobbered by the arguments;
-- the results are then moved down to `dst` (`nres` of them).
-- `local byte = string.byte`: a local the module never assigns to, bound to
-- a library function, so a call through it can become an intrinsic.
local function markLibraryLocals(f, names, exprs)
    for i, nameTok in ipairs(names) do
        local e = exprs[i]
        local name = tokText(nameTok)
        if e and e.kind == "dotIndex" and e.obj.kind == "name" and tokText(e.obj.token) == "string" and not f:binding("string") and not assignedNames[name] then
            local entry = f.scopes[#f.scopes][name]
            if entry then entry.builtin = "string." .. tokText(e.name) end
        end
    end
end
-- `string.byte(s, i)` with one result wanted, `s` a string and `i` an
-- integer by the checker: one opcode instead of a builtin call.
local function emitStrByte(f, node, dst, nres)
    local args = node.args and node.args.exprs or {}
    if #args ~= 2 or (nres or 1) > 1 then return false end
    if tyTag(args[1].inferredType) ~= "string" or not isIntegerish(args[2]) then return false end
    local s = exprAs(f, args[1], "v")
    local i = exprAs(f, args[2], "i")
    f:op("StrByte", dst, s, i)
    return true
end
local function emitCall(f, node, dst, nres)
    nres = nres or 1
    local callee = node.obj
    if callee.kind == "name" then
        local bnd = f:binding(tokText(callee.token))
        if bnd and bnd.builtin == "string.byte" and emitStrByte(f, node, dst, nres) then return end
    elseif callee.kind == "dotIndex" and callee.obj.kind == "name" and tokText(callee.obj.token) == "string" and tokText(callee.name) == "byte" and not f:binding("string") then
        if emitStrByte(f, node, dst, nres) then return end
    end
    local function finish(base) if base ~= dst then for i = 0, nres - 1 do f:op("Move", dst + i, base + i) end end end
    if node.kind == "methodCall" then
        local o = exprAs(f, node.obj, "v")
        local base, nargs = callInto(f, node, math.max(dst, f.nregs), o)
        f:op("CallMethod", f:const("str", tokText(node.name)), base, nargs)
        finish(base)
        return
    end
    if callee.kind == "name" then
        local name = tokText(callee.token)
        if name == "pcall" and not f:lookup(name) then
            local args = node.args.exprs
            local base = dst
            while f.nregs < base + #args + 1 do f:reg() end
            for i, a in ipairs(args) do exprAs(f, a, "v", base + i) end
            f:op("PCall", base, #args - 1)
            return
        end
        if name == "require" and not f:lookup(name) then
            local a = node.args.exprs[1]
            if a.kind == "string" then
                f:op("Require", dst, f:const("str", (loadstring("return " .. tokText(a.token)))()))
            else
                local r = exprAs(f, a, "v"); f:op("RequireV", dst, r)
            end
            return
        end
    end
    local fr = exprAs(f, callee, "v")
    local base, nargs = callInto(f, node, math.max(dst, f.nregs))
    local fid = callee.kind == "name" and f:knownFid(tokText(callee.token))
    if fid then f:op("CallK", fid, fr, base, nargs, nres) else f:op("CallDyn", fr, base, nargs) end
    finish(base)
end

expr = function(f, node, dst, want)
    local k = node.kind
    if k == "paren" then return expr(f, node.expr, dst, want) end
    local numeric = isNumeric(node.inferredType)
    local integer = isInteger(node.inferredType)
    if k == "number" then
        local n = tonumber(tokText(node.token))
        if want == "i" and isIntegerish(node) then local ir = f:freg(); f:op("IK", ir, string.format("%d", n)); return ir, "i" end
        local fr = f:freg(); f:op("FK", fr, n)
        return fr, "f"
    end
    if k == "binop" and isIntegerish(node.lhs) and isIntegerish(node.rhs) then
        local op = tokText(node.op)
        local map = {["+"] = "IAdd", ["-"] = "ISub"}
        if map[op] then local a = exprAs(f, node.lhs, "i"); local bb = exprAs(f, node.rhs, "i"); local d = f:freg(); f:op(map[op], d, a, bb); return d, "i" end
        local cmp = {["<"] = "ICmpSLt", ["<="] = "ICmpSLe", [">"] = "ICmpSLt", [">="] = "ICmpSLe"}
        if cmp[op] then
            local a = exprAs(f, node.lhs, "i"); local bb = exprAs(f, node.rhs, "i"); local i = f:freg()
            if op == ">" or op == ">=" then f:op(cmp[op], i, bb, a) else f:op(cmp[op], i, a, bb) end
            local d = f:reg(); f:op("BoolFromI", d, i); return d, "v"
        end
    end
    if numeric and k == "binop" then
        local op = tokText(node.op)
        local map = {["+"] = "FAdd", ["-"] = "FSub", ["*"] = "FMul", ["/"] = "FDiv", ["%"] = "FMod"}
        if map[op] and isNumeric(node.lhs.inferredType) and isNumeric(node.rhs.inferredType) then
            local a = exprAs(f, node.lhs, "f"); local b = exprAs(f, node.rhs, "f")
            local d = f:freg(); f:op(map[op], d, a, b); return d, "f"
        end
    end
    if numeric and k == "unop" and tokText(node.op) == "-" then
        local a = exprAs(f, node.operand, "f"); local d = f:freg(); f:op("FNeg", d, a); return d, "f"
    end
    if numeric and k == "unop" and tokText(node.op) == "#" then
        local a = exprAs(f, node.operand, "v"); local d = f:freg(); f:op("LenF", d, a); return d, "f"
    end
    if k == "vararg" then error("... outside a call's last argument is not in this emitter") end
    if k == "name" then
        local name = tokText(node.token)
        local r, c, cell = f:lookup(name)
        if r and cell then
            local d = f:reg(); f:op("GetCell", d, r)
            if numeric and want == "f" then local fr = f:freg(); f:op("FUnbox", fr, d); return fr, "f" end
            return d, "v"
        end
        if r then return r, c end
        local ui = f:upvalue(name)
        if ui then
            local cellReg = f:reg(); f:op("GetUpval", cellReg, ui)
            local d = f:reg(); f:op("GetCell", d, cellReg)
            if numeric and want == "f" then local fr = f:freg(); f:op("FUnbox", fr, d); return fr, "f" end
            return d, "v"
        end
    end
    if numeric and k == "dotIndex" then
        local shape = shapeOf(node.obj.inferredType)
        local fname = tokText(node.name)
        if shape and shape.slotIndex[fname] and shape.slots[shape.slotIndex[fname] + 1].ty == "num" then
            local o = exprAs(f, node.obj, "v")
            local d = f:freg(); f:op("GetSlotF", d, o, shape.slotIndex[fname]); return d, "f"
        end
    end
    if numeric and k == "bracketIndex" then
        local o = exprAs(f, node.obj, "v"); local d = f:reg()
        if isIntegerish(node.expr) then local i = exprAs(f, node.expr, "i"); f:op("GetIdxI", d, o, i)
        elseif isNumeric(node.expr.inferredType) then local i = exprAs(f, node.expr, "f"); f:op("GetIdxF", d, o, i)
        else local i = exprAs(f, node.expr, "v"); f:op("GetIdx", d, o, i) end
        if want == "i" and integer then local ir = f:freg(); f:op("IUnbox", ir, d); return ir, "i" end
        if want == "f" then local fr = f:freg(); f:op("FUnbox", fr, d); return fr, "f" end
        return d, "v"
    end
    if k == "binop" then
        local op = tokText(node.op)
        local cmp = {["<"] = "FCmpLt", ["<="] = "FCmpLe", [">"] = "FCmpLt", [">="] = "FCmpLe", ["=="] = "FCmpEq", ["~="] = "FCmpNe"}
        if cmp[op] and isNumeric(node.lhs.inferredType) and isNumeric(node.rhs.inferredType) then
            local a = exprAs(f, node.lhs, "f"); local b = exprAs(f, node.rhs, "f")
            local i = f:freg()
            if op == ">" or op == ">=" then f:op(cmp[op], i, b, a) else f:op(cmp[op], i, a, b) end
            local d = f:reg(); f:op("BoolFromI", d, i); return d, "v"
        end
    end
    if k == "switchExpr" or k == "doExpr" then error("switch and do expressions are not in this emitter") end
    -- Everything else lands in a value register.
    dst = (want ~= "f" and want ~= "i" and dst) or nil
    dst = dst or f:reg()
    if k == "number" then
        f:op("K", dst, f:const("num", tonumber(tokText(node.token))))
    elseif k == "string" then
        local raw = tokText(node.token)
        local value = raw
        if raw:sub(1, 1) == '"' or raw:sub(1, 1) == "'" then value = assert(loadstring("return " .. raw), "literal " .. raw)() end
        if raw:sub(1, 1) == "[" then value = assert(loadstring("return " .. raw))() end
        f:op("K", dst, f:const("str", value))
    elseif k == "trueExpr" then f:op("K", dst, f:const("true", ""))
    elseif k == "falseExpr" then f:op("K", dst, f:const("false", ""))
    elseif k == "nil" or k == "nilExpr" then f:op("Nil", dst)
    elseif k == "name" then
        local name = tokText(node.token)
        if BUILTINS[name] then f:op("K", dst, f:const("builtin", name))
        elseif name == "pcall" then f:op("K", dst, f:const("builtin", "pcall"))
        else error("unresolved name " .. name .. " in " .. f.name) end
    elseif k == "binop" then
        local op = tokText(node.op)
        if op == "and" or op == "or" then
            exprAs(f, node.lhs, "v", dst)
            local branch = f:op(op == "and" and "JmpIfNot" or "JmpIf", dst, 0)
            exprAs(f, node.rhs, "v", dst)
            f:patch(branch, op == "and" and "JmpIfNot" or "JmpIf", dst, f:offset(branch, f:here()))
        elseif op == "??" then
            exprAs(f, node.lhs, "v", dst)
            local n = f:reg(); f:op("Nil", n); local c = f:reg(); f:op("Ne", c, dst, n)
            local branch = f:op("JmpIf", c, 0)
            exprAs(f, node.rhs, "v", dst)
            f:patch(branch, "JmpIf", c, f:offset(branch, f:here()))
        else
            local a = exprAs(f, node.lhs, "v"); local b = exprAs(f, node.rhs, "v")
            local map = {["+"] = "Add", ["-"] = "Sub", ["*"] = "Mul", ["/"] = "Div", ["%"] = "Mod", ["<"] = "Lt", ["<="] = "Le", ["=="] = "Eq", [".."] = "Concat", ["~="] = "Ne", [">"] = "Gt", [">="] = "Ge"}
            local name = assert(map[op], "operator " .. op)
            if name == "Gt" then f:op("Lt", dst, b, a) elseif name == "Ge" then f:op("Le", dst, b, a) else f:op(name, dst, a, b) end
        end
    elseif k == "unop" then
        local op = tokText(node.op)
        local a = exprAs(f, node.operand, "v")
        if op == "not" then f:op("Not", dst, a) elseif op == "-" then f:op("Neg", dst, a) elseif op == "#" then f:op("Len", dst, a) else error("unop " .. op) end
    elseif k == "ternary" then
        local c = exprAs(f, node.cond, "v")
        local branch = f:op("JmpIfNot", c, 0)
        exprAs(f, node.ifTrue, "v", dst)
        local skip = f:op("Jmp", 0)
        f:patch(branch, "JmpIfNot", c, f:offset(branch, f:here()))
        exprAs(f, node.ifFalse, "v", dst)
        f:patch(skip, "Jmp", f:offset(skip, f:here()))
    elseif k == "dotIndex" then
        local fname = tokText(node.name)
        if node.obj.kind == "name" and LIBS[tokText(node.obj.token)] and not f:lookup(tokText(node.obj.token)) then
            f:op("K", dst, f:const("builtin", tokText(node.obj.token) .. "." .. fname))
        else
            local shape = shapeOf(node.obj.inferredType)
            local o = exprAs(f, node.obj, "v")
            if shape and shape.slotIndex[fname] then f:op("GetSlot", dst, o, shape.slotIndex[fname])
            else f:op("GetField", dst, o, f:const("str", fname)) end
        end
    elseif k == "bracketIndex" then
        local o = exprAs(f, node.obj, "v")
        if isIntegerish(node.expr) then local i = exprAs(f, node.expr, "i"); f:op("GetIdxI", dst, o, i)
        elseif isNumeric(node.expr.inferredType) then local i = exprAs(f, node.expr, "f"); f:op("GetIdxF", dst, o, i)
        else local i = exprAs(f, node.expr, "v"); f:op("GetIdx", dst, o, i) end
    elseif k == "call" or k == "methodCall" then
        emitCall(f, node, dst)
    elseif k == "newExpr" then
        local call = node.call
        local shape = assert(shapeOf(node.inferredType), "new of unknown record")
        f:op("NewRecord", dst, shape.id)
        for _, a in ipairs(call.args.exprs or {}) do
            assert(a.kind == "namedArg", "new with positional arguments")
            local slot = assert(shape.slotIndex[tokText(a.name)], "field " .. tokText(a.name))
            if shape.slots[slot + 1].ty == "num" then local v = exprAs(f, a.value, "f"); f:op("SetSlotF", dst, slot, v)
            else local v = exprAs(f, a.value, "v"); f:op("SetSlot", dst, slot, v) end
        end
    elseif k == "tableExpr" then
        local items, named = 0, 0
        for _, field in ipairs(node.fields) do if field.kind == "fieldItem" then items = items + 1 else named = named + 1 end end
        local struct = items == 0 and structShape(node.inferredType)
        if struct then
            local every = true
            for _, field in ipairs(node.fields) do if field.kind ~= "fieldNamed" or not struct.slotIndex[tokText(field.name)] then every = false end end
            if every then
                f:op("NewRecord", dst, struct.id)
                for _, field in ipairs(node.fields) do
                    local slot = struct.slotIndex[tokText(field.name)]
                    if struct.slots[slot + 1].ty == "num" then local fv = exprAs(f, field.value, "f"); f:op("SetSlotF", dst, slot, fv)
                    else local v = exprAs(f, field.value, "v"); f:op("SetSlot", dst, slot, v) end
                end
                return dst, "v"
            end
        end
        f:op("NewTableN", dst, math.min(items, 255), math.min(named, 255))
        local n = 0
        for _, field in ipairs(node.fields) do
            if field.kind == "fieldNamed" then
                local v = exprAs(f, field.value, "v")
                f:op("SetField", dst, f:const("str", tokText(field.name)), v)
            elseif field.kind == "fieldItem" then
                n = n + 1
                local i = f:reg(); f:op("K", i, f:const("num", n))
                local v = exprAs(f, field.value, "v")
                f:op("SetIdx", dst, i, v)
            elseif field.kind == "fieldBracket" then
                local kreg = exprAs(f, field.key, "v"); local v = exprAs(f, field.value, "v")
                f:op("SetIdx", dst, kreg, v)
            else error("table field " .. field.kind) end
        end
    elseif k == "funcExpr" then
        emitClosure(f, node.body, dst, f.name .. ".fn" .. tostring(#functions))
    elseif k == "castExpr" then
        local target = node.inferredType
        local v = exprAs(f, node.expr, "v", dst)
        local shape = shapeOf(target)
        if shape then f:op("TagCheckRec", dst, v, shape.id)
        elseif tyTag(target) == "number" or tyTag(target) == "integer" then f:op("TagCheckNum", dst, v)
        elseif tyTag(target) == "string" then f:op("TagCheckStr", dst, v)
        else if v ~= dst then f:op("Move", dst, v) end end
    else
        error("expression kind " .. tostring(k) .. " in " .. f.name)
    end
    return dst, "v"
end

-- A closure over `funcbody`: compiled as a nested function, its captures
-- moved into place, the closure value landing in `dst`.
emitClosure = function(f, funcbody, dst, name, implicitSelf)
    local inner = newFn(name, f)
    inner.sig = {}
    inner.implicitSelf = implicitSelf
    -- A vararg parameter is not a parameter: the runtime packs the surplus
    -- arguments into a table in the register after the last fixed one.
    local fixed = {}
    for _, p in ipairs(funcbody.params or {}) do if p.vararg then inner.vararg = true else fixed[#fixed + 1] = p end end
    for i = 1, #fixed + (implicitSelf and 1 or 0) do inner.sig[i] = "v" end
    inner.nparams = #fixed + (implicitSelf and 1 or 0)
    inner.ret = "v"
    markCaptures(inner, funcbody)
    defineFunction(inner, funcbody)
    local base = f:reg()
    while f.nregs < base + #inner.upvals + 1 do f:reg() end
    for i, u in ipairs(inner.upvals) do
        if u.kind == "local" then f:op("Move", base + i, u.reg) else local t = f:reg(); f:op("GetUpval", t, u.index); f:op("Move", base + i, t) end
    end
    f:op("NewClosure", dst, inner.id, base, #inner.upvals)
    return inner
end

-- Multiple results: evaluate `exprs` for `count` targets into consecutive
-- registers from `base`, the last call supplying the remainder.
local function exprsInto(f, exprs, count, base)
    while f.nregs < base + count do f:reg() end
    for i, e in ipairs(exprs) do
        if i == #exprs and i < count and (e.kind == "call" or e.kind == "methodCall") then
            emitCall(f, e, base + i - 1, count - i + 1)
            return
        end
        if i <= count then exprAs(f, e, "v", base + i - 1) else expr(f, e, nil, "v") end
    end
    for i = #exprs + 1, count do f:op("Nil", base + i - 1) end
end

local function assignTo(f, target, valueReg)
    if target.kind == "name" then
        local r, c, cell = f:lookup(tokText(target.token))
        if r and cell then f:op("SetCell", r, valueReg)
        elseif r then coerce(f, valueReg, "v", c, r)
        else
            local ui = assert(f:upvalue(tokText(target.token)), "assign to unknown name " .. tokText(target.token))
            local cellReg = f:reg(); f:op("GetUpval", cellReg, ui); f:op("SetCell", cellReg, valueReg)
        end
    elseif target.kind == "dotIndex" then
        local shape = shapeOf(target.obj.inferredType)
        local o = exprAs(f, target.obj, "v")
        local fname = tokText(target.name)
        if shape and shape.slotIndex[fname] then
            local slot = shape.slotIndex[fname]
            if shape.slots[slot + 1].ty == "num" then local fv = f:freg(); f:op("FUnbox", fv, valueReg); f:op("SetSlotF", o, slot, fv) else f:op("SetSlot", o, slot, valueReg) end
        else f:op("SetField", o, f:const("str", fname), valueReg) end
    elseif target.kind == "bracketIndex" then
        local o = exprAs(f, target.obj, "v")
        if isIntegerish(target.expr) then local i = exprAs(f, target.expr, "i"); f:op("SetIdxI", o, i, valueReg)
        elseif isNumeric(target.expr.inferredType) then local i = exprAs(f, target.expr, "f"); f:op("SetIdxF", o, i, valueReg)
        else local i = exprAs(f, target.expr, "v"); f:op("SetIdx", o, i, valueReg) end
    else error("assignment target " .. target.kind) end
end

local function loopBegin(f) f.breaks[#f.breaks + 1] = {} end
local function loopEnd(f) local list = table.remove(f.breaks); for _, at in ipairs(list) do f:patch(at, "Jmp", f:offset(at, f:here())) end end

stmt = function(f, node)
    local k = node.kind
    if k == "localStmt" then
        local names = node.names
        local declared = {}
        for i, nameTok in ipairs(names) do
            local name = tokText(nameTok)
            local value = node.exprs and node.exprs[i]
            local ty = node.types and node.types[i] and node.types[i].resolvedType
            local class = "v"
            if not f.captured[name] then
                if isInteger(ty) or (not ty and value and isInteger(value.inferredType)) then class = "i"
                elseif isNumeric(ty) or (not ty and value and isNumeric(value.inferredType)) then class = "f" end
            end
            declared[i] = {name = name, class = class}
        end
        local exprs = node.exprs or {}
        if #names == 1 and #exprs <= 1 then
            local d = declared[1]
            local value = exprs[1]
            local r, cell = f:declare(d.name, d.class)
            if cell then
                local v = f:reg()
                if value then exprAs(f, value, "v", v) else f:op("Nil", v) end
                f:op("NewCell", r, v)
            elseif value then exprAs(f, value, d.class, r)
            elseif d.class == "v" then f:op("Nil", r) elseif d.class == "i" then f:op("IK", r, 0) else f:op("FK", r, 0) end
            markLibraryLocals(f, names, exprs)
            return
        end
        local base = f.nregs
        exprsInto(f, exprs, #names, base)
        for i, d in ipairs(declared) do
            local r, cell = f:declare(d.name, d.class)
            if cell then f:op("NewCell", r, base + i - 1) else coerce(f, base + i - 1, "v", d.class, r) end
        end
        markLibraryLocals(f, names, exprs)
    elseif k == "assignStmt" then
        local targets, exprs = node.targets, node.exprs
        if #targets == 1 and #exprs == 1 then
            local target = targets[1]
            if target.kind == "name" then
                local r, c, cell = f:lookup(tokText(target.token))
                if r and not cell then exprAs(f, exprs[1], c, r); return end
            end
            local v = exprAs(f, exprs[1], "v")
            assignTo(f, target, v)
            return
        end
        local base = f.nregs
        exprsInto(f, exprs, #targets, base)
        for i, target in ipairs(targets) do assignTo(f, target, base + i - 1) end
    elseif k == "callStmt" then
        expr(f, node.expr, nil, "v")
    elseif k == "returnStmt" then
        local exprs = node.exprs or {}
        if #exprs == 0 then f:op("RetNil")
        elseif #exprs == 1 and exprs[1].kind ~= "call" and exprs[1].kind ~= "methodCall" then
            local r, c = expr(f, exprs[1], nil, nil)
            local vr = coerce(f, r, c, "v"); f:op("Ret", vr)
        else
            local base = f.nregs
            local n = #exprs
            if exprs[n].kind == "call" or exprs[n].kind == "methodCall" then
                -- A trailing call's results are all returned: evaluate the others, then it.
                while f.nregs < base + n + 1 do f:reg() end
                for i = 1, n - 1 do exprAs(f, exprs[i], "v", base + i - 1) end
                emitCall(f, exprs[n], base + n - 1, 8)
                -- 128 | fixed: the fixed values, then exactly what the call returned.
                f:op("RetN", base, 128 + (n - 1))
            else
                exprsInto(f, exprs, n, base)
                f:op("RetN", base, n)
            end
        end
    elseif k == "exportStmt" then
        if node.value then local r = exprAs(f, node.value, "v"); f:op("Ret", r) elseif node.stat then stmt(f, node.stat) end
    elseif k == "ifStmt" then
        local exits = {}
        -- A condition's temporaries die at its branch: the body starts from
        -- the registers live before the condition, or its locals would be
        -- declared above every temporary the condition used.
        local mark = f.nregs
        for _, clause in ipairs(node.clauses) do
            local c = exprAs(f, clause.cond, "v")
            local branch = f:op("JmpIfNot", c, 0)
            f.nregs = math.max(mark, f.declTop or 0)
            block(f, clause.body)
            exits[#exits + 1] = f:op("Jmp", 0)
            f:patch(branch, "JmpIfNot", c, f:offset(branch, f:here()))
        end
        if node.elseClause then block(f, node.elseClause.body or node.elseClause) end
        for _, e in ipairs(exits) do f:patch(e, "Jmp", f:offset(e, f:here())) end
    elseif k == "whileStmt" then
        local top = f:here()
        local mark = f.nregs
        local c = exprAs(f, node.cond, "v")
        local branch = f:op("JmpIfNot", c, 0)
        f.nregs = math.max(mark, f.declTop or 0)
        loopBegin(f)
        block(f, node.body)
        local back = f:op("Jmp", 0); f:patch(back, "Jmp", f:offset(back, top))
        f:patch(branch, "JmpIfNot", c, f:offset(branch, f:here()))
        loopEnd(f)
    elseif k == "repeatStmt" then
        local top = f:here()
        loopBegin(f)
        f:push()
        for _, s in ipairs(node.body.stats or {}) do stmtReclaim(f, s) end
        local c = exprAs(f, node.cond, "v")
        f:pop()
        local back = f:op("JmpIfNot", c, 0); f:patch(back, "JmpIfNot", c, f:offset(back, top))
        loopEnd(f)
    elseif k == "fornumStmt" then
        f:push()
        local var = f:declare(tokText(node.var), "f")
        local varCell = f.captured[tokText(node.var)]
        assert(not varCell, "captured loop variable")
        exprAs(f, node.start, "f", var)
        local limit = exprAs(f, node.stop, "f")
        local step = f:freg(); if node.step then exprAs(f, node.step, "f", step) else f:op("FK", step, 1) end
        local top = f:here()
        local c = f:freg(); f:op("FCmpLe", c, var, limit)
        local branch = f:op("JmpIfIZero", c, 0)
        loopBegin(f)
        block(f, node.body)
        f:op("FAdd", var, var, step)
        local back = f:op("Jmp", 0); f:patch(back, "Jmp", f:offset(back, top))
        f:patch(branch, "JmpIfIZero", c, f:offset(branch, f:here()))
        loopEnd(f)
        f:pop()
    elseif k == "forinStmt" then
        -- The generic protocol: f, s, control = explist; each round calls f(s, control).
        f:push()
        local base = f.nregs
        exprsInto(f, node.exprs, 3, base)
        local fnReg, stateReg, ctl = base, base + 1, base + 2
        while f.nregs < base + 3 do f:reg() end
        local call = f.nregs
        while f.nregs < call + math.max(#node.names, 3) + 1 do f:reg() end
        local top = f:here()
        f:op("Move", call + 1, stateReg); f:op("Move", call + 2, ctl)
        f:op("CallDyn", fnReg, call, 2)
        local exit = f:op("JmpIfNot", call, 0)
        f:op("Move", ctl, call)
        loopBegin(f)
        f:push()
        for i, nameTok in ipairs(node.names) do
            local name = tokText(nameTok)
            local r, cell = f:declare(name, "v")
            if cell then f:op("NewCell", r, call + i - 1) else f:op("Move", r, call + i - 1) end
        end
        block(f, node.body)
        f:pop()
        local back = f:op("Jmp", 0); f:patch(back, "Jmp", f:offset(back, top))
        f:patch(exit, "JmpIfNot", call, f:offset(exit, f:here()))
        loopEnd(f)
        f:pop()
    elseif k == "breakStmt" then
        local list = assert(f.breaks[#f.breaks], "break outside a loop")
        list[#list + 1] = f:op("Jmp", 0)
    elseif k == "localFuncStmt" then
        -- `local function f`: f is in scope in its own body, through its cell.
        local name = tokText(node.name)
        local r, cell = f:declare(name, "v")
        local inner
        if cell then
            f:op("Nil", r + 0) -- placeholder; the cell is made below
            local nilReg = f:reg(); f:op("Nil", nilReg); f:op("NewCell", r, nilReg)
            local c = f:reg(); inner = emitClosure(f, node.body, c, name); f:op("SetCell", r, c)
        else
            inner = emitClosure(f, node.body, r, name)
        end
        if not assignedNames[name] then f.scopes[#f.scopes][name].fid = inner.id end
    elseif k == "funcStmt" then
        local fname = node.name
        local baseName = tokText(fname.base)
        -- The dotted path is the node's own token list: name tokens after the base.
        local parts = {}
        for _, child in ipairs(fname) do
            if type(child) == "table" and child.kind == "name" and child ~= fname.base and child ~= fname.method then parts[#parts + 1] = tokText(child) end
        end
        if fname.method and shapes[baseName] then
            local member = tokText(fname.method)
            local c = f:reg(); emitClosure(f, node.body, c, baseName .. ":" .. member, true)
            f:op("SetMethod", shapes[baseName].id, f:const("str", member), c)
        else
            assert(#parts == 1 and not fname.method, "function name shape " .. baseName .. " parts " .. #parts)
            local c = f:reg(); emitClosure(f, node.body, c, baseName .. "." .. parts[1])
            local o = exprAs(f, {kind = "name", token = fname.base, inferredType = {tag = "any"}}, "v")
            f:op("SetField", o, f:const("str", parts[1]), c)
        end
    elseif k == "recordDecl" then
        local shape = declareShape(node)
        if not shape then return end
        for _, entry in ipairs(node.entries) do
            if entry.kind == "inlineMethod" then
                local c = f:reg(); emitClosure(f, entry.body, c, shape.name .. ":" .. tokText(entry.name))
                f:op("SetMethod", shape.id, f:const("str", tokText(entry.name)), c)
            end
        end
    elseif k == "emptyStmt" or k == "typeAlias" or k == "interface" or k == "annotationApply" or k == "moduleStmt" or k == "typeDecl" or k == "constTypeStmt" then
        -- Nothing at run time.
    else
        error("statement kind " .. tostring(k) .. " in " .. f.name)
    end
end

stmtReclaim = function(f, s)
    f.curStmt = s
    local mark, fmark = f.nregs, f.nfregs
    stmt(f, s)
    if os.getenv("DEBUG_REGS") and f.name:find(os.getenv("DEBUG_REGS"), 1, true) then io.stderr:write(f.name, " ", s.kind, " line ", tostring(s.line or (s[1] and s[1].line) or "?"), " nregs ", f.nregs, " declTop ", tostring(f.declTop), "\n") end
    f.nregs = math.max(mark, f.declTop or 0)
    f.nfregs = math.max(fmark, f.fdeclTop or 0)
end

block = function(f, node)
    f:push()
    for _, s in ipairs(node.stats or node.body and node.body.stats or {}) do stmtReclaim(f, s) end
    f:pop()
end

local SKIP = {parent = true, inferredType = true, resolvedType = true, signatureType = true, selectedDefinition = true, methodEntry = true, token = true}
local function walkSyntax(node, seen, visit)
    if type(node) ~= "table" or seen[node] then return end
    seen[node] = true
    if visit(node) == false then return end
    for key, v in pairs(node) do if not SKIP[key] and type(v) == "table" then walkSyntax(v, seen, visit) end end
end
-- The names a nested function declares for itself: parameters, locals,
-- local functions and loop variables, anywhere in its body.
local function declaredNames(funcbody, out)
    for _, p in ipairs(funcbody.params or {}) do if p.name then out[tokText(p.name)] = true end end
    out["..."] = true
    walkSyntax(funcbody.body, {}, function(n)
        if n.kind == "localStmt" then for _, t in ipairs(n.names) do out[tokText(t)] = true end
        elseif n.kind == "localFuncStmt" then out[tokText(n.name)] = true
        elseif n.kind == "fornumStmt" then out[tokText(n.var)] = true
        elseif n.kind == "forinStmt" then for _, t in ipairs(n.names) do out[tokText(t)] = true end end
    end)
end
-- The free names of a nested function: referenced anywhere in it and not
-- declared by it. A name it declares after an outer use is mistaken for its
-- own, which the cell assertion at emit time catches rather than miscompiles.
local function collectFree(funcbody, out)
    local declared = {}
    declaredNames(funcbody, declared)
    walkSyntax(funcbody.body, {}, function(n)
        if n.kind == "name" and n.token and not declared[tokText(n.token)] then out[tokText(n.token)] = true end
        if n.kind == "funcname" and n.base and not declared[tokText(n.base)] then out[tokText(n.base)] = true end
    end)
end
-- A local of this function is a cell when some nested function refers to it
-- freely; the analysis is scope-blind within this function, so a local that
-- shares a name with a captured one is a cell too.
markCaptures = function(f, funcbody)
    walkSyntax(funcbody.body or funcbody, {}, function(n)
        if n ~= funcbody and (n.kind == "funcExpr" or n.kind == "localFuncStmt" or n.kind == "funcStmt" or n.kind == "inlineMethod") then
            collectFree(n.body, f.captured)
            if n.kind == "localFuncStmt" then f.captured[tokText(n.name)] = true end
            return false
        end
    end)
end

defineFunction = function(f, funcbody)
    local params = funcbody.params or {}
    local cellParams = {}
    if f.implicitSelf then
        if f.captured["self"] then local r = f:reg(); cellParams[#cellParams + 1] = {"self", r} else f:declare("self", "v") end
    end
    local varargParam
    for _, p in ipairs(params) do
        if p.vararg then varargParam = p else
            local name = tokText(p.name)
            if f.captured[name] then local r = f:reg(); cellParams[#cellParams + 1] = {name, r} else f:declare(name, "v") end
        end
    end
    -- The surplus arguments stay in the frame; `...` is spread only in a call.
    if varargParam then assert(not varargParam.name, "a named vararg is not in this emitter") end
    for _, cp in ipairs(cellParams) do local cellReg = f:declare(cp[1]); f:op("NewCell", cellReg, cp[2]) end
    block(f, funcbody.body)
    local last = f.code[#f.code]
    if last == nil or (last[1] ~= "Ret" and last[1] ~= "RetNil" and last[1] ~= "RetN") then f:op("RetNil") end
end

-- Modules ----------------------------------------------------------------------
local modules, moduleOrder = {}, {}
local function modulePath(name)
    local rel = name:gsub("%.", "/")
    for _, cand in ipairs({root .. "/src/" .. rel .. "/init.nupp", root .. "/src/" .. rel .. ".nupp", root .. "/" .. rel .. ".nupp", rel .. ".nupp"}) do
        local fh = io.open(cand, "r")
        if fh then fh:close(); return cand end
    end
    return nil
end
local function requiresOf(tree)
    local names = {}
    walkSyntax(tree, {}, function(n)
        if n.kind == "call" and n.obj and n.obj.kind == "name" and tokText(n.obj.token) == "require" and n.args and n.args.exprs[1] and n.args.exprs[1].kind == "string" then
            names[#names + 1] = (loadstring("return " .. tokText(n.args.exprs[1].token)))()
        end
    end)
    return names
end
local function compileModule(name, path)
    if modules[name] then return end
    modules[name] = true
    local collected = {}
    local tree = compile.check(path, env, {}, collected)
    for _, d in ipairs(collected) do if d.severity == "error" or not d.severity then io.stderr:write(name, ": ", tostring(d.code), " ", tostring(d.msg), "\n") end end
    assert(tree, "check failed for " .. path)
    local rootNode = tree.root or tree
    local stats = rootNode.blocks[1].stats
    for _, dep in ipairs(requiresOf(rootNode)) do
        local depPath = modulePath(dep)
        if depPath then compileModule(dep, depPath) else io.stderr:write("module ", dep, " not found (left to the runtime)\n") end
    end
    for _, s in ipairs(stats) do if s.kind == "recordDecl" then declareShape(s) elseif s.kind == "exportStmt" and s.stat and s.stat.kind == "recordDecl" then declareShape(s.stat) end end
    local chunk = newFn("module:" .. name, nil)
    chunk.sig, chunk.ret, chunk.nparams = {}, "v", 0
    -- Names the module assigns to anywhere, by name: a `local function` not
    -- among them keeps its closure for the module's life.
    assignedNames = {}
    walkSyntax(rootNode.blocks[1], {}, function(n)
        if n.kind == "assignStmt" then for _, t in ipairs(n.targets) do if t.kind == "name" then assignedNames[tokText(t.token)] = true end end end
    end)
    markCaptures(chunk, {body = rootNode.blocks[1]})
    block(chunk, rootNode.blocks[1])
    local last = chunk.code[#chunk.code]
    if last == nil or (last[1] ~= "Ret" and last[1] ~= "RetNil" and last[1] ~= "RetN") then chunk:op("RetNil") end
    modules[name] = chunk
    moduleOrder[#moduleOrder + 1] = name
end

for i = 3, #arg do local p = assert(modulePath(arg[i]), "extra module " .. arg[i]); compileModule(arg[i], p) end
compileModule(entryName, assert(modulePath(entryName), "entry module " .. entryName))

-- Output -------------------------------------------------------------------
-- Every byte outside printable ASCII is escaped, so an image is ASCII text
-- whatever bytes its string constants hold.
local function q(s) return '"' .. s:gsub('[%c"\\\128-\255]', function(c) return string.format("\\%03d", c:byte()) end) .. '"' end
for _, shape in ipairs(shapeOrder) do
    local parts = {"shape", shape.id, shape.name}
    for _, slot in ipairs(shape.slots) do parts[#parts + 1] = slot.name .. ":" .. slot.ty end
    emit(table.concat(parts, " "))
end
for _, f in ipairs(functions) do
    emit(("function %s %d %d %d %d %s:%s%s"):format(f.name:gsub("%s", "_"), f.id, f.nparams, math.max(f.maxRegs or 0, f.nregs) + 9, math.max(f.maxFregs or 0, f.nfregs) + 2, table.concat(f.sig or {}), f.ret or "v", f.vararg and " vararg" or ""))
    for i, c in ipairs(f.consts) do
        if c.kind == "str" then emit(("  const %d str %s"):format(i - 1, q(c.value)))
        elseif c.kind == "builtin" then emit(("  const %d builtin %s"):format(i - 1, c.value))
        else emit(("  const %d %s %s"):format(i - 1, c.kind, tostring(c.value))) end
    end
    for _, op in ipairs(f.code) do emit("  " .. table.concat(op, " ")) end
    emit("end")
end
for _, name in ipairs(moduleOrder) do emit("module " .. name .. " " .. modules[name].id) end
emit("entry " .. modules[entryName].id)
io.write(table.concat(out, "\n"), "\n")
