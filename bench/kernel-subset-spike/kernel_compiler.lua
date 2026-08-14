-- A test-only compiler for a deliberately small `@kernel` subset.
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

local function parseKernel(source, filename)
   local parsed = parser.parse(source, filename)
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
      local applications, helperDecls = {}, {}
      for _, block in ipairs(parsed.root.blocks or {}) do
         for _, stat in ipairs(block.stats or {}) do
            if stat.kind == "pragmaStmt" and stat.name and stat.name.text == "kernel" then
               applications[#applications + 1] = stat
            elseif stat.kind == "localFuncStmt" and stat.name then
               helperDecls[stat.name.text] = stat
            end
         end
      end
      if #applications == 0 then
         reject(parsed.root, "no @kernel function was found")
      elseif #applications > 1 then
         reject(applications[2], "this spike accepts exactly one @kernel function")
      end

      local application = applications[1]
      local fn = application.stat
      if not fn or fn.kind ~= "localFuncStmt" then
         reject(fn or application, "@kernel must decorate a local function with a visible body")
      end
      if application.open then reject(application, "@kernel takes no arguments") end

      local body = fn.body
      if not body or body.generics or body.varargParam or body.captureTakes or body.captureBorrows then
         reject(body or fn, "generic, variadic, and capturing kernels are not admitted")
      end
      if #(body.rets or {}) ~= 1 or compactType(body.rets[1]) ~= "nil" then
         reject(body, "the map-kernel prototype must return nil")
      end

      local params, byName, spans, writes, reads = {}, {}, {}, {}, {}
      for _, raw in ipairs(body.params or {}) do
         local name = raw.name and raw.name.text
         if not name then reject(raw, "every kernel parameter must be named") end
         if byName[name] then reject(raw, "duplicate kernel parameter " .. name) end

         local spelling = compactType(raw.type)
         local mode = raw.modeTok and raw.modeTok.text or nil
         local param
         if spelling == "span.WriteSpan<float>" then
            if mode ~= "exclusive" then
               reject(raw, "a writable float span must be declared exclusive")
            end
            param = {
               kind = "write_span", name = name, type = "f32",
               region = "r" .. tostring(#spans), access = "write",
               ownership = "exclusive", source = site(raw),
            }
            writes[#writes + 1] = param
            spans[#spans + 1] = param
         elseif spelling == "span.Span<float>" then
            if mode ~= "borrows" then
               reject(raw, "a readable float span must be declared borrows")
            end
            param = {
               kind = "read_span", name = name, type = "f32",
               region = "r" .. tostring(#spans), access = "read",
               ownership = "shared", source = site(raw),
            }
            reads[#reads + 1] = param
            spans[#spans + 1] = param
         elseif spelling == "float" then
            if mode then reject(raw, "a uniform float parameter has no ownership mode") end
            param = {
               kind = "uniform", name = name, type = "f64",
               sourceType = "float", source = site(raw),
            }
         else
            reject(raw.type or raw, "parameter type " .. spelling .. " is not admitted")
         end
         params[#params + 1] = param
         byName[name] = param
      end
      if #writes == 0 then reject(body, "the map-kernel prototype needs a writable float span") end
      if #reads == 0 then reject(body, "the map-kernel prototype needs a readable float span") end
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
      if #stats ~= 2 then
         reject(body.body or body, "the admitted body is one length guard followed by one numeric loop")
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

      local loop = stats[2]
      if loop.kind ~= "fornumStmt" then reject(loop, "the second statement must be a numeric for loop") end
      if not loop.start or loop.start.kind ~= "number" or loop.start.token.text ~= "1" then
         reject(loop.start or loop, "kernel span loops must begin at one")
      end
      if loop.step then reject(loop.step, "the first subset does not admit an explicit loop step") end
      if dotCount(loop.stop) ~= primary.name then
         reject(loop.stop or loop, "the loop bound must be the primary output count")
      end
      local index = loop.var and loop.var.text
      if not index then reject(loop, "the kernel loop needs an index variable") end

      local helpers, helperByName, helperState = {}, {}, {}
      local lowerExpression, lowerHelper

      local arithmetic = {["+"] = "add", ["-"] = "sub", ["*"] = "mul", ["/"] = "div"}
      local comparisons = {
         ["<"] = "lt", ["<="] = "le", [">"] = "gt", [">="] = "ge",
         ["=="] = "eq", ["~="] = "ne",
      }
      local mathIntrinsics = {
         ["math.sqrt"] = "sqrt", ["math.abs"] = "abs",
         ["math.floor"] = "floor", ["math.ceil"] = "ceil",
         ["math.min"] = "min", ["math.max"] = "max",
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
         local resultSpelling = #(helperBody.rets or {}) == 1 and compactType(helperBody.rets[1]) or ""
         local resultType = resultSpelling == "boolean" and "bool"
            or (resultSpelling == "number" or resultSpelling == "float") and "f64" or nil
         if not resultType then reject(helperBody, "native helpers return one number, float, or boolean") end

         local helperParams, environment = {}, {}
         for _, raw in ipairs(helperBody.params or {}) do
            local paramName = raw.name and raw.name.text
            local spelling = compactType(raw.type)
            local paramType = spelling == "boolean" and "bool"
               or (spelling == "number" or spelling == "float") and "f64" or nil
            if not paramName or not paramType or raw.modeTok then
               reject(raw, "native helper parameters are unowned number, float, or boolean values")
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
            or #(returned.exprs or {}) ~= 1
         then
            reject(helperBody.body or helperBody, "a native helper body is one return expression")
         end
         local helper = {
            name = name, cName = privateSymbol(fn.name.text) .. "_helper_" .. privateSymbol(name):sub(4),
            params = helperParams, resultType = resultType, source = site(declaration),
         }
         helperByName[name] = helper
         helper.value = lowerExpression(returned.exprs[1], environment, nil)
         if helper.value.type ~= resultType then reject(returned, "native helper result type does not match") end
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
            return {op = op, name = name, type = value.type, cName = value.cName, source = site(node)}
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
            end
            reject(node, "unary operator " .. tostring(node.op.text) .. " is not admitted for this type")
         elseif node.kind == "methodCall" then
            local spanName = receiverName(node.obj)
            local param = spanName and byName[spanName] or nil
            local args = node.args and node.args.exprs or {}
            if not param or param.kind ~= "read_span" or not node.name or node.name.text ~= "get" then
               reject(node, "the only admitted value method is input:get(index)")
            end
            if not activeIndex or #args ~= 1 or nameOf(args[1]) ~= activeIndex then
               reject(node, "span loads must use the active loop index exactly")
            end
            return {
               op = "widen_f32_f64", type = "f64", source = site(node),
               value = {op = "load", span = spanName, index = activeIndex, type = "f32", source = site(node)},
            }
         elseif node.kind == "binop" and node.op then
            local left = lowerExpression(node.lhs, environment, activeIndex)
            local right = lowerExpression(node.rhs, environment, activeIndex)
            local written = node.op.text
            if arithmetic[written] then
               if left.type ~= "f64" or right.type ~= "f64" then
                  reject(node, "arithmetic operands must both be numeric")
               end
               return {op = arithmetic[written], left = left, right = right, type = "f64", source = site(node)}
            elseif comparisons[written] then
               if left.type ~= right.type then reject(node, "comparison operands must have the same type") end
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
               if (intrinsic == "min" or intrinsic == "max") and #args < 2 then
                  reject(node, qualified .. " needs at least two arguments")
               elseif intrinsic ~= "min" and intrinsic ~= "max" and #args ~= 1 then
                  reject(node, qualified .. " needs exactly one argument")
               end
               for _, arg in ipairs(args) do
                  if arg.type ~= "f64" then reject(node, qualified .. " arguments must be numeric") end
               end
               return {op = "math", intrinsic = intrinsic, args = args, type = "f64", source = site(node)}
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
                  args = args, type = helper.resultType, source = site(node),
               }
            end
            reject(node, "call target " .. tostring(qualified) .. " is not an admitted intrinsic or helper")
         end
         reject(node, "expression kind " .. tostring(node.kind) .. " is not admitted")
      end

      local localSerial = 0
      local function lowerBlock(rawStats, environment)
         local statements = {}
         for _, stat in ipairs(rawStats or {}) do
            if stat.kind == "localStmt" then
               if #(stat.names or {}) ~= 1 or #(stat.exprs or {}) ~= 1 then
                  reject(stat, "a native local declares one initialized value")
               end
               local name = stat.names[1].text
               if environment[name] then reject(stat, "native locals may not shadow " .. name) end
               local value = lowerExpression(stat.exprs[1], environment, index)
               local spelling = compactType(stat.types and stat.types[1])
               if spelling ~= "" then
                  local expected = spelling == "boolean" and "bool"
                     or (spelling == "number" or spelling == "float") and "f64" or nil
                  if not expected or expected ~= value.type then reject(stat, "native local annotation does not match") end
               end
               localSerial = localSerial + 1
               local binding = {
                  kind = "local", name = name, type = value.type,
                  cName = cIdentifier("v" .. tostring(localSerial), name), source = site(stat),
               }
               statements[#statements + 1] = {
                  op = "let", name = name, cName = binding.cName,
                  type = value.type, value = value, source = site(stat),
               }
               environment[name] = binding
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
               if value.type ~= "f64" then reject(call, "a float span store needs a numeric value") end
               statements[#statements + 1] = {
                  op = "store", span = spanName, index = index,
                  value = {op = "narrow_f64_f32", type = "f32", value = value, source = site(call)},
                  source = site(call),
               }
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
         version = 2,
         name = fn.name.text,
         symbol = privateSymbol(fn.name.text),
         params = params,
         regions = regions,
         aliasFacts = aliasFacts,
         guards = guards,
         helpers = helpers,
         loop = {
            index = index, first = 1, count = primary.name,
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

local function verifyIR(ir)
   assert(ir.version == 2, "unknown native C IR version")
   assert(ir.symbol == privateSymbol(ir.name), "private symbol does not match function identity")
   local byName, byRegion, writes, primary = {}, {}, {}, nil
   for _, param in ipairs(ir.params) do
      assert(not byName[param.name], "duplicate IR parameter")
      assert(param.kind == "write_span" or param.kind == "read_span" or param.kind == "uniform",
         "unknown IR parameter kind")
      if param.kind == "uniform" then
         assert(param.type == "f64" and not param.region, "invalid IR uniform")
      else
         assert(param.type == "f32" and param.region and not byRegion[param.region], "invalid IR span")
         assert(param.access == (param.kind == "write_span" and "write" or "read"),
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
      elseif node.op == "load" then
         assert(node.type == "f32" and byName[node.span]
            and byName[node.span].kind == "read_span", "invalid load root")
         assert(node.index == ir.loop.index, "unbounded load index")
      elseif node.op == "uniform" then
         assert(node.type == "f64" and byName[node.name]
            and byName[node.name].kind == "uniform", "invalid uniform")
      elseif node.op == "local" or node.op == "helper_param" then
         assert(values[node.name] == node.type, "invalid local value")
      elseif node.op == "constant" then
         assert(node.type == "f64" and tonumber(node.value), "invalid constant")
      elseif node.op == "bool" then
         assert(node.type == "bool" and type(node.value) == "boolean", "invalid boolean")
      elseif node.op == "neg" or node.op == "not" then
         verifyExpr(node.value, values)
         assert(node.type == (node.op == "neg" and "f64" or "bool"), "invalid unary result")
      elseif node.op == "add" or node.op == "sub" or node.op == "mul" or node.op == "div" then
         assert(node.type == "f64" and node.left.type == "f64" and node.right.type == "f64",
            "invalid arithmetic")
         verifyExpr(node.left, values)
         verifyExpr(node.right, values)
      elseif node.op == "lt" or node.op == "le" or node.op == "gt" or node.op == "ge"
         or node.op == "eq" or node.op == "ne"
      then
         assert(node.type == "bool" and node.left.type == node.right.type, "invalid comparison")
         verifyExpr(node.left, values)
         verifyExpr(node.right, values)
      elseif node.op == "and" or node.op == "or" then
         assert(node.type == "bool" and node.left.type == "bool" and node.right.type == "bool",
            "invalid boolean operation")
         verifyExpr(node.left, values)
         verifyExpr(node.right, values)
      elseif node.op == "math" then
         assert(node.type == "f64", "invalid math result")
         assert(node.intrinsic == "sqrt" or node.intrinsic == "abs" or node.intrinsic == "floor"
            or node.intrinsic == "ceil" or node.intrinsic == "min" or node.intrinsic == "max",
            "unknown math intrinsic")
         for _, arg in ipairs(node.args) do
            assert(arg.type == "f64", "invalid math argument")
            verifyExpr(arg, values)
         end
      elseif node.op == "helper_call" then
         local helper = helpers[node.helper]
         assert(helper and node.type == helper.resultType and #node.args == #helper.params,
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
      assert(helper.value.type == helper.resultType, "helper result mismatch")
      verifyExpr(helper.value, values)
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
         elseif statement.op == "store" then
            assert(writes[statement.span] and statement.index == ir.loop.index, "invalid store root")
            verifyExpr(statement.value, values)
            stored[statement.span] = true
         elseif statement.op == "if" then
            for _, clause in ipairs(statement.clauses) do
               assert(clause.condition.type == "bool", "non-boolean branch")
               verifyExpr(clause.condition, values)
               verifyBlock(clause.body, values)
            end
            if statement.elseBody then verifyBlock(statement.elseBody, values) end
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
   for output in pairs(writes) do assert(stored[output], "IR output is never stored") end
   return ir
end

compiler.verifyIR = verifyIR

local function irLines(ir)
   local lines = {"native-c-ir 2", "function " .. ir.name, "symbol " .. ir.symbol, "params"}
   for _, param in ipairs(ir.params) do
      if param.region then
         lines[#lines + 1] = ("  %s %s:%s region(%s) %s @%d:%d"):format(
            param.kind, param.name, param.type, param.region, param.access,
            param.source.line, param.source.column
         )
      else
         lines[#lines + 1] = ("  uniform %s:f64 source(%s) @%d:%d"):format(
            param.name, param.sourceType, param.source.line, param.source.column
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
         helper.name, helper.resultType, helper.source.line, helper.source.column
      )
   end
   lines[#lines + 1] = "guards"
   for _, guard in ipairs(ir.guards) do
      lines[#lines + 1] = ("  equal_count %s %s @%d:%d"):format(
         guard.left, guard.right, guard.source.line, guard.source.column
      )
   end
   lines[#lines + 1] = ("loop %s = 1 .. count(%s) @%d:%d"):format(
      ir.loop.index, ir.loop.count, ir.loop.source.line, ir.loop.source.column
   )
   local function expression(node)
      if node.op == "load" then return "load:f32 " .. node.span .. "[" .. node.index .. "]" end
      if node.op == "uniform" or node.op == "local" or node.op == "helper_param" then
         return node.op .. ":" .. node.type .. " " .. node.name
      end
      if node.op == "constant" then return "constant:f64 " .. node.value end
      if node.op == "bool" then return "bool " .. tostring(node.value) end
      if node.op == "widen_f32_f64" or node.op == "narrow_f64_f32"
         or node.op == "neg" or node.op == "not"
      then
         return node.op .. "(" .. expression(node.value) .. ")"
      end
      if node.op == "math" then
         local args = {}
         for _, arg in ipairs(node.args) do args[#args + 1] = expression(arg) end
         return "math." .. node.intrinsic .. "(" .. table.concat(args, ", ") .. ")"
      end
      if node.op == "helper_call" then
         local args = {}
         for _, arg in ipairs(node.args) do args[#args + 1] = expression(arg) end
         return "call " .. node.helper .. "(" .. table.concat(args, ", ") .. ")"
      end
      return node.op .. "(" .. expression(node.left) .. ", " .. expression(node.right) .. ")"
   end
   local function block(statements, depth)
      local prefix = string.rep("  ", depth)
      for _, statement in ipairs(statements) do
         if statement.op == "let" then
            lines[#lines + 1] = prefix .. "let " .. statement.name .. ":" .. statement.type
               .. " = " .. expression(statement.value)
         elseif statement.op == "store" then
            lines[#lines + 1] = prefix .. "store " .. statement.span .. "[" .. statement.index
               .. "] = " .. expression(statement.value)
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
         elseif statement.op == "block" then
            lines[#lines + 1] = prefix .. "block"
            block(statement.body, depth + 1)
         else
            lines[#lines + 1] = prefix .. statement.op
         end
      end
   end
   block(ir.loop.statements, 1)
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
   if node.op == "narrow_f64_f32" then return "(float)(" .. renderExpr(node.value) .. ")" end
   if node.op == "widen_f32_f64" then return "((double)" .. renderExpr(node.value) .. ")" end
   if node.op == "load" then return cIdentifier("p", node.span) .. "[i]" end
   if node.op == "uniform" then return cIdentifier("p", node.name) end
   if node.op == "local" or node.op == "helper_param" then return node.cName end
   if node.op == "constant" then return doubleLiteral(node.value) end
   if node.op == "bool" then return node.value and "true" or "false" end
   if node.op == "neg" then return "(-(" .. renderExpr(node.value) .. "))" end
   if node.op == "not" then return "(!(" .. renderExpr(node.value) .. "))" end
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
      local cName = ({sqrt = "sqrt", abs = "fabs", floor = "floor", ceil = "ceil"})[node.intrinsic]
      return cName .. "(" .. args[1] .. ")"
   end
   if node.op == "helper_call" then
      local args = {}
      for _, arg in ipairs(node.args) do args[#args + 1] = renderExpr(arg) end
      return node.cName .. "(" .. table.concat(args, ", ") .. ")"
   end
   error("cannot render expression " .. tostring(node.op))
end

local function cType(typeName)
   return typeName == "bool" and "bool" or "double"
end

local function cParams(ir)
   local params = {}
   for _, param in ipairs(ir.params) do
      local name = cIdentifier("p", param.name)
      if param.kind == "write_span" then params[#params + 1] = "float *restrict " .. name
      elseif param.kind == "read_span" then params[#params + 1] = "const float *" .. name
      else params[#params + 1] = "double " .. name
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
   emit("")
   emit("static inline double nupp_min2(double left, double right) {")
   emit("    return left < right ? left : right;")
   emit("}")
   emit("static inline double nupp_max2(double left, double right) {")
   emit("    return left > right ? left : right;")
   emit("}")
   emit("")

   for _, helper in ipairs(ir.helpers or {}) do
      local params = {}
      for _, param in ipairs(helper.params) do
         params[#params + 1] = cType(param.type) .. " " .. param.cName
      end
      emit("static inline " .. cType(helper.resultType) .. " " .. helper.cName
         .. "(" .. table.concat(params, ", ") .. ");")
   end
   if #(ir.helpers or {}) > 0 then emit("") end
   for _, helper in ipairs(ir.helpers or {}) do
      local params = {}
      for _, param in ipairs(helper.params) do
         params[#params + 1] = cType(param.type) .. " " .. param.cName
      end
      emit("static inline " .. cType(helper.resultType) .. " " .. helper.cName
         .. "(" .. table.concat(params, ", ") .. ") {")
      emit("    return " .. renderExpr(helper.value) .. ";")
      emit("}")
      emit("")
   end

   local function renderBlock(statements, depth)
      local prefix = string.rep("    ", depth)
      for _, statement in ipairs(statements) do
         if statement.op == "let" then
            emit(prefix .. cType(statement.type) .. " " .. statement.cName .. " = "
               .. renderExpr(statement.value) .. ";")
         elseif statement.op == "store" then
            emit(prefix .. cIdentifier("p", statement.span) .. "[i] = " .. renderExpr(statement.value) .. ";")
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
      emit("    size_t i = 0;")
      if forced then
         emit("#if defined(__clang__)")
         emit("#pragma clang loop vectorize(disable) interleave(disable)")
         emit("#endif")
      end
      emit("    for (; i < count; ++i) {")
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
   local lines = {"-- Generated from verified test-only native C IR.", "", "cdef function " .. ir.symbol .. "("}
   for _, param in ipairs(ir.params) do
      if param.kind == "write_span" then
         lines[#lines + 1] = "    borrows " .. param.name .. ": float* countedBy(count),"
      elseif param.kind == "read_span" then
         lines[#lines + 1] = "    borrows " .. param.name .. ": const float* countedBy(count),"
      else
         lines[#lines + 1] = "    " .. param.name .. ": number,"
      end
   end
   lines[#lines + 1] = "    count: uint64"
   lines[#lines + 1] = ") from\"bench/kernel-subset-spike/build/libkernel_subset_spike\""
   lines[#lines + 1] = ""
   lines[#lines + 1] = "return {" .. ir.name .. " = " .. ir.symbol .. ",}"
   return table.concat(lines, "\n") .. "\n"
end

function compiler.compile(source, filename)
   local ir, diagnostics = parseKernel(source, filename)
   if not ir then return nil, diagnostics end
   verifyIR(ir)
   return {
      ir = ir,
      irText = irLines(ir),
      c = renderC(ir),
      binding = renderBinding(ir),
   }, diagnostics
end

return compiler
