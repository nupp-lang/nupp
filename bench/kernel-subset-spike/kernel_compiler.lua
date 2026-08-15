-- A test-only compiler for a deliberately small `@aot` subset.
--
-- It consumes Nupp's real CST, validates an admitted whole-function shape,
-- verifies a sealed typed IR, and emits private scalar C for Clang to optimize.

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local root = here .. "../.."
package.path = root .. "/build/?.lua;" .. package.path

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

local function privateSymbol(name)
   local snake = name:gsub("(%u)(%u%l)", "%1_%2"):gsub("(%l)(%u)", "%1_%2")
   return "ks_" .. snake:gsub("[^%w_]", "_"):lower()
end

local function cIdentifier(prefix, name)
   return prefix .. "_" .. name:gsub("[^%w_]", "_")
end

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
      local wantsLanes = body.simdRequired == true
      if not checked then
         for _, link in ipairs(selected.chain) do
            local written = link.name and link.name.text
            if written == "aot" then
               for _, arg in ipairs(link.annotationArgs or {}) do
                  local name = arg.name and arg.name.text
                  if name == "simd" then
                     if arg.expr and arg.expr.kind == "trueExpr" then wantsLanes = true end
                  else
                     reject(link, "@aot takes simd = true or nothing")
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
            local loaded = {
               op = op, name = name, type = value.type, cName = value.cName,
               mutable = value.mutable, source = site(node),
            }
            if loaded.type == "f32" then
               return {op = "widen_f32_f64", type = "f64", source = site(node), value = loaded}
            end
            return loaded
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
            local intrinsic = qualified and mathIntrinsics[qualified] or nil
            if intrinsic then
               if #args < intrinsic.min or intrinsic.max and #args > intrinsic.max then
                  reject(node, qualified .. " has an unsupported argument count")
               end
               for i, arg in ipairs(args) do
                  if arg.type == "i32" or arg.type == "u32" then
                     args[i] = {op = "int_to_f64", value = arg, type = "f64", source = arg.source}
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
                  if arg.type ~= helper.params[i].type then reject(node, "native helper argument type does not match") end
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

Four lanes of binary64. Ordinary Nupp arithmetic is binary64 and removing `@aot`
may not change an answer, so the lanes are too; four of them is two NEON
registers or one AVX2 register, which a body of eight live values can hold.
Eight would be four registers each and would spill.

The tail is a scalar epilogue over the same body rather than a masked final
group, because a masked load still reads the addresses it masks off and the
last element of a span may be the last byte of a page.
]]

local LANES = 4

local function lanesVectorType(scalar)
   if scalar == "f64" then return "f64x4" end
   if scalar == "bool" then return "m64x4" end

   return nil
end

--- Rewrites one lowered loop body to run `LANES` iterations at once.
---
--- @param ir the verified scalar IR
--- @param reject how to report a construct this pass cannot represent
local function vectorizeLoop(ir, reject)
   local varyingLocals = {}
   local refBindings = {}
   local index = ir.loop.index

   local function exprVarying(node)
      if node == nil then return false end
      local op = node.op
      if op == "element_ref" or op == "load" then
         return node.index == index
      elseif op == "local" then
         return varyingLocals[node.name] == true or refBindings[node.name] ~= nil
      elseif op == "uniform" or op == "constant" or op == "constant_i32"
         or op == "bool" or op == "helper_param" then
         return false
      elseif op == "field_load" then
         return exprVarying(node.object)
      elseif node.left or node.right then
         return exprVarying(node.left) or exprVarying(node.right)
      elseif node.value then
         return exprVarying(node.value)
      elseif node.args then
         for _, arg in ipairs(node.args) do
            if exprVarying(arg) then return true end
         end
         return false
      end

      return false
   end

   local function markBlock(statements)
      for _, statement in ipairs(statements) do
         if statement.op == "let" then
            if exprVarying(statement.value) then varyingLocals[statement.name] = true end
         elseif statement.op == "assign" then
            for _, assignment in ipairs(statement.values) do
               if assignment.target.kind == "local" and exprVarying(assignment.value) then
                  varyingLocals[assignment.target.name] = true
               end
            end
         elseif statement.op == "if" then
            for _, clause in ipairs(statement.clauses) do markBlock(clause.body) end
            if statement.elseBody then markBlock(statement.elseBody) end
         elseif statement.op == "while" or statement.op == "block" then
            markBlock(statement.body)
         elseif statement.op == "fornum" then
            markBlock(statement.body)
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
      markBlock(ir.loop.statements)
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

   local function splat(node)
      if node.type == "f64" then
         return {op = "vsplat64", args = {node}, type = "f64x4", source = node.source}
      end
      reject(nil, "a uniform " .. tostring(node.type) .. " cannot enter a lane-parallel expression")
   end

   local VECTOR_BINARY = {
      add = "vadd64", sub = "vsub64", mul = "vmul64", div = "vdiv64",
      lt = "vlt64", le = "vle64", gt = "vgt64", ge = "vge64",
      eq = "veq64", ne = "vne64",
   }
   local COMPARISON = {vlt64 = true, vle64 = true, vgt64 = true, vge64 = true,
      veq64 = true, vne64 = true}

   --- Rewrites one expression, returning it unchanged when it is uniform.
   local function rewriteExpr(node)
      if not exprVarying(node) then return node, false end
      local op = node.op
      if op == "local" then
         return {op = "local", name = node.name, cName = node.cName,
            type = lanesVectorType(node.type) or reject(nil, "varying local of unsupported type"),
            source = node.source}, true
      elseif op == "field_load" then
         local object = resolveRef(node.object)
         if not object or object.index ~= index then
            reject(nil, "a lane-parallel field load reads consecutive elements only")
         end
         local loaded = {
            op = "vfield_load", span = object.span, layout = object.layout,
            field = node.field, lanes = LANES, type = "f64x4", source = node.source,
         }
         return loaded, true
      elseif op == "widen_f32_f64" or op == "int_to_f64" then
         -- The lane load already produced binary64, so the scalar widening the
         -- front end inserted has nothing left to do.
         local inner = rewriteExpr(node.value)
         return inner, true
      elseif VECTOR_BINARY[op] then
         local left = rewriteExpr(node.left)
         local right = rewriteExpr(node.right)
         if not exprVarying(node.left) then left = splat(node.left) end
         if not exprVarying(node.right) then right = splat(node.right) end
         local chosen = VECTOR_BINARY[op]
         return {op = chosen, args = {left, right},
            type = COMPARISON[chosen] and "m64x4" or "f64x4", source = node.source}, true
      elseif op == "and" or op == "or" then
         -- Lane-wise eager evaluation is not ordinary short-circuiting. Keep it
         -- outside the admitted subset until the checked IR carries a verified
         -- pure-and-total effect fact or the right side is lowered under a mask.
         reject(nil, "a lane-parallel and/or needs mask-aware short-circuit lowering")
      elseif op == "not" then
         return {op = "vmnot", args = {rewriteExpr(node.value)}, type = "m64x4",
            source = node.source}, true
      elseif op == "neg" then
         return {op = "vneg64", args = {rewriteExpr(node.value)}, type = "f64x4",
            source = node.source}, true
      elseif op == "math" then
         local args = {}
         for i, arg in ipairs(node.args) do
            args[i] = exprVarying(arg) and rewriteExpr(arg) or splat(arg)
         end
         return {op = "vmath", intrinsic = node.intrinsic, args = args,
            type = "f64x4", source = node.source}, true
      elseif op == "helper_call" then
         reject(nil, "a lane-parallel loop cannot call a helper yet")
      elseif op == "numeric_cast" or op == "narrow_f64_f32" then
         return rewriteExpr(node.value), true
      end
      reject(nil, "operation " .. tostring(op) .. " has no lane-parallel form")
   end

   --- Rewrites a block under an execution mask. `mask` is nil at the top level,
   --- where every lane is active and no select is needed.
   local function rewriteBlock(statements, mask)
      local out = {}
      for _, statement in ipairs(statements) do
         if statement.op == "let" and statement.value.op == "element_ref"
            and statement.value.index == index then
            refBindings[statement.name] = statement.value
         elseif statement.op == "let" then
            local value = rewriteExpr(statement.value)
            local varying = exprVarying(statement.value)
            out[#out + 1] = {
               op = "let", name = statement.name, cName = statement.cName,
               value = varying and value or statement.value,
               type = varying and value.type or statement.type,
               source = statement.source,
            }
         elseif statement.op == "assign" then
            local assignments = {}
            for i, assignment in ipairs(statement.values) do
               local target = assignment.target
               local value = rewriteExpr(assignment.value)
               if not exprVarying(assignment.value)
                  and (target.kind == "field" or varyingLocals[target.name])
               then
                  value = splat(assignment.value)
               end
               if mask then
                  -- An inactive lane keeps what it had, which is what makes a
                  -- conditional a mask rather than a branch. A field target
                  -- reads its own current lanes back for the same reason.
                  local previous
                  if target.kind == "local" then
                     previous = {op = "local", name = target.name, cName = target.cName,
                        type = value.type, source = statement.source}
                  else
                     local object = resolveRef(target.object)
                     if not object or object.index ~= index then
                        reject(nil, "a lane-parallel field store writes consecutive elements only")
                     end
                     previous = {op = "vfield_load", span = object.span,
                        layout = target.layout, field = target.field, lanes = LANES,
                        type = "f64x4", source = statement.source}
                  end
                  value = {op = "vselect", args = {mask, value, previous},
                     type = value.type, source = statement.source}
               end
               if target.kind == "field" then
                  local object = resolveRef(target.object)
                  if not object or object.index ~= index then
                     reject(nil, "a lane-parallel field store writes consecutive elements only")
                  end
                  assignments[i] = {
                     target = {kind = "vfield", span = object.span,
                        layout = target.layout, field = target.field,
                        scalarType = target.type},
                     value = value,
                  }
               else
                  assignments[i] = {target = target, value = value}
               end
            end
            out[#out + 1] = {op = "vassign", values = assignments, source = statement.source}
         elseif statement.op == "store" then
            reject(nil, "a lane-parallel loop stores through struct fields for now")
         elseif statement.op == "if" then
            if #statement.clauses ~= 1 or statement.elseBody then
               reject(nil, "a lane-parallel conditional takes one clause and no else yet")
            end
            local clause = statement.clauses[1]
            local condition = rewriteExpr(clause.condition)
            if not exprVarying(clause.condition) then
               reject(nil, "a uniform condition in a lane-parallel loop is not lowered yet")
            end
            local combined = condition
            if mask then
               combined = {op = "vmand", args = {mask, condition}, type = "m64x4",
                  source = statement.source}
            end
            local inner = rewriteBlock(clause.body, combined)
            for _, produced in ipairs(inner) do out[#out + 1] = produced end
         elseif statement.op == "block" then
            local inner = rewriteBlock(statement.body, mask)
            for _, produced in ipairs(inner) do out[#out + 1] = produced end
         elseif statement.op == "while" or statement.op == "fornum" then
            reject(nil, "a loop inside a lane-parallel loop is not lowered yet")
         elseif statement.op == "break" or statement.op == "continue" then
            reject(nil, "break and continue in a lane-parallel loop are not lowered yet")
         else
            reject(nil, "statement " .. tostring(statement.op) .. " has no lane-parallel form")
         end
      end

      return out
   end

   return {lanes = LANES, statements = rewriteBlock(ir.loop.statements, nil)}
end

local function verifyIR(ir)
   assert(ir.version == 3, "unknown native C IR version")
   assert(ir.symbol == privateSymbol(ir.name), "private symbol does not match function identity")
   local layouts = {}
   for _, layout in ipairs(ir.layouts or {}) do
      assert(not layouts[layout.name] and layout.cName and #layout.fields > 0, "invalid native layout")
      local fields = {}
      for _, field in ipairs(layout.fields) do
         assert(not fields[field.name]
            and (field.type == "f32" or field.type == "i32" or field.type == "u32"),
            "invalid native layout field")
         fields[field.name] = field.type
      end
      layout.fieldTypes = fields
      layouts[layout.name] = layout
   end
   local byName, byRegion, writes, primary = {}, {}, {}, nil
   for _, param in ipairs(ir.params) do
      assert(not byName[param.name], "duplicate IR parameter")
      assert(param.kind == "write_span" or param.kind == "read_span" or param.kind == "uniform",
         "unknown IR parameter kind")
      if param.kind == "uniform" then
         assert((param.type == "f64" or param.type == "f32" or param.type == "i32" or param.type == "u32")
            and not param.region, "invalid IR uniform")
      else
         local structName = param.type:match("^struct:(.+)$")
         assert((param.type == "f32" or param.type == "i32" or param.type == "u32"
            or structName and layouts[structName]) and param.region and not byRegion[param.region],
            "invalid IR span")
         assert(param.access == (param.kind == "write_span" and "readwrite" or "read"),
            "invalid IR region access")
         byRegion[param.region] = param
         if param.kind == "write_span" then
            writes[param.name] = true
            primary = primary or param
         end
      end
      byName[param.name] = param
   end
   assert(primary and ir.loop.count == primary.name, "loop is not bounded by its primary output")
   if ir.rangeGuard then
      assert(ir.loop.first == ir.rangeGuard.first and ir.loop.last == ir.rangeGuard.last
         and ir.rangeGuard.count == primary.name, "loop range proof mismatch")
      assert(byName[ir.rangeGuard.first] and byName[ir.rangeGuard.first].sourceType == "integer"
         and byName[ir.rangeGuard.last] and byName[ir.rangeGuard.last].sourceType == "integer",
         "range proof does not use integer uniforms")
   else
      assert(ir.loop.first == 1 and ir.loop.last == primary.name, "invalid full-span loop")
   end

   local declaredRegions = {}
   for _, region in ipairs(ir.regions) do
      local param = byRegion[region.id]
      assert(param and not declaredRegions[region.id], "invalid or duplicate region declaration")
      assert(region.param == param.name and region.access == param.access, "region declaration mismatch")
      assert(region.proof == param.ownership .. "_borrow", "invalid region proof")
      declaredRegions[region.id] = true
   end
   for region in pairs(byRegion) do assert(declaredRegions[region], "undeclared parameter region") end

   local facts = {}
   for _, fact in ipairs(ir.aliasFacts) do
      assert(byRegion[fact.left] and byRegion[fact.right] and fact.left ~= fact.right,
         "alias fact references an invalid region")
      local key = fact.left < fact.right
         and fact.left .. ":" .. fact.right or fact.right .. ":" .. fact.left
      assert(not facts[key], "duplicate alias fact")
      local hasWrite = byRegion[fact.left].kind == "write_span"
         or byRegion[fact.right].kind == "write_span"
      assert(fact.relation == (hasWrite and "disjoint" or "may_alias"), "invalid alias relationship")
      assert(fact.proof == (hasWrite and "exclusive_borrow" or "shared_borrows"), "invalid alias proof")
      facts[key] = true
   end
   local regionCount = 0
   for _ in pairs(byRegion) do regionCount = regionCount + 1 end
   assert(#ir.aliasFacts == regionCount * (regionCount - 1) / 2, "incomplete alias matrix")

   local guarded = {}
   for _, guard in ipairs(ir.guards) do
      assert(guard.op == "equal_count" and guard.left == primary.name, "invalid IR guard")
      assert(byName[guard.right] and byName[guard.right].region, "guarded non-span")
      guarded[guard.right] = true
   end
   for _, param in ipairs(ir.params) do
      if param.region and param ~= primary then assert(guarded[param.name], "unguarded IR span") end
   end

   local helpers = {}
   for _, helper in ipairs(ir.helpers or {}) do
      assert(not helpers[helper.name], "duplicate IR helper")
      helpers[helper.name] = helper
   end

   local function verifyExpr(node, values)
      assert(node and node.type, "untyped IR expression")
      if node.op == "narrow_f64_f32" then
         assert(node.type == "f32" and node.value.type == "f64", "invalid narrowing conversion")
         verifyExpr(node.value, values)
      elseif node.op == "widen_f32_f64" then
         assert(node.type == "f64" and node.value.type == "f32", "invalid widening conversion")
         verifyExpr(node.value, values)
      elseif node.op == "int_to_f64" then
         assert(node.type == "f64" and (node.value.type == "i32" or node.value.type == "u32"),
            "invalid integer promotion")
         verifyExpr(node.value, values)
      elseif node.op == "numeric_cast" then
         assert((node.type == "i32" or node.type == "u32")
            and (node.value.type == "f64" or node.value.type == "i32" or node.value.type == "u32"),
            "invalid numeric cast")
         verifyExpr(node.value, values)
      elseif node.op == "load" then
         local root = byName[node.span]
         assert(root and (root.kind == "read_span" or root.kind == "write_span")
            and node.type == root.type and not node.type:match("^struct:"), "invalid load root")
         assert(node.index == ir.loop.index, "unbounded load index")
      elseif node.op == "element_ref" then
         local root = byName[node.span]
         local layoutName = node.type:match("^ref:(.+)$")
         assert(root and layoutName and root.type == "struct:" .. layoutName and layouts[layoutName],
            "invalid struct element root")
         assert(node.mutable == (root.kind == "write_span") and node.index == ir.loop.index,
            "invalid struct element access")
      elseif node.op == "field_load" then
         local layout = layouts[node.layout]
         assert(layout and layout.fieldTypes[node.field] == node.type, "invalid struct field load")
         verifyExpr(node.object, values)
      elseif node.op == "uniform" then
         assert(byName[node.name] and byName[node.name].kind == "uniform"
            and node.type == byName[node.name].type, "invalid uniform")
      elseif node.op == "local" or node.op == "helper_param" then
         assert(values[node.name] == node.type, "invalid local value")
      elseif node.op == "constant_i32" then
         assert(node.type == "i32", "integer constant type")
      elseif node.op == "constant" then
         assert(node.type == "f64" and tonumber(node.value), "invalid constant")
      elseif node.op == "bool" then
         assert(node.type == "bool" and type(node.value) == "boolean", "invalid boolean")
      elseif node.op == "neg" or node.op == "not" or node.op == "bnot" then
         verifyExpr(node.value, values)
         local expected = node.op == "neg" and "f64" or node.op == "not" and "bool" or "i32"
         assert(node.type == expected, "invalid unary result")
         if node.op == "bnot" then
            local number = node.value.op == "constant" and tonumber(node.value.value) or nil
            assert(node.value.type == "i32" or node.value.type == "u32"
               or number and number >= 0 and number <= 4294967295 and number % 1 == 0,
               "invalid bitwise operand")
         end
      elseif node.op == "add" or node.op == "sub" or node.op == "mul" or node.op == "div"
         or node.op == "mod" or node.op == "pow"
      then
         assert(node.type == "f64" and node.left.type == "f64" and node.right.type == "f64",
            "invalid arithmetic")
         verifyExpr(node.left, values)
         verifyExpr(node.right, values)
      elseif node.op == "band" or node.op == "bor" or node.op == "bxor"
         or node.op == "lshift" or node.op == "rshift" or node.op == "arshift"
      then
         local function bitOperand(value)
            if value.type == "i32" or value.type == "u32" then return true end
            local number = value.op == "constant" and tonumber(value.value) or nil
            return number and number >= 0 and number <= 4294967295 and number % 1 == 0
         end
         assert(node.type == "i32" and bitOperand(node.left) and bitOperand(node.right),
            "invalid bitwise operation")
         verifyExpr(node.left, values)
         verifyExpr(node.right, values)
      elseif node.op == "lt" or node.op == "le" or node.op == "gt" or node.op == "ge"
         or node.op == "eq" or node.op == "ne"
      then
         local numeric = {f64 = true, f32 = true, i32 = true, u32 = true}
         assert(node.type == "bool" and (node.left.type == node.right.type
            or numeric[node.left.type] and numeric[node.right.type]), "invalid comparison")
         verifyExpr(node.left, values)
         verifyExpr(node.right, values)
      elseif node.op == "and" or node.op == "or" then
         assert(node.type == "bool" and node.left.type == "bool" and node.right.type == "bool",
            "invalid boolean operation")
         verifyExpr(node.left, values)
         verifyExpr(node.right, values)
      elseif node.op == "math" then
         assert(node.type == "f64", "invalid math result")
         local admitted = {
            sqrt = true, abs = true, floor = true, ceil = true, min = true, max = true,
            sin = true, cos = true, tan = true, asin = true, acos = true, atan = true,
            atan2 = true, sinh = true, cosh = true, tanh = true, exp = true, log = true,
            pow = true, fmod = true, deg = true, rad = true,
         }
         assert(admitted[node.intrinsic], "unknown math intrinsic")
         for _, arg in ipairs(node.args) do
            assert(arg.type == "f64", "invalid math argument")
            verifyExpr(arg, values)
         end
      elseif node.op == "helper_call" then
         local helper = helpers[node.helper]
         assert(helper and #node.args == #helper.params
            and (node.type == helper.resultType or node.type == "multi"),
            "invalid helper call")
         for i, arg in ipairs(node.args) do
            assert(arg.type == helper.params[i].type, "invalid helper argument")
            verifyExpr(arg, values)
         end
      else
         error("unknown expression opcode " .. tostring(node.op))
      end
   end

   for _, helper in ipairs(ir.helpers or {}) do
      local values = {}
      for _, param in ipairs(helper.params) do
         assert(not values[param.name], "duplicate helper parameter")
         values[param.name] = param.type
      end
      assert(#helper.values == #helper.resultTypes and helper.resultType == helper.resultTypes[1],
         "helper result mismatch")
      for i, value in ipairs(helper.values) do
         assert(value.type == helper.resultTypes[i], "helper result type mismatch")
         verifyExpr(value, values)
      end
   end

   local stored = {}
   local function verifyBlock(statements, inherited)
      local values = copyEnvironment(inherited)
      for _, statement in ipairs(statements) do
         if statement.op == "let" then
            assert(not values[statement.name] and statement.type == statement.value.type,
               "invalid local declaration")
            verifyExpr(statement.value, values)
            values[statement.name] = statement.type
         elseif statement.op == "multi_let" then
            verifyExpr(statement.call, values)
            assert(statement.call.type == "multi"
               and #statement.bindings == #statement.call.resultTypes, "invalid multiple-result declaration")
            for i, binding in ipairs(statement.bindings) do
               assert(not values[binding.name] and binding.type == statement.call.resultTypes[i],
                  "invalid multiple-result binding")
               values[binding.name] = binding.type
            end
         elseif statement.op == "store" then
            assert(writes[statement.span] and statement.index == ir.loop.index, "invalid store root")
            verifyExpr(statement.value, values)
            assert(statement.value.type == byName[statement.span].type, "store type mismatch")
            stored[statement.span] = true
         elseif statement.op == "assign" then
            for _, assignment in ipairs(statement.values) do
               local target = assignment.target
               if target.kind == "local" then
                  assert(values[target.name] == target.type, "invalid local assignment target")
               else
                  local layout = layouts[target.layout]
                  assert(target.kind == "field" and target.object.mutable and layout
                     and layout.fieldTypes[target.field] == target.type, "invalid field assignment target")
                  verifyExpr(target.object, values)
               end
               assert(assignment.value.type == target.type, "assignment type mismatch")
               verifyExpr(assignment.value, values)
            end
         elseif statement.op == "if" then
            for _, clause in ipairs(statement.clauses) do
               assert(clause.condition.type == "bool", "non-boolean branch")
               verifyExpr(clause.condition, values)
               verifyBlock(clause.body, values)
            end
            if statement.elseBody then verifyBlock(statement.elseBody, values) end
         elseif statement.op == "fornum" then
            for _, bound in ipairs({statement.from, statement.to}) do
               assert(bound.type == "i32" or bound.type == "u32" or bound.type == "f64",
                  "non-numeric for bound")
               verifyExpr(bound, values)
            end
            assert(statement.binding.type == "i32", "for induction variable type")
            local inner = {}
            for k, v in pairs(values) do inner[k] = v end
            inner[statement.binding.name] = "i32"
            verifyBlock(statement.body, inner)
         elseif statement.op == "while" then
            assert(statement.condition.type == "bool", "non-boolean loop condition")
            verifyExpr(statement.condition, values)
            verifyBlock(statement.body, values)
         elseif statement.op == "block" then
            verifyBlock(statement.body, values)
         else
            assert(statement.op == "break" or statement.op == "continue", "unknown statement opcode")
         end
      end
   end
   local uniforms = {}
   for _, param in ipairs(ir.params) do
      if param.kind == "uniform" then uniforms[param.name] = param.type end
   end
   verifyBlock(ir.loop.statements, uniforms)
   for output in pairs(writes) do
      local span = byName[output]
      if not span.type:match("^struct:") then
         assert(stored[output], "scalar IR output is never stored")
      end
   end
   if ir.lanes then
      assert(ir.wantsLanes and ir.lanes.lanes == LANES, "invalid lane width or missing SIMD contract")

      local laneMath = {
         sqrt = true, abs = true, floor = true, ceil = true, min = true, max = true,
         sin = true, cos = true, tan = true, asin = true, acos = true, atan = true,
         atan2 = true, sinh = true, cosh = true, tanh = true, exp = true, log = true,
         pow = true, fmod = true, deg = true, rad = true,
      }
      local laneBinary = {
         vadd64 = "f64x4", vsub64 = "f64x4", vmul64 = "f64x4", vdiv64 = "f64x4",
         vlt64 = "m64x4", vle64 = "m64x4", vgt64 = "m64x4", vge64 = "m64x4",
         veq64 = "m64x4", vne64 = "m64x4",
      }

      local function verifyLaneExpr(node, values)
         assert(node and node.type, "untyped lane expression")
         if node.type ~= "f64x4" and node.type ~= "m64x4" then
            verifyExpr(node, values)
         elseif node.op == "local" then
            assert(values[node.name] == node.type, "invalid lane local")
         elseif node.op == "vsplat64" then
            assert(node.type == "f64x4" and #node.args == 1 and node.args[1].type == "f64",
               "invalid lane splat")
            verifyExpr(node.args[1], values)
         elseif node.op == "vfield_load" then
            local root = byName[node.span]
            local layout = layouts[node.layout]
            assert(root and root.type == "struct:" .. tostring(node.layout)
               and layout and layout.fieldTypes[node.field] == "f32"
               and node.lanes == LANES and node.type == "f64x4",
               "invalid lane field load")
         elseif laneBinary[node.op] then
            assert(#node.args == 2 and node.type == laneBinary[node.op]
               and node.args[1].type == "f64x4" and node.args[2].type == "f64x4",
               "invalid lane binary operation")
            verifyLaneExpr(node.args[1], values)
            verifyLaneExpr(node.args[2], values)
         elseif node.op == "vmand" or node.op == "vmor" then
            assert(node.type == "m64x4" and #node.args == 2
               and node.args[1].type == "m64x4" and node.args[2].type == "m64x4",
               "invalid lane mask operation")
            verifyLaneExpr(node.args[1], values)
            verifyLaneExpr(node.args[2], values)
         elseif node.op == "vmnot" then
            assert(node.type == "m64x4" and #node.args == 1 and node.args[1].type == "m64x4",
               "invalid lane mask negation")
            verifyLaneExpr(node.args[1], values)
         elseif node.op == "vneg64" then
            assert(node.type == "f64x4" and #node.args == 1 and node.args[1].type == "f64x4",
               "invalid lane negation")
            verifyLaneExpr(node.args[1], values)
         elseif node.op == "vselect" then
            assert(#node.args == 3 and node.args[1].type == "m64x4"
               and node.args[2].type == node.type and node.args[3].type == node.type,
               "invalid lane select")
            verifyLaneExpr(node.args[1], values)
            verifyLaneExpr(node.args[2], values)
            verifyLaneExpr(node.args[3], values)
         elseif node.op == "vmath" then
            assert(node.type == "f64x4" and laneMath[node.intrinsic], "invalid lane math operation")
            for _, arg in ipairs(node.args) do
               assert(arg.type == "f64x4", "invalid lane math argument")
               verifyLaneExpr(arg, values)
            end
         else
            error("unknown lane expression opcode " .. tostring(node.op))
         end
      end

      local laneValues = copyEnvironment(uniforms)
      for _, statement in ipairs(ir.lanes.statements) do
         if statement.op == "let" then
            assert(not laneValues[statement.name] and statement.type == statement.value.type,
               "invalid lane local declaration")
            verifyLaneExpr(statement.value, laneValues)
            laneValues[statement.name] = statement.type
         elseif statement.op == "vassign" then
            for _, assignment in ipairs(statement.values) do
               local target = assignment.target
               verifyLaneExpr(assignment.value, laneValues)
               if target.kind == "local" then
                  assert(laneValues[target.name] == assignment.value.type,
                     "invalid lane local assignment")
               else
                  local root = byName[target.span]
                  local layout = layouts[target.layout]
                  assert(target.kind == "vfield" and root and root.kind == "write_span"
                     and root.type == "struct:" .. tostring(target.layout)
                     and layout and layout.fieldTypes[target.field] == target.scalarType
                     and target.scalarType == "f32" and assignment.value.type == "f64x4",
                     "invalid lane field assignment")
               end
            end
         else
            error("unknown lane statement opcode " .. tostring(statement.op))
         end
      end
   end
   return ir
end

compiler.verifyIR = verifyIR

local function irLines(ir)
   local lines = {"native-c-ir 3", "function " .. ir.name, "symbol " .. ir.symbol}
   -- The contract is part of what the IR means, not a build setting, because it
   -- decides what the function answers rather than only how fast it gets there.
   if ir.fpContract then lines[#lines + 1] = "contract fp-contract(fused)" end
   lines[#lines + 1] = "layouts"
   for _, layout in ipairs(ir.layouts or {}) do
      local fields = {}
      for _, field in ipairs(layout.fields) do fields[#fields + 1] = field.name .. ":" .. field.type end
      lines[#lines + 1] = "  " .. layout.name .. "{" .. table.concat(fields, ",") .. "}"
   end
   lines[#lines + 1] = "params"
   for _, param in ipairs(ir.params) do
      if param.region then
         lines[#lines + 1] = ("  %s %s:%s region(%s) %s @%d:%d"):format(
            param.kind, param.name, param.type, param.region, param.access,
            param.source.line, param.source.column
         )
      else
         lines[#lines + 1] = ("  uniform %s:%s source(%s) @%d:%d"):format(
            param.name, param.type, param.sourceType, param.source.line, param.source.column
         )
      end
   end
   lines[#lines + 1] = "aliasing"
   for _, fact in ipairs(ir.aliasFacts) do
      lines[#lines + 1] = ("  %s %s %s proof(%s)"):format(
         fact.relation, fact.left, fact.right, fact.proof
      )
   end
   lines[#lines + 1] = "helpers"
   for _, helper in ipairs(ir.helpers or {}) do
      lines[#lines + 1] = ("  %s -> %s @%d:%d"):format(
         helper.name, table.concat(helper.resultTypes, ","), helper.source.line, helper.source.column
      )
   end
   lines[#lines + 1] = "guards"
   for _, guard in ipairs(ir.guards) do
      lines[#lines + 1] = ("  equal_count %s %s @%d:%d"):format(
         guard.left, guard.right, guard.source.line, guard.source.column
      )
   end
   if ir.rangeGuard then
      lines[#lines + 1] = ("  range %s %s count(%s) @%d:%d"):format(
         ir.rangeGuard.first, ir.rangeGuard.last, ir.rangeGuard.count,
         ir.rangeGuard.source.line, ir.rangeGuard.source.column
      )
   end
   lines[#lines + 1] = ("loop %s = %s .. %s count(%s) @%d:%d"):format(
      ir.loop.index, tostring(ir.loop.first), tostring(ir.loop.last), ir.loop.count,
      ir.loop.source.line, ir.loop.source.column
   )
   local function expression(node)
      if node.op == "load" then return "load:" .. node.type .. " " .. node.span .. "[" .. node.index .. "]" end
      if node.op == "element_ref" then return "element_ref:" .. node.layout .. " " .. node.span .. "[" .. node.index .. "]" end
      if node.op == "field_load" then return "field:" .. node.type .. " " .. expression(node.object) .. "." .. node.field end
      if node.op == "vfield_load" then
         return "vfield:" .. node.type .. " " .. node.span .. "[i..i+"
            .. tostring(node.lanes - 1) .. "]." .. node.field
      end
      if node.op == "uniform" or node.op == "local" or node.op == "helper_param" then
         return node.op .. ":" .. node.type .. " " .. node.name
      end
      if node.op == "constant_i32" then return "constant:i32 " .. node.value end
      if node.op == "constant" then return "constant:f64 " .. node.value end
      if node.op == "bool" then return "bool " .. tostring(node.value) end
      if node.op == "widen_f32_f64" or node.op == "narrow_f64_f32"
         or node.op == "int_to_f64" or node.op == "numeric_cast"
         or node.op == "neg" or node.op == "not" or node.op == "bnot"
      then
         return node.op .. "(" .. expression(node.value) .. ")"
      end
      if node.op == "math" then
         local args = {}
         for _, arg in ipairs(node.args) do args[#args + 1] = expression(arg) end
         return "math." .. node.intrinsic .. "(" .. table.concat(args, ", ") .. ")"
      end
      if node.op == "vmath" then
         local args = {}
         for _, arg in ipairs(node.args) do args[#args + 1] = expression(arg) end
         return "vmath." .. node.intrinsic .. ":" .. node.type
            .. "(" .. table.concat(args, ", ") .. ")"
      end
      if node.op == "helper_call" then
         local args = {}
         for _, arg in ipairs(node.args) do args[#args + 1] = expression(arg) end
         return "call " .. node.helper .. "(" .. table.concat(args, ", ") .. ")"
      end
      if node.args then
         local args = {}
         for _, arg in ipairs(node.args) do args[#args + 1] = expression(arg) end
         return node.op .. ":" .. node.type .. "(" .. table.concat(args, ", ") .. ")"
      end
      return node.op .. "(" .. expression(node.left) .. ", " .. expression(node.right) .. ")"
   end
   local function block(statements, depth)
      local prefix = string.rep("  ", depth)
      for _, statement in ipairs(statements) do
         if statement.op == "let" then
            lines[#lines + 1] = prefix .. "let " .. statement.name .. ":" .. statement.type
               .. " = " .. expression(statement.value)
         elseif statement.op == "multi_let" then
            local names = {}
            for _, binding in ipairs(statement.bindings) do names[#names + 1] = binding.name .. ":" .. binding.type end
            lines[#lines + 1] = prefix .. "let " .. table.concat(names, ",") .. " = " .. expression(statement.call)
         elseif statement.op == "store" then
            lines[#lines + 1] = prefix .. "store " .. statement.span .. "[" .. statement.index
               .. "] = " .. expression(statement.value)
         elseif statement.op == "assign" then
            for _, assignment in ipairs(statement.values) do
               local target = assignment.target.kind == "local" and assignment.target.name
                  or expression(assignment.target.object) .. "." .. assignment.target.field
               lines[#lines + 1] = prefix .. "set " .. target .. " = " .. expression(assignment.value)
            end
         elseif statement.op == "vassign" then
            for _, assignment in ipairs(statement.values) do
               local target = assignment.target.kind == "local" and assignment.target.name
                  or assignment.target.span .. "[i..i+" .. tostring(LANES - 1)
                     .. "]." .. assignment.target.field
               lines[#lines + 1] = prefix .. "vset " .. target .. " = "
                  .. expression(assignment.value)
            end
         elseif statement.op == "if" then
            for i, clause in ipairs(statement.clauses) do
               lines[#lines + 1] = prefix .. (i == 1 and "if " or "elseif ")
                  .. expression(clause.condition)
               block(clause.body, depth + 1)
            end
            if statement.elseBody then
               lines[#lines + 1] = prefix .. "else"
               block(statement.elseBody, depth + 1)
            end
            lines[#lines + 1] = prefix .. "end"
         elseif statement.op == "fornum" then
            lines[#lines + 1] = prefix .. "for " .. statement.binding.name .. " = "
               .. expression(statement.from) .. " .. " .. expression(statement.to)
            block(statement.body, depth + 1)
            lines[#lines + 1] = prefix .. "end"
         elseif statement.op == "while" then
            lines[#lines + 1] = prefix .. "while " .. expression(statement.condition)
            block(statement.body, depth + 1)
            lines[#lines + 1] = prefix .. "end"
         elseif statement.op == "block" then
            lines[#lines + 1] = prefix .. "block"
            block(statement.body, depth + 1)
         else
            lines[#lines + 1] = prefix .. statement.op
         end
      end
   end
   block(ir.loop.statements, 1)
   if ir.lanes then
      lines[#lines + 1] = "simd lanes(" .. tostring(ir.lanes.lanes) .. ")"
      block(ir.lanes.statements, 1)
   end
   return table.concat(lines, "\n") .. "\n"
end

local function doubleLiteral(value)
   return value:find("[%.eE]") and value or value .. ".0"
end

local cBinary = {
   add = "+", sub = "-", mul = "*", div = "/",
   lt = "<", le = "<=", gt = ">", ge = ">=", eq = "==", ne = "!=",
   ["and"] = "&&", ["or"] = "||",
}

local function renderExpr(node)
   local LANE_BINARY = {vadd64 = " + ", vsub64 = " - ", vmul64 = " * ", vdiv64 = " / ",
      vlt64 = " < ", vle64 = " <= ", vgt64 = " > ", vge64 = " >= ", veq64 = " == ",
      vne64 = " != ", vmand = " & ", vmor = " | "}
   if LANE_BINARY[node.op] then
      return "(" .. renderExpr(node.args[1]) .. LANE_BINARY[node.op]
         .. renderExpr(node.args[2]) .. ")"
   end
   if node.op == "vsplat64" then
      return "ks_splat64(" .. renderExpr(node.args[1]) .. ")"
   end
   if node.op == "vmnot" then
      return "(~" .. renderExpr(node.args[1]) .. ")"
   end
   if node.op == "vneg64" then
      return "(-" .. renderExpr(node.args[1]) .. ")"
   end
   if node.op == "vselect" then
      return "ks_sel64(" .. renderExpr(node.args[1]) .. ", " .. renderExpr(node.args[2])
         .. ", " .. renderExpr(node.args[3]) .. ")"
   end
   if node.op == "vfield_load" then
      local parts = {}
      for lane = 0, node.lanes - 1 do
         parts[#parts + 1] = "p_" .. node.span .. "[i + " .. lane .. "]." .. node.field
      end
      return "((ks_f64x4){" .. table.concat(parts, ", ") .. "})"
   end
   if node.op == "vmath" then
      -- One scalar call per lane, rendered through the ordinary math path so the
      -- lane-parallel form cannot drift from the scalar one. Clang recognizes
      -- the shape and uses a vector library call where it has one.
      local parts = {}
      for lane = 0, 3 do
         local args = {}
         for i, arg in ipairs(node.args) do
            args[i] = {op = "raw", text = renderExpr(arg) .. "[" .. lane .. "]"}
         end
         parts[#parts + 1] = renderExpr({op = "math", intrinsic = node.intrinsic, args = args})
      end

      return "((ks_f64x4){" .. table.concat(parts, ", ") .. "})"
   end
   if node.op == "raw" then return node.text end
   if node.op == "narrow_f64_f32" then return "(float)(" .. renderExpr(node.value) .. ")" end
   if node.op == "widen_f32_f64" then return "((double)" .. renderExpr(node.value) .. ")" end
   if node.op == "int_to_f64" then return "((double)" .. renderExpr(node.value) .. ")" end
   if node.op == "numeric_cast" then
      return "((" .. (node.type == "u32" and "uint32_t" or "int32_t") .. ")" .. renderExpr(node.value) .. ")"
   end
   if node.op == "load" then return cIdentifier("p", node.span) .. "[i]" end
   if node.op == "element_ref" then return "(&" .. cIdentifier("p", node.span) .. "[i])" end
   if node.op == "field_load" then return "(" .. renderExpr(node.object) .. "->" .. node.field .. ")" end
   if node.op == "uniform" then return cIdentifier("p", node.name) end
   if node.op == "local" or node.op == "helper_param" then return node.cName end
   if node.op == "constant_i32" then return "INT32_C(" .. tostring(math.floor(tonumber(node.value))) .. ")" end
   if node.op == "constant" then return doubleLiteral(node.value) end
   if node.op == "bool" then return node.value and "true" or "false" end
   if node.op == "neg" then return "(-(" .. renderExpr(node.value) .. "))" end
   if node.op == "not" then return "(!(" .. renderExpr(node.value) .. "))" end
   if node.op == "bnot" then return "((int32_t)(~nupp_u32(" .. renderExpr(node.value) .. ")))" end
   if node.op == "band" or node.op == "bor" or node.op == "bxor" then
      local op = node.op == "band" and "&" or node.op == "bor" and "|" or "^"
      return "((int32_t)(nupp_u32(" .. renderExpr(node.left) .. ") " .. op
         .. " nupp_u32(" .. renderExpr(node.right) .. ")))"
   end
   if node.op == "lshift" or node.op == "rshift" or node.op == "arshift" then
      local left = "nupp_u32(" .. renderExpr(node.left) .. ")"
      local shift = "(nupp_u32(" .. renderExpr(node.right) .. ") & 31u)"
      if node.op == "lshift" then return "((int32_t)(" .. left .. " << " .. shift .. "))" end
      if node.op == "rshift" then return "((int32_t)(" .. left .. " >> " .. shift .. "))" end
      return "nupp_arshift(" .. left .. ", " .. shift .. ")"
   end
   if node.op == "mod" then return "fmod(" .. renderExpr(node.left) .. ", " .. renderExpr(node.right) .. ")" end
   if node.op == "pow" then return "pow(" .. renderExpr(node.left) .. ", " .. renderExpr(node.right) .. ")" end
   if cBinary[node.op] then
      return "(" .. renderExpr(node.left) .. " " .. cBinary[node.op] .. " " .. renderExpr(node.right) .. ")"
   end
   if node.op == "math" then
      local args = {}
      for _, arg in ipairs(node.args) do args[#args + 1] = renderExpr(arg) end
      if node.intrinsic == "min" or node.intrinsic == "max" then
         local call = "nupp_" .. node.intrinsic .. "2(" .. args[1] .. ", " .. args[2] .. ")"
         for i = 3, #args do call = "nupp_" .. node.intrinsic .. "2(" .. call .. ", " .. args[i] .. ")" end
         return call
      end
      if node.intrinsic == "log" and #args == 2 then
         return "(log(" .. args[1] .. ") / log(" .. args[2] .. "))"
      end
      if node.intrinsic == "deg" then return "(" .. args[1] .. " * (180.0 / M_PI))" end
      if node.intrinsic == "rad" then return "(" .. args[1] .. " * (M_PI / 180.0))" end
      local cName = ({
         sqrt = "sqrt", abs = "fabs", floor = "floor", ceil = "ceil",
         sin = "sin", cos = "cos", tan = "tan", asin = "asin", acos = "acos",
         atan = "atan", atan2 = "atan2", sinh = "sinh", cosh = "cosh", tanh = "tanh",
         exp = "exp", log = "log", pow = "pow", fmod = "fmod",
      })[node.intrinsic]
      return cName .. "(" .. table.concat(args, ", ") .. ")"
   end
   if node.op == "helper_call" then
      local args = {}
      for _, arg in ipairs(node.args) do args[#args + 1] = renderExpr(arg) end
      return node.cName .. "(" .. table.concat(args, ", ") .. ")"
   end
   error("cannot render expression " .. tostring(node.op))
end

local function cType(typeName)
   if typeName == "bool" then return "bool" end
   if typeName == "f64" then return "double" end
   if typeName == "f32" then return "float" end
   if typeName == "i32" then return "int32_t" end
   if typeName == "u32" then return "uint32_t" end
   if typeName == "f64x4" then return "ks_f64x4" end
   if typeName == "m64x4" then return "ks_m64x4" end
   local layout = typeName:match("^ref:(.+)$")
   if layout then return "Ks" .. layout .. " *" end
   error("unknown C type " .. tostring(typeName))
end

local function cParams(ir)
   local params = {}
   for _, param in ipairs(ir.params) do
      local name = cIdentifier("p", param.name)
      local layout = param.type:match("^struct:(.+)$")
      local elementType = layout and "Ks" .. layout or cType(param.type)
      if param.kind == "write_span" then params[#params + 1] = elementType .. " *restrict " .. name
      elseif param.kind == "read_span" then params[#params + 1] = "const " .. elementType .. " *" .. name
      else params[#params + 1] = cType(param.type) .. " " .. name
      end
   end
   params[#params + 1] = "size_t count"
   return table.concat(params, ", ")
end

local function renderC(ir)
   local lines = {}
   local function emit(line) lines[#lines + 1] = line or "" end
   emit("/* Generated from verified test-only native C IR. */")
   emit("#include <math.h>")
   emit("#include <stdbool.h>")
   emit("#include <stddef.h>")
   emit("#include <stdint.h>")
   emit("#ifndef M_PI")
   emit("#define M_PI 3.14159265358979323846264338327950288")
   emit("#endif")
   emit("")
   for _, layout in ipairs(ir.layouts or {}) do
      emit("typedef struct {")
      for _, field in ipairs(layout.fields) do
         emit("    " .. cType(field.type) .. " " .. field.name .. ";")
      end
      emit("} " .. layout.cName .. ";")
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
   emit("typedef double ks_f64x4 __attribute__((vector_size(32)));")
   emit("typedef long long ks_m64x4 __attribute__((vector_size(32)));")
   emit("static inline __attribute__((unused)) ks_f64x4 ks_splat64(double v)"
      .. " { return (ks_f64x4){v, v, v, v}; }")
   emit("static inline __attribute__((unused)) ks_f64x4 ks_sel64(ks_m64x4 m, ks_f64x4 a, ks_f64x4 b)"
      .. " { return (ks_f64x4)((m & (ks_m64x4)a) | (~m & (ks_m64x4)b)); }")
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
                  emit(prefix .. "    ks_f64x4 lanes = " .. rendered .. ";")
                  for lane = 0, 3 do
                     emit(prefix .. "    p_" .. target.span .. "[i + " .. lane .. "]."
                        .. target.field .. " = (" .. cType(target.scalarType)
                        .. ")lanes[" .. lane .. "];")
                  end
                  emit(prefix .. "}")
               else
                  emit(prefix .. target.cName .. " = " .. renderExpr(assignment.value) .. ";")
               end
            end
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

   local params = cParams(ir)
   local function implementation(symbol, forced)
      emit("__attribute__((noinline))")
      emit("void " .. symbol .. "(" .. params .. ") {")
      -- Scoped to this function rather than set as a build flag, so a relaxation
      -- one function asked for cannot silently change another one's answers.
      if ir.fpContract then
         emit("#if defined(__clang__)")
         emit("#pragma clang fp contract(fast)")
         emit("#endif")
      end
      if ir.rangeGuard then
         emit("    (void)count;")
         emit("    size_t i = (size_t)(p_" .. ir.rangeGuard.first .. " - 1.0);")
         emit("    size_t end = (size_t)p_" .. ir.rangeGuard.last .. ";")
      else
         emit("    size_t i = 0;")
         emit("    size_t end = count;")
      end
      if forced then
         emit("#if defined(__clang__)")
         emit("#pragma clang loop vectorize(disable) interleave(disable)")
         emit("#endif")
      end
      -- The forced-scalar body stays scalar: it is the oracle the lane-parallel
      -- one is diffed against, so it must not share its lowering.
      if ir.lanes and not forced then
         -- Whole groups run several iterations at once; the remainder runs the
         -- same body one iteration at a time. A masked final group would still
         -- read the addresses it masked off, and the last element of a span may
         -- be the last byte of a page.
         emit("    size_t groups = (end > i) ? ((end - i) / " .. ir.lanes.lanes
            .. ") * " .. ir.lanes.lanes .. " + i : i;")
         emit("    for (; i < groups; i += " .. ir.lanes.lanes .. ") {")
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

local function renderBinding(ir)
   local lib = '"bench/kernel-subset-spike/build/libkernel_subset_spike"'
   local lines = {"-- Generated from verified test-only native C IR.", "", 'local span = require("nupp.span")', ""}
   for _, layout in ipairs(ir.layouts or {}) do
      lines[#lines + 1] = "local struct " .. layout.name
      for _, field in ipairs(layout.fields) do
         local sourceType = ({f32 = "float", i32 = "int32", u32 = "uint32"})[field.type]
         lines[#lines + 1] = "    " .. field.name .. ": " .. sourceType
      end
      lines[#lines + 1] = "end"
      lines[#lines + 1] = ""
      lines[#lines + 1] = "cdef function " .. ir.symbol .. "_layout_" .. layout.name
         .. "_size(): uint64 from" .. lib
      for _, field in ipairs(layout.fields) do
         lines[#lines + 1] = "cdef function " .. ir.symbol .. "_layout_" .. layout.name
            .. "_offset_" .. field.name .. "(): uint64 from" .. lib
         lines[#lines + 1] = "cdef function " .. ir.symbol .. "_layout_" .. layout.name
            .. "_size_" .. field.name .. "(): uint64 from" .. lib
      end
      lines[#lines + 1] = "const " .. layout.name .. "Layout = layoutof(" .. layout.name .. ")"
      lines[#lines + 1] = "if " .. layout.name .. "Layout.size ~= " .. ir.symbol .. "_layout_"
         .. layout.name .. "_size() then error(\"native struct layout size mismatch\", 0) end"
      for i, field in ipairs(layout.fields) do
         lines[#lines + 1] = "if " .. layout.name .. "Layout.fields[" .. tostring(i) .. "].offset ~= "
            .. ir.symbol .. "_layout_" .. layout.name .. "_offset_" .. field.name
            .. "() then error(\"native struct field offset mismatch\", 0) end"
         lines[#lines + 1] = "if " .. layout.name .. "Layout.fields[" .. tostring(i) .. "].size ~= "
            .. ir.symbol .. "_layout_" .. layout.name .. "_size_" .. field.name
            .. "() then error(\"native struct field size mismatch\", 0) end"
      end
      lines[#lines + 1] = ""
   end
   lines[#lines + 1] = "cdef function " .. ir.symbol .. "("
   local physicalParams = {}
   for _, param in ipairs(ir.params) do
      if param.kind == "write_span" then
         physicalParams[#physicalParams + 1] = "exclusive " .. param.name .. ": voidptr"
      elseif param.kind == "read_span" then
         physicalParams[#physicalParams + 1] = "borrows " .. param.name .. ": voidptr"
      else
         local abiType = param.type == "f64" and "number" or param.type == "f32" and "float"
            or param.type == "u32" and "uint32" or "int32"
         physicalParams[#physicalParams + 1] = param.name .. ": " .. abiType
      end
   end
   physicalParams[#physicalParams + 1] = "count: uint64"
   for i, param in ipairs(physicalParams) do
      lines[#lines + 1] = "    " .. param .. (i < #physicalParams and "," or "")
   end
   lines[#lines + 1] = ") from" .. lib
   lines[#lines + 1] = ""
   lines[#lines + 1] = "local function " .. ir.name .. "("
   local logicalParams = {}
   for _, param in ipairs(ir.params) do
      local sourceType = param.type:match("^struct:(.+)$") or ({f32 = "float", i32 = "int32", u32 = "uint32"})[param.type]
      if param.kind == "write_span" then
         logicalParams[#logicalParams + 1] = "exclusive " .. param.name .. ": span.WriteSpan<" .. sourceType .. ">"
      elseif param.kind == "read_span" then
         logicalParams[#logicalParams + 1] = "borrows " .. param.name .. ": span.Span<" .. sourceType .. ">"
      else
         logicalParams[#logicalParams + 1] = param.name .. ": " .. param.sourceType
      end
   end
   for i, param in ipairs(logicalParams) do
      lines[#lines + 1] = "    " .. param .. (i < #logicalParams and "," or "")
   end
   lines[#lines + 1] = "): nil"
   if ir.rangeGuard then
      lines[#lines + 1] = "    if " .. ir.rangeGuard.first .. " < 1 or " .. ir.rangeGuard.last
         .. " > " .. ir.rangeGuard.count .. ".count or " .. ir.rangeGuard.first .. " > "
         .. ir.rangeGuard.last .. " + 1 then"
      lines[#lines + 1] = "        error(\"native range out of bounds\", 2)"
      lines[#lines + 1] = "    end"
   end
   local primaryPointer, primaryCount
   local physicalArgs = {}
   for _, param in ipairs(ir.params) do
      if param.kind == "write_span" or param.kind == "read_span" then
         local pointer = "native_" .. param.name
         local count = "native_" .. param.name .. "Count"
         lines[#lines + 1] = "    local " .. pointer .. ", " .. count .. " = " .. param.name .. ":ref()"
         if not primaryPointer then primaryPointer, primaryCount = pointer, count end
         if count ~= primaryCount then
            lines[#lines + 1] = "    if " .. count .. " ~= " .. primaryCount
               .. " then error(\"native spans have incompatible lengths\", 2) end"
         end
         physicalArgs[#physicalArgs + 1] = pointer .. " as voidptr"
      else
         physicalArgs[#physicalArgs + 1] = param.name
      end
   end
   physicalArgs[#physicalArgs + 1] = primaryCount
   lines[#lines + 1] = "    unsafe do"
   lines[#lines + 1] = "        " .. ir.symbol .. "(" .. table.concat(physicalArgs, ", ") .. ")"
   lines[#lines + 1] = "    end"
   lines[#lines + 1] = "end"
   lines[#lines + 1] = ""
   local exports = {ir.name .. " = " .. ir.name}
   for _, layout in ipairs(ir.layouts or {}) do exports[#exports + 1] = layout.name .. " = " .. layout.name end
   lines[#lines + 1] = "return {" .. table.concat(exports, ", ") .. ",}"
   return table.concat(lines, "\n") .. "\n"
end

function compiler.compile(source, filename, checked)
   local ir, diagnostics = parseKernel(source, filename, checked)
   if not ir then return nil, diagnostics end
   verifyIR(ir)
   -- The lane-parallel pass runs on verified scalar IR: what it rewrites has
   -- already been proved to mean something, so a refusal here is only ever
   -- about lowering it several iterations at a time.
   if ir.wantsLanes then
      local refusals = {}
      local ok, problem = pcall(function()
         ir.lanes = vectorizeLoop(ir, function(_, message)
            refusals[#refusals + 1] = diagnostic(filename, ir.loop.source, message)
            error(STOP, 0)
         end)
      end)
      if not ok then
         if problem ~= STOP then error(problem, 0) end

         return nil, refusals
      end
      verifyIR(ir)
   end
   return {
      ir = ir,
      irText = irLines(ir),
      c = renderC(ir),
      binding = renderBinding(ir),
   }, diagnostics
end

return compiler
