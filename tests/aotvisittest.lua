-- The scalar child mapper is the optimizer's single structural authority.

local visit = require("nupp.compiler.aot.visit")

local M = {}

local function localValue(name)
   return {op = "local", name = name, cName = name, type = "u32"}
end

local function replacement(child)
   if child.op == "local" then
      return {op = "constant_i32", value = "7", type = child.type}
   end
   return child
end

function M.rewritesEveryPreviouslyOmittedExpressionChild()
   local substring = {
      op = "lua_substring",
      bytes = localValue("bytes"),
      first = localValue("first"),
      last = localValue("last"),
      type = "lua_string",
   }
   visit.expressionChildren(substring, replacement)
   assert(substring.bytes.op == "constant_i32")
   assert(substring.first.op == "constant_i32")
   assert(substring.last.op == "constant_i32")

   local tableGet = {
      op = "lua_table_get_index",
      table = localValue("table"),
      key = localValue("key"),
      type = "f64",
   }
   visit.expressionChildren(tableGet, replacement)
   assert(tableGet.table.op == "constant_i32")
   assert(tableGet.key.op == "constant_i32")

   local buffer = {op = "lua_string_buffer", initial = localValue("initial"), type = "lua_string_buffer"}
   visit.expressionChildren(buffer, replacement)
   assert(buffer.initial.op == "constant_i32")
   local finish = {op = "lua_string_buffer_finish", buffer = localValue("buffer"), type = "lua_string"}
   visit.expressionChildren(finish, replacement)
   assert(finish.buffer.op == "constant_i32")
end

function M.rewritesEveryBuilderEventChildInExpressionsAndStatements()
   local function event()
      return {
         op = "lua_builder_decimal64",
         builder = localValue("builder"),
         mode = "eager",
         sourceBytes = localValue("sourceBytes"),
         start = localValue("start"),
         length = localValue("length"),
         escaped = localValue("escaped"),
         value = localValue("value"),
         negative = localValue("negative"),
         exponent = localValue("exponent"),
         exact = localValue("exact"),
         capacity = localValue("capacity"),
         scratch = localValue("scratch"),
         escapeScratch = localValue("escapeScratch"),
         escapeIndex = localValue("escapeIndex"),
         escapeCount = localValue("escapeCount"),
         type = "lua_effect",
      }
   end

   local expression = event()
   visit.expressionChildren(expression, replacement)
   local statement = event()
   visit.statementExpressions(statement, replacement)
   for _, node in ipairs({expression, statement}) do
      for _, field in ipairs({
         "builder", "sourceBytes", "start", "length", "escaped", "value", "negative", "exponent",
         "exact", "capacity", "scratch", "escapeScratch", "escapeIndex", "escapeCount",
      }) do
         assert(node[field].op == "constant_i32", field)
      end
   end
end

return M
