-- A test-only compiler for one deliberately small `@kernel` subset.
--
-- It consumes Nupp's real CST, validates an admitted whole-function shape,
-- verifies a sealed typed IR, and emits private C plus a checked Nupp binding.

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

local function privateSymbol(name)
   local snake = name:gsub("(%u)(%u%l)", "%1_%2"):gsub("(%l)(%u)", "%1_%2")
   snake = snake:gsub("[^%w_]", "_"):lower()
   return "ks_" .. snake
end

local function diagnostic(filename, node, message)
   local at = site(node)
   return {
      file = filename,
      line = at.line,
      column = at.column,
      message = message,
   }
end

local function renderDiagnostic(value)
   return ("%s:%d:%d: kernel subset: %s"):format(
      value.file, value.line, value.column, value.message
   )
end

compiler.renderDiagnostic = renderDiagnostic

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
      local applications = {}
      for _, block in ipairs(parsed.root.blocks or {}) do
         for _, stat in ipairs(block.stats or {}) do
            if stat.kind == "pragmaStmt" and stat.name and stat.name.text == "kernel" then
               applications[#applications + 1] = stat
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
      if application.open then
         reject(application, "@kernel takes no arguments")
      end

      local body = fn.body
      if not body or body.generics or body.varargParam or body.captureTakes or body.captureBorrows then
         reject(body or fn, "generic, variadic, and capturing kernels are not admitted")
      end
      if #(body.rets or {}) ~= 1 or compactType(body.rets[1]) ~= "nil" then
         reject(body, "the map-kernel prototype must return nil")
      end

      local params, byName = {}, {}
      local output
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
            if output then reject(raw, "the map-kernel prototype admits one writable span") end
            param = {
               kind = "write_span",
               name = name,
               type = "f32",
               region = "r" .. tostring(#params),
               access = "write",
               ownership = "exclusive",
               source = site(raw),
            }
            output = param
         elseif spelling == "span.Span<float>" then
            if mode ~= "borrows" then
               reject(raw, "a readable float span must be declared borrows")
            end
            param = {
               kind = "read_span",
               name = name,
               type = "f32",
               region = "r" .. tostring(#params),
               access = "read",
               ownership = "shared",
               source = site(raw),
            }
         elseif spelling == "float" then
            if mode then reject(raw, "a uniform float parameter has no ownership mode") end
            -- Nupp's annotations erase at runtime. A `float` parameter is a Lua
            -- number in an ordinary function, so the native ABI and expression
            -- IR must retain its binary64 value.
            param = {kind = "uniform", name = name, type = "f64", sourceType = "float", source = site(raw)}
         else
            reject(raw.type or raw, "parameter type " .. spelling .. " is not admitted")
         end
         params[#params + 1] = param
         byName[name] = param
      end
      if not output then reject(body, "the map-kernel prototype needs one writable float span") end

      local reads = {}
      for _, param in ipairs(params) do
         if param.kind == "read_span" then reads[#reads + 1] = param end
      end
      if #reads == 0 then reject(body, "the map-kernel prototype needs a readable float span") end

      local regions, aliasFacts = {}, {}
      for _, param in ipairs(params) do
         if param.region then
            regions[#regions + 1] = {
               id = param.region,
               param = param.name,
               access = param.access,
               proof = param.ownership .. "_borrow",
            }
         end
      end
      for _, input in ipairs(reads) do
         aliasFacts[#aliasFacts + 1] = {
            relation = "disjoint",
            left = output.region,
            right = input.region,
            proof = "exclusive_borrow",
         }
      end
      for left = 1, #reads do
         for right = left + 1, #reads do
            aliasFacts[#aliasFacts + 1] = {
               relation = "may_alias",
               left = reads[left].region,
               right = reads[right].region,
               proof = "shared_borrows",
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
         if left == output.name then other = right
         elseif right == output.name then other = left
         end
         if not other or not byName[other] or byName[other].kind ~= "read_span" then
            reject(expr, "each guard comparison must compare output.count with an input count")
         end
         if guarded[other] then reject(expr, "duplicate length guard for " .. other) end
         guarded[other] = site(expr)
      end
      collectGuards(clause.cond)
      local guards = {}
      for _, input in ipairs(reads) do
         if not guarded[input.name] then
            reject(guard, "the length guard does not cover input " .. input.name)
         end
         guards[#guards + 1] = {
            op = "equal_count",
            left = output.name,
            right = input.name,
            source = guarded[input.name],
         }
      end

      local loop = stats[2]
      if loop.kind ~= "fornumStmt" then
         reject(loop, "the second statement must be a numeric for loop")
      end
      if not loop.start or loop.start.kind ~= "number" or loop.start.token.text ~= "1" then
         reject(loop.start or loop, "kernel span loops must begin at one")
      end
      if loop.step then reject(loop.step, "the first subset does not admit an explicit loop step") end
      if dotCount(loop.stop) ~= output.name then
         reject(loop.stop or loop, "the loop bound must be output.count")
      end
      local index = loop.var and loop.var.text
      if not index then reject(loop, "the kernel loop needs an index variable") end

      local loopStats = loop.body and loop.body.stats or {}
      local store = loopStats[1] and loopStats[1].kind == "callStmt" and loopStats[1].expr or nil
      if #loopStats ~= 1 or not store or store.kind ~= "methodCall"
         or receiverName(store.obj) ~= output.name or not store.name or store.name.text ~= "set"
      then
         reject(loop.body or loop, "the loop body must be one output:set(index, value) call")
      end
      local storeArgs = store.args and store.args.exprs or {}
      if #storeArgs ~= 2 or nameOf(storeArgs[1]) ~= index then
         reject(store, "output:set must store at the loop index")
      end

      local function expression(node)
         if not node then reject(store, "the store needs a value") end
         if node.kind == "name" then
            local name = nameOf(node)
            local param = byName[name]
            if not param or param.kind ~= "uniform" then
               reject(node, "only uniform scalar parameters may appear as bare values")
            end
            return {op = "uniform", name = name, type = "f64", source = site(node)}
         elseif node.kind == "number" then
            local value = node.token and node.token.text or ""
            if not tonumber(value) then reject(node, "the kernel needs a finite decimal numeric literal") end
            return {op = "constant", value = value, type = "f64", source = site(node)}
         elseif node.kind == "methodCall" then
            local spanName = receiverName(node.obj)
            local param = spanName and byName[spanName] or nil
            local args = node.args and node.args.exprs or {}
            if not param or param.kind ~= "read_span" or not node.name or node.name.text ~= "get" then
               reject(node, "the only admitted value call is input:get(index)")
            end
            if #args ~= 1 or nameOf(args[1]) ~= index then
               reject(node, "span loads must use the loop index exactly")
            end
            return {
               op = "widen_f32_f64",
               type = "f64",
               value = {
                  op = "load",
                  span = spanName,
                  index = index,
                  type = "f32",
                  source = site(node),
               },
               source = site(node),
            }
         elseif node.kind == "binop" and node.op then
            local op = ({["+"] = "add", ["-"] = "sub", ["*"] = "mul", ["/"] = "div"})[node.op.text]
            if not op then reject(node, "operator " .. node.op.text .. " is not admitted in float expressions") end
            return {
               op = op,
               left = expression(node.lhs),
               right = expression(node.rhs),
               type = "f64",
               source = site(node),
            }
         end
         reject(node, "expression kind " .. tostring(node.kind) .. " is not admitted")
      end

      local value = expression(storeArgs[2])
      return {
         version = 1,
         name = fn.name.text,
         symbol = privateSymbol(fn.name.text),
         params = params,
         regions = regions,
         aliasFacts = aliasFacts,
         guards = guards,
         loop = {
            index = index,
            first = 1,
            count = output.name,
            store = {
               span = output.name,
               value = {op = "narrow_f64_f32", type = "f32", value = value, source = site(store)},
               source = site(store),
            },
            source = site(loop),
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
   assert(ir.version == 1, "unknown kernel IR version")
   assert(ir.symbol == privateSymbol(ir.name), "private symbol does not match function identity")
   local byName, byRegion, output = {}, {}, nil
   for _, param in ipairs(ir.params) do
      assert(not byName[param.name], "duplicate IR parameter")
      assert(param.kind == "write_span" or param.kind == "read_span" or param.kind == "uniform",
         "unknown IR parameter kind")
      if param.kind == "uniform" then
         assert(param.type == "f64" and not param.region, "invalid IR uniform")
      else
         assert(param.type == "f32" and param.region, "invalid IR span")
         assert(not byRegion[param.region], "duplicate IR region")
         assert(param.access == (param.kind == "write_span" and "write" or "read"),
            "invalid IR region access")
         byRegion[param.region] = param
      end
      byName[param.name] = param
      if param.kind == "write_span" then
         assert(not output, "several IR outputs")
         output = param
      end
   end
   assert(output and ir.loop.count == output.name, "loop is not bounded by its output")

   local declaredRegions = {}
   for _, region in ipairs(ir.regions) do
      assert(not declaredRegions[region.id], "duplicate region declaration")
      local param = byRegion[region.id]
      assert(param and region.param == param.name and region.access == param.access,
         "region declaration does not match its parameter")
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
      if fact.relation == "disjoint" then
         assert(fact.proof == "exclusive_borrow", "disjointness lacks an exclusive-borrow proof")
      else
         assert(fact.relation == "may_alias" and fact.proof == "shared_borrows",
            "invalid alias fact")
      end
      facts[key] = fact.relation
   end
   for _, left in ipairs(ir.params) do
      if left.kind ~= "uniform" then
         for _, right in ipairs(ir.params) do
            if right.kind ~= "uniform" and left.region < right.region then
               local hasWrite = left.kind == "write_span" or right.kind == "write_span"
               local expected = hasWrite and "disjoint" or "may_alias"
               assert(facts[left.region .. ":" .. right.region] == expected,
                  "missing or invalid alias relationship")
            end
         end
      end
   end
   local guarded = {}
   for _, guard in ipairs(ir.guards) do
      assert(guard.op == "equal_count" and guard.left == output.name, "invalid IR guard")
      assert(byName[guard.right] and byName[guard.right].kind == "read_span", "guarded non-input")
      guarded[guard.right] = true
   end
   for _, param in ipairs(ir.params) do
      if param.kind == "read_span" then assert(guarded[param.name], "unguarded IR input") end
   end

   local function verifyExpr(node)
      if node.op == "narrow_f64_f32" then
         assert(node.type == "f32" and node.value.type == "f64", "invalid narrowing conversion")
         verifyExpr(node.value)
         return
      elseif node.op == "widen_f32_f64" then
         assert(node.type == "f64" and node.value.type == "f32", "invalid widening conversion")
         verifyExpr(node.value)
         return
      end
      if node.op == "uniform" then
         assert(node.type == "f64" and byName[node.name]
            and byName[node.name].kind == "uniform", "invalid uniform")
      elseif node.op == "load" then
         assert(node.type == "f32" and byName[node.span]
            and byName[node.span].kind == "read_span", "invalid load root")
         assert(node.index == ir.loop.index, "unbounded load index")
      elseif node.op == "constant" then
         assert(node.type == "f64" and tonumber(node.value), "invalid constant")
      else
         assert(node.type == "f64", "non-f64 arithmetic")
         assert(node.op == "add" or node.op == "sub" or node.op == "mul" or node.op == "div",
            "unknown expression opcode")
         verifyExpr(node.left)
         verifyExpr(node.right)
      end
   end
   assert(ir.loop.store.span == output.name, "store does not target output")
   verifyExpr(ir.loop.store.value)
   return ir
end

compiler.verifyIR = verifyIR

local function irLines(ir)
   local lines = {"kernel-ir 1", "function " .. ir.name, "symbol " .. ir.symbol, "params"}
   for _, param in ipairs(ir.params) do
      if param.region then
         lines[#lines + 1] = ("  %s %s:%s region(%s) %s @%d:%d"):format(
            param.kind, param.name, param.type, param.region, param.access,
            param.source.line, param.source.column
         )
      else
         lines[#lines + 1] = ("  %s %s:%s source(%s) @%d:%d"):format(
            param.kind, param.name, param.type, param.sourceType,
            param.source.line, param.source.column
         )
      end
   end
   lines[#lines + 1] = "regions"
   for _, region in ipairs(ir.regions) do
      lines[#lines + 1] = ("  %s %s %s proof(%s)"):format(
         region.id, region.param, region.access, region.proof
      )
   end
   lines[#lines + 1] = "aliasing"
   for _, fact in ipairs(ir.aliasFacts) do
      lines[#lines + 1] = ("  %s %s %s proof(%s)"):format(
         fact.relation, fact.left, fact.right, fact.proof
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
   local function expression(node, depth)
      local prefix = string.rep("  ", depth)
      if node.op == "load" then
         lines[#lines + 1] = prefix .. "load:f32 " .. node.span .. "[" .. node.index .. "]"
      elseif node.op == "uniform" then
         lines[#lines + 1] = prefix .. "uniform:f64 " .. node.name
      elseif node.op == "constant" then
         lines[#lines + 1] = prefix .. "constant:f64 " .. node.value
      elseif node.op == "widen_f32_f64" or node.op == "narrow_f64_f32" then
         lines[#lines + 1] = prefix .. node.op
         expression(node.value, depth + 1)
      else
         lines[#lines + 1] = prefix .. node.op .. ":f64"
         expression(node.left, depth + 1)
         expression(node.right, depth + 1)
      end
   end
   lines[#lines + 1] = "  store " .. ir.loop.store.span .. "[" .. ir.loop.index .. "]"
   expression(ir.loop.store.value, 2)
   return table.concat(lines, "\n") .. "\n"
end

local function doubleLiteral(value)
   if value:find("[%.eE]") then return value end
   return value .. ".0"
end

local backends = {
   scalar = {
      lanes = 1,
      load = function(name) return "((double)" .. name .. "[i])" end,
      uniform = function(name) return name end,
      constant = doubleLiteral,
      ops = {add = "+", sub = "-", mul = "*", div = "/"},
      store = function(name, value) return name .. "[i] = (float)(" .. value .. ");" end,
   },
   neon = {
      lanes = 2,
      load = function(name) return "vcvt_f64_f32(vld1_f32(" .. name .. " + i))" end,
      uniform = function(name) return "vdupq_n_f64(" .. name .. ")" end,
      constant = function(value) return "vdupq_n_f64(" .. doubleLiteral(value) .. ")" end,
      ops = {add = "vaddq_f64", sub = "vsubq_f64", mul = "vmulq_f64", div = "vdivq_f64"},
      store = function(name, value)
         return "vst1_f32(" .. name .. " + i, vcvt_f32_f64(" .. value .. "));"
      end,
   },
   sse2 = {
      lanes = 2,
      load = function(name)
         return "_mm_cvtps_pd(_mm_castsi128_ps(_mm_loadl_epi64((const __m128i *)("
            .. name .. " + i))))"
      end,
      uniform = function(name) return "_mm_set1_pd(" .. name .. ")" end,
      constant = function(value) return "_mm_set1_pd(" .. doubleLiteral(value) .. ")" end,
      ops = {add = "_mm_add_pd", sub = "_mm_sub_pd", mul = "_mm_mul_pd", div = "_mm_div_pd"},
      store = function(name, value)
         return "_mm_storel_epi64((__m128i *)(" .. name
            .. " + i), _mm_castps_si128(_mm_cvtpd_ps(" .. value .. ")));"
      end,
   },
   avx2 = {
      lanes = 4,
      load = function(name) return "_mm256_cvtps_pd(_mm_loadu_ps(" .. name .. " + i))" end,
      uniform = function(name) return "_mm256_set1_pd(" .. name .. ")" end,
      constant = function(value) return "_mm256_set1_pd(" .. doubleLiteral(value) .. ")" end,
      ops = {add = "_mm256_add_pd", sub = "_mm256_sub_pd", mul = "_mm256_mul_pd", div = "_mm256_div_pd"},
      store = function(name, value)
         return "_mm_storeu_ps(" .. name .. " + i, _mm256_cvtpd_ps(" .. value .. "));"
      end,
   },
}

local function renderExpr(node, backendName)
   local backend = backends[backendName]
   if node.op == "narrow_f64_f32" then return renderExpr(node.value, backendName)
   elseif node.op == "widen_f32_f64" then return backend.load(node.value.span)
   elseif node.op == "load" then error("unwidened f32 load reached backend")
   elseif node.op == "uniform" then return backend.uniform(node.name)
   elseif node.op == "constant" then return backend.constant(node.value)
   end
   local left, right = renderExpr(node.left, backendName), renderExpr(node.right, backendName)
   if backendName == "scalar" then
      return "(" .. left .. " " .. backend.ops[node.op] .. " " .. right .. ")"
   end
   return backend.ops[node.op] .. "(" .. left .. ", " .. right .. ")"
end

local function cParams(ir)
   local params = {}
   for _, param in ipairs(ir.params) do
      if param.kind == "write_span" then params[#params + 1] = "float *restrict " .. param.name
      elseif param.kind == "read_span" then params[#params + 1] = "const float *" .. param.name
      else params[#params + 1] = "double " .. param.name
      end
   end
   params[#params + 1] = "size_t count"
   return table.concat(params, ", ")
end

local function cArguments(ir)
   local args = {}
   for _, param in ipairs(ir.params) do args[#args + 1] = param.name end
   args[#args + 1] = "count"
   return table.concat(args, ", ")
end

local function renderC(ir)
   local lines = {}
   local function emit(line) lines[#lines + 1] = line or "" end
   emit("/* Generated from verified test-only kernel IR. */")
   emit("#include <stddef.h>")
   emit("#include <stdint.h>")
   emit("#include <stdatomic.h>")
   emit("")
   emit("#if defined(__aarch64__) || defined(__arm64__)")
   emit("#include <arm_neon.h>")
   emit("#elif defined(__x86_64__) || defined(_M_X64)")
   emit("#include <immintrin.h>")
   emit("#endif")
   emit("")

   local params, args = cParams(ir), cArguments(ir)
   local output = ir.loop.store.span
   local function implementation(suffix, backendName, attribute, exported, forceScalar)
      local backend = backends[backendName]
      if attribute then emit(attribute) end
      emit((exported and "" or "static ") .. "void " .. ir.symbol .. "_" .. suffix .. "(" .. params .. ") {")
      emit("    size_t i = 0;")
      if backendName == "scalar" then
         if forceScalar then
            emit("#if defined(__clang__)")
            emit("#pragma clang loop vectorize(disable) interleave(disable)")
            emit("#endif")
         end
         emit("    for (; i < count; ++i) {")
      else
         emit("    for (; i + " .. backend.lanes .. " <= count; i += " .. backend.lanes .. ") {")
      end
      emit("        " .. backend.store(output, renderExpr(ir.loop.store.value, backendName)))
      emit("    }")
      if backendName ~= "scalar" then
         emit("#if defined(__clang__)")
         emit("#pragma clang loop vectorize(disable) interleave(disable)")
         emit("#endif")
         emit("    for (; i < count; ++i) {")
         emit("        " .. backends.scalar.store(output, renderExpr(ir.loop.store.value, "scalar")))
         emit("    }")
      end
      emit("}")
      emit("")
   end

   implementation("forced_scalar", "scalar", "__attribute__((noinline))", true, true)
   implementation("auto", "scalar", "__attribute__((noinline))", true, false)
   emit("#if defined(__aarch64__) || defined(__arm64__)")
   implementation("neon", "neon")
   emit("#elif defined(__x86_64__) || defined(_M_X64)")
   implementation("sse2", "sse2", "__attribute__((target(\"sse2\")))")
   implementation("avx2", "avx2", "__attribute__((target(\"avx2\")))")
   emit("#endif")

   emit("enum { KS_UNKNOWN = 0, KS_SCALAR = 1, KS_NEON = 2, KS_SSE2 = 3, KS_AVX2 = 4 };")
   emit("static atomic_int ks_selected = ATOMIC_VAR_INIT(KS_UNKNOWN);")
   emit("")
   emit("static int ks_select_backend(void) {")
   emit("    int selected = atomic_load_explicit(&ks_selected, memory_order_acquire);")
   emit("    if (selected != KS_UNKNOWN) return selected;")
   emit("#if defined(__aarch64__) || defined(__arm64__)")
   emit("    int detected = KS_NEON;")
   emit("#elif defined(__x86_64__) || defined(_M_X64)")
   emit("    __builtin_cpu_init();")
   emit("    int detected = __builtin_cpu_supports(\"avx2\") ? KS_AVX2 : KS_SSE2;")
   emit("#else")
   emit("    int detected = KS_SCALAR;")
   emit("#endif")
   emit("    int expected = KS_UNKNOWN;")
   emit("    atomic_compare_exchange_strong_explicit(&ks_selected, &expected, detected,")
   emit("        memory_order_release, memory_order_relaxed);")
   emit("    return atomic_load_explicit(&ks_selected, memory_order_acquire);")
   emit("}")
   emit("")
   emit("const char *ks_backend(void) {")
   emit("    switch (ks_select_backend()) {")
   emit("        case KS_NEON: return \"neon\";")
   emit("        case KS_SSE2: return \"sse2\";")
   emit("        case KS_AVX2: return \"avx2\";")
   emit("        default: return \"scalar\";")
   emit("    }")
   emit("}")
   emit("")
   emit("uint32_t ks_lanes_f64(void) {")
   emit("    switch (ks_select_backend()) {")
   emit("        case KS_NEON: return 2;")
   emit("        case KS_SSE2: return 2;")
   emit("        case KS_AVX2: return 4;")
   emit("        default: return 1;")
   emit("    }")
   emit("}")
   emit("")
   emit("void " .. ir.symbol .. "(" .. params .. ") {")
   emit("    switch (ks_select_backend()) {")
   emit("#if defined(__aarch64__) || defined(__arm64__)")
   emit("        case KS_NEON: " .. ir.symbol .. "_neon(" .. args .. "); return;")
   emit("#elif defined(__x86_64__) || defined(_M_X64)")
   emit("        case KS_AVX2: " .. ir.symbol .. "_avx2(" .. args .. "); return;")
   emit("        case KS_SSE2: " .. ir.symbol .. "_sse2(" .. args .. "); return;")
   emit("#endif")
   emit("        default: " .. ir.symbol .. "_forced_scalar(" .. args .. "); return;")
   emit("    }")
   emit("}")
   return table.concat(lines, "\n") .. "\n"
end

local function renderBinding(ir)
   local lines = {"-- Generated from verified test-only kernel IR.", "", "cdef function " .. ir.symbol .. "("}
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
