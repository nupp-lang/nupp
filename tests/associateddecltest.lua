-- Declaration checking for associated types.
--
-- Two passes over the body: the names are predeclared and their collisions refused
-- before anything resolves, and conformance runs once every member is known. That is
-- what makes a body order-independent -- both for a member naming one, and for a
-- collision, which has to report the same either way round.
local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function codes(source)
   env.loaded = {}
   local parsed = parser.parse(source, "test.g.nupp")
   assertEq(#parsed.errors, 0, "syntax: "
      .. (parsed.errors[1] and parsed.errors[1].msg or ""))
   local out = {}
   for j, d in ipairs(check.check(parsed, "test.g.nupp", env)) do
      out[j] = d.code
   end
   return table.concat(out, " ")
end

local function src(...)
   return table.concat({...}, "\n") .. "\n"
end

local function clean(source)
   assertEq(codes(source), "", "expected clean check for:\n" .. source)
end

local function reports(source, want)
   assertEq(codes(source), want, "for:\n" .. source)
end

local READER = src(
   "local interface Named",
   "   name: string",
   "end",
   "local interface Reader",
   "   associated type Item",
   "   associated type Error = string",
   "end")

local M = {}

function M.anAnswerSatisfiesItsContract()
   clean(READER .. src(
      "local record Lines is Reader",
      "   associated type Item = string",
      "end",
      "return Lines"))
end

function M.anExplicitAnswerReplacesAnInheritedDefault()
   clean(READER .. src(
      "local record Lines is Reader",
      "   associated type Item = string",
      "   associated type Error = integer",
      "end",
      "return Lines"))
end

function M.anInterfaceIsNotHeldToItsInheritedRequirements()
   clean(READER .. src(
      "local interface Buffered is Reader",
      "end",
      "return Buffered"))
end

function M.aMissingTransitiveRequirementReports()
   reports(READER .. src(
      "local interface Buffered is Reader",
      "end",
      "local record Slow is Buffered",
      "end",
      "return Slow"), "NUPP2127")
end

function M.aRequirementOutsideAnInterfaceReports()
   reports(src(
      "local record Box",
      "   associated type Item",
      "end",
      "return Box"), "NUPP2128")
end

function M.anAnswerForNoContractReports()
   reports(src(
      "local record Box",
      "   associated type Item = string",
      "end",
      "return Box"), "NUPP2128")
end

function M.anAnswerMayNotRestateTheBound()
   reports(READER .. src(
      "local record Lines is Reader",
      "   associated type Item is Named = string",
      "end",
      "return Lines"), "NUPP2128")
end

function M.aDefaultMustFitItsOwnBound()
   reports(src(
      "local interface Named",
      "   name: string",
      "end",
      "local interface Tagged",
      "   associated type Tag is Named = integer",
      "end",
      "return Tagged"), "NUPP2116")
end

function M.anAnswerMustFitEveryInheritedBound()
   local contracts = src(
      "local interface Named",
      "   name: string",
      "end",
      "local interface Counted",
      "   count: integer",
      "end",
      "local interface A",
      "   associated type Item is Named",
      "end",
      "local interface B",
      "   associated type Item is Counted",
      "end")
   reports(contracts .. src(
      "local record Half is A, B",
      "   associated type Item = Named",
      "end",
      "return Half"), "NUPP2116")
   clean(contracts .. src(
      "local interface Both is Named, Counted",
      "   name: string",
      "   count: integer",
      "end",
      "local record Whole is A, B",
      "   associated type Item = Both",
      "end",
      "return Whole"))
end

function M.conflictingDefaultsNeedAnExplicitAnswer()
   local contracts = src(
      "local interface A",
      "   associated type Item = string",
      "end",
      "local interface B",
      "   associated type Item = integer",
      "end")
   reports(contracts .. src(
      "local record Taker is A, B",
      "end",
      "return Taker"), "NUPP2127")
   clean(contracts .. src(
      "local record Taker is A, B",
      "   associated type Item = string",
      "end",
      "return Taker"))
end

function M.aStructMayAnswerARequirement()
   clean(src(
      "local interface Sized",
      "   associated type Unit",
      "end",
      "local struct Vec is Sized",
      "   associated type Unit = float",
      "   x: float",
      "end",
      "return Vec"))
end

-- Collisions. All of these are one namespace saying two things.
function M.duplicateAssociatedNamesReport()
   reports(src(
      "local interface Reader",
      "   associated type Item",
      "   associated type Item",
      "end",
      "return Reader"), "NUPP2129")
   reports(src(
      "local interface Reader",
      "   associated type Item",
      "   associated type Item = string",
      "end",
      "return Reader"), "NUPP2129")
   reports(READER .. src(
      "local record Lines is Reader",
      "   associated type Item = string",
      "   associated type Item = integer",
      "end",
      "return Lines"), "NUPP2129")
end

function M.anAssociatedNameCollidesWithATypeMemberEitherWayRound()
   reports(src(
      "local interface Reader",
      "   type Item = string",
      "   associated type Item",
      "end",
      "return Reader"), "NUPP2129")
   reports(src(
      "local interface Reader",
      "   associated type Item",
      "   type Item = string",
      "end",
      "return Reader"), "NUPP2129")
   reports(src(
      "local interface Reader",
      "   associated type Item",
      "   record Item",
      "      x: integer",
      "   end",
      "end",
      "return Reader"), "NUPP2129")
end

-- Types and values are separate namespaces already, and this changes nothing there.
function M.aFieldMayShareTheSpelling()
   clean(READER .. src(
      "local record Lines is Reader",
      "   associated type Item = string",
      "   Item: integer",
      "end",
      "return Lines"))
end

-- The two passes exist so a body reads the same in either order.
function M.conformanceDoesNotDependOnOrder()
   clean(READER .. src(
      "local record Lines is Reader",
      "   count: integer",
      "   associated type Item = string",
      "end",
      "return Lines"))
   clean(READER .. src(
      "local record Lines is Reader",
      "   associated type Item = string",
      "   count: integer",
      "end",
      "return Lines"))
   -- and a declaration written before the contract it takes
   clean(src(
      "local interface Reader",
      "   associated type Item",
      "end",
      "local record Lines is Reader",
      "   associated type Item = string",
      "end",
      "return Lines"))
end

-- `= self` in both shapes. Whether it resolves to the implementor is item 4's to
-- assert; what conformance has to say now is that the copied default answers.
function M.selfDefaultsAnswerForEveryImplementor()
   local contract = src(
      "local interface Holds",
      "   associated type Value = self",
      "end")
   clean(contract .. src(
      "local record Plain is Holds",
      "   count: integer",
      "end",
      "return Plain"))
   clean(contract .. src(
      "local record Boxed<T> is Holds",
      "   held: T",
      "end",
      "return Boxed"))
   -- and an implementor may still answer otherwise
   clean(contract .. src(
      "local record Otherwise is Holds",
      "   associated type Value = string",
      "end",
      "return Otherwise"))
end

-- A generic interface's requirement is owed by whatever takes it.
function M.aGenericInterfaceStillOwesItsAnswer()
   local contract = src(
      "local interface Source<K>",
      "   associated type Item",
      "   key: K",
      "end")
   reports(contract .. src(
      "local record Silent is Source<string>",
      "   key: string",
      "end",
      "return Silent"), "NUPP2127")
   clean(contract .. src(
      "local record Answered is Source<string>",
      "   key: string",
      "   associated type Item = integer",
      "end",
      "return Answered"))
end

-- Associated types settle before any member is read, so what a declaration means does
-- not depend on the order it was written in. The method here is checked against
-- `self.Item`, which is the answer written beside it -- before it in one and after it
-- in the other.
function M.aMemberSeesTheAnswerWhereverItSits()
   local contract = src(
      "local interface Reader",
      "   associated type Item",
      "end")
   local wrongEarly = contract .. src(
      "local record Early is Reader",
      "   function read(self): self.Item",
      "      return 42",
      "   end",
      "   associated type Item = string",
      "end",
      "return Early")
   local wrongLate = contract .. src(
      "local record Late is Reader",
      "   associated type Item = string",
      "   function read(self): self.Item",
      "      return 42",
      "   end",
      "end",
      "return Late")
   assertEq(codes(wrongEarly), codes(wrongLate), "the two orders disagree")
   assertEq(codes(wrongEarly), "NUPP2002", "the answer was not in force")
   clean(contract .. src(
      "local record Early is Reader",
      "   function read(self): self.Item",
      "      return 'x'",
      "   end",
      "   associated type Item = string",
      "end",
      "return Early"))
   clean(contract .. src(
      "local record Late is Reader",
      "   associated type Item = string",
      "   function read(self): self.Item",
      "      return 'x'",
      "   end",
      "end",
      "return Late"))
end

-- Resolution asks the query rather than assuming a binder is a namespace.
function M.aProjectionIsOnlyATypeWhenSomethingStatesIt()
   reports(src(
      "local function stray<T>(x: T): T.Item",
      "   return nil as any",
      "end",
      "return stray"), "NUPP2134")
   reports(src(
      "local interface Reader",
      "   associated type Item",
      "end",
      "local function missing<T is Reader>(x: T): T.Missing",
      "   return nil as any",
      "end",
      "return missing"), "NUPP2134")
   -- a stated one is a type, and stays opaque while the head is a contract
   clean(src(
      "local interface Reader",
      "   associated type Item",
      "end",
      "local function held<T is Reader>(x: T): T.Item",
      "   return nil as any",
      "end",
      "return held"))
end

-- A concrete declaration answers through `associatedAnswers`; a nested alias of the
-- same name answers nothing.
function M.aPathReachesTheAnswerAndNotAnAlias()
   clean(src(
      "local interface Reader",
      "   associated type Item",
      "end",
      "local record Lines is Reader",
      "   associated type Item = string",
      "end",
      "local held: Lines.Item = 'x'",
      "return held"))
   reports(src(
      "local interface Reader",
      "   associated type Item",
      "end",
      "local record Lines is Reader",
      "   associated type Item = string",
      "end",
      "local held: Lines.Item = 42",
      "return held"), "NUPP2001")
end

return M
