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
    local f = setmetatable({name = name, consts = {}, constIndex = {}, code = {}, nregs = 1, scopes = {{}}, nparams = 0}, Fn)
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
function Fn:declare(name) local r = self:reg(); self.scopes[#self.scopes][name] = r; return r end
function Fn:lookup(name) for i = #self.scopes, 1, -1 do local r = self.scopes[i][name]; if r then return r end end end
function Fn:push() self.scopes[#self.scopes + 1] = {} end
function Fn:pop() self.scopes[#self.scopes] = nil end
function Fn:here() return #self.code end
function Fn:offset(from, to) return to - from end  -- relative to the op after `from`

local function tokText(tok) return tok.value ~= nil and tok.value or tok.text end

-- Expressions: evaluate `node` into register `dst` (allocating when nil); returns the register.
local expr
local function exprInto(f, node, dst) return expr(f, node, dst) end

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
        if type(a) == "number" then f:op("Move", base + i, a) else exprInto(f, a, base + i) end
    end
    return base, nargs
end

expr = function(f, node, dst)
    local k = node.kind
    if k == "paren" then return expr(f, node.expr, dst) end
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
        local r = f:lookup(name)
        if r then f:op("Move", dst, r)
        elseif funcByName[name] then f:op("K", dst, f:const("func", funcByName[name].id))
        elseif name == "pcall" then f:op("K", dst, f:const("builtin", "pcall"))
        else error("unresolved name " .. name) end
    elseif k == "binop" then
        local op = tokText(node.op)
        if op == "and" or op == "or" then
            expr(f, node.lhs, dst)
            local branch = f:op(op == "and" and "JmpIfNot" or "JmpIf", dst, 0)
            expr(f, node.rhs, dst)
            f:patch(branch, op == "and" and "JmpIfNot" or "JmpIf", dst, f:offset(branch, f:here()))
        else
            local a = expr(f, node.lhs); local b = expr(f, node.rhs)
            local map = {["+"] = "Add", ["-"] = "Sub", ["*"] = "Mul", ["<"] = "Lt", ["<="] = "Le", ["=="] = "Eq", [".."] = "Concat", ["~="] = "Ne", [">"] = "Gt", [">="] = "Ge"}
            local name = assert(map[op], "operator " .. op)
            if name == "Gt" then f:op("Lt", dst, b, a) elseif name == "Ge" then f:op("Le", dst, b, a) else f:op(name, dst, a, b) end
        end
    elseif k == "unop" then
        local op = tokText(node.op)
        local a = expr(f, node.operand)
        if op == "not" then f:op("Not", dst, a) elseif op == "-" then f:op("Neg", dst, a) elseif op == "#" then f:op("Len", dst, a) else error("unop " .. op) end
    elseif k == "dotIndex" then
        local objTy = node.obj.inferredType
        local fname = tokText(node.name)
        if tyTag(objTy) == "nominal" and shapes[objTy.name] then
            local o = expr(f, node.obj)
            f:op("GetSlot", dst, o, (assert(shapes[objTy.name].slotIndex[fname], "field " .. fname)))
        else
            local o = expr(f, node.obj)
            f:op("GetField", dst, o, f:const("str", fname))
        end
    elseif k == "bracketIndex" then
        local o = expr(f, node.obj); local i = expr(f, node.index or node.key or node.expr)
        f:op("GetIdx", dst, o, i)
    elseif k == "call" then
        local callee = node.obj
        if callee.kind == "name" and tokText(callee.token) == "pcall" then
            -- pcall(fn, args...): fn goes in dst+1, args after; results ok at dst, value at dst+1.
            local args = node.args.exprs
            local base = dst
            while f.nregs < base + #args + 1 do f:reg() end
            for i, a in ipairs(args) do exprInto(f, a, base + i) end
            f:op("PCall", base, #args - 1)
        elseif callee.kind == "name" and funcByName[tokText(callee.token)] and not f:lookup(tokText(callee.token)) then
            local base, nargs = callInto(f, node, dst)
            f:op("Call", funcByName[tokText(callee.token)].id, base, nargs)
        else
            local fr = expr(f, callee)
            local base, nargs = callInto(f, node, dst)
            f:op("CallDyn", fr, base, nargs)
        end
    elseif k == "methodCall" then
        local objTy = node.obj.inferredType
        local mname = tokText(node.name)
        local o = expr(f, node.obj)
        if tyTag(objTy) == "nominal" and funcByName[objTy.name .. "." .. mname] then
            local base, nargs = callInto(f, node, dst, o)
            f:op("Call", funcByName[objTy.name .. "." .. mname].id, base, nargs)
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
            local v = expr(f, a.value or a.expr)
            f:op("SetSlot", dst, (assert(shape.slotIndex[tokText(a.name)])), v)
        end
    elseif k == "tableExpr" then
        f:op("NewTable", dst)
        local n = 0
        for _, field in ipairs(node.fields) do
            if field.kind == "fieldNamed" then
                local v = expr(f, field.value)
                f:op("SetField", dst, f:const("str", tokText(field.name)), v)
            elseif field.kind == "fieldItem" then
                n = n + 1
                local i = f:reg(); f:op("K", i, f:const("num", n))
                local v = expr(f, field.value or field.expr)
                f:op("SetIdx", dst, i, v)
            else error("table field " .. field.kind) end
        end
    elseif k == "castExpr" then
        local target = node.inferredType
        local v = expr(f, node.expr, dst)
        if tyTag(target) == "nominal" and shapes[target.name] then f:op("TagCheckRec", dst, v, shapes[target.name].id)
        elseif tyTag(target) == "number" or tyTag(target) == "integer" then f:op("TagCheckNum", dst, v)
        elseif tyTag(target) == "string" then f:op("TagCheckStr", dst, v)
        else if v ~= dst then f:op("Move", dst, v) end end
    else
        error("expression kind " .. tostring(k))
    end
    return dst
end

local block
local function stmt(f, node)
    local k = node.kind
    local mark = f.nregs
    if k == "localStmt" then
        local name = tokText(node.names[1])
        local value = node.exprs and node.exprs[1]
        local r = f:declare(name)
        if value then expr(f, value, r) else f:op("Nil", r) end
        mark = f.nregs
    elseif k == "assignStmt" then
        local target = node.targets[1]
        local value = node.exprs[1]
        if target.kind == "name" then
            local r = assert(f:lookup(tokText(target.token)), "assign to unknown local")
            expr(f, value, r)
        elseif target.kind == "dotIndex" then
            local objTy = target.obj.inferredType
            local o = expr(f, target.obj); local v = expr(f, value)
            if tyTag(objTy) == "nominal" and shapes[objTy.name] then f:op("SetSlot", o, shapes[objTy.name].slotIndex[tokText(target.name)], v)
            else f:op("SetField", o, f:const("str", tokText(target.name)), v) end
        elseif target.kind == "bracketIndex" then
            local o = expr(f, target.obj); local i = expr(f, target.index or target.key or target.expr); local v = expr(f, value)
            f:op("SetIdx", o, i, v)
        else error("assignment target " .. target.kind) end
    elseif k == "callStmt" then
        expr(f, node.expr)
    elseif k == "returnStmt" then
        if #node.exprs == 0 then f:op("RetNil") else local r = expr(f, node.exprs[1]); f:op("Ret", r) end
    elseif k == "ifStmt" then
        local exits = {}
        for _, clause in ipairs(node.clauses) do
            local c = expr(f, clause.cond)
            local branch = f:op("JmpIfNot", c, 0)
            block(f, clause.body)
            exits[#exits + 1] = f:op("Jmp", 0)
            f:patch(branch, "JmpIfNot", c, f:offset(branch, f:here()))
        end
        if node.elseClause then block(f, node.elseClause.body or node.elseClause) end
        for _, e in ipairs(exits) do f:patch(e, "Jmp", f:offset(e, f:here())) end
    elseif k == "whileStmt" then
        local top = f:here()
        local c = expr(f, node.cond)
        local branch = f:op("JmpIfNot", c, 0)
        block(f, node.body)
        local back = f:op("Jmp", 0); f:patch(back, "Jmp", f:offset(back, top))
        f:patch(branch, "JmpIfNot", c, f:offset(branch, f:here()))
    elseif k == "fornumStmt" then
        f:push()
        local var = f:declare(tokText(node.var or node.name))
        expr(f, node.start, var)
        local limit = f:reg(); expr(f, node.stop, limit)
        local step = f:reg(); if node.step then expr(f, node.step, step) else f:op("K", step, f:const("num", 1)) end
        local top = f:here()
        local c = f:reg(); f:op("Le", c, var, limit)
        local branch = f:op("JmpIfNot", c, 0)
        block(f, node.body)
        f:op("Add", var, var, step)
        local back = f:op("Jmp", 0); f:patch(back, "Jmp", f:offset(back, top))
        f:patch(branch, "JmpIfNot", c, f:offset(branch, f:here()))
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

local function defineFunction(f, funcbody)
    local params = funcbody.params or {}
    f.nparams = #params
    for _, p in ipairs(params) do f:declare(tokText(p.name)) end
    block(f, funcbody.body)
    if f.code[#f.code] == nil or (f.code[#f.code][1] ~= "Ret" and f.code[#f.code][1] ~= "RetNil") then f:op("RetNil") end
end

-- Pass 1: declare shapes and functions so references resolve regardless of order.
local root = tree.root or tree
local stats = root.blocks[1].stats
for _, s in ipairs(stats) do if s.kind == "recordDecl" then declareShape(s) end end
local pending = {}
for _, s in ipairs(stats) do
    if s.kind == "localFuncStmt" then pending[#pending + 1] = {newFn(tokText(s.name)), s.body}
    elseif s.kind == "recordDecl" then
        local shape = shapes[tokText(s.name)]
        for _, entry in ipairs(s.entries) do
            if entry.kind == "inlineMethod" then
                local fn = newFn(shape.name .. "." .. tokText(entry.name))
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
    emit(("function %s %d %d %d"):format(f.name, f.id, f.nparams, f.nregs + 2))
    for i, c in ipairs(f.consts) do
        if c.kind == "str" then emit(("  const %d str %s"):format(i - 1, q(c.value))) else emit(("  const %d %s %s"):format(i - 1, c.kind, tostring(c.value))) end
    end
    for _, op in ipairs(f.code) do emit("  " .. table.concat(op, " ")) end
    emit("end")
end
emit("entry " .. (funcByName.main and funcByName.main.id or 0))
io.write(table.concat(out, "\n"), "\n")
