-- Narrowing through paths, discriminated unions, literal types, and the
-- strict-mode module boundary.
local parser = require("nupp.parser")
local check = require("fragment")
local envMod = require("nupp.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function diagsOf(src, opts)
   local result = parser.parse(src, "test")
   assertEq(#result.errors, 0, "syntax: "
      .. (result.errors[1] and result.errors[1].msg or ""))
   local out = {}
   for j, d in ipairs(check.check(result, "test", env, opts)) do
      out[j] = d.code .. ":" .. d.line
   end
   return table.concat(out, " ")
end

local function assertClean(src, opts)
   assertEq(diagsOf(src, opts), "", "expected clean:\n" .. src)
end

local CFG = table.concat({
   "local record Cfg",
   "    port: number?",
   "    name: string",
   "end",
}, "\n")

local M = {}

function M.nilChecksNarrowThroughFieldPaths()
   assertClean(CFG .. table.concat({
      "",
      "local c: Cfg = new Cfg {}",
      "if c.port ~= nil then",
      "    local p: number = c.port",
      "end",
   }, "\n"))
   -- and outside the guard the field is still optional
   assertEq(diagsOf(CFG .. "\nlocal c: Cfg = new Cfg {}\nlocal p: number = c.port"),
      "NUPP2001:6")
end

function M.narrowingSurvivesTheElseBranch()
   assertClean(CFG .. table.concat({
      "",
      "local c: Cfg = new Cfg {}",
      "if c.port == nil then",
      "else",
      "    local p: number = c.port",
      "end",
   }, "\n"))
end

function M.assignmentForgetsWhatWasNarrowed()
   -- writing through the path invalidates the refinement
   assertEq(diagsOf(CFG .. table.concat({
      "",
      "local c: Cfg = new Cfg {}",
      "if c.port ~= nil then",
      "    c.port = nil",
      "    local p: number = c.port",
      "end",
   }, "\n")), "NUPP2001:8")
end

local SHAPE = "local s: {tag: 'circle', r: number} | {tag: 'rect', w: number}"

function M.literalTypesAreWritableInAnnotations()
   assertClean("local t: 'circle' = 'circle'")
   assertEq(diagsOf("local t: 'circle' = 'square'"), "NUPP2001:1")
end

function M.discriminantNarrowsAUnionOfShapes()
   assertClean(SHAPE .. table.concat({
      "",
      "if s.tag == 'circle' then",
      "    local r: number = s.r",
      "else",
      "    local w: number = s.w",
      "end",
   }, "\n"))
   -- the member field is not reachable without narrowing
   assertEq(diagsOf(SHAPE .. "\nlocal r: number = s.r"), "NUPP2004:2")
end

function M.discriminantInvertsForInequality()
   assertClean(SHAPE .. table.concat({
      "",
      "if s.tag ~= 'circle' then",
      "    local w: number = s.w",
      "else",
      "    local r: number = s.r",
      "end",
   }, "\n"))
end

function M.fieldsCommonToEveryMemberAreReadable()
   -- the discriminant itself is reachable before any narrowing
   assertClean(SHAPE .. "\nlocal t: string = s.tag")
end

function M.numberLiteralsCarryTheirValue()
   assertClean("local n: number = 1")
   assertClean("local i: integer = 1")
   -- an inferred binding still holds a number, not that one number
   assertClean("local n = 1\nn = 2")
   -- arithmetic is unaffected by literal types
   assertClean("local i: integer = 1 + 2")
   assertClean("local f: number = 1 / 2")
end

function M.strictModeRequiresTypedExports()
   local src = table.concat({
      "local function typed(n: number): number",
      "    return n",
      "end",
      "local function loose(n)",
      "    return n",
      "end",
      "return {typed = typed, loose = loose}",
   }, "\n")
   assertClean(src)
   assertEq(diagsOf(src, {strict = true}), "NUPP2106:7")
   -- a fully annotated boundary passes
   assertClean(table.concat({
      "local function typed(n: number): number",
      "    return n",
      "end",
      "return {typed = typed}",
   }, "\n"), {strict = true})
end

-- Each conjunct of an `and` is only reached when the ones before it held, so
-- it is checked knowing that. The condition ending in a bare call is the case
-- that used to get this wrong: inferring the chain narrowed, but analyzing
-- what it proved did not, and the call's arguments were checked as though
-- nothing had been tested.
function M.narrowingReachesLaterConjuncts()
   local decl = table.concat({
      "local record P",
      "    tag: 'p'",
      "end",
      "local record F",
      "    tag: 'f'",
      "    extra: U?",
      "end",
      "local type U = P | F",
      "local function pair(v: U, w: U): boolean",
      "    return v == w",
      "end",
   }, "\n")
   assertClean(decl .. "\n" .. table.concat({
      "local function f(a: U, b: U): boolean",
      "    if a.tag == 'f' and b.tag == 'f' then",
      "        if a.extra and b.extra and not pair(b.extra, a.extra) then",
      "            return false",
      "        end",
      "    end",
      "    return true",
      "end",
   }, "\n"))
   -- the same through plain locals, and through `or` on its falsy side
   assertClean(table.concat({
      "local function use(x: number, y: number): number",
      "    return x + y",
      "end",
      "local function f(a: number?, b: number?): number",
      "    if a and b and use(a, b) > 0 then return 1 end",
      "    if not a or not b or use(a, b) > 0 then return 2 end",
      "    return 0",
      "end",
   }, "\n"))
end

-- A helper that always throws leaves the branch it stands in, so a guard
-- clause keeps narrowing when it is spelled as a call rather than inline.
function M.noreturnHelperGuardsLikeError()
   assertClean(table.concat({
      "local function fail(msg: string)",
      "    error(msg)",
      "end",
      "local function use(x: string?)",
      "    if not x then fail('no x') end",
      "    print(#x)",
      "end",
      "return {use = use}",
   }, "\n"))
   -- every arm of a complete chain raising counts too
   assertClean(table.concat({
      "local function fail(msg: string)",
      "    if msg == '' then",
      "        error('empty')",
      "    else",
      "        error(msg)",
      "    end",
      "end",
      "local function use(x: string?)",
      "    if not x then fail('no x') end",
      "    print(#x)",
      "end",
      "return {use = use}",
   }, "\n"))
end

-- A function that can return is not noreturn, however it ends.
function M.noreturnIsNotInferredWhenAPathReturns()
   assertEq(diagsOf(table.concat({
      "local function maybe(msg: string): integer",
      "    if msg == '' then return 0 end",
      "    error(msg)",
      "end",
      "local function use(x: string?)",
      "    if not x then maybe('no x') end",
      "    print(#x)",
      "end",
      "return {use = use}",
   }, "\n")), "NUPP2003:7")
end

-- A declared `never` return says what the checker cannot see, and is refused
-- where it plainly contradicts the body.
function M.declaredNeverReturn()
   assertClean(table.concat({
      "local function bail(code: integer): never",
      "    print(code)",
      "    error('bail')",
      "end",
      "local function use(x: string?)",
      "    if x == nil then bail(1) end",
      "    print(#x)",
      "end",
      "return {use = use}",
   }, "\n"))
   assertEq(diagsOf(table.concat({
      "local function claims(x: integer): never",
      "    if x > 0 then return x end",
      "    error('no')",
      "end",
      "return {claims = claims}",
   }, "\n")), "NUPP2002:2")
end

-- The prelude declares `error` itself as returning `never`, not through an
-- annotation. `never` fits any declared return, which is what lets `return
-- error(...)` satisfy a typed result in one line -- previously a type error,
-- since a call to the old zero-result signature typed as `nil`.
function M.errorItselfReturnsNever()
   assertClean(table.concat({
      "local function pick(s: string?): string",
      "    if s then return s end",
      "    return error('missing')",
      "end",
      "return {pick = pick}",
   }, "\n"))
end

-- `{}` is `table`, which is gradual toward every table structure. Beside one in a
-- union it therefore says nothing that member does not, and a union carrying it is
-- one no field can be read from. Defaulting a declared binding -- the `x = x or {}`
-- every optional parameter is written with -- is what reaches this.
function M.defaultingADeclaredTableKeepsItsStructure()
   local OPTS = "local type Opts = {output: string?, title: string?}\n"
   -- assigned back to the parameter, alone and among several targets
   assertClean(OPTS .. table.concat({
      "local function run(opts: Opts?): string?",
      "    opts = opts or {}",
      "    return opts.output",
      "end",
      "return {run = run}",
   }, "\n"))
   assertClean(OPTS .. table.concat({
      "local function run(root: string?, opts: Opts?): string?",
      "    root, opts = root or '.', opts or {}",
      "    return opts.output or root",
      "end",
      "return {run = run}",
   }, "\n"))
   -- and written as the branch that defaults it, where the join is what unions
   assertClean(OPTS .. table.concat({
      "local function run(opts: Opts?): string?",
      "    if not opts then",
      "        opts = {}",
      "    end",
      "    return opts.output",
      "end",
      "return {run = run}",
   }, "\n"))
   -- an array reached the same way, and an element read off it
   assertClean(table.concat({
      "local function first(items: {string}?): string?",
      "    items = items or {}",
      "    return items[1]",
      "end",
      "return {first = first}",
   }, "\n"))
   -- what the collapse must not do: a literal with fields still narrows a
   -- variable declared as a plain table
   assertClean(table.concat({
      "local t: table = {}",
      "t = {a = 1}",
      "local n: integer = t.a",
   }, "\n"))
end

return M
