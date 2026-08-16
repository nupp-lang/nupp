-- A test-only compiler for a deliberately small `@aot` subset.
--
-- It consumes Nupp's real CST, validates an admitted whole-function shape,
-- verifies a sealed typed IR, and emits private scalar C for Clang to optimize.

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local root = here .. "../.."
package.path = root .. "/build/?.lua;" .. package.path

local lane = require("nupp.compiler.aot.lane")
local intensity = require("nupp.compiler.aot.intensity")
local scalarIR = require("nupp.compiler.aot.scalar")
local irVerify = require("nupp.compiler.aot.verify")
local irText = require("nupp.compiler.aot.text")
local rewriteRules = require("nupp.compiler.aot.rewrite")
local emitRules = require("nupp.compiler.aot.emit")
local bindingRules = require("nupp.compiler.aot.binding")
local parser = require("nupp.compiler.parser")
local cst = require("nupp.compiler.cst")

local compiler = {}
local STOP = {}

local function firstToken(node)
   return node and cst.firstToken(node) or nil
end

local function site(node)
   local token = firstToken(node)
   return {line = token and token.line or 1, column = token and token.col or 1}
end

local function nameOf(node)
   return node and node.kind == "name" and node.token and node.token.text or nil
end

local function compactType(node)
   return node and cst.textOf(node):gsub("%s+", "") or ""
end

local function receiverName(node)
   return nameOf(node)
end

local function dotCount(node)
   if not node or node.kind ~= "dotIndex" or not node.name or node.name.text ~= "count" then
      return nil
   end
   return receiverName(node.obj)
end

local function dottedName(node)
   if not node then return nil end
   if node.kind == "name" then return nameOf(node) end
   if node.kind == "dotIndex" and node.name then
      local base = dottedName(node.obj)
      return base and base .. "." .. node.name.text or nil
   end
   return nil
end

local privateSymbol = scalarIR.privateSymbol
local cIdentifier = scalarIR.cIdentifier

local function diagnostic(filename, node, message)
   local at = site(node)
   return {file = filename, line = at.line, column = at.column, message = message}
end

local function renderDiagnostic(value)
   return ("%s:%d:%d: kernel subset: %s"):format(
      value.file, value.line, value.column, value.message
   )
end

compiler.renderDiagnostic = renderDiagnostic

local function copyEnvironment(environment)
   local copied = {}
   for name, value in pairs(environment) do copied[name] = value end
   return copied
end

local function parseKernel(source, filename, checked)
   local parsed = checked or parser.parse(source, filename)
   if #parsed.errors > 0 then
      local diagnostics = {}
      for _, problem in ipairs(parsed.errors) do
         diagnostics[#diagnostics + 1] = {
            file = filename,
            line = problem.line or 1,
            column = problem.col or 1,
            message = "syntax error: " .. problem.msg,
         }
      end
      return nil, diagnostics
   end

   local diagnostics = {}
   local function reject(node, message)
      diagnostics[#diagnostics + 1] = diagnostic(filename, node, message)
      error(STOP, 0)
   end

   local ok, ir = pcall(function()
      local applications, helperDecls, structDecls = {}, {}, {}
      for _, block in ipairs(parsed.root.blocks or {}) do
         for _, stat in ipairs(block.stats or {}) do
            if stat.kind == "pragmaStmt" then
               -- Annotations stack, so walk the whole chain rather than only
               -- looking at the outermost one. `@aot` may be written above or
               -- below `@relax`, and both orders mean the same thing.
               local chain, cursor = {}, stat
               while cursor and cursor.kind == "pragmaStmt" do
                  chain[#chain + 1] = cursor
                  cursor = cursor.stat
               end
               local isAot = false
               for _, link in ipairs(chain) do
                  if link.name and link.name.text == "aot" then isAot = true end
               end
               if checked then
                  isAot = cursor and cursor.body and cursor.body.aotRequired == true
               end
               if isAot then
                  applications[#applications + 1] = {chain = chain, tail = cursor, at = stat}
               end
            elseif stat.kind == "localFuncStmt" and stat.name then
               helperDecls[stat.name.text] = stat
            elseif stat.kind == "recordDecl" and stat.declKind == "struct" and stat.name then
               structDecls[stat.name.text] = stat
            end
         end
      end
      if #applications == 0 then
         reject(parsed.root, "no @aot function was found")
      elseif #applications > 1 then
         reject(applications[2], "this spike accepts exactly one @aot function")
      end

      local selected = applications[1]
      local application = selected.at
      local fn = selected.tail
      if not fn or fn.kind ~= "localFuncStmt" then
         reject(fn or application, "@aot must decorate a local function with a visible body")
      end
      -- `@relax("fp-contract")` is the only relaxation this spike acts on. It
      -- permits the backend to fuse a multiply and an add into one rounding,
      -- which is faster and gives a different answer, so it is per function and
      -- appears in the IR rather than being a build-wide compiler flag.
      local body = fn.body
      local fpContract = body.relaxedGuarantees
         and body.relaxedGuarantees["fp-contract"] == true or false
      -- Lane lowering is attempted for every admitted body; `lanes = false`
      -- declines it. A body that cannot lower lane-parallel is not an error --
      -- it compiles scalar, and the vectorisation check is what has something to
      -- say about it.
      local wantsLanes = body.lanesDeclined ~= true
      local lanesRequired = body.lanesRequired == true
      if not checked then
         for _, link in ipairs(selected.chain) do
            local written = link.name and link.name.text
            if written == "aot" then
               for _, arg in ipairs(link.annotationArgs or {}) do
                  local name = arg.name and arg.name.text
                  if name == "lanes" then
                     if arg.expr and arg.expr.kind == "falseExpr" then wantsLanes = false end
                     if arg.expr and arg.expr.kind == "trueExpr" then lanesRequired = true end
                  else
                     reject(link, "@aot takes lanes = true, lanes = false, or nothing")
                  end
               end
            elseif written == "relax" then
               for _, arg in ipairs(link.annotationArgs or {}) do
                  local token = firstToken(arg.expr)
                  local text = token and token.text or ""
                  if text:sub(1, 1) == '"' or text:sub(1, 1) == "'" then
                     text = text:sub(2, -2)
                  end
                  if text == "fp-contract" then fpContract = true end
               end
            end
         end
      end
      if not body or body.generics or body.varargParam or body.captureTakes or body.captureBorrows then
         reject(body or fn, "generic, variadic, and capturing kernels are not admitted")
      end
      if #(body.rets or {}) ~= 1 or compactType(body.rets[1]) ~= "nil" then
         reject(body, "the map-kernel prototype must return nil")
      end

      local storageTypes = {float = "f32", int32 = "i32", uint32 = "u32"}
      local layouts, layoutByName = {}, {}
      local function lowerLayout(name, at)
         if layoutByName[name] then return layoutByName[name] end
         local declaration = structDecls[name]
         if not declaration then reject(at, "span element " .. name .. " is not a visible local struct") end
         if declaration.generics or declaration.supertypes and #declaration.supertypes > 0 then
            reject(declaration, "native structs must be non-generic and have no supertypes")
         end
         local layout = {name = name, cName = "Ks" .. name, fields = {}, source = site(declaration)}
         local seen = {}
         for _, entry in ipairs(declaration.entries or {}) do
            if entry.kind ~= "fieldDecl" or not entry.name then
               reject(entry, "native structs initially contain only stored fields")
            end
            local fieldName = entry.name.text
            local fieldType = storageTypes[compactType(entry.type)]
            if not fieldType then
               reject(entry.type or entry, "native struct field type " .. compactType(entry.type) .. " is not admitted")
            end
            if seen[fieldName] then reject(entry, "duplicate native struct field " .. fieldName) end
            seen[fieldName] = true
            layout.fields[#layout.fields + 1] = {
               name = fieldName, type = fieldType, source = site(entry),
            }
         end
         if #layout.fields == 0 then reject(declaration, "native structs need at least one field") end
         layoutByName[name] = layout
         layouts[#layouts + 1] = layout
         return layout
      end

      local function spanElement(spelling, prefix, at)
         local element = spelling:match("^" .. prefix .. "<(.+)>$")
         if not element then return nil end
         local storage = storageTypes[element]
         if storage then return {kind = "scalar", type = storage, sourceType = element} end
         return {kind = "struct", type = "struct:" .. element, layout = lowerLayout(element, at)}
      end

      local params, byName, spans, writes, reads = {}, {}, {}, {}, {}
      for _, raw in ipairs(body.params or {}) do
         local name = raw.name and raw.name.text
         if not name then reject(raw, "every kernel parameter must be named") end
         if byName[name] then reject(raw, "duplicate kernel parameter " .. name) end

         local spelling = compactType(raw.type)
         local mode = raw.modeTok and raw.modeTok.text or nil
         local param
         local writeElement = spanElement(spelling, "span%.WriteSpan", raw.type or raw)
         local readElement = spanElement(spelling, "span%.Span", raw.type or raw)
         if writeElement then
            if mode ~= "exclusive" then
               reject(raw, "a writable float span must be declared exclusive")
            end
            param = {
               kind = "write_span", name = name, type = writeElement.type,
               element = writeElement, region = "r" .. tostring(#spans), access = "readwrite",
               ownership = "exclusive", source = site(raw),
            }
            writes[#writes + 1] = param
            spans[#spans + 1] = param
         elseif readElement then
            if mode ~= "borrows" then
               reject(raw, "a readable float span must be declared borrows")
            end
            param = {
               kind = "read_span", name = name, type = readElement.type,
               element = readElement,
               region = "r" .. tostring(#spans), access = "read",
               ownership = "shared", source = site(raw),
            }
            reads[#reads + 1] = param
            spans[#spans + 1] = param
         elseif spelling == "float" or spelling == "number" or spelling == "integer" then
            if mode then reject(raw, "a uniform float parameter has no ownership mode") end
            param = {
               kind = "uniform", name = name, type = spelling == "float" and "f32" or "f64",
               sourceType = spelling, source = site(raw),
            }
         elseif spelling == "uint32" or spelling == "int32" then
            if mode then reject(raw, "a uniform integer parameter has no ownership mode") end
            param = {
               kind = "uniform", name = name, type = spelling == "uint32" and "u32" or "i32",
               sourceType = spelling, source = site(raw),
            }
         else
            reject(raw.type or raw, "parameter type " .. spelling .. " is not admitted")
         end
         params[#params + 1] = param
         byName[name] = param
      end
      if #writes == 0 then reject(body, "the map-kernel prototype needs a writable span") end
      if #reads == 0 then reject(body, "the map-kernel prototype needs a readable span") end
      local primary = writes[1]

      local regions, aliasFacts = {}, {}
      for _, param in ipairs(spans) do
         regions[#regions + 1] = {
            id = param.region, param = param.name, access = param.access,
            proof = param.ownership .. "_borrow",
         }
      end
      for left = 1, #spans do
         for right = left + 1, #spans do
            local hasWrite = spans[left].kind == "write_span" or spans[right].kind == "write_span"
            aliasFacts[#aliasFacts + 1] = {
               relation = hasWrite and "disjoint" or "may_alias",
               left = spans[left].region,
               right = spans[right].region,
               proof = hasWrite and "exclusive_borrow" or "shared_borrows",
            }
         end
      end

      local stats = body.body and body.body.stats or {}
      if #stats ~= 2 and #stats ~= 3 then
         reject(body.body or body, "the admitted body is a length guard, optional range guard, and one numeric loop")
      end

      local guard = stats[1]
      if guard.kind ~= "ifStmt" or #(guard.clauses or {}) ~= 1 or guard.elseClause then
         reject(guard, "the first statement must be a single length-mismatch guard")
      end
      local clause = guard.clauses[1]
      local guardBody = clause.body and clause.body.stats or {}
      local errorCall = guardBody[1] and guardBody[1].kind == "callStmt" and guardBody[1].expr or nil
      if #guardBody ~= 1 or not errorCall or errorCall.kind ~= "call"
         or nameOf(errorCall.obj) ~= "error"
      then
         reject(guard, "a length guard must call error directly")
      end

      local guarded = {}
      local function collectGuards(expr)
         if expr and expr.kind == "binop" and expr.op and expr.op.text == "or" then
            collectGuards(expr.lhs)
            collectGuards(expr.rhs)
            return
         end
         if not expr or expr.kind ~= "binop" or not expr.op or expr.op.text ~= "~=" then
            reject(expr or guard, "the guard may only compare span counts with ~=")
         end
         local left, right = dotCount(expr.lhs), dotCount(expr.rhs)
         local other
         if left == primary.name then other = right
         elseif right == primary.name then other = left
         end
         if not other or not byName[other] or not byName[other].region or other == primary.name then
            reject(expr, "each guard comparison must compare the primary output with another span")
         end
         if guarded[other] then reject(expr, "duplicate length guard for " .. other) end
         guarded[other] = site(expr)
      end
      collectGuards(clause.cond)
      local guards = {}
      for _, span in ipairs(spans) do
         if span ~= primary then
            if not guarded[span.name] then reject(guard, "the length guard does not cover span " .. span.name) end
            guards[#guards + 1] = {
               op = "equal_count", left = primary.name, right = span.name,
               source = guarded[span.name],
            }
         end
      end

      local rangeGuard
      local loop = stats[#stats]
      if #stats == 3 then
         local candidate = stats[2]
         if candidate.kind ~= "ifStmt" or #(candidate.clauses or {}) ~= 1 or candidate.elseClause then
            reject(candidate, "the optional second statement must be a range guard")
         end
         local rangeClause = candidate.clauses[1]
         local rangeBody = rangeClause.body and rangeClause.body.stats or {}
         local rangeError = rangeBody[1] and rangeBody[1].kind == "callStmt" and rangeBody[1].expr or nil
         if #rangeBody ~= 1 or not rangeError or rangeError.kind ~= "call"
            or nameOf(rangeError.obj) ~= "error"
         then
            reject(candidate, "a range guard must call error directly")
         end
         local written = cst.textOf(rangeClause.cond):gsub("%s+", "")
         local firstName, lastName = written:match(
            "^([%a_][%w_]*)<1or([%a_][%w_]*)>[%a_][%w_]*%.countor"
         )
         local expected = firstName and (
            firstName .. "<1or" .. lastName .. ">" .. primary.name .. ".countor"
               .. firstName .. ">" .. lastName .. "+1"
         ) or ""
         if written ~= expected then
            reject(rangeClause.cond, "range guard must be `first < 1 or last > output.count or first > last + 1`")
         end
         local firstParam, lastParam = byName[firstName], byName[lastName]
         if not firstParam or not lastParam or firstParam.kind ~= "uniform" or lastParam.kind ~= "uniform"
            or firstParam.sourceType ~= "integer" or lastParam.sourceType ~= "integer"
         then
            reject(rangeClause.cond, "range bounds must be uniform integer parameters")
         end
         rangeGuard = {first = firstName, last = lastName, count = primary.name, source = site(candidate)}
      end
      if loop.kind ~= "fornumStmt" then reject(loop, "the final statement must be a numeric for loop") end
      local first = loop.start and (nameOf(loop.start) or (loop.start.kind == "number" and loop.start.token.text))
      if first ~= (rangeGuard and rangeGuard.first or "1") then
         reject(loop.start or loop, "kernel loop start must match its verified range")
      end
      if loop.step then reject(loop.step, "the first subset does not admit an explicit loop step") end
      local stop = nameOf(loop.stop) or dotCount(loop.stop)
      local expectedStop = rangeGuard and rangeGuard.last or primary.name
      if stop ~= expectedStop then
         reject(loop.stop or loop, "the loop bound must match its verified range")
      end
      local index = loop.var and loop.var.text
      if not index then reject(loop, "the kernel loop needs an index variable") end

      local helpers, helperByName, helperState = {}, {}, {}
      local lowerExpression, lowerHelper

      local arithmetic = {
         ["+"] = "add", ["-"] = "sub", ["*"] = "mul", ["/"] = "div",
         ["%"] = "mod", ["^"] = "pow",
      }
      local bitwise = {
         ["&"] = "band", ["|"] = "bor", ["~"] = "bxor",
         ["<<"] = "lshift", [">>"] = "rshift", ["~>>"] = "arshift",
      }
      local comparisons = {
         ["<"] = "lt", ["<="] = "le", [">"] = "gt", [">="] = "ge",
         ["=="] = "eq", ["~="] = "ne",
      }
      -- The released fixed-width namespaces. These are ordinary Nupp calls with
      -- an exact Lua implementation in nupp.math, so admitting them here adds no
      -- surface: it lets the same source say binary32 instead of binary64 and
      -- have the backend believe it. A binary32 operation over binary32 operands
      -- computed in binary64 and rounded once is bit-identical to the native
      -- single-precision instruction, because 53 >= 2 * 24 + 2, so this lowering
      -- is exact rather than a relaxation.
      local fixedIntrinsics = {
         ["nupp.math.f32.narrow"] = {op = "narrow_f64_f32", arity = 1, from = "f64", result = "f32"},
         ["nupp.math.f32.add"] = {op = "f32_add", arity = 2, from = "f32", result = "f32"},
         ["nupp.math.f32.sub"] = {op = "f32_sub", arity = 2, from = "f32", result = "f32"},
         ["nupp.math.f32.mul"] = {op = "f32_mul", arity = 2, from = "f32", result = "f32"},
         ["nupp.math.f32.div"] = {op = "f32_div", arity = 2, from = "f32", result = "f32"},
         ["nupp.math.f32.sqrt"] = {op = "f32_sqrt", arity = 1, from = "f32", result = "f32"},
         -- These three are not covered by the double-rounding argument the
         -- arithmetic above rests on. A differential over every interesting
         -- binary32 value found that they disagree with fminf, fmaxf and fmaf
         -- in exactly one respect each and nowhere else: nupp.math.f32
         -- canonicalizes every NaN where the instruction propagates a payload,
         -- and min/max return that canonical NaN where IEEE minNum returns the
         -- operand that is not NaN. Both are repaired by a select, so they are
         -- admitted with one rather than left out.
         ["nupp.math.f32.min"] = {op = "f32_min", arity = 2, from = "f32", result = "f32"},
         ["nupp.math.f32.max"] = {op = "f32_max", arity = 2, from = "f32", result = "f32"},
         ["nupp.math.f32.fma"] = {op = "f32_fma", arity = 3, from = "f32", result = "f32"},
         ["nupp.math.i32.wrap"] = {op = "numeric_cast", arity = 1, from = "f64", result = "i32"},
         ["nupp.math.i32.add"] = {op = "i32_add", arity = 2, from = "i32", result = "i32"},
         ["nupp.math.i32.sub"] = {op = "i32_sub", arity = 2, from = "i32", result = "i32"},
         ["nupp.math.i32.mul"] = {op = "i32_mul", arity = 2, from = "i32", result = "i32"},
      }
      local mathIntrinsics = {
         ["math.sqrt"] = {name = "sqrt", min = 1, max = 1},
         ["math.abs"] = {name = "abs", min = 1, max = 1},
         ["math.floor"] = {name = "floor", min = 1, max = 1},
         ["math.ceil"] = {name = "ceil", min = 1, max = 1},
         ["math.min"] = {name = "min", min = 2},
         ["math.max"] = {name = "max", min = 2},
         ["math.sin"] = {name = "sin", min = 1, max = 1},
         ["math.cos"] = {name = "cos", min = 1, max = 1},
         ["math.tan"] = {name = "tan", min = 1, max = 1},
         ["math.asin"] = {name = "asin", min = 1, max = 1},
         ["math.acos"] = {name = "acos", min = 1, max = 1},
         ["math.atan"] = {name = "atan", min = 1, max = 1},
         ["math.atan2"] = {name = "atan2", min = 2, max = 2},
         ["math.sinh"] = {name = "sinh", min = 1, max = 1},
         ["math.cosh"] = {name = "cosh", min = 1, max = 1},
         ["math.tanh"] = {name = "tanh", min = 1, max = 1},
         ["math.exp"] = {name = "exp", min = 1, max = 1},
         ["math.log"] = {name = "log", min = 1, max = 2},
         ["math.pow"] = {name = "pow", min = 2, max = 2},
         ["math.fmod"] = {name = "fmod", min = 2, max = 2},
         ["math.deg"] = {name = "deg", min = 1, max = 1},
         ["math.rad"] = {name = "rad", min = 1, max = 1},
      }

      lowerHelper = function(name, at)
         if helperState[name] == "lowering" then reject(at, "recursive native helpers are not admitted") end
         if helperByName[name] then return helperByName[name] end
         local declaration = helperDecls[name]
         if not declaration then reject(at, "call target " .. name .. " is not a visible pure helper") end
         helperState[name] = "lowering"
         local helperBody = declaration.body
         if not helperBody or helperBody.generics or helperBody.varargParam
            or helperBody.captureTakes or helperBody.captureBorrows
         then
            reject(declaration, "native helpers must be non-generic, non-variadic, and non-capturing")
         end
         local resultTypes = {}
         for _, result in ipairs(helperBody.rets or {}) do
            local spelling = compactType(result)
            local resultType = spelling == "boolean" and "bool"
               or (spelling == "number" or spelling == "float") and "f64"
               or spelling == "integer" and "f64"
               or spelling == "uint32" and "u32"
               or spelling == "int32" and "i32" or nil
            if not resultType then
               reject(result, "native helper results are numeric or boolean values")
            end
            resultTypes[#resultTypes + 1] = resultType
         end
         if #resultTypes == 0 then reject(helperBody, "native helpers need at least one result") end

         local helperParams, environment = {}, {}
         for _, raw in ipairs(helperBody.params or {}) do
            local paramName = raw.name and raw.name.text
            local spelling = compactType(raw.type)
            local paramType = spelling == "boolean" and "bool"
               or (spelling == "number" or spelling == "float" or spelling == "integer") and "f64"
               or spelling == "uint32" and "u32"
               or spelling == "int32" and "i32" or nil
            if not paramName or not paramType or raw.modeTok then
               reject(raw, "native helper parameters are unowned numeric or boolean values")
            end
            if environment[paramName] then reject(raw, "duplicate helper parameter " .. paramName) end
            local param = {
               kind = "helper_param", name = paramName, type = paramType,
               cName = cIdentifier("a", paramName), source = site(raw),
            }
            helperParams[#helperParams + 1] = param
            environment[paramName] = param
         end
         local helperStats = helperBody.body and helperBody.body.stats or {}
         local returned = helperStats[1]
         if #helperStats ~= 1 or not returned or returned.kind ~= "returnStmt"
            or #(returned.exprs or {}) ~= #resultTypes
         then
            reject(helperBody.body or helperBody, "a native helper body is one matching return list")
         end
         local helper = {
            name = name, cName = privateSymbol(fn.name.text) .. "_helper_" .. privateSymbol(name):sub(4),
            params = helperParams, resultTypes = resultTypes, source = site(declaration),
         }
         helperByName[name] = helper
         helper.values = {}
         for i, result in ipairs(returned.exprs or {}) do
            local value = lowerExpression(result, environment, nil)
            if value.type ~= resultTypes[i] then reject(returned, "native helper result type does not match") end
            helper.values[i] = value
         end
         helper.resultType = resultTypes[1]
         helperState[name] = "done"
         helpers[#helpers + 1] = helper
         return helper
      end

      lowerExpression = function(node, environment, activeIndex)
         if not node then reject(loop, "an expression is missing") end
         if node.kind == "paren" or node.kind == "castExpr" then
            return lowerExpression(node.expr, environment, activeIndex)
         elseif node.kind == "name" then
            local name = nameOf(node)
            local value = environment[name]
            if not value then reject(node, "value " .. tostring(name) .. " is not available in native code") end
            local op = value.kind == "uniform" and "uniform"
               or value.kind == "helper_param" and "helper_param" or "local"
            -- A name keeps whatever refinement its binding holds. Only a
            -- physical load widens eagerly, because that is where ordinary Nupp
            -- turns storage into a Lua number; widening here as well would make
            -- an established `float` local unreadable as one.
            return {
               op = op, name = name, type = value.type, cName = value.cName,
               mutable = value.mutable, source = site(node),
            }
         elseif node.kind == "number" then
            local value = node.token and node.token.text or ""
            if not tonumber(value) then reject(node, "the kernel needs a finite decimal numeric literal") end
            return {op = "constant", value = value, type = "f64", source = site(node)}
         elseif node.kind == "trueExpr" or node.kind == "falseExpr" then
            return {op = "bool", value = node.kind == "trueExpr", type = "bool", source = site(node)}
         elseif node.kind == "unop" and node.op then
            local value = lowerExpression(node.operand, environment, activeIndex)
            if node.op.text == "-" and value.type == "f64" then
               return {op = "neg", value = value, type = "f64", source = site(node)}
            elseif node.op.text == "not" and value.type == "bool" then
               return {op = "not", value = value, type = "bool", source = site(node)}
            elseif node.op.text == "~" and (value.type == "i32" or value.type == "u32"
               or value.op == "constant" and tonumber(value.value) >= 0
                  and tonumber(value.value) <= 4294967295 and tonumber(value.value) % 1 == 0)
            then
               return {op = "bnot", value = value, type = "i32", source = site(node)}
            end
            reject(node, "unary operator " .. tostring(node.op.text) .. " is not admitted for this type")
         elseif node.kind == "methodCall" then
            local spanName = receiverName(node.obj)
            local param = spanName and byName[spanName] or nil
            local args = node.args and node.args.exprs or {}
            local method = node.name and node.name.text or ""
            local readable = param and (
               param.kind == "read_span" and method == "get"
               or param.kind == "write_span" and method == "getMut"
            )
            if not readable then
               reject(node, "span reads use input:get(index) or output:getMut(index)")
            end
            if not activeIndex or #args ~= 1 or nameOf(args[1]) ~= activeIndex then
               reject(node, "span loads must use the active loop index exactly")
            end
            if param.element.kind == "struct" then
               return {
                  op = "element_ref", span = spanName, index = activeIndex,
                  layout = param.element.layout.name,
                  mutable = param.kind == "write_span", type = "ref:" .. param.element.layout.name,
                  source = site(node),
               }
            end
            local loaded = {
               op = "load", span = spanName, index = activeIndex,
               type = param.element.type, source = site(node),
            }
            if loaded.type == "f32" then
               return {op = "widen_f32_f64", type = "f64", source = site(node), value = loaded}
            end
            return loaded
         elseif node.kind == "dotIndex" and node.name then
            local object = lowerExpression(node.obj, environment, activeIndex)
            local layoutName = object.type and object.type:match("^ref:(.+)$")
            local layout = layoutName and layoutByName[layoutName] or nil
            if not layout then reject(node, "native field access needs a reified struct element") end
            local field
            for _, candidate in ipairs(layout.fields) do
               if candidate.name == node.name.text then field = candidate break end
            end
            if not field then reject(node, "struct " .. layoutName .. " has no field " .. node.name.text) end
            local loaded = {
               op = "field_load", object = object, layout = layoutName,
               field = field.name, type = field.type, source = site(node),
            }
            if loaded.type == "f32" then
               return {op = "widen_f32_f64", type = "f64", source = site(node), value = loaded}
            end
            return loaded
         elseif node.kind == "binop" and node.op then
            local left = lowerExpression(node.lhs, environment, activeIndex)
            local right = lowerExpression(node.rhs, environment, activeIndex)
            local written = node.op.text
            if arithmetic[written] then
               local function promote(value)
                  if value.type == "f64" then return value end
                  if value.type == "f32" then
                     return {op = "widen_f32_f64", value = value, type = "f64", source = value.source}
                  end
                  if value.type == "i32" or value.type == "u32" then
                     return {op = "int_to_f64", value = value, type = "f64", source = value.source}
                  end
                  reject(node, "arithmetic operands must both be numeric")
               end
               return {
                  op = arithmetic[written], left = promote(left), right = promote(right),
                  type = "f64", source = site(node),
               }
            elseif bitwise[written] then
               local function admittedBitOperand(value)
                  if value.type == "i32" or value.type == "u32" then return true end
                  local number = value.op == "constant" and tonumber(value.value) or nil
                  return number and number >= 0 and number <= 4294967295 and number % 1 == 0
               end
               if not admittedBitOperand(left) or not admittedBitOperand(right) then
                  reject(node, "bitwise operands must be fixed 32-bit values or nonnegative uint32 literals")
               end
               return {op = bitwise[written], left = left, right = right, type = "i32", source = site(node)}
            elseif comparisons[written] then
               local numeric = {f64 = true, f32 = true, i32 = true, u32 = true}
               if left.type ~= right.type and not (numeric[left.type] and numeric[right.type]) then
                  reject(node, "comparison operands must have compatible types")
               end
               return {op = comparisons[written], left = left, right = right, type = "bool", source = site(node)}
            elseif written == "and" or written == "or" then
               if left.type ~= "bool" or right.type ~= "bool" then
                  reject(node, "native and/or operands must both be boolean")
               end
               return {op = written, left = left, right = right, type = "bool", source = site(node)}
            end
            reject(node, "operator " .. tostring(written) .. " is not admitted")
         elseif node.kind == "call" then
            local args = {}
            for _, arg in ipairs(node.args and node.args.exprs or {}) do
               args[#args + 1] = lowerExpression(arg, environment, activeIndex)
            end
            local qualified = dottedName(node.obj)
            local fixed = qualified and fixedIntrinsics[qualified] or nil
            if fixed then
               if #args ~= fixed.arity then
                  reject(node, qualified .. " has an unsupported argument count")
               end
               for i, arg in ipairs(args) do
                  -- An exact decimal literal establishes a fixed-width value, so
                  -- a constant may enter directly. Anything else must already
                  -- carry the refinement: this is where the front end refuses to
                  -- invent establishment the source never performed.
                  if arg.op == "constant" and fixed.from ~= "f64" then
                     local number = tonumber(arg.value)
                     if fixed.from == "i32" then
                        if not number or number % 1 ~= 0 or number < -2147483648 or number > 2147483647 then
                           reject(node, qualified .. " needs an exact int32 literal")
                        end
                        args[i] = {op = "constant_i32", value = arg.value, type = "i32", source = arg.source}
                     else
                        args[i] = {op = "narrow_f64_f32", value = arg, type = "f32", source = arg.source}
                     end
                  elseif arg.type ~= fixed.from then
                     reject(node, qualified .. " argument " .. tostring(i) .. " is "
                        .. tostring(arg.type) .. " and was never established as " .. fixed.from)
                  end
               end
               if fixed.arity == 1 then
                  return {op = fixed.op, value = args[1], type = fixed.result, source = site(node)}
               end
               if fixed.arity == 3 then
                  return {op = fixed.op, args = args, type = fixed.result, source = site(node)}
               end
               return {op = fixed.op, left = args[1], right = args[2],
                  type = fixed.result, source = site(node)}
            end
            local intrinsic = qualified and mathIntrinsics[qualified] or nil
            if intrinsic then
               if #args < intrinsic.min or intrinsic.max and #args > intrinsic.max then
                  reject(node, qualified .. " has an unsupported argument count")
               end
               for i, arg in ipairs(args) do
                  if arg.type == "i32" or arg.type == "u32" then
                     args[i] = {op = "int_to_f64", value = arg, type = "f64", source = arg.source}
                  elseif arg.type == "f32" then
                     args[i] = {op = "widen_f32_f64", value = arg, type = "f64", source = arg.source}
                  elseif arg.type ~= "f64" then
                     reject(node, qualified .. " arguments must be numeric")
                  end
               end
               return {op = "math", intrinsic = intrinsic.name, args = args, type = "f64", source = site(node)}
            end
            local helperName = nameOf(node.obj)
            if helperName then
               local helper = lowerHelper(helperName, node)
               if #args ~= #helper.params then reject(node, "native helper argument count does not match") end
               for i, arg in ipairs(args) do
                  local wanted = helper.params[i].type
                  -- A helper takes ordinary Nupp values, so a fixed-width
                  -- argument widens into it exactly as it would at any other
                  -- binary64 operator.
                  if arg.type ~= wanted and wanted == "f64" and arg.type == "f32" then
                     args[i] = {op = "widen_f32_f64", value = arg, type = "f64", source = arg.source}
                  elseif arg.type ~= wanted and wanted == "f64"
                     and (arg.type == "i32" or arg.type == "u32")
                  then
                     args[i] = {op = "int_to_f64", value = arg, type = "f64", source = arg.source}
                  elseif arg.type ~= wanted then
                     reject(node, "native helper argument type does not match")
                  end
               end
               return {
                  op = "helper_call", helper = helper.name, cName = helper.cName,
                  args = args,
                  type = #helper.resultTypes == 1 and helper.resultType or "multi",
                  resultTypes = helper.resultTypes, source = site(node),
               }
            end
            reject(node, "call target " .. tostring(qualified) .. " is not an admitted intrinsic or helper")
         end
         reject(node, "expression kind " .. tostring(node.kind) .. " is not admitted")
      end

      local localSerial = 0
      local function sourceValueType(spelling)
         return spelling == "boolean" and "bool"
            or (spelling == "number" or spelling == "integer") and "f64"
            or spelling == "float" and "f32"
            or spelling == "uint32" and "u32"
            or spelling == "int32" and "i32" or nil
      end

      local function convertValue(value, targetType, at)
         if value.type == targetType then return value end
         if targetType == "f64" and (value.type == "i32" or value.type == "u32") then
            return {op = "int_to_f64", value = value, type = "f64", source = site(at)}
         end
         if targetType == "f64" and value.type == "f32" then
            return {op = "widen_f32_f64", value = value, type = "f64", source = site(at)}
         end
         if targetType == "f32" and value.type == "f64" then
            return {op = "narrow_f64_f32", value = value, type = "f32", source = site(at)}
         end
         if (targetType == "i32" or targetType == "u32")
            and (value.type == "f64" or value.type == "i32" or value.type == "u32")
         then
            return {op = "numeric_cast", value = value, type = targetType, source = site(at)}
         end
         reject(at, "native value cannot convert from " .. tostring(value.type) .. " to " .. tostring(targetType))
      end

      local function lowerBlock(rawStats, environment)
         local statements = {}
         for _, stat in ipairs(rawStats or {}) do
            if stat.kind == "localStmt" then
               if #(stat.names or {}) == 0 or #(stat.exprs or {}) == 0 then
                  reject(stat, "native locals must be initialized")
               end
               local values = {}
               if #(stat.exprs or {}) == 1 then
                  local only = lowerExpression(stat.exprs[1], environment, index)
                  if only.type == "multi" then
                     if #only.resultTypes ~= #(stat.names or {}) then
                        reject(stat, "multiple-result helper count does not match local names")
                     end
                     values = only.resultTypes
                     local bindings = {}
                     for i, token in ipairs(stat.names or {}) do
                        local name = token.text
                        if environment[name] then reject(stat, "native locals may not shadow " .. name) end
                        local annotated = sourceValueType(compactType(stat.types and stat.types[i]))
                        local valueType = only.resultTypes[i]
                        if annotated and annotated ~= valueType then reject(stat, "native local annotation does not match") end
                        localSerial = localSerial + 1
                        local binding = {
                           kind = "local", name = name, type = valueType,
                           cName = cIdentifier("v" .. tostring(localSerial), name), source = site(stat),
                        }
                        bindings[i] = binding
                        environment[name] = binding
                     end
                     statements[#statements + 1] = {
                        op = "multi_let", call = only, bindings = bindings, source = site(stat),
                     }
                     goto continue_statement
                  end
                  values[1] = only
               else
                  for _, expression in ipairs(stat.exprs or {}) do
                     local value = lowerExpression(expression, environment, index)
                     if value.type == "multi" then reject(expression, "a multiple-result call must be the only initializer") end
                     values[#values + 1] = value
                  end
               end
               if #values ~= #(stat.names or {}) then reject(stat, "native local initializer count must match names") end
               for i, token in ipairs(stat.names or {}) do
                  local name = token.text
                  if environment[name] then reject(stat, "native locals may not shadow " .. name) end
                  local value = values[i]
                  local spelling = compactType(stat.types and stat.types[i])
                  local expected = spelling ~= "" and sourceValueType(spelling) or value.type
                  if not expected then reject(stat, "native local annotation " .. spelling .. " is not admitted") end
                  value = convertValue(value, expected, stat)
                  localSerial = localSerial + 1
                  local binding = {
                     kind = "local", name = name, type = expected,
                     mutable = value.mutable, cName = cIdentifier("v" .. tostring(localSerial), name),
                     source = site(stat),
                  }
                  statements[#statements + 1] = {
                     op = "let", name = name, cName = binding.cName,
                     type = expected, value = value, source = site(stat),
                  }
                  environment[name] = binding
               end
            elseif stat.kind == "callStmt" then
               local call = stat.expr
               local spanName = call and call.kind == "methodCall" and receiverName(call.obj) or nil
               local output = spanName and byName[spanName] or nil
               local args = call and call.args and call.args.exprs or {}
               if not output or output.kind ~= "write_span" or not call.name or call.name.text ~= "set" then
                  reject(stat, "a native call statement must be output:set(index, value)")
               end
               if #args ~= 2 or nameOf(args[1]) ~= index then
                  reject(call, "span stores must use the active loop index exactly")
               end
               local value = lowerExpression(args[2], environment, index)
               local stored = convertValue(value, output.element.type, call)
               statements[#statements + 1] = {
                  op = "store", span = spanName, index = index,
                  value = stored,
                  source = site(call),
               }
            elseif stat.kind == "assignStmt" then
               local rawValues = {}
               if #(stat.exprs or {}) == 1 then
                  local only = lowerExpression(stat.exprs[1], environment, index)
                  if only.type == "multi" then
                     reject(stat, "multiple-result helpers initialize locals; ordinary multiple assignment uses explicit values")
                  end
                  rawValues[1] = only
               else
                  for _, expression in ipairs(stat.exprs or {}) do
                     rawValues[#rawValues + 1] = lowerExpression(expression, environment, index)
                  end
               end
               if #rawValues ~= #(stat.targets or {}) then reject(stat, "native assignment counts must match") end
               local assignments = {}
               for i, target in ipairs(stat.targets or {}) do
                  local loweredTarget
                  if target.kind == "name" then
                     local binding = environment[nameOf(target)]
                     if not binding or binding.kind ~= "local" then reject(target, "native assignment target must be a local") end
                     loweredTarget = {
                        kind = "local", name = binding.name, cName = binding.cName, type = binding.type,
                     }
                  elseif target.kind == "dotIndex" and target.name then
                     local object = lowerExpression(target.obj, environment, index)
                     local layoutName = object.type and object.type:match("^ref:(.+)$")
                     local layout = layoutName and layoutByName[layoutName] or nil
                     if not layout or not object.mutable then reject(target, "native field assignment needs getMut(index)") end
                     local field
                     for _, candidate in ipairs(layout.fields) do
                        if candidate.name == target.name.text then field = candidate break end
                     end
                     if not field then reject(target, "unknown native struct field " .. target.name.text) end
                     loweredTarget = {
                        kind = "field", object = object, layout = layoutName,
                        field = field.name, type = field.type,
                     }
                  else
                     reject(target, "native assignment targets are locals or mutable struct fields")
                  end
                  assignments[i] = {
                     target = loweredTarget,
                     value = convertValue(rawValues[i], loweredTarget.type, stat),
                  }
               end
               statements[#statements + 1] = {op = "assign", values = assignments, source = site(stat)}
            elseif stat.kind == "ifStmt" then
               local lowered = {op = "if", clauses = {}, source = site(stat)}
               for _, branch in ipairs(stat.clauses or {}) do
                  local condition = lowerExpression(branch.cond, environment, index)
                  if condition.type ~= "bool" then reject(branch.cond, "native branch conditions must be boolean") end
                  lowered.clauses[#lowered.clauses + 1] = {
                     condition = condition,
                     body = lowerBlock(branch.body and branch.body.stats or {}, copyEnvironment(environment)),
                     source = site(branch),
                  }
               end
               if stat.elseClause then
                  lowered.elseBody = lowerBlock(
                     stat.elseClause.body and stat.elseClause.body.stats or {},
                     copyEnvironment(environment)
                  )
               end
               statements[#statements + 1] = lowered
            elseif stat.kind == "fornumStmt" then
               -- A bounded nested loop with an integer induction variable. The
               -- outer row loop already counts in an integer; a `while` over a
               -- number local does the same job with a double, which is a worse
               -- lowering of the same intent.
               if stat.step then
                  reject(stat, "a native nested for loop takes no explicit step")
               end
               local from = lowerExpression(stat.start, environment, index)
               local to = lowerExpression(stat.stop, environment, index)
               -- An integer literal bound stays an integer rather than being
               -- written as a double for the emitter to cast back.
               local function integral(bound)
                  if bound.op == "constant" then
                     local number = tonumber(bound.value)
                     if number and number == math.floor(number) then
                        return {op = "constant_i32", value = number, type = "i32",
                           source = bound.source}
                     end
                  end
                  if bound.type ~= "i32" and bound.type ~= "u32" and bound.type ~= "f64" then
                     reject(stat, "native for bounds must be numeric")
                  end

                  return bound
               end
               from, to = integral(from), integral(to)
               local name = stat.var and stat.var.text
               if not name then reject(stat, "a native for loop needs an induction variable") end
               if environment[name] then
                  reject(stat, "native locals may not shadow " .. name)
               end
               localSerial = localSerial + 1
               local binding = {
                  kind = "local", name = name, type = "i32",
                  cName = cIdentifier("v" .. tostring(localSerial), name), source = site(stat),
               }
               local inner = copyEnvironment(environment)
               inner[name] = binding
               statements[#statements + 1] = {
                  op = "fornum", binding = binding, from = from, to = to,
                  body = lowerBlock(stat.body and stat.body.stats or {}, inner),
                  source = site(stat),
               }
            elseif stat.kind == "whileStmt" then
               -- A nested loop the kernel controls itself, as distinct from the
               -- outer row loop the prototype supplies. Nothing here bounds its
               -- trip count: the condition is ordinary Nupp and termination is
               -- the source's business, exactly as it is when the same function
               -- runs as ordinary Nupp. That is a real difference from the outer
               -- loop, whose bounds the IR carries and the verifier checks, and
               -- it is why this is a spike rather than the production pass.
               local condition = lowerExpression(stat.cond, environment, index)
               if condition.type ~= "bool" then
                  reject(stat.cond, "native loop conditions must be boolean")
               end
               statements[#statements + 1] = {
                  op = "while",
                  condition = condition,
                  body = lowerBlock(stat.body and stat.body.stats or {}, copyEnvironment(environment)),
                  source = site(stat),
               }
            elseif stat.kind == "doStmt" then
               statements[#statements + 1] = {
                  op = "block",
                  body = lowerBlock(stat.body and stat.body.stats or {}, copyEnvironment(environment)),
                  source = site(stat),
               }
            elseif stat.kind == "breakStmt" or stat.kind == "continueStmt" then
               statements[#statements + 1] = {
                  op = stat.kind == "breakStmt" and "break" or "continue", source = site(stat),
               }
            else
               reject(stat, "statement kind " .. tostring(stat.kind) .. " is not admitted in the native loop")
            end
            ::continue_statement::
         end
         return statements
      end

      local environment = {}
      for _, param in ipairs(params) do
         if param.kind == "uniform" then environment[param.name] = param end
      end
      local statements = lowerBlock(loop.body and loop.body.stats or {}, environment)
      if #statements == 0 then reject(loop.body or loop, "the native loop body may not be empty") end

      return {
         version = 3,
         name = fn.name.text,
         symbol = privateSymbol(fn.name.text),
         fpContract = fpContract,
         wantsLanes = wantsLanes,
         lanesRequired = lanesRequired,
         params = params,
         layouts = layouts,
         regions = regions,
         aliasFacts = aliasFacts,
         guards = guards,
         rangeGuard = rangeGuard,
         helpers = helpers,
         loop = {
            index = index,
            first = rangeGuard and rangeGuard.first or 1,
            last = rangeGuard and rangeGuard.last or primary.name,
            count = primary.name,
            statements = statements, source = site(loop),
         },
         source = site(fn),
      }
   end)

   if not ok then
      if ir ~= STOP then error(ir, 0) end
      return nil, diagnostics
   end
   return ir, diagnostics
end

-- Declared in `nupp.compiler.aot.intensity`, which is where this decision
-- belongs: whether a loop is worth running several iterations at once is
-- compiler policy, not a property of this spike.
local function arithmeticIntensity(ir)
   local estimate = intensity.estimate(ir.loop.statements)
   return estimate.perByte, estimate.operations, estimate.bytes, estimate.worthwhile
end

-- The released fixed-width scalar operations, as IR. Each is one binary32 or
-- wrapping int32 operation with an exact `nupp.math` implementation behind it,
-- which is what lets the backend emit the native instruction and still owe the
-- same answer as ordinary Nupp.
local FIXED_BINARY = {
   f32_add = "f32", f32_sub = "f32", f32_mul = "f32", f32_div = "f32",
   i32_add = "i32", i32_sub = "i32", i32_mul = "i32",
}
-- Operations whose native instruction is right about the value and wrong about
-- NaN, and the C helper that repairs it. Emitting the bare instruction would let
-- an AOT build change bits that `nupp.math.f32.toBits` can read back, so each
-- carries its correction rather than being left out of the subset.
local FIXED_CORRECTED = {
   f32_min = {element = "f32", arity = 2, helper = "nupp_f32_min"},
   f32_max = {element = "f32", arity = 2, helper = "nupp_f32_max"},
   f32_fma = {element = "f32", arity = 3, helper = "nupp_f32_fma"},
}
local FIXED_OPERATOR = {
   f32_add = "+", f32_sub = "-", f32_mul = "*", f32_div = "/",
   i32_add = "+", i32_sub = "-", i32_mul = "*",
}

--[[
Lane-parallel lowering.

`@aot(simd = true)` says the admitted loop's iterations are independent. This pass takes
the loop body that was already lowered, typed, and bound as scalar IR and
rewrites it to run several iterations at once: a value that depends on the loop
index becomes a vector, a value that does not stays scalar and broadcasts where
it meets one, a conditional becomes a mask, and an assignment under a mask
becomes a select so inactive lanes keep what they had.

It runs on IR rather than on the tree because the front end has already settled
what everything means. What is left is a choice about how many iterations to do
at a time, which is exactly the kind of decision an IR pass should own.

The gang size follows the widths the loop's varying values actually need, not a
single element type. Ordinary Nupp arithmetic is binary64, so a loop written
with operators gets four binary64 lanes: two NEON registers or one AVX2
register per live value, which a body of eight of them can hold, where eight
lanes would be four registers each and would spill.

A loop whose varying values are all 32-bit -- because the source asked for
binary32 and wrapping int32 through the released `nupp.math` namespaces -- gets
eight lanes at the same register cost. That is a different program with
different answers, and it is the source that says so; this pass only declines
to waste half of each register on it.

The tail is a scalar epilogue over the same body rather than a masked final
group, because a masked load still reads the addresses it masks off and the
last element of a span may be the last byte of a page.
]]

--- The lane shapes this backend can choose between. Both are 32 bytes wide, so
--- a group costs the same registers either way and only the lane count differs.
-- Declared in `nupp.compiler.aot.lane`, which is where this backend is going.
-- Keeping a second copy here is how the two would disagree about what a gang is.
local SHAPES = lane.SHAPES

local SHAPE_BY_NAME = {}
for _, entry in ipairs(SHAPES) do SHAPE_BY_NAME[entry.name] = entry end

--- Rewrites one lowered loop body to run `shape.lanes` iterations at once.
---
--- @param ir the verified scalar IR
--- @param reject how to report a construct this pass cannot represent
--- @param shape the lane shape to attempt
local function vectorizeLoop(ir, reject, shape)
   local varyingLocals = {}
   local refBindings = {}
   local index = ir.loop.index
   local internalSerial = 0
   local LANES = shape.lanes
   local MASK = shape.mask

   local function lanesVectorType(scalar)
      return shape.vectorFor[scalar]
   end

   -- Bound while one helper call is being inlined: parameter name to the lane
   -- vector its argument produced. A helper is a parameter list and a list of
   -- result expressions over those parameters, so inlining it is substitution.
   local helperBindings = {}
   local helperByName = {}
   for _, helper in ipairs(ir.helpers or {}) do helperByName[helper.name] = helper end

   -- `nupp.compiler.aot.rewrite` owns this: whether a value depends on the
   -- iteration is the decision the whole rewrite turns on, so it belongs with
   -- the vocabulary rather than beside the loop that reads it.
   local rewriteState = {
      shape = shape,
      index = index,
      varyingLocals = varyingLocals,
      refBindings = refBindings,
      helperBindings = helperBindings,
      helpers = helperByName,
      reject = function(why) reject(nil, why) end,
   }
   local function exprVarying(node)
      return rewriteRules.varying(node, rewriteState)
   end

   local function markBlock(statements, controlled)
      for _, statement in ipairs(statements) do
         if statement.op == "let" then
            if controlled or exprVarying(statement.value) then
               varyingLocals[statement.name] = true
            end
         elseif statement.op == "multi_let" then
            -- Every result of one call varies together: the call is inlined as a
            -- whole, so if any argument varies then all of its results do. This
            -- has to be decided here rather than while rewriting, because a
            -- later read of one of these names is rewritten on the answer.
            if controlled or exprVarying(statement.call) then
               for _, binding in ipairs(statement.bindings) do
                  varyingLocals[binding.name] = true
               end
            end
         elseif statement.op == "assign" then
            for _, assignment in ipairs(statement.values) do
               if assignment.target.kind == "local"
                  and (controlled or exprVarying(assignment.value))
               then
                  varyingLocals[assignment.target.name] = true
               end
            end
         elseif statement.op == "if" then
            local branchControlled = controlled
            for _, clause in ipairs(statement.clauses) do
               branchControlled = branchControlled or exprVarying(clause.condition)
               markBlock(clause.body, branchControlled)
            end
            if statement.elseBody then markBlock(statement.elseBody, branchControlled) end
         elseif statement.op == "while" then
            markBlock(statement.body, controlled or exprVarying(statement.condition))
         elseif statement.op == "block" then
            markBlock(statement.body, controlled)
         elseif statement.op == "fornum" then
            markBlock(statement.body, controlled
               or exprVarying(statement.from) or exprVarying(statement.to))
         end
      end
   end
   -- A local assigned a varying value inside a loop is varying on every
   -- iteration, including the ones lowered before the assignment was seen, so
   -- the marking runs to a fixed point.
   local before
   repeat
      before = 0
      for _ in pairs(varyingLocals) do before = before + 1 end
      markBlock(ir.loop.statements, false)
      local after = 0
      for _ in pairs(varyingLocals) do after = after + 1 end
   until after == before

   -- `span:get(i)` binds a reference that field accesses later go through. The
   -- reference itself has no lane-parallel form -- four elements are four
   -- addresses -- but every use of it does, so the binding is remembered and
   -- resolved at each use rather than emitted.
   local function resolveRef(node)
      if node == nil then return nil end
      if node.op == "element_ref" then return node end
      if node.op == "local" then return refBindings[node.name] end

      return nil
   end

   --- Brings a uniform scalar to the element type its gang carries it in. An
   --- f64 gang widens everything; a 32-bit gang has nothing to widen to and
   --- refuses a binary64 uniform rather than narrowing one.
   -- `nupp.compiler.aot.rewrite` owns bringing a uniform into a lane: which
   -- element a gang carries a value in, and what conversion that takes, is the
   -- vocabulary's business rather than this loop's.
   local function splat(node, scalarType)
      return rewriteRules.splat(node, scalarType or node.type, rewriteState)
   end

   local function boolMask(node)
      return {op = "vbool_splat", args = {node}, type = MASK, source = node.source}
   end

   -- The mask combinators are the compiler's: which lanes a statement applies
   -- to is part of what lane IR means, not bookkeeping this loop invents.
   local function maskLocal(binding, source)
      return rewriteRules.maskLocal(binding, source, rewriteState)
   end

   local blockState = {serial = 0}
   local function internalMask(label, source)
      return rewriteRules.internalMask(label, source, blockState, rewriteState)
   end

   local function maskAnd(left, right, source)
      return rewriteRules.maskAnd(left, right, source, rewriteState)
   end

   local function maskNot(value, source)
      return rewriteRules.maskNot(value, source, rewriteState)
   end

   local function activeMask(mask, loopContext, source)
      return rewriteRules.activeMask(mask, loopContext, source, rewriteState)
   end

   -- Scalar opcode to lane opcode. The f64 gang carries every scalar type in
   -- binary64 lanes, so one entry each is enough; the 32-bit gang keeps
   -- binary32 and int32 apart, so the arithmetic rows are chosen by the operand
   -- type at the use site and the comparison rows by what they compare.
   local VECTOR_ARITHMETIC = {add = "add", sub = "sub", mul = "mul", div = "div"}
   -- Bitwise operations on flag words are what an entity query is made of, so
   -- they lower rather than refusing the loop. Unary `bnot` has no right operand.
   local LANE_BITWISE = {band = "and", bor = "or", bxor = "xor", bnot = "not",
      lshift = "shl", rshift = "shr", arshift = "sar"}
   local VECTOR_COMPARISON = {lt = "lt", le = "le", gt = "gt", ge = "ge",
      eq = "eq", ne = "ne"}
   local FIXED_LANE = {
      f32_add = {"add", "f32"}, f32_sub = {"sub", "f32"}, f32_mul = {"mul", "f32"},
      f32_div = {"div", "f32"}, i32_add = {"add", "i32"}, i32_sub = {"sub", "i32"},
      i32_mul = {"mul", "i32"},
   }

   local rewriteExpr
   local inlineHelper

   --- The vector opcode for `verb` over `element` lanes, e.g. "vmul.f32x8".
   --- Encoding the element in the opcode keeps the verifier's type check total:
   --- there is no lane operation whose operand width has to be inferred.
   local function laneOp(verb, element)
      local vector = lanesVectorType(element)
      if not vector then
         reject(nil, "a varying " .. tostring(element) .. " cannot enter " .. shape.name .. " SIMD")
      end
      return verb, vector
   end

   --- Rewrites `node` to a vector of the type the gang uses for `want`, or for
   --- the node's own scalar type when the caller has no opinion.
   local function numericVector(node, want)
      local scalarType = want or node.type
      local vector = lanesVectorType(scalarType)
      if exprVarying(node) then
         local value = rewriteExpr(node)
         if value.type ~= vector then
            reject(nil, "a varying " .. tostring(node.type) .. " cannot enter "
               .. tostring(vector) .. " SIMD")
         end
         return value
      end
      return splat(node, scalarType)
   end

   local function conditionMask(node)
      if exprVarying(node) then
         local value = rewriteExpr(node)
         if value.type ~= MASK then reject(nil, "a varying condition did not produce a mask") end
         return value
      end
      return boolMask(node)
   end

   -- Liveness and the continue search are the compiler's: what a lane-local's
   -- value is worth after a lane retires is the reasoning behind the
   -- speculation rule, and it belongs beside it.
   local function containsContinue(statements)
      return rewriteRules.containsContinue(statements)
   end

   local rewriteExpr
   local inlineHelper

   --- The vector opcode for `verb` over `element` lanes, e.g. "vmul.f32x8".
   --- Encoding the element in the opcode keeps the verifier's type check total:
   --- there is no lane operation whose operand width has to be inferred.
   local function laneOp(verb, element)
      local vector = lanesVectorType(element)
      if not vector then
         reject(nil, "a varying " .. tostring(element) .. " cannot enter " .. shape.name .. " SIMD")
      end
      return verb, vector
   end

   --- Rewrites `node` to a vector of the type the gang uses for `want`, or for
   --- the node's own scalar type when the caller has no opinion.
   local function numericVector(node, want)
      local scalarType = want or node.type
      local vector = lanesVectorType(scalarType)
      if exprVarying(node) then
         local value = rewriteExpr(node)
         if value.type ~= vector then
            reject(nil, "a varying " .. tostring(node.type) .. " cannot enter "
               .. tostring(vector) .. " SIMD")
         end
         return value
      end
      return splat(node, scalarType)
   end

   local function conditionMask(node)
      if exprVarying(node) then
         local value = rewriteExpr(node)
         if value.type ~= MASK then reject(nil, "a varying condition did not produce a mask") end
         return value
      end
      return boolMask(node)
   end

   local function collectExprReads(node, reads)
      if not node then return end
      if node.op == "local" then reads[node.name] = true end
      if node.value then collectExprReads(node.value, reads) end
      if node.left then collectExprReads(node.left, reads) end
      if node.right then collectExprReads(node.right, reads) end
      for _, arg in ipairs(node.args or {}) do collectExprReads(arg, reads) end
      if node.object then collectExprReads(node.object, reads) end
   end

   local rewriteExpr
   local inlineHelper

   --- The vector opcode for `verb` over `element` lanes, e.g. "vmul.f32x8".
   --- Encoding the element in the opcode keeps the verifier's type check total:
   --- there is no lane operation whose operand width has to be inferred.
   local function laneOp(verb, element)
      local vector = lanesVectorType(element)
      if not vector then
         reject(nil, "a varying " .. tostring(element) .. " cannot enter " .. shape.name .. " SIMD")
      end
      return verb, vector
   end

   --- Rewrites `node` to a vector of the type the gang uses for `want`, or for
   --- the node's own scalar type when the caller has no opinion.
   local function numericVector(node, want)
      local scalarType = want or node.type
      local vector = lanesVectorType(scalarType)
      if exprVarying(node) then
         local value = rewriteExpr(node)
         if value.type ~= vector then
            reject(nil, "a varying " .. tostring(node.type) .. " cannot enter "
               .. tostring(vector) .. " SIMD")
         end
         return value
      end
      return splat(node, scalarType)
   end

   local function conditionMask(node)
      if exprVarying(node) then
         local value = rewriteExpr(node)
         if value.type ~= MASK then reject(nil, "a varying condition did not produce a mask") end
         return value
      end
      return boolMask(node)
   end

   -- Liveness and the continue search are the compiler's: what a lane-local's
   -- value is worth after a lane retires is the reasoning behind the
   -- speculation rule, and it belongs beside it.
   local function containsContinue(statements)
      return rewriteRules.containsContinue(statements)
   end

   local rewriteExpr
   local inlineHelper

   --- The vector opcode for `verb` over `element` lanes, e.g. "vmul.f32x8".
   --- Encoding the element in the opcode keeps the verifier's type check total:
   --- there is no lane operation whose operand width has to be inferred.
   local function laneOp(verb, element)
      local vector = lanesVectorType(element)
      if not vector then
         reject(nil, "a varying " .. tostring(element) .. " cannot enter " .. shape.name .. " SIMD")
      end
      return verb, vector
   end

   --- Rewrites `node` to a vector of the type the gang uses for `want`, or for
   --- the node's own scalar type when the caller has no opinion.
   local function numericVector(node, want)
      local scalarType = want or node.type
      local vector = lanesVectorType(scalarType)
      if exprVarying(node) then
         local value = rewriteExpr(node)
         if value.type ~= vector then
            reject(nil, "a varying " .. tostring(node.type) .. " cannot enter "
               .. tostring(vector) .. " SIMD")
         end
         return value
      end
      return splat(node, scalarType)
   end

   local function conditionMask(node)
      if exprVarying(node) then
         local value = rewriteExpr(node)
         if value.type ~= MASK then reject(nil, "a varying condition did not produce a mask") end
         return value
      end
      return boolMask(node)
   end

   local function collectExprReads(node, reads)
      if not node then return end
      if node.op == "local" then reads[node.name] = true end
      if node.value then collectExprReads(node.value, reads) end
      if node.left then collectExprReads(node.left, reads) end
      if node.right then collectExprReads(node.right, reads) end
      for _, arg in ipairs(node.args or {}) do collectExprReads(arg, reads) end
      if node.object then collectExprReads(node.object, reads) end
   end

   local collectStatementReads
   collectStatementReads = function(statement, reads)
      if statement.op == "let" then
         collectExprReads(statement.value, reads)
      elseif statement.op == "assign" then
         for _, assignment in ipairs(statement.values) do
            collectExprReads(assignment.value, reads)
            collectExprReads(assignment.target.object, reads)
         end
      elseif statement.op == "store" then
         collectExprReads(statement.value, reads)
      elseif statement.op == "if" then
         for _, clause in ipairs(statement.clauses) do
            collectExprReads(clause.condition, reads)
            for _, inner in ipairs(clause.body) do collectStatementReads(inner, reads) end
         end
         for _, inner in ipairs(statement.elseBody or {}) do collectStatementReads(inner, reads) end
      elseif statement.op == "while" then
         collectExprReads(statement.condition, reads)
         for _, inner in ipairs(statement.body) do collectStatementReads(inner, reads) end
      elseif statement.op == "fornum" then
         collectExprReads(statement.from, reads)
         collectExprReads(statement.to, reads)
         for _, inner in ipairs(statement.body) do collectStatementReads(inner, reads) end
      elseif statement.op == "block" then
         for _, inner in ipairs(statement.body) do collectStatementReads(inner, reads) end
      end
   end

   local function containsContinue(statements)
      for _, statement in ipairs(statements) do
         if statement.op == "continue" then return true end
         if statement.op == "if" then
            for _, clause in ipairs(statement.clauses) do
               if containsContinue(clause.body) then return true end
            end
            if statement.elseBody and containsContinue(statement.elseBody) then return true end
         elseif statement.body and containsContinue(statement.body) then
            return true
         end
      end
      return false
   end

   --- Rewrites a helper call to the helper's own result expressions, with each
   --- parameter bound to the lane vector its argument produced.
   ---
   --- The helper body is already verified scalar IR over `helper_param` nodes,
   --- so nothing here decides what the helper means -- it decides only that this
   --- call's arguments are what its parameters are. Bindings are saved and
   --- restored around the call, so a helper called twice, or a helper calling
   --- another, cannot see the wrong ones.
   inlineHelper = function(node)
      local helper = helperByName[node.helper]
      if not helper then reject(nil, "a lane-parallel call has no visible helper") end
      if #node.args ~= #helper.params then
         reject(nil, "a lane-parallel helper call has the wrong argument count")
      end
      local bound, saved = {}, {}
      for i, param in ipairs(helper.params) do
         bound[param.name] = numericVector(node.args[i], param.type)
      end
      for name, value in pairs(bound) do
         saved[name] = helperBindings[name]
         helperBindings[name] = value
      end
      local values = {}
      for i, value in ipairs(helper.values) do
         values[i] = rewriteExpr(value)
      end
      for name in pairs(bound) do
         helperBindings[name] = saved[name]
      end

      return values
   end

   --- Rewrites one expression, returning it unchanged when it is uniform.
   rewriteExpr = function(node)
      return rewriteRules.expression(node, rewriteState)
   end

   --- Rewrites a block under an execution mask. `mask` is nil at the top level,
   --- where every lane is active and no select is needed.
   local rewriteBlock
   rewriteBlock = function(statements, mask, loopContext, following)
      local out = {}
      local readsAfter = rewriteRules.readsAfter(statements, following or {})
      for position, statement in ipairs(statements) do
         local statementMask = activeMask(mask, loopContext, statement.source)
         if statement.op == "let" and statement.value.op == "element_ref"
            and statement.value.index == index then
            refBindings[statement.name] = statement.value
         elseif statement.op == "let" then
            out[#out + 1] = rewriteRules.let(statement, rewriteState)
         elseif statement.op == "multi_let" then
            -- One binding per result, each declared separately. The scalar form
            -- needs one statement because a C call returns once; inlined, the
            -- results are ordinary expressions and there is nothing to hold
            -- together.
            local varying = exprVarying(statement.call)
            local values = varying and inlineHelper(statement.call) or nil
            for i, binding in ipairs(statement.bindings) do
               local value
               if varying then
                  value = values[i]
               else
                  value = {op = "helper_result", call = statement.call, index = i,
                     type = binding.type, source = statement.source}
               end
               out[#out + 1] = {
                  op = "let", name = binding.name, cName = binding.cName,
                  value = value, type = varying and value.type or binding.type,
                  source = statement.source,
               }
            end
         elseif statement.op == "assign" then
            local assignments = {}
            for i, assignment in ipairs(statement.values) do
               local target = assignment.target
               local targetVarying = target.kind == "field"
                  or varyingLocals[target.name] == true
               local value = exprVarying(assignment.value)
                  and rewriteExpr(assignment.value) or assignment.value
               if not exprVarying(assignment.value)
                  and targetVarying
               then
                  value = splat(assignment.value)
               end
               local assignmentMask = statementMask
               if assignmentMask and target.kind == "local"
                  and rewriteRules.maySpeculate(target.name, mask, loopContext)
               then
                  assignmentMask = nil
               end
               -- The lane target is worked out once, then used both to read the
               -- old value back for the select and to say where the store goes.
               local laneTarget
               if target.kind == "field" then
                  local object = resolveRef(target.object)
                  if not object or object.index ~= index then
                     reject(nil, "a lane-parallel field store writes consecutive elements only")
                  end
                  laneTarget = {kind = "vfield", span = object.span,
                     layout = target.layout, field = target.field,
                     scalarType = target.type}
               else
                  laneTarget = {kind = "local", name = target.name, cName = target.cName}
               end
               value = rewriteRules.assignedValue(
                  value, laneTarget, assignmentMask, statement.source, rewriteState
               )
               assignments[i] = {
                  target = target.kind == "field" and laneTarget or target,
                  value = value,
               }
            end
            out[#out + 1] = {op = "vassign", values = assignments, source = statement.source}
         elseif statement.op == "store" then
            reject(nil, "a lane-parallel loop stores through struct fields for now")
         elseif statement.op == "if" then
            -- Each arm's mask is captured into its own binding before the arm
            -- runs, so a body that assigns to a name the condition read cannot
            -- change which lanes execute the statements after it.
            local arms, remaining = rewriteRules.branchMasks(
               statement.clauses, statementMask, blockState, rewriteState
            )
            for _, arm in ipairs(arms) do
               out[#out + 1] = {
                  op = "let", name = arm.binding.name, cName = arm.binding.cName,
                  value = arm.entry, type = MASK, source = arm.clause.source,
               }
               local inner = rewriteBlock(
                  arm.clause.body, maskLocal(arm.binding, arm.clause.source),
                  loopContext, readsAfter[position]
               )
               for _, produced in ipairs(inner) do out[#out + 1] = produced end
            end
            if statement.elseBody then
               local inner = rewriteBlock(
                  statement.elseBody, remaining, loopContext, readsAfter[position]
               )
               for _, produced in ipairs(inner) do out[#out + 1] = produced end
            end
         elseif statement.op == "block" then
            local inner = rewriteBlock(
               statement.body, statementMask, loopContext, readsAfter[position]
            )
            for _, produced in ipairs(inner) do out[#out + 1] = produced end
         elseif statement.op == "while" then
            if not exprVarying(statement.condition) then
               reject(nil, "a uniform inner while loop is not lane-controlled yet")
            end
            local context = rewriteRules.loopContext(
               statement, readsAfter[position], blockState, rewriteState
            )
            local condition = conditionMask(statement.condition)
            local initial = maskAnd(statementMask, condition, statement.source)
            local body = rewriteBlock(
               statement.body,
               maskLocal(context.executing, statement.source),
               context,
               nil
            )
            out[#out + 1] = {
               op = "vwhile", live = context.live, executing = context.executing,
               initial = initial, condition = condition, body = body,
               source = statement.source,
            }
         elseif statement.op == "fornum" then
            reject(nil, "a nested numeric loop is not lane-controlled yet")
         elseif statement.op == "break" or statement.op == "continue" then
            if not loopContext then
               reject(nil, statement.op .. " applies to the outer map loop and is not admitted")
            end
            out[#out + 1] = rewriteRules.exit(statement, statementMask, loopContext)
         else
            reject(nil, "statement " .. tostring(statement.op) .. " has no lane-parallel form")
         end
      end

      return out
   end

   return {lanes = LANES, shape = shape.name, statements = rewriteBlock(ir.loop.statements, nil, nil, nil)}
end

-- The rules live in `nupp.compiler.aot.verify`, against the typed vocabulary.
-- This spike hands one over and keeps nothing of its own: what makes IR well
-- formed is compiler policy, not a property of a test-only front end.
local verifyIR = irVerify.program

compiler.verifyIR = verifyIR

-- The readable form lives in `nupp.compiler.aot.text`.
local irLines = irText.program

-- Lane and scalar rendering both live in `nupp.compiler.aot.emit`.
local renderExpr = emitRules.lane

local cType = emitRules.cType

--- A set's keys in a fixed order, so the same IR renders the same text.
local function sortedKeys(set)
   local names = {}
   for key in pairs(set) do names[#names + 1] = key end
   table.sort(names)
   return names
end

local function renderC(ir)
   emitRules.begin()
   local lines = {}
   local function emit(line) lines[#lines + 1] = line or "" end
   emit("/* Generated from verified test-only native C IR. */")
   emit("#include <math.h>")
   emit("#include <string.h>")
   emit("#include <stdbool.h>")
   emit("#include <stddef.h>")
   emit("#include <stdint.h>")
   emit("#ifndef M_PI")
   emit("#define M_PI 3.14159265358979323846264338327950288")
   emit("#endif")
   emit("")
   for _, layout in ipairs(ir.layouts or {}) do
      for _, line in ipairs(emitRules.layout(layout)) do emit(line) end
      emit("")
      emit("size_t " .. ir.symbol .. "_layout_" .. layout.name .. "_size(void) { return sizeof("
         .. layout.cName .. "); }")
      for _, field in ipairs(layout.fields) do
         emit("size_t " .. ir.symbol .. "_layout_" .. layout.name .. "_offset_" .. field.name
            .. "(void) { return offsetof(" .. layout.cName .. ", " .. field.name .. "); }")
         emit("size_t " .. ir.symbol .. "_layout_" .. layout.name .. "_size_" .. field.name
            .. "(void) { return sizeof(((" .. layout.cName .. " *)0)->" .. field.name .. "); }")
      end
      emit("")
   end
   -- Marked unused for the same reason the helpers below are: the prelude is
   -- emitted whole, so a kernel with no bit operation never calls these, and
   -- -Werror would fail a correct program for a conversion it did not need.
   -- One 32-byte group either way: four binary64 lanes or eight 32-bit ones.
   -- Both preludes are emitted whole and marked unused, like the helpers below,
   -- so a kernel that uses one shape does not fail -Werror for the other.
   local shape = ir.lanes and SHAPE_BY_NAME[ir.lanes.shape] or SHAPES[1]
   local vectors = {}
   for _, vector in pairs(shape.vectorFor) do vectors[vector] = true end
   local ELEMENT_C = {f64 = "double", f32 = "float", i32 = "int32_t", u32 = "uint32_t"}
   vectors[shape.bits] = true
   local MASK_C = {m64x4 = "long long", m32x8 = "int"}
   emit("typedef " .. MASK_C[shape.mask] .. " ks_" .. shape.mask
      .. " __attribute__((vector_size(32)));")
   -- Sorted, because `pairs` over a set does not order it the same way in two
   -- processes, and the same IR has to render the same text or an artifact cache
   -- keyed by it misses on every build.
   for _, vector in ipairs(sortedKeys(vectors)) do
      if vector ~= shape.mask then
         local element = vector:match("^(%a%d+)x")
         local lanes = tonumber(vector:match("x(%d+)$"))
         local width = tonumber(element:match("%d+")) / 8 * lanes
         emit("typedef " .. ELEMENT_C[element] .. " ks_" .. vector
            .. " __attribute__((vector_size(" .. tostring(math.floor(width)) .. ")));")
         -- The signed companion of the bit vector, for arithmetic shift.
         if vector == shape.bits and element:sub(1, 1) == "u" then
            emit("typedef int" .. element:match("%d+") .. "_t ks_i" .. vector:sub(2)
               .. " __attribute__((vector_size(" .. tostring(math.floor(width)) .. ")));")
         end
      end
   end
   local ones, zeros = {}, {}
   for _ = 1, shape.lanes do ones[#ones + 1] = "-1" zeros[#zeros + 1] = "0" end
   emit("static inline __attribute__((unused)) ks_" .. shape.mask .. " ks_mask_all(void)"
      .. " { return (ks_" .. shape.mask .. "){" .. table.concat(ones, ", ") .. "}; }")
   emit("static inline __attribute__((unused)) ks_" .. shape.mask .. " ks_bool_mask(bool v)"
      .. " { return v ? ks_mask_all() : (ks_" .. shape.mask .. "){"
      .. table.concat(zeros, ", ") .. "}; }")
   local anyTerms = {}
   for lane = 0, shape.lanes - 1 do anyTerms[#anyTerms + 1] = "m[" .. lane .. "]" end
   emit("static inline __attribute__((unused)) bool ks_any(ks_" .. shape.mask .. " m)"
      .. " { return (" .. table.concat(anyTerms, " | ") .. ") != 0; }")
   -- A splat and a select are wanted for every vector that carries values, and
   -- for nothing else. The bit vector is not one of them in a binary64 gang --
   -- it is half the width and has no mask to pair with -- but in a 32-bit gang
   -- it is also where integers live, so membership of `vectorFor` is the test
   -- rather than whether it happens to be `shape.bits`.
   local carriers = {}
   for _, vector in pairs(shape.vectorFor) do carriers[vector] = true end
   for _, vector in ipairs(sortedKeys(carriers)) do
      if vector ~= shape.mask then
         local element = vector:match("^(%a%d+)x")
         local splatLanes = {}
         for _ = 1, shape.lanes do splatLanes[#splatLanes + 1] = "v" end
         emit("static inline __attribute__((unused)) ks_" .. vector .. " ks_splat_" .. vector
            .. "(" .. ELEMENT_C[element] .. " v) { return (ks_" .. vector .. "){"
            .. table.concat(splatLanes, ", ") .. "}; }")
         -- Blend through the mask's integer lanes. A branchless select is what
         -- makes an inactive lane keep its old value instead of computing a new
         -- one, so it must not be an arithmetic idiom: multiplying by zero turns
         -- an escaped lane's infinity into a NaN and destroys it.
         emit("static inline __attribute__((unused)) ks_" .. vector .. " ks_sel_" .. vector
            .. "(ks_" .. shape.mask .. " m, ks_" .. vector .. " a, ks_" .. vector .. " b)"
            .. " { return (ks_" .. vector .. ")((m & (ks_" .. shape.mask .. ")a)"
            .. " | (~m & (ks_" .. shape.mask .. ")b)); }")
      end
   end
   emit("static inline __attribute__((unused)) uint32_t nupp_u32(double value) { return (uint32_t)value; }")
   emit("static inline __attribute__((unused)) uint32_t nupp_u32_i32(int32_t value) { return (uint32_t)value; }")
   emit("static inline __attribute__((unused)) uint32_t nupp_u32_u32(uint32_t value) { return value; }")
   emit("#define nupp_u32(value) _Generic((value), int32_t: nupp_u32_i32, uint32_t: nupp_u32_u32, default: nupp_u32)(value)")
   emit("static inline __attribute__((unused)) int32_t nupp_arshift(uint32_t value, uint32_t shift) {")
   emit("    if (shift == 0u) return (int32_t)value;")
   emit("    uint32_t shifted = value >> shift;")
   emit("    if ((value & UINT32_C(0x80000000)) != 0u) shifted |= ~(UINT32_MAX >> shift);")
   emit("    return (int32_t)shifted;")
   emit("}")
   emit("")
   -- Canonical quiet NaN, as nupp.math.f32 defines it. min and max additionally
   -- differ from IEEE minNum: a NaN operand makes the result NaN here, where
   -- fminf and fmaxf return the operand that is not NaN.
   emit("static inline __attribute__((unused)) float nupp_f32_nan(void) {")
   emit("    uint32_t bits = UINT32_C(0x7fc00000);")
   emit("    float out;")
   emit("    memcpy(&out, &bits, 4);")
   emit("    return out;")
   emit("}")
   emit("static inline __attribute__((unused)) float nupp_f32_min(float left, float right) {")
   emit("    if (left != left || right != right) return nupp_f32_nan();")
   emit("    return fminf(left, right);")
   emit("}")
   emit("static inline __attribute__((unused)) float nupp_f32_max(float left, float right) {")
   emit("    if (left != left || right != right) return nupp_f32_nan();")
   emit("    return fmaxf(left, right);")
   emit("}")
   emit("static inline __attribute__((unused)) float nupp_f32_fma(float a, float b, float c) {")
   emit("    float out = fmaf(a, b, c);")
   emit("    return out == out ? out : nupp_f32_nan();")
   emit("}")
   emit("")
   emit("static inline __attribute__((unused)) double nupp_min2(double left, double right) {")
   emit("    return left < right ? left : right;")
   emit("}")
   emit("static inline __attribute__((unused)) double nupp_max2(double left, double right) {")
   emit("    return left > right ? left : right;")
   emit("}")
   emit("")

   for _, helper in ipairs(ir.helpers or {}) do
      if #helper.resultTypes > 1 then
         helper.cResult = helper.cName .. "_result"
         emit("typedef struct {")
         for i, resultType in ipairs(helper.resultTypes) do
            emit("    " .. cType(resultType) .. " v" .. tostring(i) .. ";")
         end
         emit("} " .. helper.cResult .. ";")
      end
   end
   if #(ir.helpers or {}) > 0 then emit("") end
   for _, helper in ipairs(ir.helpers or {}) do
      local params = {}
      for _, param in ipairs(helper.params) do
         params[#params + 1] = cType(param.type) .. " " .. param.cName
      end
      local result = helper.cResult or cType(helper.resultType)
      emit("static inline " .. result .. " " .. helper.cName
         .. "(" .. table.concat(params, ", ") .. ");")
   end
   if #(ir.helpers or {}) > 0 then emit("") end
   for _, helper in ipairs(ir.helpers or {}) do
      local params = {}
      for _, param in ipairs(helper.params) do
         params[#params + 1] = cType(param.type) .. " " .. param.cName
      end
      local result = helper.cResult or cType(helper.resultType)
      emit("static inline " .. result .. " " .. helper.cName
         .. "(" .. table.concat(params, ", ") .. ") {")
      if helper.cResult then
         local values = {}
         for _, value in ipairs(helper.values) do values[#values + 1] = renderExpr(value) end
         emit("    " .. helper.cResult .. " result = {" .. table.concat(values, ", ") .. "};")
         emit("    return result;")
      else
         emit("    return " .. renderExpr(helper.values[1]) .. ";")
      end
      emit("}")
      emit("")
   end

   local function renderBlock(statements, depth)
      local prefix = string.rep("    ", depth)
      local temporary = 0
      local function localCType(typeName, mutable)
         local layout = typeName:match("^ref:(.+)$")
         if layout then return (mutable and "" or "const ") .. "Ks" .. layout .. " *" end
         return cType(typeName) .. " "
      end
      for _, statement in ipairs(statements) do
         if statement.op == "let" then
            emit(prefix .. localCType(statement.type, statement.value.mutable) .. statement.cName .. " = "
               .. renderExpr(statement.value) .. ";")
         elseif statement.op == "multi_let" then
            temporary = temporary + 1
            local helper
            for _, candidate in ipairs(ir.helpers or {}) do
               if candidate.name == statement.call.helper then helper = candidate break end
            end
            local temp = "mr" .. tostring(temporary)
            emit(prefix .. helper.cResult .. " " .. temp .. " = " .. renderExpr(statement.call) .. ";")
            for i, binding in ipairs(statement.bindings) do
               emit(prefix .. cType(binding.type) .. " " .. binding.cName .. " = " .. temp .. ".v" .. tostring(i) .. ";")
            end
         elseif statement.op == "store" then
            emit(prefix .. cIdentifier("p", statement.span) .. "[i] = " .. renderExpr(statement.value) .. ";")
         elseif statement.op == "assign" then
            local temps = {}
            for _, assignment in ipairs(statement.values) do
               temporary = temporary + 1
               local temp = "as" .. tostring(temporary)
               temps[#temps + 1] = temp
               emit(prefix .. cType(assignment.target.type) .. " " .. temp .. " = "
                  .. renderExpr(assignment.value) .. ";")
            end
            for i, assignment in ipairs(statement.values) do
               local target = assignment.target.kind == "local" and assignment.target.cName
                  or "(" .. renderExpr(assignment.target.object) .. "->" .. assignment.target.field .. ")"
               emit(prefix .. target .. " = " .. temps[i] .. ";")
            end
         elseif statement.op == "if" then
            for i, clause in ipairs(statement.clauses) do
               emit(prefix .. (i == 1 and "if (" or "else if (") .. renderExpr(clause.condition) .. ") {")
               renderBlock(clause.body, depth + 1)
               emit(prefix .. "}")
            end
            if statement.elseBody then
               emit(prefix .. "else {")
               renderBlock(statement.elseBody, depth + 1)
               emit(prefix .. "}")
            end
         elseif statement.op == "vassign" then
            for _, assignment in ipairs(statement.values) do
               local target = assignment.target
               if target.kind == "vfield" then
                  -- Consecutive elements, one lane each. Clang turns the group
                  -- into an interleaving store where the target has one.
                  local rendered = renderExpr(assignment.value)
                  emit(prefix .. "{")
                  emit(prefix .. "    " .. cType(assignment.value.type) .. " lanes = " .. rendered .. ";")
                  for lane = 0, ir.lanes.lanes - 1 do
                     emit(prefix .. "    p_" .. target.span .. "[i + " .. lane .. "]."
                        .. target.field .. " = (" .. cType(target.scalarType)
                        .. ")lanes[" .. lane .. "];")
                  end
                  emit(prefix .. "}")
               else
                  emit(prefix .. target.cName .. " = " .. renderExpr(assignment.value) .. ";")
               end
            end
         elseif statement.op == "vwhile" then
            emit(prefix .. cType(statement.live.type) .. " " .. statement.live.cName .. " = "
               .. renderExpr(statement.initial) .. ";")
            emit(prefix .. "while (ks_any(" .. statement.live.cName .. ")) {")
            emit(prefix .. "    " .. cType(statement.executing.type) .. " " .. statement.executing.cName .. " = "
               .. statement.live.cName .. ";")
            renderBlock(statement.body, depth + 1)
            emit(prefix .. "    " .. statement.live.cName .. " &= "
               .. renderExpr(statement.condition) .. ";")
            emit(prefix .. "}")
         elseif statement.op == "vbreak" then
            local mask = renderExpr(statement.mask)
            emit(prefix .. statement.live.cName .. " &= ~(" .. mask .. ");")
            emit(prefix .. statement.executing.cName .. " &= ~(" .. mask .. ");")
         elseif statement.op == "vcontinue" then
            emit(prefix .. statement.executing.cName .. " &= ~("
               .. renderExpr(statement.mask) .. ");")
         elseif statement.op == "fornum" then
            local v = statement.binding.cName
            emit(prefix .. "for (int32_t " .. v .. " = " .. renderExpr(statement.from)
               .. "; " .. v .. " <= (int32_t)" .. renderExpr(statement.to) .. "; ++" .. v .. ") {")
            renderBlock(statement.body, depth + 1)
            emit(prefix .. "}")
         elseif statement.op == "while" then
            emit(prefix .. "while (" .. renderExpr(statement.condition) .. ") {")
            renderBlock(statement.body, depth + 1)
            emit(prefix .. "}")
         elseif statement.op == "block" then
            emit(prefix .. "{")
            renderBlock(statement.body, depth + 1)
            emit(prefix .. "}")
         else
            emit(prefix .. statement.op .. ";")
         end
      end
   end

   local params = emitRules.parameters(ir.params)
   local function implementation(symbol, forced)
      emit("__attribute__((noinline))")
      emit("void " .. symbol .. "(" .. params .. ") {")
      -- Scoped to this function rather than set as a build flag, so a relaxation
      -- one function asked for cannot silently change another one's answers.
      if ir.fpContract then
         for _, line in ipairs(emitRules.contractPragma()) do emit(line) end
      end
      for _, line in ipairs(emitRules.bounds(ir.rangeGuard)) do emit(line) end
      if forced then
         for _, line in ipairs(emitRules.forcedScalarPragma()) do emit(line) end
      end
      -- The forced-scalar body stays scalar: it is the oracle the lane-parallel
      -- one is diffed against, so it must not share its lowering.
      if ir.lanes and not forced then
         -- Whole groups run several iterations at once; the remainder runs the
         -- same body one iteration at a time. A masked final group would still
         -- read the addresses it masked off, and the last element of a span may
         -- be the last byte of a page.
         for _, line in ipairs(emitRules.groupBound(ir.lanes.lanes)) do emit(line) end
         renderBlock(ir.lanes.statements, 2)
         emit("    }")
      end
      emit("    for (; i < end; ++i) {")
      renderBlock(ir.loop.statements, 2)
      emit("    }")
      emit("}")
      emit("")
   end
   implementation(ir.symbol .. "_forced_scalar", true)
   implementation(ir.symbol, false)
   return table.concat(lines, "\n") .. "\n"
end

--- Where the compiled object lands, which is what the generated module loads.
local SPIKE_LIBRARY = "bench/kernel-subset-spike/build/libkernel_subset_spike"

local function renderBinding(ir)
   return bindingRules.module(ir, SPIKE_LIBRARY)
end

function compiler.compile(source, filename, checked)
   local ir, diagnostics = parseKernel(source, filename, checked)
   if not ir then return nil, diagnostics end
   verifyIR(ir)
   -- The lane-parallel pass runs on verified scalar IR: what it rewrites has
   -- already been proved to mean something, so a refusal here is only ever
   -- about lowering it several iterations at a time.
   local worthwhile
   ir.intensity, ir.operations, ir.touchedBytes, worthwhile = arithmeticIntensity(ir)
   if not ir.lanesRequired and not worthwhile then
      ir.wantsLanes = false
      ir.thin = true
   end
   ir.lanesDeclined = not ir.wantsLanes
   if ir.wantsLanes then
      -- Try the shapes widest lane count first. The 32-bit gang refuses the
      -- moment any varying value turns out to be binary64, so a loop written
      -- with ordinary operators lands on f64x4 exactly as it did before, and a
      -- loop whose values the source established as float or int32 gets twice
      -- the lanes for the same registers. The pass builds fresh IR and touches
      -- nothing else, so a declined attempt costs a retry and no state.
      --
      -- Only the last shape's refusals are reported. A loop that cannot lower
      -- at all cannot lower in any width, and the binary64 refusal is the one
      -- that names the construct rather than the width.
      local refusals
      for position = #SHAPES, 1, -1 do
         local attempted, lanes = {}, nil
         local ok, problem = pcall(function()
            lanes = vectorizeLoop(ir, function(_, message)
               attempted[#attempted + 1] = diagnostic(filename, ir.loop.source, message)
               error(STOP, 0)
            end, SHAPES[position])
         end)
         if ok then ir.lanes = lanes break end
         if problem ~= STOP then error(problem, 0) end
         if os.getenv("NUPP_SPIKE_SHAPES") then
            for _, refusal in ipairs(attempted) do
               io.stderr:write("shape ", SHAPES[position].name, ": ",
                  renderDiagnostic(refusal), "\n")
            end
         end
         refusals = attempted
      end
      -- A body that cannot lower lane-parallel still compiles: it keeps its
      -- scalar loop, and the refusals are carried so the vectorisation check can
      -- name the construct that stopped it rather than the build failing on a
      -- performance property.
      if not ir.lanes then
         ir.laneRefusals = refusals
         ir.lanesDeclined = false
      else
         verifyIR(ir)
      end
   end
   return {
      ir = ir,
      irText = irLines(ir),
      c = renderC(ir),
      binding = renderBinding(ir),
   }, diagnostics
end

return compiler
