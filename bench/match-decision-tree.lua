-- Where a goto lowering stops being interchangeable with if/elseif.
-- Run: luajit bench/match-decision-tree.lua
--
-- bench/match-lowering.lua showed that flat dispatch on one discriminant lowers just as
-- well to `local r if .. then r = .. elseif .. end`: same tests, no allocation, no trace
-- abort. So goto earns nothing there, and the closure was the only real finding.
--
-- Nested patterns are the case that differs, and the reason is sharing. A decision tree
-- over several columns tests each column once and reaches an arm from more than one
-- path, so the tree is a DAG. Structured if/elseif has no way to express a join: every
-- path that reaches an arm has to carry its own copy of that arm's body. A label does
-- express it, because many jumps can target one.
--
-- This counts the copies rather than timing anything, so a loaded machine cannot affect
-- the answer. It is a property of the emitted source, not of how fast it runs.

----------------------------------------------------------------------------------------
-- A pattern matrix. Each arm is one pattern per column plus the body it selects; two
-- arms naming the same body are the sharing this is about.
----------------------------------------------------------------------------------------

local WILDCARD = "_"

local function copyPatterns(patterns)
   local out = {}
   for index, pattern in ipairs(patterns) do out[index] = pattern end
   return out
end

-- Leftmost column that any arm still discriminates on. Maranget picks a better column
-- than this; the choice changes the tree's size but not whether it is a DAG.
local function branchColumn(matrix)
   for column = 1, #matrix[1].patterns do
      for _, row in ipairs(matrix) do
         if row.patterns[column] ~= WILDCARD then return column end
      end
   end
   return nil
end

local function buildTree(matrix)
   if #matrix == 0 then return {body = "fail"} end
   local column = branchColumn(matrix)
   if not column then return {body = matrix[1].body} end

   local constructors, seen = {}, {}
   for _, row in ipairs(matrix) do
      local pattern = row.patterns[column]
      if pattern ~= WILDCARD and not seen[pattern] then
         seen[pattern] = true
         constructors[#constructors + 1] = pattern
      end
   end

   local node = {column = column, branches = {}}
   for _, constructor in ipairs(constructors) do
      local narrowed = {}
      for _, row in ipairs(matrix) do
         if row.patterns[column] == constructor or row.patterns[column] == WILDCARD then
            local patterns = copyPatterns(row.patterns)
            patterns[column] = WILDCARD
            narrowed[#narrowed + 1] = {patterns = patterns, body = row.body}
         end
      end
      node.branches[#node.branches + 1] = {constructor = constructor, tree = buildTree(narrowed)}
   end

   local fallthrough = {}
   for _, row in ipairs(matrix) do
      if row.patterns[column] == WILDCARD then fallthrough[#fallthrough + 1] = row end
   end
   node.default = buildTree(fallthrough)
   return node
end

----------------------------------------------------------------------------------------
-- Two emissions of the same tree.
----------------------------------------------------------------------------------------

-- Bodies are given a few statements each, because the question is what duplicating one
-- costs and a one-token body would understate it.
local function bodyText(name)
   return ([[r = compute%s ( v ) ; log ( "%s" , r ) ; r = r * weight%s]]):format(name, name, name)
end

-- Structured: every leaf carries its own copy of the body.
local function emitStructured(tree, out, indent, tally)
   if tree.body then
      tally[tree.body] = (tally[tree.body] or 0) + 1
      out[#out + 1] = indent .. bodyText(tree.body)
      return
   end
   local keyword = "if"
   for _, branch in ipairs(tree.branches) do
      out[#out + 1] = ("%s%s v%d == %q then"):format(indent, keyword, tree.column, branch.constructor)
      emitStructured(branch.tree, out, indent .. "   ", tally)
      keyword = "elseif"
   end
   out[#out + 1] = indent .. "else"
   emitStructured(tree.default, out, indent .. "   ", tally)
   out[#out + 1] = indent .. "end"
end

-- Goto: every leaf is a jump, and each body is emitted once behind its own label.
local function emitGoto(tree, out, indent, tally)
   if tree.body then
      tally[tree.body] = (tally[tree.body] or 0) + 1
      out[#out + 1] = indent .. "goto B" .. tree.body
      return
   end
   local keyword = "if"
   for _, branch in ipairs(tree.branches) do
      out[#out + 1] = ("%s%s v%d == %q then"):format(indent, keyword, tree.column, branch.constructor)
      emitGoto(branch.tree, out, indent .. "   ", tally)
      keyword = "elseif"
   end
   out[#out + 1] = indent .. "else"
   emitGoto(tree.default, out, indent .. "   ", tally)
   out[#out + 1] = indent .. "end"
end

local function bodiesOf(matrix)
   local names, seen = {"fail"}, {fail = true}
   for _, row in ipairs(matrix) do
      if not seen[row.body] then seen[row.body] = true names[#names + 1] = row.body end
   end
   return names
end

local function render(matrix)
   local tree = buildTree(matrix)

   local structured, structuredTally = {}, {}
   emitStructured(tree, structured, "   ", structuredTally)

   local jumped, jumpTally = {}, {}
   emitGoto(tree, jumped, "   ", jumpTally)
   for _, name in ipairs(bodiesOf(matrix)) do
      jumped[#jumped + 1] = ("   ::B%s:: %s goto DONE"):format(name, bodyText(name))
   end
   jumped[#jumped + 1] = "   ::DONE::"

   local copies = 0
   for _, count in pairs(structuredTally) do copies = copies + count end
   return {
      structured = table.concat(structured, "\n"),
      jumped = table.concat(jumped, "\n"),
      bodyCopies = copies,
      distinctBodies = #bodiesOf(matrix),
   }
end

----------------------------------------------------------------------------------------
-- The matrix: over `columns` fields, an arm per column saying "this one is A", every one
-- of them selecting the same body. That is one `when A|A|..` or-pattern in source, and it
-- is the shape where a tree reaches one body from many paths.
----------------------------------------------------------------------------------------

local function sharedBodyMatrix(columns)
   local matrix = {}
   for column = 1, columns do
      local patterns = {}
      for index = 1, columns do patterns[index] = index == column and "A" or WILDCARD end
      matrix[#matrix + 1] = {patterns = patterns, body = "Hit"}
   end
   local allB = {}
   for index = 1, columns do allB[index] = "B" end
   matrix[#matrix + 1] = {patterns = allB, body = "Both"}
   local wildcards = {}
   for index = 1, columns do wildcards[index] = WILDCARD end
   matrix[#matrix + 1] = {patterns = wildcards, body = "Miss"}
   return matrix
end

print("Arms sharing one body, over N columns of nested pattern.\n")
print(" Columns  Distinct bodies  Body copies (if/elseif)  Body copies (goto)  Chars if/elseif  Chars goto")
print(" ───────  ───────────────  ───────────────────────  ──────────────────  ───────────────  ──────────")
for columns = 2, 8 do
   local result = render(sharedBodyMatrix(columns))
   print((" %7d  %15d  %23d  %18d  %15d  %10d"):format(
      columns, result.distinctBodies, result.bodyCopies, result.distinctBodies,
      #result.structured, #result.jumped))
end

print("\nThe three-column case, emitted both ways:\n")
local sample = render(sharedBodyMatrix(3))
print("-- if/elseif ------------------------------------------------")
print(sample.structured)
print("\n-- goto -----------------------------------------------------")
print(sample.jumped)
