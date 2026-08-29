-- Verified scalar AOT optimisation, independently of source lowering.
--
-- These operate on the small public IR records as plain Lua tables. That keeps
-- each case about the rewrite itself; lowering and emission are covered by the
-- AOT CLI and build suites.

local effects = require("nupp.compiler.aot.effects")
local optimize = require("nupp.compiler.aot.optimize")

local M = {}

local function constant(value)
   return {op = "constant", value = tostring(value), type = "f64"}
end

local function program(body)
   return {body = body, helpers = {}, maxStack = 19}
end

function M.effectsFailClosed()
   local pure = effects.expression("add")
   assert(not pure.observable and not pure.mayRaise)

   local allocation = effects.expression("lua_new_table")
   assert(allocation.observable and allocation.mayRaise and allocation.allocatesLua)

   local ok, message = pcall(effects.expression, "future_opcode")
   assert(not ok)
   assert(tostring(message):match("unclassified AOT expression opcode future_opcode"))

   ok, message = pcall(effects.statement, "future_statement")
   assert(not ok)
   assert(tostring(message):match("unclassified AOT statement opcode future_statement"))
end

function M.foldsConstantsAndRemovesDeadPureDeclarations()
   local ir = program({
      {
         op = "let",
         name = "unused",
         cName = "unused_1",
         type = "f64",
         value = {op = "add", left = constant(2), right = constant(3), type = "f64"},
      },
      {
         op = "return",
         values = {{op = "sub", left = constant(9), right = constant(4), type = "f64"}},
      },
      {op = "let", name = "unreachable", cName = "unreachable_2", type = "f64", value = constant(1)},
   })

   local stats = optimize.program(ir)
   assert(stats.folds == 2)
   assert(stats.removedStatements == 2)
   assert(stats.afterNodes < stats.beforeNodes)
   assert(#ir.body == 1)
   assert(ir.body[1].op == "return")
   assert(ir.body[1].values[1].value == "5.0")
   assert(ir.maxStack == nil, "derived stack state must be recomputed by verification")
end

function M.selectsAStaticBranchWithoutLeakingItsScope()
   local ir = program({
      {
         op = "if",
         clauses = {
            {condition = {op = "bool", value = false, type = "bool"}, body = {{op = "return", values = {constant(1)}}}},
            {condition = {op = "bool", value = true, type = "bool"}, body = {{op = "return", values = {constant(2)}}}},
         },
         elseBody = {{op = "return", values = {constant(3)}}},
      },
   })

   local stats = optimize.program(ir)
   assert(stats.folds == 1)
   assert(ir.body[1].op == "block")
   assert(ir.body[1].body[1].values[1].value == "2")
end

function M.keepsUnusedLuaAllocationsAndMayRaiseReads()
   local ir = program({
      {
         op = "let",
         name = "table",
         cName = "table_1",
         type = "lua_table",
         value = {
            op = "lua_new_table",
            arrayCapacity = constant(0),
            hashCapacity = constant(0),
            type = "lua_table",
         },
      },
      {
         op = "let",
         name = "byte",
         cName = "byte_2",
         type = "u32",
         value = {
            op = "lua_string_byte",
            bytes = {op = "local", name = "input", cName = "input_0", type = "lua_string"},
            index = {op = "constant_i32", value = "0", type = "u32"},
            type = "u32",
         },
      },
      {op = "return", values = {}},
   })

   local stats = optimize.program(ir)
   assert(stats.removedStatements == 0)
   assert(#ir.body == 3)
end

function M.foldsWidthEstablishmentAndSpecializesConstantHelpers()
   local ir = program({
      {
         op = "return",
         values = {
            {
               op = "helper_call",
               helper = "increment",
               cName = "increment",
               args = {{op = "numeric_cast", value = constant(41), type = "u32"}},
               resultTypes = {"u32"},
               type = "u32",
            },
         },
      },
   })
   ir.helpers = {
      {
         name = "increment",
         cName = "increment",
         params = {{op = "helper_param", name = "value", cName = "value_1", type = "u32"}},
         values = {
            {
               op = "u32_add",
               left = {op = "helper_param", name = "value", cName = "value_1", type = "u32"},
               right = {op = "constant_i32", value = "1", type = "u32"},
               type = "u32",
            },
         },
         resultType = "u32",
         resultTypes = {"u32"},
      },
   }

   local stats = optimize.program(ir)
   assert(stats.specializedHelperCalls == 1)
   assert(stats.folds >= 2)
   assert(ir.body[1].values[1].op == "constant_i32")
   assert(ir.body[1].values[1].value == "42")
end

function M.foldsExactWideIntegerArithmeticWithoutBinary64Rounding()
   local ir = program({
      {
         op = "return",
         values = {
            {
               op = "u64_mul",
               left = {op = "numeric_cast", value = constant(6), type = "u64"},
               right = {op = "numeric_cast", value = constant(7), type = "u64"},
               type = "u64",
            },
         },
      },
   })

   local stats = optimize.program(ir)
   assert(stats.folds == 3)
   assert(ir.body[1].values[1].op == "constant_i64")
   assert(ir.body[1].values[1].type == "u64")
   assert(ir.body[1].values[1].value == "42")
end

function M.declinesRoundedWideIntegerArithmetic()
   local ir = program({
      {
         op = "return",
         values = {
            {
               op = "i64_add",
               left = {op = "constant_i64", value = "9007199254740991", type = "i64"},
               right = {op = "constant_i64", value = "2", type = "i64"},
               type = "i64",
            },
            {
               op = "numeric_cast",
               value = {op = "constant", value = "9007199254740993", type = "f64"},
               type = "i64",
            },
         },
      },
   })

   local stats = optimize.program(ir)
   assert(stats.folds == 0)
   assert(ir.body[1].values[1].op == "i64_add")
   assert(ir.body[1].values[2].op == "numeric_cast")
end

function M.unrollsOnlySmallLiteralTripCountsWithinOneGrowthBudget()
   local function loop(last)
      return {
         op = "fornum",
         binding = {kind = "local", name = "round", cName = "round_1", type = "i32"},
         from = {op = "constant_i32", value = "1", type = "i32"},
         to = {op = "constant_i32", value = tostring(last), type = "i32"},
         body = {
            {
               op = "assign",
               values = {{
                  target = {kind = "local", name = "value", cName = "value_0", type = "f64"},
                  value = {
                     op = "add",
                     left = {op = "local", name = "value", cName = "value_0", type = "f64"},
                     right = {op = "int_to_f64", value = {op = "local", name = "round", cName = "round_1", type = "i32"}, type = "f64"},
                     type = "f64",
                  },
               }},
            },
         },
      }
   end

   local ir = program({loop(4), loop(5), {op = "return", values = {constant(0)}}})
   local stats = optimize.program(ir)
   assert(stats.unrolledLoops == 1)
   assert(stats.unrolledIterations == 4)
   assert(ir.body[1].op == "block" and ir.body[4].op == "block")
   assert(ir.body[5].op == "fornum", "five trips exceed the fixed unroll cap")

   local exiting = program({loop(2)})
   exiting.body[1].body = {{op = "break"}}
   local exitStats = optimize.program(exiting)
   assert(exitStats.unrolledLoops == 0)
   assert(exiting.body[1].op == "fornum", "a break keeps the loop that owns it")

   local manyLoops = {}
   for index = 1, 12 do
      manyLoops[index] = loop(4)
   end
   local bounded = program(manyLoops)
   local boundedStats = optimize.program(bounded)
   assert(boundedStats.unrolledLoops > 0 and boundedStats.unrolledLoops < #manyLoops)
   local retained = false
   for _, statement in ipairs(bounded.body) do
      retained = retained or statement.op == "fornum"
   end
   assert(retained, "the shared growth budget leaves later fixed loops intact")
end

return M
