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
-- With the store where the project keeps it. This suite is about that store --
-- what a warm run reuses, and what a damaged file costs -- so it has to be the
-- one the run reads, not whichever shared directory the whole test run named.
local function run(dir, argv)
   local outfile = os.tmpname()
   local status = os.execute(("cd '%s' && NUPP_CACHE_DIR= '%s' %s > '%s' 2>&1")
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

-- A method call left in its sugar form gets its parens back by default, and
-- keeps them however many times it is formatted again.
function M.addsMethodCallParensByDefault()
   local dir = tempProject({
      ["nupp.lua"] = 'return { include = { "src" } }\n',
      ["src/sugar.nupp"] = "obj:m{a = 1}\n",
   })
   local out, ok = run(dir, "fmt -w")
   assert(ok, "formatting succeeds: " .. out)
   assert(readFile(dir .. "/src/sugar.nupp") == "obj:m({a = 1})\n",
      "the sugar-form call gains its parens")

   local again, againOk = run(dir, "fmt --check")
   assert(againOk and again == "",
      "and formatting it again changes nothing: " .. again)
   os.execute("rm -rf '" .. dir .. "'")
end

-- --no-method-parens turns that off, leaving the sugar as written.
function M.noMethodParensLeavesTheSugarAlone()
   local dir = tempProject({
      ["nupp.lua"] = 'return { include = { "src" } }\n',
      ["src/sugar.nupp"] = "obj:m{a = 1}\n",
   })
   local out, ok = run(dir, "fmt --check --no-method-parens")
   assert(ok and out == "",
      "already-formatted sugar passes the check: " .. out)
   os.execute("rm -rf '" .. dir .. "'")
end

-- A manifest can turn it off for the whole project, without a flag on every
-- invocation.
function M.manifestCanTurnMethodParensOffProjectWide()
   local dir = tempProject({
      ["nupp.lua"] = 'return { include = { "src" }, '
         .. 'fmt = { methodParens = false } }\n',
      ["src/sugar.nupp"] = "obj:m{a = 1}\n",
   })
   local out, ok = run(dir, "fmt --check")
   assert(ok and out == "",
      "the manifest default leaves the sugar formatted: " .. out)
   os.execute("rm -rf '" .. dir .. "'")
end

-- --no-method-parens is redundant over that manifest, but not a conflict.
function M.noMethodParensAgreesWithAManifestThatAlreadySaysSo()
   local dir = tempProject({
      ["nupp.lua"] = 'return { include = { "src" }, '
         .. 'fmt = { methodParens = false } }\n',
      ["src/sugar.nupp"] = "obj:m{a = 1}\n",
   })
   local out, ok = run(dir, "fmt --check --no-method-parens")
   assert(ok and out == "", "still passes: " .. out)
   os.execute("rm -rf '" .. dir .. "'")
end

local WIDE_SIGNATURE = "function addAndDouble(firstNumber: integer, secondNumber: integer): integer\n"
   .. "    return (firstNumber + secondNumber) * 2\n"
   .. "end\n"

-- --width changes the column a line breaks past, and what counts as formatted moves
-- with it: a line that fits at the default 120 and is left alone there breaks once
-- asked to fit 60, and the broken form is then what --check wants back.
function M.widthBreaksALineOverTheGivenWidth()
   local dir = tempProject({
      ["nupp.lua"] = 'return { include = { "src" } }\n',
      ["src/wide.nupp"] = WIDE_SIGNATURE,
   })
   local atDefault, defaultOk = run(dir, "fmt --check")
   assert(defaultOk and atDefault == "",
      "the signature already fits 120 columns: " .. atDefault)

   local narrow, narrowOk = run(dir, "fmt --width 60 --check")
   assert(not narrowOk and narrow:find("wide.nupp", 1, true),
      "the same signature does not fit 60: " .. narrow)

   local out, ok = run(dir, "fmt --width 60 -w")
   assert(ok, "formatting at width 60 succeeds: " .. out)
   assert(readFile(dir .. "/src/wide.nupp") ~= WIDE_SIGNATURE,
      "the parameter list broke onto its own lines")

   local stillNarrow, stillNarrowOk = run(dir, "fmt --width 60 --check")
   assert(stillNarrowOk and stillNarrow == "",
      "and formatting it again at width 60 changes nothing: " .. stillNarrow)

   local nowDefault, nowDefaultOk = run(dir, "fmt --check")
   assert(not nowDefaultOk and nowDefault:find("wide.nupp", 1, true),
      "but the width-60 form is not the width-120 form: " .. nowDefault)
   os.execute("rm -rf '" .. dir .. "'")
end

function M.widthRejectsATooSmallValue()
   local dir = tempProject({
      ["nupp.lua"] = 'return { include = { "src" } }\n',
      ["src/x.nupp"] = FORMATTED,
   })
   local out, ok = run(dir, "fmt --width 5 --check")
   assert(not ok, "a width under 20 is refused")
   assert(out:find("at least 20", 1, true), "and says why: " .. out)
   os.execute("rm -rf '" .. dir .. "'")
end

function M.widthRejectsANonNumericValue()
   local dir = tempProject({
      ["nupp.lua"] = 'return { include = { "src" } }\n',
      ["src/x.nupp"] = FORMATTED,
   })
   local out, ok = run(dir, "fmt --width columns --check")
   assert(not ok, "a non-numeric width is refused")
   assert(out:find("whole number", 1, true), "and says why: " .. out)
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

-- Asking twice has to give the same answer as asking once, because the second
-- ask does not format anything: whether a file already formats to itself is
-- kept between runs. Both answers are kept, which is the half worth testing --
-- a project that is unformatted is the normal case for a gate, and the run
-- that says so must go on saying so.
function M.theProjectAnswerIsTheSameWarmAsCold()
   local dir = tempProject({
      ["nupp.lua"] = 'return { include = { "src" } }\n',
      ["src/messy.nupp"] = UNFORMATTED,
      ["src/tidy.nupp"] = FORMATTED,
   })
   local cold, coldOk = run(dir, "fmt")
   local warm, warmOk = run(dir, "fmt")
   assert(not coldOk and not warmOk, "both runs fail on an unformatted project")
   assert(lines(cold) == lines(warm),
      ("warm answer differs from cold:\n  cold: %s\n  warm: %s")
      :format(lines(cold), lines(warm)))
   assert(lines(warm) == "src/messy.nupp", "and it is the right answer")

   -- Fixing the file has to be noticed, which is the failure a stored verdict
   -- would otherwise cause: the answer is keyed on the bytes, so new bytes
   -- are a new question.
   local fixed = assert(io.open(dir .. "/src/messy.nupp", "wb"))
   fixed:write(FORMATTED)
   fixed:close()
   local after, afterOk = run(dir, "fmt")
   assert(afterOk, "a formatted project passes: " .. after)

   -- And breaking one again is noticed too.
   local broken = assert(io.open(dir .. "/src/tidy.nupp", "wb"))
   broken:write(UNFORMATTED)
   broken:close()
   local again, againOk = run(dir, "fmt")
   assert(not againOk, "breaking a file fails again")
   assert(lines(again) == "src/tidy.nupp", "and names it: " .. lines(again))

   -- A damaged store is a slow run, never a wrong one.
   local damaged = assert(io.open(dir .. "/build/cache/format.buf", "wb"))
   damaged:write("not a buffer")
   damaged:close()
   local corrupt, corruptOk = run(dir, "fmt")
   assert(not corruptOk and lines(corrupt) == "src/tidy.nupp",
      "a damaged store gives the same answer: " .. lines(corrupt))

   os.execute("rm -rf '" .. dir .. "'")
end

-- `--write` cannot act on a stored "not formatted": it needs the formatted
-- bytes, which a verdict is not. It has to format the file anyway.
function M.writeStillRewritesAFileAlreadyKnownToBeUnformatted()
   local dir = tempProject({
      ["nupp.lua"] = 'return { include = { "src" } }\n',
      ["src/messy.nupp"] = UNFORMATTED,
   })
   local _, reportedOk = run(dir, "fmt")
   assert(not reportedOk, "the verdict is recorded by the reporting run")
   local out, ok = run(dir, "fmt -w")
   assert(ok, "writing succeeds: " .. out)
   assert(readFile(dir .. "/src/messy.nupp") == FORMATTED,
      "and the file is actually rewritten, not merely known to be wrong")
   os.execute("rm -rf '" .. dir .. "'")
end

return M
