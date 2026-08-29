-- The formatter's golden corpus.
--
-- Every case is a pair: `<name>.nupp` is written the way somebody might write it,
-- and `<name>.expected.nupp` is what the formatter is required to make of it. A
-- case is checked three ways, because exact output alone is the weakest of the
-- three claims:
--
--   * the formatted input equals the golden output, byte for byte;
--   * formatting the golden output again returns it unchanged, so the style is a
--     fixed point rather than a direction of travel;
--   * both re-lex to the same token sequence the input had, so no rewrite here is
--     ever more than whitespace.
--
-- The corpus lives outside the manifest's include roots, so `nupp fmt` and
-- `nupp check` never walk it: an input is allowed to be as badly written as the
-- rule it exercises requires.
--
-- To add a case, write the input, run the suite once with NUPP_FMT_CORPUS_WRITE=1
-- to record what the formatter does with it, and read the recorded output before
-- committing it. A golden nobody read is a record of a bug as readily as of a rule.
local fmt = require("nupp.compiler.fmt")
local lexer = require("nupp.compiler.lexer")
local parser = require("nupp.compiler.parser")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local CORPUS = HERE .. "/fmtcorpus"
local WRITE = os.getenv("NUPP_FMT_CORPUS_WRITE") == "1"

local function readFile(path)
   local file = assert(io.open(path, "rb"), "cannot read " .. path)
   local text = file:read("*a")
   file:close()
   return text
end

local function writeFile(path, text)
   local file = assert(io.open(path, "wb"), "cannot write " .. path)
   file:write(text)
   file:close()
end

-- Case names come from the directory listing, so the suite reports one test per
-- case and a new file needs no registration anywhere.
local function cases()
   local found = {}
   local listing = assert(io.popen("ls '" .. CORPUS .. "'"), "cannot list the corpus")
   for entry in listing:lines() do
      if not entry:match("%.") then
         local files = assert(io.popen("ls '" .. CORPUS .. "/" .. entry .. "' 2>/dev/null"))
         for name in files:lines() do
            local case = name:match("^(.*)%.nupp$")
            if case and not case:match("%.expected$") then
               found[#found + 1] = {category = entry, case = case}
            end
         end
         files:close()
      end
   end
   listing:close()
   table.sort(found, function(a, b)
      if a.category ~= b.category then return a.category < b.category end
      return a.case < b.case
   end)
   return found
end

-- Token kinds and their text, which formatting must never change -- except for the
-- three rewrites the formatter exempts, each proven safe rather than merely
-- whitespace. One of those, dropping a type shape's unnecessary trailing separator,
-- is elided here so a case may exercise it. The other two, annotation shorthand and
-- method parenthesization, would fail this check; a case that wants either has to
-- widen it deliberately rather than by accident.
local CLOSERS = {["}"] = true, [")"] = true, ["]"] = true}

local function tokens(source)
   local kept = {}
   for _, token in ipairs(lexer.lex(source)) do
      if token.kind ~= "eof" then
         kept[#kept + 1] = token
      end
   end
   local out = {}
   for index, token in ipairs(kept) do
      local separator = token.kind == "," or token.kind == ";"
      local trailing = separator and kept[index + 1] ~= nil and CLOSERS[kept[index + 1].kind]
      if not trailing then
         out[#out + 1] = token.kind .. "\1" .. tostring(token.text)
      end
   end
   return table.concat(out, "\2")
end

local function firstDifference(got, want)
   local gotLines, wantLines = {}, {}
   for line in (got .. "\n"):gmatch("(.-)\n") do gotLines[#gotLines + 1] = line end
   for line in (want .. "\n"):gmatch("(.-)\n") do wantLines[#wantLines + 1] = line end
   for index = 1, math.max(#gotLines, #wantLines) do
      if gotLines[index] ~= wantLines[index] then
         return ("line %d:\n  want: %q\n  got:  %q"):format(
            index, tostring(wantLines[index]), tostring(gotLines[index]))
      end
   end
   return "no line differs, so the difference is in the trailing newline"
end

local M = {}

for _, entry in ipairs(cases()) do
   local base = CORPUS .. "/" .. entry.category .. "/" .. entry.case
   M[entry.category .. "/" .. entry.case] = function()
      local source = readFile(base .. ".nupp")
      local formatted, problems = fmt.format(source, base .. ".nupp")
      assert(#problems == 0, "the formatter refused the input: "
         .. tostring(problems[1] and problems[1].msg))

      local goldenPath = base .. ".expected.nupp"
      if WRITE then
         writeFile(goldenPath, formatted)
         return
      end

      local golden = readFile(goldenPath)
      assert(formatted == golden,
         "formatted output differs from the golden file\n  " .. firstDifference(formatted, golden))

      local again = fmt.format(golden, goldenPath)
      assert(again == golden,
         "formatting the golden output changed it\n  " .. firstDifference(again, golden))

      assert(tokens(formatted) == tokens(source),
         "formatting changed the token sequence, so it was not whitespace")

      local parsed = parser.parse(golden, goldenPath)
      assert(#parsed.errors == 0,
         "the golden output does not parse: " .. tostring(parsed.errors[1] and parsed.errors[1].msg))
   end
end

return M
