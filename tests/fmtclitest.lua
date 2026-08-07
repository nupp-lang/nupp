-- `nupp fmt` over a whole project, driven through the real binary.
--
-- Naming files formats those files; naming none asks about the project. The
-- second is the one with teeth: it decides which files a `-w` is allowed to
-- rewrite, and a tree holds plenty that nobody writes by hand.
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local p = assert(io.popen("pwd"))
   HERE = p:read("*l") .. "/" .. HERE
   p:close()
end
local NUPP = HERE .. "/../bin/nupp"

local function tempProject(files)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   for name, text in pairs(files) do
      local sub = name:match("^(.*)/[^/]+$")
      if sub then
         assert(os.execute("mkdir -p '" .. dir .. "/" .. sub .. "'") == 0)
      end
      local f = assert(io.open(dir .. "/" .. name, "wb"))
      f:write(text)
      f:close()
   end
   return dir
end

local function readFile(path)
   local f = assert(io.open(path, "rb"))
   local text = f:read("*a")
   f:close()
   return text
end

--- Runs the binary in `dir` and returns its output and whether it succeeded.
local function run(dir, argv)
   local outfile = os.tmpname()
   local status = os.execute(("cd '%s' && '%s' %s > '%s' 2>&1")
      :format(dir, NUPP, argv, outfile))
   local out = readFile(outfile)
   os.remove(outfile)
   return out, status == 0
end

local function lines(text)
   local out = {}
   for line in text:gmatch("([^\n]+)") do out[#out + 1] = line end
   table.sort(out)
   return table.concat(out, " ")
end

local M = {}

local UNFORMATTED = "local  x   =  1\n"
local FORMATTED = "local x = 1\n"

-- With nothing named, the project is the subject, and the answer is which of
-- its files are not formatted — not forty files printed to stdout, which
-- answers nothing anybody asked.
function M.reportsTheProjectFilesThatAreNotFormatted()
   local dir = tempProject({
      ["nupp.lua"] = 'return { include = { "src" } }\n',
      ["src/messy.nupp"] = UNFORMATTED,
      ["src/tidy.nupp"] = FORMATTED,
   })
   local out, ok = run(dir, "fmt")
   assert(not ok, "an unformatted project is a failure, so a build can gate")
   assert(lines(out) == "src/messy.nupp",
      "only the file that is not formatted is named: " .. lines(out))
   assert(readFile(dir .. "/src/messy.nupp") == UNFORMATTED,
      "and nothing is rewritten without --write")
   os.execute("rm -rf '" .. dir .. "'")
end

-- The same question answered by fixing it, which still says what it touched.
function M.writesTheProjectAndSaysWhatItChanged()
   local dir = tempProject({
      ["nupp.lua"] = 'return { include = { "src" } }\n',
      ["src/messy.nupp"] = UNFORMATTED,
      ["src/tidy.nupp"] = FORMATTED,
   })
   local out, ok = run(dir, "fmt -w")
   assert(ok, "formatting the project succeeds: " .. out)
   assert(lines(out) == "src/messy.nupp",
      "the file it rewrote is named: " .. lines(out))
   assert(readFile(dir .. "/src/messy.nupp") == FORMATTED, "and rewritten")
   assert(readFile(dir .. "/src/tidy.nupp") == FORMATTED,
      "a file already as the formatter would have it is left alone")

   local again, againOk = run(dir, "fmt")
   assert(againOk and again == "",
      "and a formatted project reports nothing: " .. again)
   os.execute("rm -rf '" .. dir .. "'")
end

-- A declaration file is source: somebody wrote it and somebody reads it. The
-- module list drops them because nothing requires one; formatting does not.
function M.formatsDeclarationFilesToo()
   local dir = tempProject({
      ["nupp.lua"] = 'return { include = { "src" } }\n',
      ["src/decls.d.nupp"] = "global record Thing\n    id:  integer\nend\n",
   })
   local out, ok = run(dir, "fmt -w")
   assert(ok, "the declaration file formats: " .. out)
   assert(lines(out) == "src/decls.d.nupp",
      "and is named as one of the project's files: " .. lines(out))
   assert(readFile(dir .. "/src/decls.d.nupp")
      == "global record Thing\n    id: integer\nend\n",
      "with its annotation spacing normalized")
   os.execute("rm -rf '" .. dir .. "'")
end

-- A project that declares no include roots is its own root — and that is the
-- case where the exclusions matter, because the tree then holds build output
-- and whatever a dot-directory is keeping.
function M.aProjectWithNoIncludeRootsIsItsOwnRoot()
   local dir = tempProject({
      ["main.nupp"] = UNFORMATTED,
      ["build/generated.nupp"] = UNFORMATTED,
      [".worktrees/other/copy.nupp"] = UNFORMATTED,
   })
   local out, ok = run(dir, "fmt -w")
   assert(ok, "formatting succeeds: " .. out)
   assert(lines(out) == "main.nupp",
      "only the hand-written file is formatted: " .. lines(out))
   assert(readFile(dir .. "/build/generated.nupp") == UNFORMATTED,
      "generated output is not rewritten to tidy what nobody wrote")
   assert(readFile(dir .. "/.worktrees/other/copy.nupp") == UNFORMATTED,
      "and neither is somebody else's bookkeeping")
   os.execute("rm -rf '" .. dir .. "'")
end

-- The manifest says where a project's source lives, so a file outside those
-- roots is not the project's to rewrite.
function M.leavesFilesOutsideTheIncludeRootsAlone()
   local dir = tempProject({
      ["nupp.lua"] = 'return { include = { "src" } }\n',
      ["src/messy.nupp"] = UNFORMATTED,
      ["examples/demo.nupp"] = UNFORMATTED,
   })
   local out, ok = run(dir, "fmt -w")
   assert(ok, "formatting succeeds: " .. out)
   assert(lines(out) == "src/messy.nupp",
      "only the include roots are formatted: " .. lines(out))
   assert(readFile(dir .. "/examples/demo.nupp") == UNFORMATTED,
      "a file outside them is left as it is")

   -- Naming it explicitly still formats it: the roots decide what "the
   -- project" means, not what the formatter is allowed to touch.
   local named, namedOk = run(dir, "fmt -w examples/demo.nupp")
   assert(namedOk and named == "", "naming it formats it quietly: " .. named)
   assert(readFile(dir .. "/examples/demo.nupp") == FORMATTED,
      "and rewrites it")
   os.execute("rm -rf '" .. dir .. "'")
end

-- Named files keep the filter behaviour they had: the text comes out whether or
-- not it changed, because a filter that sometimes emits nothing is a filter
-- that sometimes empties a file.
function M.namedFilesStillWriteToStdout()
   local dir = tempProject({
      ["nupp.lua"] = 'return { include = { "src" } }\n',
      ["src/messy.nupp"] = UNFORMATTED,
      ["src/tidy.nupp"] = FORMATTED,
   })
   local formattedOut, formattedOk = run(dir, "fmt src/tidy.nupp")
   assert(formattedOk, "a file already formatted still succeeds")
   assert(formattedOut == FORMATTED,
      "and still comes out: " .. ("%q"):format(formattedOut))

   local messyOut, messyOk = run(dir, "fmt src/messy.nupp")
   assert(messyOk, "and so does one that is not")
   assert(messyOut == FORMATTED, "formatted on the way out")
   assert(readFile(dir .. "/src/messy.nupp") == UNFORMATTED,
      "with the file itself untouched")
   os.execute("rm -rf '" .. dir .. "'")
end

-- `--check` asks the question of whatever it was given, so a build can gate on
-- the files a change touched rather than on the whole project.
function M.checkReportsNamedFilesWithoutWritingThem()
   local dir = tempProject({
      ["nupp.lua"] = 'return { include = { "src" } }\n',
      ["src/messy.nupp"] = UNFORMATTED,
      ["src/tidy.nupp"] = FORMATTED,
      ["examples/demo.nupp"] = UNFORMATTED,
   })
   local out, ok = run(dir, "fmt --check src/messy.nupp src/tidy.nupp")
   assert(not ok, "a file that is not formatted fails the check")
   assert(lines(out) == "src/messy.nupp",
      "and only it is named: " .. lines(out))
   assert(readFile(dir .. "/src/messy.nupp") == UNFORMATTED,
      "a check writes nothing")

   local clean, cleanOk = run(dir, "fmt --check src/tidy.nupp")
   assert(cleanOk and clean == "",
      "a formatted file passes quietly: " .. clean)

   -- Reaches outside the include roots, because it was named.
   local outside, outsideOk = run(dir, "fmt --check examples/demo.nupp")
   assert(not outsideOk and lines(outside) == "examples/demo.nupp",
      "a named file is checked wherever it is: " .. lines(outside))
   os.execute("rm -rf '" .. dir .. "'")
end

-- With nothing named it is the project, which is what the bare form already
-- did; saying so explicitly is what a build script wants to read.
function M.checkWithNoFilesIsTheProject()
   local dir = tempProject({
      ["nupp.lua"] = 'return { include = { "src" } }\n',
      ["src/messy.nupp"] = UNFORMATTED,
   })
   local out, ok = run(dir, "fmt --check")
   assert(not ok and lines(out) == "src/messy.nupp",
      "the project is checked: " .. lines(out))
   assert(readFile(dir .. "/src/messy.nupp") == UNFORMATTED, "and untouched")
   os.execute("rm -rf '" .. dir .. "'")
end

-- One fixes the formatting and the other reports it, so asking for both is
-- refused rather than resolved in whichever order the flags were read.
function M.checkAndWriteTogetherAreRefused()
   local dir = tempProject({
      ["nupp.lua"] = 'return { include = { "src" } }\n',
      ["src/messy.nupp"] = UNFORMATTED,
   })
   local out, ok = run(dir, "fmt --check -w")
   assert(not ok, "the combination is refused")
   assert(out:find("opposite", 1, true), "and says why: " .. out)
   assert(readFile(dir .. "/src/messy.nupp") == UNFORMATTED,
      "with nothing written on the way out")
   os.execute("rm -rf '" .. dir .. "'")
end

-- A file that does not parse is reported and nothing is written, whether it was
-- named or reached through the project.
function M.refusesToFormatWhatItCannotParse()
   local broken = "local x = = 1\n"
   local dir = tempProject({
      ["nupp.lua"] = 'return { include = { "src" } }\n',
      ["src/broken.nupp"] = broken,
      ["src/messy.nupp"] = UNFORMATTED,
   })
   local out, ok = run(dir, "fmt -w")
   assert(not ok, "a project with a file that does not parse fails")
   assert(out:find("broken.nupp", 1, true),
      "and says which file: " .. out)
   assert(readFile(dir .. "/src/broken.nupp") == broken,
      "the broken file is left exactly as it is")
   assert(readFile(dir .. "/src/messy.nupp") == FORMATTED,
      "and the rest of the project is still formatted")
   os.execute("rm -rf '" .. dir .. "'")
end

return M
