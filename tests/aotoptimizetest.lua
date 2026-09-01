-- Verified scalar AOT optimisation, independently of source lowering.
--
-- These operate on the small public IR records as plain Lua tables. That keeps
-- each case about the rewrite itself; lowering and emission are covered by the
-- AOT CLI and build suites.

local effects = require("nupp.compiler.aot.effects")
local fold = require("nupp.compiler.aot.fold")
local optimize = require("nupp.compiler.aot.optimize")

local M = {}

local function constant(value)
   return {op = "constant", value = tostring(value), type = "f64"}
end

local function program(body)
   return {body = body, helpers = {}, maxStack = 19}
end

local function integer(value, valueType)
   return {
      op = (valueType == "i64" or valueType == "u64") and "constant_i64" or "constant_i32",
      value = tostring(value), type = valueType,
   }
end

local function named(name, valueType)
   return {op = "local", name = name, cName = name, type = valueType}
end

local function ruleCount(stats, wanted)
   for _, application in ipairs(stats.ruleApplications) do
      if application.id == wanted then
         return application.count
      end
   end
   return 0
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

function M.optimizesWorkgroupRegionsWithoutCrossingPhaseBoundaries()
   local groups = {
      op = "u32_div",
      left = {
         op = "numeric_cast",
         value = {op = "span_count", span = "points", type = "f64"},
         type = "u32",
      },
      right = {
         op = "numeric_cast", value = constant(64), type = "u32",
      },
      type = "u32",
   }
   local ir = {
      helpers = {},
      maxStack = 19,
      workgroup = {
         prelude = {{
            op = "let", name = "groups", cName = "groups_1", type = "u32", value = groups,
         }},
         groups = groups,
         statements = {
            {
               op = "let", name = "controller", cName = "controller_1", type = "u32",
               value = integer(7, "u32"),
            },
            {
               op = "phase",
               body = {
                  {
                     op = "let", name = "width", cName = "width_1", type = "u32",
                     value = {op = "numeric_cast", value = constant(64), type = "u32"},
                  },
                  {
                     op = "let", name = "unused", cName = "unused_1", type = "u32",
                     value = {
                        op = "u32_mul", left = named("width", "u32"), right = integer(2, "u32"), type = "u32",
                     },
                  },
               },
            },
            {
               op = "phase",
               body = {{
                  op = "shared_store", shared = "scratch", index = integer(0, "u32"),
                  value = {op = "local", name = "controller", cName = "controller_1", type = "u32"},
               }},
            },
            {
               op = "phase",
               body = {{
                  op = "shared_store", shared = "scratch", index = integer(1, "u32"),
                  value = {
                     op = "shared_load", shared = "scratch",
                     index = {
                        op = "u32_sub", left = {op = "local_index", type = "u32"},
                        right = integer(1, "u32"), type = "u32",
                     },
                     type = "u32",
                  },
               }},
            },
         },
      },
   }

   local stats = optimize.program(ir)
   assert(ruleCount(stats, "convert.numeric-cast.constant") >= 2)
   assert(ir.workgroup.groups.right.op == "constant_i32")
   assert(#ir.workgroup.prelude == 0, "the copied dispatch local is dead")
   assert(ir.workgroup.statements[1].op == "let", "controller code stays outside phase rewrites")
   assert(ir.workgroup.statements[2].op == "phase" and #ir.workgroup.statements[2].body == 0,
      "a phase remains even when its private work simplifies away")
   local store = ir.workgroup.statements[3].body[1]
   assert(store.op == "shared_store" and store.value.op == "local" and store.value.cName == "controller_1",
      "controller constants do not propagate across a phase boundary")
   local indexed = ir.workgroup.statements[4].body[1].value.index
   assert(indexed.op == "u32_sub", "phase cleanup preserves scratch-bounds proof shapes")
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

function M.foldsFractionalBinary64ConstantsThroughThePatternCatalog()
   local ir = program({{op = "return", values = {{
      op = "add", left = constant(2.5), right = constant(0.25), type = "f64",
   }}}})
   local stats = optimize.program(ir)
   assert(ir.body[1].values[1].value == "2.75")
   assert(ruleCount(stats, "f64.add.constants") == 1)
end

function M.distinguishesPositiveAndNegativeBinary64Zero()
   local x = named("x", "f64")
   local ir = program({{op = "return", values = {
      {op = "add", left = x, right = constant(-0.0), type = "f64"},
      {op = "add", left = x, right = constant(0.0), type = "f64"},
      {op = "sub", left = x, right = constant(0.0), type = "f64"},
      {op = "sub", left = x, right = constant(-0.0), type = "f64"},
   }}})
   local stats = optimize.program(ir)
   assert(ir.body[1].values[1].op == "local")
   assert(ir.body[1].values[2].op == "add")
   assert(ir.body[1].values[3].op == "local")
   assert(ir.body[1].values[4].op == "sub")
   assert(ruleCount(stats, "f64.add.right-negzero") == 1)
   assert(ruleCount(stats, "f64.sub.right-zero") == 1)
end

function M.preservesNonfiniteAndForbiddenBinary64Identities()
   local x = named("x", "f64")
   local ir = program({{op = "return", values = {
      {op = "div", left = constant(1), right = constant(0), type = "f64"},
      {op = "div", left = constant(0), right = constant(0), type = "f64"},
      {op = "mul", left = x, right = constant(0), type = "f64"},
      {op = "sub", left = x, right = named("x", "f64"), type = "f64"},
   }}})
   local stats = optimize.program(ir)
   for _, value in ipairs(ir.body[1].values) do
      assert(value.op == "div" or value.op == "mul" or value.op == "sub")
   end
   assert(stats.folds == 0)
end

function M.removesEvaluationsOnlyWhenTheyAreDiscardable()
   local effectful = {
      op = "lua_table_get_index",
      table = named("table", "lua_table"),
      key = constant(1),
      type = "bool",
   }
   local ir = program({{op = "return", values = {
      {op = "and", left = named("pure", "bool"), right = {op = "bool", value = false, type = "bool"}, type = "bool"},
      {op = "and", left = effectful, right = {op = "bool", value = false, type = "bool"}, type = "bool"},
   }}})
   optimize.program(ir)
   assert(ir.body[1].values[1].op == "bool" and ir.body[1].values[1].value == false)
   assert(ir.body[1].values[2].op == "and")
end

function M.foldsExactU32MultiplyAndNormalizesBitResults()
   local ir = program({{op = "return", values = {
      {op = "u32_mul", left = integer(4294967295, "u32"), right = integer(4294967295, "u32"), type = "u32"},
      {op = "u32_not", value = integer(0, "u32"), type = "u32"},
      {op = "u32_and", left = integer(4294967295, "u32"), right = integer(4294967295, "u32"), type = "u32"},
   }}})
   optimize.program(ir)
   assert(ir.body[1].values[1].value == "1")
   assert(ir.body[1].values[2].value == "4294967295")
   assert(ir.body[1].values[3].value == "4294967295")
end

function M.normalizesSubtractionOnlyInAdmittedIntegerDomains()
   local ir = program({{op = "return", values = {
      {op = "i32_sub", left = named("i", "i32"), right = integer(-2147483648, "i32"), type = "i32"},
      {op = "u32_sub", left = named("u", "u32"), right = integer(1, "u32"), type = "u32"},
      {op = "u64_sub", left = named("wide", "u64"), right = integer(1, "u64"), type = "u64"},
      {op = "i64_sub", left = named("signed", "i64"), right = integer(1, "i64"), type = "i64"},
      {
         op = "i64_sub", left = named("edge", "i64"),
         right = integer(-9007199254740992, "i64"), type = "i64",
      },
   }}})
   optimize.program(ir)
   assert(ir.body[1].values[1].op == "i32_add" and ir.body[1].values[1].right.value == "-2147483648")
   assert(ir.body[1].values[2].op == "u32_add" and ir.body[1].values[2].right.value == "4294967295")
   assert(ir.body[1].values[3].op == "u64_sub")
   assert(ir.body[1].values[4].op == "i64_add" and ir.body[1].values[4].right.value == "-1")
   assert(ir.body[1].values[5].op == "i64_sub")
end

function M.reassociatesOnlyStableFixedWidthTreesAndDeclinesCanonicalOnes()
   local ir = program({{op = "return", values = {{
      op = "i32_add",
      left = {op = "i32_add", left = named("a", "i32"), right = integer(2, "i32"), type = "i32"},
      right = {op = "i32_add", left = named("b", "i32"), right = integer(3, "i32"), type = "i32"},
      type = "i32",
   }}}})
   local stats = optimize.program(ir)
   local result = ir.body[1].values[1]
   assert(result.op == "i32_add" and result.right.value == "5")
   assert(result.left.left.name == "a" and result.left.right.name == "b")
   assert(ruleCount(stats, "reassociate.i32_add") == 1)

   local canonical = program({{op = "return", values = {result}}})
   local canonicalStats = optimize.program(canonical)
   assert(ruleCount(canonicalStats, "reassociate.i32_add") == 0)

   local load = {op = "load", span = "values", index = "i", type = "i32"}
   local unstable = program({{op = "return", values = {{
      op = "i32_sub", left = load, right = {op = "load", span = "values", index = "i", type = "i32"}, type = "i32",
   }}}})
   optimize.program(unstable)
   assert(unstable.body[1].values[1].op == "i32_sub", "native reads are not stable enough for same")
end

function M.rejectsDuplicatePatternRegistrationsButAllowsMirrors()
   local base = {
      id = "left", op = "u32_add", valueType = "u32",
      left = "zero", right = "any", action = "right",
   }
   fold.validate({base, {
      id = "right", op = "u32_add", valueType = "u32",
      left = "any", right = "zero", action = "left",
   }})
   local ok, message = pcall(fold.validate, {base, base})
   assert(not ok and tostring(message):match("duplicate AOT fold rule ID left"))

   local dead = {
      id = "dead", op = "u32_add", valueType = "u32",
      left = "same", right = "any", action = "right",
   }
   ok, message = pcall(fold.validate, {dead})
   assert(not ok and tostring(message):match("uses same outside the right operand"),
      "a same pattern the matcher can never test must be rejected at registration")
end

function M.sameAndReassociationRejectUnavailableOrRaisingHelpers()
   local argument = named("value", "u32")
   local function call()
      return {
         op = "helper_call", helper = "unavailable", cName = "unavailable",
         args = {argument}, resultTypes = {"u32"}, type = "u32",
      }
   end
   local same = {op = "u32_xor", left = call(), right = call(), type = "u32"}
   local replacement = fold.apply(same, {helpers = {}})
   assert(replacement == nil, "an unavailable helper body cannot prove value stability")

   local raising = {
      op = "lua_string_byte",
      bytes = named("bytes", "lua_string"),
      index = integer(0, "u32"),
      type = "u32",
   }
   local raisingSame = {
      op = "u32_xor", left = raising,
      right = {
         op = "lua_string_byte",
         bytes = named("bytes", "lua_string"),
         index = integer(0, "u32"),
         type = "u32",
      },
      type = "u32",
   }
   replacement = fold.apply(raisingSame, {helpers = {}})
   assert(replacement == nil, "a raising Lua read cannot prove value stability")

   local tree = {
      op = "u32_add",
      left = {op = "u32_add", left = call(), right = integer(1, "u32"), type = "u32"},
      right = integer(2, "u32"),
      type = "u32",
   }
   replacement = fold.apply(tree, {helpers = {}})
   assert(replacement == nil, "reassociation needs an available stable helper body")
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

local function breakResultProgram()
   local condition = {
      op = "lt",
      left = named("iteration", "i32"),
      right = named("limit", "i32"),
      type = "bool",
   }
   local setEscaped = {
      op = "assign",
      values = {{
         target = {kind = "local", name = "escaped", cName = "escaped", type = "i32"},
         value = integer(1, "i32"),
      }},
   }
   local iterationStep = {
      op = "assign",
      values = {{
         target = {kind = "local", name = "iteration", cName = "iteration", type = "i32"},
         value = {
            op = "i32_add",
            left = named("iteration", "i32"),
            right = integer(1, "i32"),
            type = "i32",
         },
      }},
   }
   return program({
      {op = "let", name = "iteration", cName = "iteration", type = "i32", value = integer(0, "i32")},
      {op = "let", name = "escaped", cName = "escaped", type = "i32", value = integer(0, "i32")},
      {
         op = "while",
         condition = condition,
         body = {
            {
               op = "if",
               clauses = {{condition = named("stop", "bool"), body = {setEscaped, {op = "break"}}}},
            },
            iterationStep,
         },
      },
      {op = "return", values = {named("escaped", "i32")}},
   })
end

function M.derivesABreakFlagFromTheFinalLoopCondition()
   local ir = breakResultProgram()
   local stats = optimize.program(ir)
   assert(ruleCount(stats, "derive.break-result") == 1)

   local loop = ir.body[3]
   assert(loop.op == "while")
   assert(loop.body[1].op == "if" and #loop.body[1].clauses[1].body == 1)
   assert(loop.body[1].clauses[1].body[1].op == "break",
      "the loop-carried flag write remains beside break")

   local derived = ir.body[4]
   assert(derived.op == "if" and derived.clauses[1].condition.op == "lt")
   local assignment = derived.clauses[1].body[1].values[1]
   assert(assignment.target.cName == "escaped" and assignment.value.value == "1")
end

function M.derivesBreakFlagsOnlyWhenTheFinalConditionProvesThem()
   local function declined(ir, why)
      local stats = optimize.program(ir)
      assert(ruleCount(stats, "derive.break-result") == 0, why)
   end

   local changedBeforeBreak = breakResultProgram()
   local loop = changedBeforeBreak.body[3]
   loop.body[1].clauses[1].body = {loop.body[2], loop.body[1].clauses[1].body[1], {op = "break"}}
   loop.body[2] = {op = "block", body = {}}
   declined(changedBeforeBreak, "a changed condition operand was treated as the header value")

   local alternateBreak = breakResultProgram()
   table.insert(alternateBreak.body[3].body, 1, {
      op = "if",
      clauses = {{condition = named("abort", "bool"), body = {{op = "break"}}}},
   })
   declined(alternateBreak, "an unpaired break was treated as the result-setting exit")

   local readInLoop = breakResultProgram()
   table.insert(readInLoop.body[3].body, 1, {
      op = "if",
      clauses = {{
         condition = {op = "eq", left = named("escaped", "i32"), right = integer(1, "i32"), type = "bool"},
         body = {},
      }},
   })
   declined(readInLoop, "a loop-visible flag was moved out of the loop")

   local continued = breakResultProgram()
   table.insert(continued.body[3].body, 1, {
      op = "if",
      clauses = {{condition = named("skip", "bool"), body = {{op = "continue"}}}},
   })
   declined(continued, "a loop with continue received a break-result rewrite")

   local nativeCondition = breakResultProgram()
   nativeCondition.body[3].condition = {
      op = "load", span = "values", index = "i", type = "bool",
   }
   declined(nativeCondition, "a native read was repeated after the loop")
end

-- Characterizations of the rewrite scheduler's ordering. These pin how the
-- fused walk behaves today so a rearrangement of the driver has something
-- sharper than suite green to answer to.

function M.propagatesAndFoldsInOneIterationThenGoesQuiet()
   local ir = program({
      {op = "let", name = "x", cName = "x", value = integer(2, "u32"), type = "u32"},
      {op = "return", values = {{
         op = "u32_add", left = named("x", "u32"), right = integer(3, "u32"), type = "u32",
      }}},
   })
   local stats = optimize.program(ir)
   assert(ruleCount(stats, "propagate.local-constant") == 1)
   assert(stats.propagatedConstants == 1)
   assert(ir.body[#ir.body].values[1].op == "constant_i32")
   assert(ir.body[#ir.body].values[1].value == "5")
   assert(stats.removedStatements == 1, "the propagated let is dead in the same iteration")
   assert(stats.iterations == 2, "one changing pass and one quiet pass")
end

function M.propagationInsertsTheSharedValueNodeItself()
   local value = integer(2, "u32")
   local use = {op = "return", values = {named("x", "u32")}}
   local ir = program({
      {op = "let", name = "x", cName = "x", value = value, type = "u32"},
      use,
   })
   optimize.program(ir)
   assert(rawequal(use.values[1], value),
      "propagation must insert the environment's node, not a copy")
end

function M.helperValuesFoldWithoutTheBodyEnvironment()
   local ir = program({
      {op = "let", name = "m", cName = "m", value = integer(7, "u32"), type = "u32"},
      {op = "return", values = {
         named("m", "u32"),
         {
            op = "helper_call", helper = "bump", cName = "bump",
            args = {named("q", "u32")}, resultTypes = {"u32"}, type = "u32",
         },
      }},
   })
   ir.helpers = {{
      name = "bump", cName = "bump",
      params = {{op = "helper_param", name = "value", cName = "value_1", type = "u32"}},
      values = {{
         op = "u32_add", left = named("m", "u32"), right = integer(1, "u32"), type = "u32",
      }},
      resultType = "u32", resultTypes = {"u32"},
   }}
   local stats = optimize.program(ir)
   assert(stats.specializedHelperCalls == 0, "a nonliteral argument blocks specialization")
   assert(ir.helpers[1].values[1].left.op == "local",
      "a helper value never sees the body's constant environment")
   assert(stats.propagatedConstants == 1, "only the body use of m propagates")
end

function M.specializedReplacementsWaitForTheNextPassToPropagate()
   local body = {}
   for index = 1, 10 do
      body[index] = {
         op = "let", name = "pad" .. index, cName = "pad" .. index,
         value = integer(index, "u32"), type = "u32",
      }
   end
   body[#body + 1] = {op = "let", name = "m", cName = "m", value = integer(7, "u32"), type = "u32"}
   body[#body + 1] = {op = "return", values = {{
      op = "helper_call", helper = "bump", cName = "bump", args = {},
      resultTypes = {"u32"}, type = "u32",
   }}}
   local ir = program(body)
   ir.helpers = {{
      name = "bump", cName = "bump", params = {},
      values = {{
         op = "u32_add", left = named("m", "u32"), right = integer(1, "u32"), type = "u32",
      }},
      resultType = "u32", resultTypes = {"u32"},
   }}
   local stats = optimize.program(ir)
   assert(stats.specializedHelperCalls == 1)
   assert(stats.propagatedConstants == 1)
   assert(ir.body[#ir.body].values[1].op == "constant_i32")
   assert(ir.body[#ir.body].values[1].value == "8")
   assert(stats.iterations == 3,
      "a specialized body meets the constant environment only on the next pass")
end

function M.declinedSpecializationChangesNothing()
   local chain = named("value", "u32")
   for _ = 1, 12 do
      chain = {op = "u32_add", left = chain, right = named("value", "u32"), type = "u32"}
   end
   local ir = program({
      {op = "return", values = {{
         op = "helper_call", helper = "wide", cName = "wide",
         args = {integer(1, "u32")}, resultTypes = {"u32"}, type = "u32",
      }}},
   })
   ir.helpers = {{
      name = "wide", cName = "wide",
      params = {{op = "helper_param", name = "value", cName = "value", type = "u32"}},
      values = {chain},
      resultType = "u32", resultTypes = {"u32"},
   }}
   local stats = optimize.program(ir)
   assert(stats.specializedHelperCalls == 0, "growth beyond the budget declines")
   assert(ir.body[1].values[1].op == "helper_call", "the call survives a declined proposal")
   assert(stats.iterations == 1, "a declined proposal marks nothing changed")
end

return M
