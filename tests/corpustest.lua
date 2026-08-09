-- The superset oracle: a large body of real-world untyped Lua must parse
-- with no errors, round-trip byte for byte, and check with no diagnostics.
-- Every valid LuaJIT program is a valid Nupp program; this is the test
-- that keeps that true, and it is the reason contextual keywords need more
-- than a two-token lookahead.
local parser = require("nupp.compiler.parser")
local check = require("fragment")
local cst = require("nupp.compiler.cst")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

-- Corpus files are large real-world Lua; skipped when unavailable so the
-- suite still runs on a bare checkout.
local CORPUS = {
   "/Users/dowling/projects/tl/tl.lua",
   "/Users/dowling/projects/tl/teal.lua",
}

local function read(path)
   local f = io.open(path, "rb")
   if not f then return nil end
   local text = f:read("*a")
   f:close()
   return text
end

local M = {}

function M.realWorldLuaStaysClean()
   local env = envMod.new(HERE .. "/..")
   -- The corpus is an oracle for accepted Lua, not a style guide for projects
   -- outside this one. Its `else`/`if` chains are legal and intentionally left
   -- as-written, even though this project's default style warns about them.
   local lintConfig = {
      ['else-if'] = 'off',
      ['unused-binding'] = 'off',
      ['discarded-result'] = 'off',
   }
   local checked = 0
   for _, path in ipairs(CORPUS) do
      local src = read(path)
      if src then
         checked = checked + 1
         local result = parser.parse(src, path)
         if #result.errors > 0 then
            local e = result.errors[1]
            error(("%s: %d parse errors, first at line %d: %s")
               :format(path, #result.errors, e.line, e.msg), 2)
         end
         assert(cst.textOf(result.root) == src,
            path .. ": lossless round-trip broken")
         local diags = check.check(result, path, env, {lints = lintConfig})
         if #diags > 0 then
            local d = diags[1]
            error(("%s: %d diagnostics, first at line %d: %s %s")
               :format(path, #diags, d.line, d.code, d.msg), 2)
         end
      end
   end
   if checked == 0 then
      print("  (corpus unavailable; oracle skipped)")
   end
end

-- The shapes that broke the oracle before: a declaration introducer used as
-- an ordinary variable name, with the next statement starting on its own
-- line. Kept as fast, self-contained regression cases.
function M.declarationKeywordsRemainOrdinaryNames()
   local env = envMod.new(HERE .. "/..")
   for _, kw in ipairs({"def", "record", "interface", "struct", "type"}) do
      for _, follow in ipairs({
         "i, j = 1, 2",       -- assignment target list
         "i = 1",             -- single assignment
         "print(i)",          -- ordinary call
      }) do
         local src = ("local %s\n%s\n"):format(kw, follow)
         local result = parser.parse(src, "kw.g.nupp")
         assert(#result.errors == 0,
            ("`local %s` + `%s` must stay ordinary Lua: %s")
               :format(kw, follow, result.errors[1] and result.errors[1].msg or ""))
         local diags = check.check(result, "kw.g.nupp", env)
         assert(#diags == 0, ("`local %s` + `%s`: %s")
            :format(kw, follow, diags[1] and diags[1].msg or ""))
      end
   end
end

function M.declarationsStillParseWhenTheyAreDeclarations()
   local cases = {
      "local record R\n    x: number\nend",
      "local struct S\n    x: float\nend",
      "local interface I\n    f: function(): nil\nend",
      "local type Alias = number",
      "local type Choice = 'a' | 'b'",
   }
   for _, src in ipairs(cases) do
      local result = parser.parse(src, "decl")
      assert(#result.errors == 0, "declaration must still parse: " .. src
         .. " -> " .. (result.errors[1] and result.errors[1].msg or ""))
   end
end

return M
