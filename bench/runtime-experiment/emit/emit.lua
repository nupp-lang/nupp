-- A whole-language bytecode emitter for a bounded slice of Nupp, walking the
-- checked tree the compiler already produces. Run as `nupp run emit.lua FILE`.
-- Emits a text image: shapes, then functions with constants and ops, then
-- the entry function's name. Opcode names are the runtime's `Op` variants.
local envMod = require("nupp.compiler.project.env")
local compile = require("nupp.tools.cli.compile")

local path = assert(arg[1], "source file")
local env = envMod.new(arg[2] or ".")
local collected = {}
local tree = compile.check(path, env, {}, collected)
for _, d in ipairs(collected) do io.stderr:write(tostring(d.code), " ", tostring(d.msg), "\n") end
assert(tree, "check failed")

local out = {}
local function emit(s) out[#out + 1] = s end

-- Shapes: one per record declaration, slots in declared order, methods as
-- functions named Record.method with self first.
local shapes, shapeOrder = {}, {}
local functions, funcByName = {}, {}

local function tyTag(t) return type(t) == "table" and t.tag or "?" end
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
    local name = node.name.value or node.name.text
    local shape = {id = #shapeOrder, name = name, slots = {}, slotIndex = {}, methods = {}}
    shapes[name] = shape
    shapeOrder[#shapeOrder + 1] = shape
    local nominal = node.resolvedType
    for _, entry in ipairs(node.entries) do
        if entry.kind == "fieldDecl" then
            local fname = entry.name.value or entry.name.text
            shape.slotIndex[fname] = #shape.slots
            shape.slots[#shape.slots + 1] = {name = fname, ty = slotTy(nominal and nominal.byname and nominal.byname[fname])}
        end
    end
    return shape
end

-- Function emission ---------------------------------------------------------
local Fn = {}
Fn.__index = Fn
local function newFn(name)
    local f = setmetatable({name = name, consts = {}, constIndex = {}, code = {}, nregs = 1, nfregs = 0, scopes = {{}}, nparams = 0}, Fn)
    functions[#functions + 1] = f
    f.id = #functions - 1
    funcByName[name] = f
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
function Fn:reg() local r = self.nregs; self.nregs = r + 1; return r end
function Fn:freg() local r = self.nfregs; self.nfregs = r + 1; return r end
function Fn:declare(name, class) local r = class == "f" and self:freg() or self:reg(); self.scopes[#self.scopes][name] = {reg = r, class = class or "v"}; return r end
function Fn:lookup(name) for i = #self.scopes, 1, -1 do local r = self.scopes[i][name]; if r then return r.reg, r.class end end end
function Fn:push() self.scopes[#self.scopes + 1] = {} end
function Fn:pop() self.scopes[#self.scopes] = nil end
function Fn:here() return #self.code end
function Fn:offset(from, to) return to - from end  -- relative to the op after `from`

local function tokText(tok) return tok.value ~= nil and tok.value or tok.text end

local function isNumeric(t)
    local tag = tyTag(t)
    if tag == "number" or tag == "integer" then return true end
    if tag == "literal" then return isNumeric(t.base) end
    return false
end

-- Move a value between classes: a float register boxes into a value register,
-- a value register of numeric type unboxes into a float register.
local function coerce(f, reg, class, want, dst)
    if class == want then
        if dst and dst ~= reg then f:op(want == "f" and "FMov" or "Move", dst, reg) return dst end
        return reg
    end
    if want == "v" then dst = dst or f:reg(); f:op("FBox", dst, reg); return dst end
    dst = dst or f:freg(); f:op("FUnbox", dst, reg); return dst
end

-- Expressions: evaluate `node` into register `dst` (allocating when nil); returns the register.
local expr
local function exprInto(f, node, dst) return expr(f, node, dst, "v") end
local function exprAs(f, node, want, dst)
    local r, c = expr(f, node, nil, want)
    return coerce(f, r, c, want, dst)
end

-- A static call under the typed convention: value arguments into dst+1..,
-- float arguments into a fresh float window; the result lands in dst or in
-- the float window's first register, by the callee's return class.
local function callTyped(f, callee, node, dst, extraSelf)
    local args = node.args and node.args.exprs or {}
    local all = {}
    if extraSelf then all[1] = extraSelf end
    for _, a in ipairs(args) do all[#all + 1] = a end
    assert(#all == #callee.sig, "arity for " .. callee.name)
    local nv, nf = 0, 0
    for _, c in ipairs(callee.sig) do if c == "f" then nf = nf + 1 else nv = nv + 1 end end
    local base = dst
    while f.nregs < base + nv + 1 do f:reg() end
    local fbase = f.nfregs
    for _ = 1, math.max(nf, 1) do f:freg() end
    local vi, fi = 0, 0
    for i, a in ipairs(all) do
        if callee.sig[i] == "f" then
            if type(a) == "number" then f:op("FUnbox", fbase + fi, a) else exprAs(f, a, "f", fbase + fi) end
            fi = fi + 1
        else
            vi = vi + 1
            if type(a) == "number" then f:op("Move", base + vi, a) else exprAs(f, a, "v", base + vi) end
        end
    end
    f:op("CallT", callee.id, base, fbase, #all)
    if callee.ret == "f" then return fbase, "f" end
    return base, "v"
end

local function callInto(f, node, dst, extraSelf)
    -- Common call layout: base = dst, args at dst+1..; registers above dst are temporaries.
    local base = dst
    local nargs = 0
    local args = node.args and node.args.exprs or {}
    local argRegs = {}
    if extraSelf then nargs = nargs + 1; argRegs[1] = extraSelf end
    for i, a in ipairs(args) do nargs = nargs + 1; argRegs[nargs] = a end
    -- Ensure the registers dst+1.. are allocated for the arguments.
    while f.nregs < base + nargs + 1 do f:reg() end
    for i, a in ipairs(argRegs) do
        if type(a) == "number" then f:op("Move", base + i, a) else exprAs(f, a, "v", base + i) end
    end
    return base, nargs
end

-- Returns the register holding the result and its class. `dst` is honoured
-- only when it has class `want`; callers that need a particular register use exprAs.
expr = function(f, node, dst, want)
    local k = node.kind
    if k == "paren" then return expr(f, node.expr, dst, want) end
    local numeric = isNumeric(node.inferredType)
    if k == "number" then
        local fr = f:freg(); f:op("FK", fr, tonumber(tokText(node.token)))
        return fr, "f"
    end
    if numeric and k == "binop" then
        local op = tokText(node.op)
        local map = {["+"] = "FAdd", ["-"] = "FSub", ["*"] = "FMul", ["/"] = "FDiv"}
        if map[op] then
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
    if k == "name" then
        local name = tokText(node.token)
        local r, c = f:lookup(name)
        if r then return r, c end
    end
    if numeric and k == "dotIndex" then
        local objTy = node.obj.inferredType
        local fname = tokText(node.name)
        if tyTag(objTy) == "nominal" and shapes[objTy.name] then
            local o = exprAs(f, node.obj, "v")
            local d = f:freg(); f:op("GetSlotF", d, o, (assert(shapes[objTy.name].slotIndex[fname]))); return d, "f"
        end
    end
    if numeric and k == "bracketIndex" then
        -- A numeric element read from a value container unboxes after the read.
        local o = exprAs(f, node.obj, "v"); local i = exprAs(f, node.expr, "f")
        local d = f:reg(); f:op("GetIdxF", d, o, i)
        local fr = f:freg(); f:op("FUnbox", fr, d); return fr, "f"
    end
    if k == "binop" then
        local op = tokText(node.op)
        local cmp = {["<"] = "FCmpLt", ["<="] = "FCmpLe", [">"] = "FCmpLt", [">="] = "FCmpLe", ["=="] = "FCmpEq", ["~="] = "FCmpNe"}
        if cmp[op] and isNumeric(node.lhs.inferredType) and isNumeric(node.rhs.inferredType) then
            local a = exprAs(f, node.lhs, "f"); local b = exprAs(f, node.rhs, "f")
            local i = f:freg() -- integer registers share the float counter in this emitter's numbering scheme
            if op == ">" or op == ">=" then f:op(cmp[op], i, b, a) else f:op(cmp[op], i, a, b) end
            local d = f:reg(); f:op("BoolFromI", d, i); return d, "v"
        end
    end
    -- Everything else lands in a value register.
    dst = (want ~= "f" and dst) or nil
    dst = dst or f:reg()
    if k == "number" then
        f:op("K", dst, f:const("num", tonumber(tokText(node.token))))
    elseif k == "string" then
        local raw = tokText(node.token)
        local text = raw
        if raw:sub(1, 1) == '"' or raw:sub(1, 1) == "'" then
            text = raw:sub(2, -2):gsub("\\(.)", {n = "\n", t = "\t", ["\\"] = "\\", ['"'] = '"', ["'"] = "'"})
        end
        f:op("K", dst, f:const("str", text))
    elseif k == "trueExpr" then f:op("K", dst, f:const("true", ""))
    elseif k == "falseExpr" then f:op("K", dst, f:const("false", ""))
    elseif k == "nil" or k == "nilExpr" then f:op("Nil", dst)
    elseif k == "name" then
        local name = tokText(node.token)
        if funcByName[name] then f:op("K", dst, f:const("func", funcByName[name].id))
        elseif name == "pcall" then f:op("K", dst, f:const("builtin", "pcall"))
        else error("unresolved name " .. name) end
    elseif k == "binop" then
        local op = tokText(node.op)
        if op == "and" or op == "or" then
            exprAs(f, node.lhs, "v", dst)
            local branch = f:op(op == "and" and "JmpIfNot" or "JmpIf", dst, 0)
            exprAs(f, node.rhs, "v", dst)
            f:patch(branch, op == "and" and "JmpIfNot" or "JmpIf", dst, f:offset(branch, f:here()))
        else
            local a = exprAs(f, node.lhs, "v"); local b = exprAs(f, node.rhs, "v")
            local map = {["+"] = "Add", ["-"] = "Sub", ["*"] = "Mul", ["<"] = "Lt", ["<="] = "Le", ["=="] = "Eq", [".."] = "Concat", ["~="] = "Ne", [">"] = "Gt", [">="] = "Ge"}
            local name = assert(map[op], "operator " .. op)
            if name == "Gt" then f:op("Lt", dst, b, a) elseif name == "Ge" then f:op("Le", dst, b, a) else f:op(name, dst, a, b) end
        end
    elseif k == "unop" then
        local op = tokText(node.op)
        local a = exprAs(f, node.operand, "v")
        if op == "not" then f:op("Not", dst, a) elseif op == "-" then f:op("Neg", dst, a) elseif op == "#" then f:op("Len", dst, a) else error("unop " .. op) end
    elseif k == "dotIndex" then
        local objTy = node.obj.inferredType
        local fname = tokText(node.name)
        if tyTag(objTy) == "nominal" and shapes[objTy.name] then
            local o = exprAs(f, node.obj, "v")
            f:op("GetSlot", dst, o, (assert(shapes[objTy.name].slotIndex[fname], "field " .. fname)))
        else
            local o = exprAs(f, node.obj, "v")
            f:op("GetField", dst, o, f:const("str", fname))
        end
    elseif k == "bracketIndex" then
        local o = exprAs(f, node.obj, "v")
        if isNumeric(node.expr.inferredType) then
            local i = exprAs(f, node.expr, "f"); f:op("GetIdxF", dst, o, i)
        else
            local i = exprAs(f, node.expr, "v"); f:op("GetIdx", dst, o, i)
        end
    elseif k == "call" then
        local callee = node.obj
        if callee.kind == "name" and tokText(callee.token) == "pcall" then
            -- pcall(fn, args...): fn goes in dst+1, args after; results ok at dst, value at dst+1.
            local args = node.args.exprs
            local base = dst
            while f.nregs < base + #args + 1 do f:reg() end
            for i, a in ipairs(args) do exprAs(f, a, "v", base + i) end
            f:op("PCall", base, #args - 1)
        elseif callee.kind == "name" and funcByName[tokText(callee.token)] and not f:lookup(tokText(callee.token)) then
            local r, c = callTyped(f, funcByName[tokText(callee.token)], node, dst)
            return r, c
        else
            local fr = exprAs(f, callee, "v")
            local base, nargs = callInto(f, node, dst)
            f:op("CallDyn", fr, base, nargs)
        end
    elseif k == "methodCall" then
        local objTy = node.obj.inferredType
        local mname = tokText(node.name)
        local o = exprAs(f, node.obj, "v")
        if tyTag(objTy) == "nominal" and funcByName[objTy.name .. "." .. mname] then
            local r, c = callTyped(f, funcByName[objTy.name .. "." .. mname], node, dst, o)
            return r, c
        else
            local base, nargs = callInto(f, node, dst, o)
            f:op("CallMethod", f:const("str", mname), base, nargs)
        end
    elseif k == "newExpr" then
        local call = node.call
        local ty = node.inferredType
        local shape = assert(shapes[ty.name], "new of unknown record")
        f:op("NewRecord", dst, shape.id)
        for _, a in ipairs(call.args.exprs or {}) do
            assert(a.kind == "namedArg", "new with positional arguments")
            local slot = (assert(shape.slotIndex[tokText(a.name)]))
            if shape.slots[slot + 1].ty == "num" then
                local v = exprAs(f, a.value, "f"); f:op("SetSlotF", dst, slot, v)
            else
                local v = exprAs(f, a.value, "v"); f:op("SetSlot", dst, slot, v)
            end
        end
    elseif k == "tableExpr" then
        f:op("NewTable", dst)
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
            else error("table field " .. field.kind) end
        end
    elseif k == "castExpr" then
        local target = node.inferredType
        local v = exprAs(f, node.expr, "v", dst)
        if tyTag(target) == "nominal" and shapes[target.name] then f:op("TagCheckRec", dst, v, shapes[target.name].id)
        elseif tyTag(target) == "number" or tyTag(target) == "integer" then f:op("TagCheckNum", dst, v)
        elseif tyTag(target) == "string" then f:op("TagCheckStr", dst, v)
        else if v ~= dst then f:op("Move", dst, v) end end
    else
        error("expression kind " .. tostring(k))
    end
    return dst, "v"
end

local block
local function stmt(f, node)
    local k = node.kind
    local mark = f.nregs
    if k == "localStmt" then
        local name = tokText(node.names[1])
        local value = node.exprs and node.exprs[1]
        local declared = node.types and node.types[1] and node.types[1].resolvedType
        local class = (isNumeric(declared) or (not declared and value and isNumeric(value.inferredType))) and "f" or "v"
        local r = f:declare(name, class)
        if value then exprAs(f, value, class, r) elseif class == "v" then f:op("Nil", r) else f:op("FK", r, 0) end
        mark = f.nregs
    elseif k == "assignStmt" then
        local target = node.targets[1]
        local value = node.exprs[1]
        if target.kind == "name" then
            local r, c = f:lookup(tokText(target.token))
            assert(r, "assign to unknown local")
            exprAs(f, value, c, r)
        elseif target.kind == "dotIndex" then
            local objTy = target.obj.inferredType
            local o = exprAs(f, target.obj, "v")
            if tyTag(objTy) == "nominal" and shapes[objTy.name] then
                local shape = shapes[objTy.name]; local slot = shape.slotIndex[tokText(target.name)]
                if shape.slots[slot + 1].ty == "num" then local v = exprAs(f, value, "f"); f:op("SetSlotF", o, slot, v)
                else local v = exprAs(f, value, "v"); f:op("SetSlot", o, slot, v) end
            else local v = exprAs(f, value, "v"); f:op("SetField", o, f:const("str", tokText(target.name)), v) end
        elseif target.kind == "bracketIndex" then
            local o = exprAs(f, target.obj, "v"); local v = exprAs(f, value, "v")
            if isNumeric(target.expr.inferredType) then
                local i = exprAs(f, target.expr, "f"); f:op("SetIdxF", o, i, v)
            else
                local i = exprAs(f, target.expr, "v"); f:op("SetIdx", o, i, v)
            end
        else error("assignment target " .. target.kind) end
    elseif k == "callStmt" then
        expr(f, node.expr, nil, "v")
    elseif k == "returnStmt" then
        if #node.exprs == 0 then f:op("RetNil") else
            local r, c = expr(f, node.exprs[1], nil, nil)
            if f.ret == "f" then local fr = coerce(f, r, c, "f"); f:op("FRet", fr) else local vr = coerce(f, r, c, "v"); f:op("Ret", vr) end
        end
    elseif k == "ifStmt" then
        local exits = {}
        for _, clause in ipairs(node.clauses) do
            local c = exprAs(f, clause.cond, "v")
            local branch = f:op("JmpIfNot", c, 0)
            block(f, clause.body)
            exits[#exits + 1] = f:op("Jmp", 0)
            f:patch(branch, "JmpIfNot", c, f:offset(branch, f:here()))
        end
        if node.elseClause then block(f, node.elseClause.body or node.elseClause) end
        for _, e in ipairs(exits) do f:patch(e, "Jmp", f:offset(e, f:here())) end
    elseif k == "whileStmt" then
        local top = f:here()
        local c = exprAs(f, node.cond, "v")
        local branch = f:op("JmpIfNot", c, 0)
        block(f, node.body)
        local back = f:op("Jmp", 0); f:patch(back, "Jmp", f:offset(back, top))
        f:patch(branch, "JmpIfNot", c, f:offset(branch, f:here()))
    elseif k == "fornumStmt" then
        -- Numeric loops run on float registers; the condition is a float compare
        -- whose integer flag drives the branch directly.
        f:push()
        local var = f:declare(tokText(node.var), "f")
        exprAs(f, node.start, "f", var)
        local limit = exprAs(f, node.stop, "f")
        local step = f:freg(); if node.step then exprAs(f, node.step, "f", step) else f:op("FK", step, 1) end
        local top = f:here()
        local c = f:freg(); f:op("FCmpLe", c, var, limit)
        local branch = f:op("JmpIfIZero", c, 0)
        block(f, node.body)
        f:op("FAdd", var, var, step)
        local back = f:op("Jmp", 0); f:patch(back, "Jmp", f:offset(back, top))
        f:patch(branch, "JmpIfIZero", c, f:offset(branch, f:here()))
        f:pop()
    elseif k == "localFuncStmt" or k == "recordDecl" then
        -- Declared ahead of time; nothing to do inline.
    else
        error("statement kind " .. tostring(k))
    end
    f.nregs = math.max(mark, f.nregs)
end

block = function(f, node)
    f:push()
    for _, s in ipairs(node.stats or node.body and node.body.stats or {}) do stmt(f, s) end
    f:pop()
end

-- The calling convention: parameters of numeric type travel in float
-- registers, in declaration order among the float parameters; everything
-- else travels in value registers, in declaration order among those. The
-- result travels as a float when the declared return type is numeric.
local function signatureOf(f, funcbody)
    -- The checker's signature type carries the resolved parameter and result types.
    local st = funcbody.signatureType or {}
    local params = funcbody.params or {}
    f.sig = {}
    f.nparams = #params
    for i = 1, #params do
        f.sig[i] = isNumeric(st.params and st.params[i]) and "f" or "v"
    end
    f.ret = (st.rets and st.rets[1] and isNumeric(st.rets[1])) and "f" or "v"
end

local function defineFunction(f, funcbody)
    local params = funcbody.params or {}
    -- Float parameters are float registers 0.., value parameters value registers 1..
    local nf = 0
    for i, p in ipairs(params) do
        if f.sig[i] == "f" then f:declare(tokText(p.name), "f"); nf = nf + 1 else f:declare(tokText(p.name), "v") end
    end
    block(f, funcbody.body)
    if f.code[#f.code] == nil or (f.code[#f.code][1] ~= "Ret" and f.code[#f.code][1] ~= "RetNil") then f:op("RetNil") end
end

-- Pass 1: declare shapes and functions so references resolve regardless of order.
local root = tree.root or tree
local stats = root.blocks[1].stats
for _, s in ipairs(stats) do if s.kind == "recordDecl" then declareShape(s) end end
local pending = {}
for _, s in ipairs(stats) do
    if s.kind == "localFuncStmt" then local fn = newFn(tokText(s.name)); signatureOf(fn, s.body); pending[#pending + 1] = {fn, s.body}
    elseif s.kind == "recordDecl" then
        local shape = shapes[tokText(s.name)]
        for _, entry in ipairs(s.entries) do
            if entry.kind == "inlineMethod" then
                local fn = newFn(shape.name .. "." .. tokText(entry.name))
                signatureOf(fn, entry.body)
                shape.methods[tokText(entry.name)] = fn.id
                pending[#pending + 1] = {fn, entry.body}
            end
        end
    end
end
-- Resolve slot types that name records declared later.
for _, shape in ipairs(shapeOrder) do end
for _, p in ipairs(pending) do defineFunction(p[1], p[2]) end

-- Output -------------------------------------------------------------------
local function q(s) return '"' .. s:gsub('[%c"\\]', function(c) return string.format("\\%03d", c:byte()) end) .. '"' end
for _, shape in ipairs(shapeOrder) do
    local parts = {"shape", shape.id, shape.name}
    for _, slot in ipairs(shape.slots) do parts[#parts + 1] = slot.name .. ":" .. slot.ty end
    for mname, fid in pairs(shape.methods) do parts[#parts + 1] = "method:" .. mname .. "=" .. fid end
    emit(table.concat(parts, " "))
end
for _, f in ipairs(functions) do
    emit(("function %s %d %d %d %d %s:%s"):format(f.name, f.id, f.nparams, f.nregs + 2, f.nfregs + 2, table.concat(f.sig or {}), f.ret or "v"))
    for i, c in ipairs(f.consts) do
        if c.kind == "str" then emit(("  const %d str %s"):format(i - 1, q(c.value))) else emit(("  const %d %s %s"):format(i - 1, c.kind, tostring(c.value))) end
    end
    for _, op in ipairs(f.code) do emit("  " .. table.concat(op, " ")) end
    emit("end")
end
emit("entry " .. (funcByName.main and funcByName.main.id or 0))
if funcByName.hot then emit("entry2 " .. funcByName.hot.id) end
io.write(table.concat(out, "\n"), "\n")
