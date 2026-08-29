-- Idempotency fuzz for the formatter.
--
-- The corpus in `tests/fmtcorpus` says what the formatter does with the inputs
-- somebody thought to write down. This says what it does with the ones nobody did:
-- programs assembled at random from the grammar's shapes, at random widths, with
-- the line breaks and indentation of the input deliberately arbitrary.
--
-- Three claims per program, and none of them needs a golden file:
--
--   * formatting is a fixed point -- `fmt(fmt(x))` is `fmt(x)`;
--   * formatting is whitespace -- the output re-lexes to the input's tokens;
--   * the output parses.
--
-- The seed is fixed, so a run is reproducible and a failure is not a story about
-- a machine somebody no longer has. Set NUPP_FMT_FUZZ_SEED to explore, and
-- NUPP_FMT_FUZZ_PROGRAMS to explore for longer. A failure is minimized to the
-- fewest statements that still fail and printed as a whole file, ready to be
-- checked into `tests/fmtcorpus/regressions/` as an ordinary case.
local fmt = require("nupp.compiler.fmt")
local lexer = require("nupp.compiler.lexer")
local parser = require("nupp.compiler.parser")

local SEED = tonumber(os.getenv("NUPP_FMT_FUZZ_SEED") or "") or 20260814
local PROGRAMS = tonumber(os.getenv("NUPP_FMT_FUZZ_PROGRAMS") or "") or 200

-- A generator of its own rather than `math.random`, so a seed means the same
-- programs in every process that runs it, whatever else has drawn from the global one.
local function generator(seed)
   local state = seed % 2147483647
   if state <= 0 then state = state + 2147483646 end
   return function(bound)
      state = (state * 16807) % 2147483647
      return (state % bound) + 1
   end
end

local NAMES = {"alpha", "beta", "gamma", "delta", "value", "count", "rows", "handler",
   "aRatherLongerNameToPushLinesOverTheWidth", "n", "x"}
local ATOMS = {"1", "42", "0.5", '"text"', '"a rather longer string literal to push a line over the width"',
   "true", "false", "nil", "#rows", "-count", "`a template ${count} of them`"}
-- `a ? b : c` where `b` ends in a name is `b:c(...)` to the grammar, which is the
-- program's problem rather than the formatter's. The middle branch stays a literal so
-- every generated ternary is one.
local LITERALS = {"1", "42", '"text"', "true", "false", "nil"}
local TYPES = {"integer", "string", "boolean", "{string}", "{[string]: integer}", "number?",
   "function(value: integer): string", "m.Handle"}

local function build(next_)
   local pick = function(list) return list[next_(#list)] end
   local expression

   local function arguments(depth)
      local count = next_(4) - 1
      local parts = {}
      for _ = 1, count do
         parts[#parts + 1] = expression(depth + 1)
      end
      return table.concat(parts, ", ")
   end

   expression = function(depth)
      local choice = depth > 2 and next_(4) or next_(11)
      if choice == 1 then
         return pick(ATOMS)
      elseif choice == 2 then
         return pick(NAMES)
      elseif choice == 3 then
         return pick(NAMES) .. "." .. pick(NAMES)
      elseif choice == 4 then
         return ("%s(%s)"):format(pick(NAMES), arguments(depth))
      elseif choice == 5 then
         return ("%s:%s(%s)"):format(pick(NAMES), pick(NAMES), arguments(depth))
      elseif choice == 6 then
         return ("%s:%s(%s):%s(%s)"):format(pick(NAMES), pick(NAMES), arguments(depth),
            pick(NAMES), arguments(depth))
      elseif choice == 7 then
         return ("{%s}"):format(arguments(depth))
      elseif choice == 8 then
         return ("{%s = %s, %s = %s}"):format(pick(NAMES), expression(depth + 1),
            pick(NAMES), expression(depth + 1))
      elseif choice == 9 then
         return ("%s %s %s"):format(expression(depth + 1),
            pick({"and", "or", "..", "+", "*", "=="}), expression(depth + 1))
      elseif choice == 10 then
         return ("%s ? %s : %s"):format(expression(depth + 1), pick(LITERALS),
            expression(depth + 1))
      end
      return ("|%s| -> %s"):format(pick(NAMES), expression(depth + 1))
   end

   local statement
   local function block(depth)
      local parts = {}
      for _ = 1, next_(3) do
         parts[#parts + 1] = statement(depth + 1)
      end
      return table.concat(parts, "\n")
   end

   statement = function(depth)
      local choice = depth > 1 and next_(6) or next_(13)
      if choice == 1 then
         return ("local %s = %s"):format(pick(NAMES), expression(0))
      elseif choice == 2 then
         return ("local %s: %s = %s"):format(pick(NAMES), pick(TYPES), expression(0))
      elseif choice == 3 then
         return ("%s = %s"):format(pick(NAMES), expression(0))
      elseif choice == 4 then
         return ("%s(%s)"):format(pick(NAMES), arguments(0))
      elseif choice == 5 then
         return ("%s:%s(%s)"):format(pick(NAMES), pick(NAMES), arguments(0))
      elseif choice == 6 then
         return ("-- a comment about %s"):format(pick(NAMES))
      elseif choice == 7 then
         return ("if %s then\n%s\nelseif %s then\n%s\nelse\n%s\nend"):format(
            expression(1), block(depth), expression(1), block(depth), block(depth))
      elseif choice == 8 then
         return ("for index = 1, %s do\n%s\nend"):format(expression(1), block(depth))
      elseif choice == 9 then
         return ("for _, %s in ipairs(%s) do\n%s\nend"):format(pick(NAMES), pick(NAMES), block(depth))
      elseif choice == 10 then
         return ("while %s do\n%s\nend"):format(expression(1), block(depth))
      elseif choice == 11 then
         return ("local function %s(%s: %s): %s\n%s\nreturn %s\nend"):format(
            pick(NAMES), pick(NAMES), pick(TYPES), pick(TYPES), block(depth), expression(0))
      elseif choice == 12 then
         return ("--- Documents what follows.\nlocal %s = %s"):format(pick(NAMES), expression(0))
      end
      return ("do\n%s\nend"):format(block(depth))
   end

   return statement
end

-- The input's own layout must not matter, so it is made not to: every statement is
-- indented at random and separated by a random number of newlines.
local function scatter(statements, next_)
   local parts = {}
   for _, text in ipairs(statements) do
      parts[#parts + 1] = ("\n"):rep(next_(3) - 1) .. (" "):rep(next_(9) - 1) .. text
   end
   return table.concat(parts, "\n") .. "\n"
end

local function tokens(source)
   local out = {}
   for _, token in ipairs(lexer.lex(source)) do
      if token.kind ~= "eof" then
         out[#out + 1] = token.kind .. "\1" .. tostring(token.text)
      end
   end
   return table.concat(out, "\2")
end

-- What the three claims come to for one source. Returns nil when it holds, and why
-- when it does not.
local function failure(source)
   local parsed = parser.parse(source, "fuzz.nupp")
   if #parsed.errors > 0 then
      -- The generator only writes programs that parse. One that does not is this
      -- suite's bug rather than the formatter's, so it is not a finding.
      return nil
   end
   local once, problems = fmt.format(source, "fuzz.nupp")
   if #problems > 0 then
      return "the formatter refused it: " .. tostring(problems[1].msg)
   end
   if tokens(once) ~= tokens(source) then
      return "formatting changed the token sequence"
   end
   local twice = fmt.format(once, "fuzz.nupp")
   if twice ~= once then
      return "formatting is not a fixed point"
   end
   local reparsed = parser.parse(once, "fuzz.nupp")
   if #reparsed.errors > 0 then
      return "the output does not parse: " .. tostring(reparsed.errors[1].msg)
   end
   return nil
end

-- The fewest of these statements that still fails, by dropping one at a time for as
-- long as dropping keeps the failure. Linear rather than clever: a generated program
-- is a dozen statements, and a wrong minimization is worse than a slow one.
local function minimize(statements, next_)
   local best = statements
   local index = 1
   while index <= #best do
      local without = {}
      for at, text in ipairs(best) do
         if at ~= index then without[#without + 1] = text end
      end
      if #without > 0 and failure(scatter(without, next_)) then
         best = without
      else
         index = index + 1
      end
   end
   return best
end

local M = {}

function M.formattingIsAFixedPointOnRandomPrograms()
   for program = 1, PROGRAMS do
      -- Every program draws from its own stream, so program 137 is the same program
      -- whether the run started at 1 or at 137.
      local next_ = generator(SEED + program)
      local statement = build(next_)
      local statements = {}
      for _ = 1, next_(8) do
         statements[#statements + 1] = statement(0)
      end
      local source = scatter(statements, next_)
      local why = failure(source)
      if why then
         local smallest = scatter(minimize(statements, generator(SEED + program)), generator(SEED + program))
         error(("%s\n  seed %d, program %d\n  check this in under tests/fmtcorpus/regressions/:\n%s")
            :format(why, SEED, program, smallest), 0)
      end
   end
end

return M
