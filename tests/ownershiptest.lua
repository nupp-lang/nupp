local parser = require("nupp.compiler.parser")
local check = require("fragment")
local gen = require("nupp.compiler.gen")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function checked(source, opts)
   local result = parser.parse(source, "ownership-test.g.nupp")
   assertEq(#result.errors, 0, "syntax: "
      .. (result.errors[1] and result.errors[1].msg or ""))
   local diags = check.check(result, "ownership-test.g.nupp", env, opts)
   return result, diags
end

local function codes(source)
   local _, diags = checked(source)
   local out = {}
   for _, diag in ipairs(diags) do out[#out + 1] = diag.code end
   return table.concat(out, " ")
end

local function assertClean(source)
   local _, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
end

local RESOURCE = table.concat({
   "cdef struct resource",
   "   value: int32",
   "end",
   "cdef function resource_create(): resource*",
   "cdef function resource_free(takes value: resource*)",
   "local function resource_new(): affine(resource*, resource_free)",
   "   return resource_create()",
   "end",
}, "\n")

local M = {}

-- The arms of a branch are alternatives, so an owner discharged on one is not
-- discharged on its sibling. A narrowed binding shares its declaration's ownership
-- state, which used to make the first arm's move visible in the second and report
-- the second as a use after move.
function M.everyArmOfABranchDischargesIndependently()
   assertClean(table.concat({
      RESOURCE,
      "local function twoArms(flag: boolean): nil",
      "   local value = resource_new()",
      "   if flag then",
      "      drop(value)",
      "   else",
      "      drop(value)",
      "   end",
      "end",
   }, "\n"))

   assertClean(table.concat({
      RESOURCE,
      "local function chain(n: integer): nil",
      "   local value = resource_new()",
      "   if n == 1 then",
      "      drop(value)",
      "   elseif n == 2 then",
      "      drop(value)",
      "   else",
      "      drop(value)",
      "   end",
      "end",
   }, "\n"))
end

-- The independence is per arm, not a licence to discharge twice: a second move on
-- the same path, and a use after the statement, both still report.
function M.branchIndependenceStillCatchesADoubleMove()
   assertEq(codes(table.concat({
      RESOURCE,
      "local function twice(flag: boolean): nil",
      "   local value = resource_new()",
      "   if flag then",
      "      drop(value)",
      "      drop(value)",
      "   end",
      "end",
   }, "\n")), "NUPP2601", "a second move on one path still reports")

   assertEq(codes(table.concat({
      RESOURCE,
      "local function afterwards(flag: boolean): nil",
      "   local value = resource_new()",
      "   if flag then",
      "      drop(value)",
      "   else",
      "      drop(value)",
      "   end",
      "   drop(value)",
      "end",
   }, "\n")), "NUPP2601", "a move after every arm moved still reports")
end

function M.scalarGenericPreservationTransfersAnOwner()
   assertClean(table.concat({
      RESOURCE,
      "local function id<T>(takes value: T): T preserves value",
      "   return value",
      "end",
      "local value = resource_new()",
      "local forwarded = id(value)",
      "drop(forwarded)",
   }, "\n"))
end

function M.scalarGenericPreservationMovesItsInputExactlyOnce()
   assertEq(codes(table.concat({
      RESOURCE,
      "local function id<T>(takes value: T): T preserves value",
      "   return value",
      "end",
      "local value = resource_new()",
      "local forwarded = id(value)",
      "print(value)",
      "drop(forwarded)",
   }, "\n")), "NUPP2601")
end

function M.genericPreservationAgreesAcrossBranchSpecificReturns()
   assertClean(table.concat({
      RESOURCE,
      "local function id<T>(takes value: T): T preserves value return value end",
      "local function choose<T>(takes value: T, flag: boolean): T preserves value",
      "   if flag then",
      "      return value",
      "   else",
      "      return id(value)",
      "   end",
      "end",
      "local forwarded = choose(resource_new(), true)",
      "drop(forwarded)",
   }, "\n"))
end

function M.fixedPackPreservationCarriesTheExactResultSlot()
   assertClean(table.concat({
      RESOURCE,
      "local function label<T>(takes value: T): (string, T preserves value)",
      "   return 'resource', value",
      "end",
      "local name, forwarded = label(resource_new())",
      "print(name)",
      "drop(forwarded)",
   }, "\n"))
end

function M.genericPreservationMovesCapabilitiesIntoAggregateResults()
   assertClean(table.concat({
      RESOURCE,
      "local record Box<T>",
      "   value: T",
      "end",
      "local function box<T>(takes value: T): Box<T> preserves value",
      "   return new Box(value = value)",
      "end",
      "local boxed = box(resource_new())",
      "drop(boxed)",
   }, "\n"))

   assertEq(codes(table.concat({
      "local record Pair<T>",
      "   left: T",
      "   right: T",
      "end",
      "local function ambiguous<T>(takes value: T): Pair<T> preserves value",
      "   return new Pair(left = value, right = value)",
      "end",
   }, "\n")), "NUPP2606 NUPP2602", "a relation cannot guess between repeated components or duplicate a move")
end

function M.genericPreservationReducesIdentityMappedResults()
   assertClean(table.concat({
      "local type View<T> = {readonly [K in keyof T]: T.[K]}",
      "local record Box<T>",
      "   value: T",
      "end",
      "local function box<T>(takes value: T): View<Box<T>> preserves value",
      "   return new Box(value = value)",
      "end",
      RESOURCE,
      "local boxed = box(resource_new())",
      "drop(boxed)",
   }, "\n"))
end

function M.callableAssignmentCannotEraseAPreservationRelation()
   assertEq(codes(table.concat({
      "local function preserving<T>(takes value: T): T preserves value",
      "   return value",
      "end",
      "local plain: function<T>(takes value: T): T = preserving",
      "print(plain)",
   }, "\n")), "NUPP2001")
end

function M.assertPreservesAndNarrowsAnOptionalOwner()
   assertClean(table.concat({
      RESOURCE,
      "local function cleanup(takes value: resource*): nil end",
      "cdef function maybe_resource_c(): resource*?",
      "local function maybe_resource(): affine(resource*?, cleanup)",
      "   return maybe_resource_c()",
      "end",
      "local value = assert(maybe_resource())",
      "drop(value)",
   }, "\n"))
end

function M.assertingANamedOptionalOwnerKeepsItInPlace()
   local declaration = table.concat({
      RESOURCE,
      "local function cleanup(takes value: resource*): nil end",
      "cdef function maybe_resource_c(): resource*?",
      "local function maybe_resource(): affine(resource*?, cleanup)",
      "   return maybe_resource_c()",
      "end",
   }, "\n")
   assertClean(table.concat({
      declaration,
      "local value = maybe_resource()",
      "local present = assert(value, 'resource is required')",
      "drop(present)",
   }, "\n"))
   assertEq(codes(declaration .. "\nassert(maybe_resource())"), "NUPP2605")
end

function M.aPreservesBodyMustReturnTheNamedParameter()
   assertEq(codes(table.concat({
      "local function wrong<T>(takes value: T, other: T): T preserves value",
      "   return other",
      "end",
   }, "\n")), "NUPP2602")
end

function M.stringPointerProvenanceRejectsAnUnanchoredExpression()
   assertEq(codes(table.concat({
      "local pointer = ffi.cast<cstring>('a' .. 'b')",
   }, "\n")), "NUPP2501")
end

function M.stringPointerProvenanceFollowsBindingsAndPreservation()
   assertClean(table.concat({
      "local function id<T>(takes value: T): T preserves value",
      "   return value",
      "end",
      "local text = 'a' .. 'b'",
      "local direct = ffi.cast<cstring>(text)",
      "local forwarded = ffi.cast<cstring>(id(text))",
      "print(direct, forwarded)",
   }, "\n"))
end

function M.ffiGcCannotAttachASecondCleanupToAnOwner()
   assertEq(codes(table.concat({
      RESOURCE,
      "local value = resource_new()",
      "ffi.gc(value, resource_free)",
      "drop(value)",
   }, "\n")), "NUPP2603")
end

function M.anAliasedCFunctionKeepsItsForeignBoundary()
   assertEq(codes(table.concat({
      "cdef function inspect(value: voidptr)",
      "local indirect = inspect",
      "local raw = ffi.cast<voidptr>(8)",
      "indirect(raw)",
   }, "\n")), "NUPP2604")
end

function M.nominalRecordsCanRetainDeclaredBorrowedFields()
   assertClean(table.concat({
      "local record Buffer",
      "   value: string",
      "end",
      "local function closeBuffer(takes value: Buffer): nil end",
      "local function openBuffer(): affine(Buffer, closeBuffer)",
      "   return new Buffer(value = 'bytes')",
      "end",
      "local function view(borrows source: Buffer): Buffer borrows (source)",
      "   return source",
      "end",
      "local record Cursor",
      "   source: Buffer",
      "   bytes: Buffer borrows (source)",
      "end",
      "local source = openBuffer()",
      "do",
      "   local cursor = new Cursor(source = source, bytes = view(source))",
      "   print(cursor.bytes.value)",
      "end",
      "drop(source)",
   }, "\n"))
end

function M.aBorrowedFieldMustMatchItsDeclaredSiblingRoot()
   assertEq(codes(table.concat({
      "local record Buffer",
      "   value: string",
      "end",
      "local function view(borrows source: Buffer): Buffer borrows (source)",
      "   return source",
      "end",
      "local record Cursor",
      "   source: Buffer",
      "   bytes: Buffer borrows (source)",
      "end",
      "local left = new Buffer(value = 'left')",
      "local right = new Buffer(value = 'right')",
      "local cursor = new Cursor(source = left, bytes = view(right))",
   }, "\n")), "NUPP2619")
end

function M.aRecordCanOwnTheRootOfItsBorrowedField()
   assertClean(table.concat({
      RESOURCE,
      "local record Parsed",
      "   source: affine(resource*, resource_free)",
      "   view: resource* borrows (source)",
      "end",
      "local source = resource_new()",
      "local parsed = new Parsed(source = source, view = borrow(source))",
      "print(parsed.view.value)",
      "drop(parsed)",
   }, "\n"))
end

function M.anInternallyBorrowedRootFieldCannotMoveAlone()
   assertEq(codes(table.concat({
      RESOURCE,
      "local record Parsed",
      "   source: affine(resource*, resource_free)",
      "   view: resource* borrows (source)",
      "end",
      "local source = resource_new()",
      "local parsed = new Parsed(source = source, view = borrow(source))",
      "local detached = parsed.source",
      "drop(detached)",
      "drop(parsed)",
   }, "\n")), "NUPP2602")
end

function M.scopedCallbacksMayCaptureABorrow()
   assertClean(table.concat({
      RESOURCE,
      "local value = resource_new()",
      "do",
      "   local view = borrow(value)",
      "   pcall(function() borrows (view) print(view.value) end)",
      "end",
      "drop(value)",
   }, "\n"))
end

function M.callbackCapturesBorrowOwnersByDefault()
   assertClean(table.concat({
      RESOURCE,
      "local value = resource_new()",
      "pcall(function() print(value.value) end)",
      "drop(value)",
   }, "\n"))
end

function M.coroutineChildrenCannotCaptureAParentBorrow()
   assertEq(codes(table.concat({
      RESOURCE,
      "local suspension = require('nupp.suspension')",
      "local value = resource_new()",
      "do",
      "   local view = borrow(value)",
      "   local child = suspension.create(function() print(view.value) end)",
      "   coroutine.resume(child)",
      "end",
      "drop(value)",
   }, "\n")), "NUPP2603")
end

function M.cleanupContractsCannotSuspend()
   assertEq(codes(table.concat({
      "local record Resource value: integer end",
      "local function close(takes value: Resource)",
      "   coroutine.yield()",
      "end",
      "local function open(): affine(Resource, close)",
      "   return new Resource(value = 1)",
      "end",
      "local value = open()",
      "drop(value)",
   }, "\n")), "NUPP2603 NUPP2615 NUPP2701")
end

-- Parameter modes were read at the position the parameter takes in the function type,
-- which an inline method spelling `self` shifts by one. Every mode came from the
-- neighbour on its left: `takes` landed on the receiver and the argument arrived
-- borrowing, so a method that consumed an owner was checked as one that did not.
function M.anInlineMethodOwnsTheParameterItTakes()
   assertEq(codes(table.concat({
      RESOURCE,
      "local record Holder",
      "   count: integer",
      "   function keep(self, takes value: resource*): nil",
      "      self.count = self.count + 1",
      "   end",
      "end",
   }, "\n")), "NUPP2603")
end

-- The same body, discharging what it took. The receiver stays a borrow throughout:
-- shifting the modes the other way would consume `self` instead.
function M.anInlineMethodDischargesWhatItTakes()
   assertClean(table.concat({
      RESOURCE,
      "local record Holder",
      "   count: integer",
      "   function keep(self, takes value: resource*): nil",
      "      self.count = self.count + 1",
      "      resource_free(value)",
      "   end",
      "end",
   }, "\n"))
end

-- A qualified method reads its modes from the same source positions, and always did.
function M.aQualifiedMethodOwnsTheParameterItTakes()
   assertClean(table.concat({
      RESOURCE,
      "local record Holder",
      "   count: integer",
      "end",
      "function Holder.keep(self, takes value: resource*): nil",
      "   self.count = self.count + 1",
      "end",
   }, "\n"))
end

-- `unsafe release` lowers to its argument, so using it for the assertion rather than the
-- value left an expression where Lua wants a statement. The check and the build both
-- passed and the output would not load.
function M.aDiscardedOwnershipIntrinsicEmitsLoadableLua()
   local source = table.concat({
      RESOURCE,
      "local function spend(takes value: resource*): nil",
      "   unsafe do",
      "      local _raw = unsafe release value",
      "   end",
      "end",
      "return spend",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   local chunk, loadErr = loadstring(code, "@ownership-discarded-intrinsic")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
end

function M.managedGroupsUseOrdinaryLibraryCalls()
   local source = table.concat({
      RESOURCE,
      "local managed = require('nupp.managed')",
      "do",
      "   local group = managed.group()",
      "   local handle = group:adopt(nupp.manage(resource_new()))",
      "   local value = handle:with(function(borrows item) return item.value end)",
      "   print(value)",
      "end",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   assert(code:find("__nupp%.__manage%(") and code:find(":%s*adopt%s*%("),
      "managed custody must lower through ordinary manage and adopt calls:\n" .. code)
   assert(not code:find("__nuppAdopt"),
      "ManagedGroup must not receive a compiler-injected witness:\n" .. code)
end

function M.manageRejectsTransferOnlyOwners()
   assertEq(codes(table.concat({
      "local record Request",
      "   value: integer",
      "end",
      "local function beginRequest(): affine(Request) return new Request(value = 1) end",
      "local cell = nupp.manage(beginRequest())",
   }, "\n")), "NUPP2612")
end

function M.managedGroupsCanTransferARegistrationBackOutExactlyOnce()
   assertClean(table.concat({
      RESOURCE,
      "local managed = require('nupp.managed')",
      "do",
      "   local group = managed.group()",
      "   local handle = group:adopt(nupp.manage(resource_new()))",
      "   local returned = group:remove(handle)",
      "   drop(returned)",
      "end",
   }, "\n"))
end

function M.managedCellsCarryExactCleanupPoliciesBehindAliases()
   local source = table.concat({
      RESOURCE,
      "do",
      "   local owner = nupp.manage(resource_new())",
      "   local handle = owner:alias()",
      "   local returned, problem = handle:take()",
      "   assert(problem == nil)",
      "   drop(assert(returned))",
      "end",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   assert(code:find("__nupp%.__manage%([^,]+,__nuppManagedCleanup%d+,") ,
      "manage must receive its cleanup program and policy:\n" .. code)
   assert(code:find("const __nuppManagedCleanup%d+ = function%(__nuppV%)"),
      "managed cleanup must be declared once per policy:\n" .. code)
end

function M.managedCellsEnforceCustodyAtRuntime()
   local source = table.concat({
      "local cleaned = 0",
      "local record FileState value: integer end",
      "local function closeFile(takes file: FileState): nil",
      "   cleaned = cleaned + file.value",
      "end",
      "local function openFile(value: integer): affine(FileState, closeFile)",
      "   return new FileState(value = value)",
      "end",
      "local owner = nupp.manage(openFile(1))",
      "local handle = owner:alias()",
      "local stale = handle",
      "local erased: any = handle",
      "local recoveredAlias, recoveryProblem = nupp.recoverAlias(erased)",
      "assert(recoveryProblem == nil)",
      "if not recoveredAlias then error('recovery failed') end",
      "local recovered, policyProblem = recoveredAlias:downcast<affine(FileState, closeFile)>()",
      "assert(policyProblem == nil)",
      "if not recovered then error('downcast failed') end",
      "local file, takeProblem = recovered:take()",
      "assert(takeProblem == nil)",
      "if not file then error('take failed') end",
      "drop(file)",
      "local _, staleProblem = stale:with(function(borrows value) return value.value end)",
      "assert(staleProblem ~= nil)",
      "do local another = nupp.manage(openFile(2)) end",
      "return cleaned, staleProblem and staleProblem.code",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-dynamic-runtime")
   assertEq(#genDiags, 0, (genDiags[1] and genDiags[1].msg or "generate")
      .. "\n" .. code)
   local chunk, loadErr = loadstring(code, "@ownership-dynamic-runtime")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   local cleaned, staleCode = chunk()
   assertEq(cleaned, 3, "take and managed destruction each clean exactly once")
   assertEq(staleCode, "NUPP2614", "taking a cell tombstones every copied alias")
end

function M.managedCellsRejectCapabilitiesTheyCannotDischarge()
   assertEq(codes(table.concat({
      "local record Request value: integer end",
      "local function begin(): affine(Request) return new Request(value = 1) end",
      "local owner = nupp.manage(begin())",
   }, "\n")), "NUPP2612")
end

function M.dynamicErasureAndBorrowEscapesHaveDedicatedDiagnostics()
   assertEq(codes(table.concat({
      RESOURCE,
      "local value: any = resource_new()",
   }, "\n")), "NUPP2611")

   assertEq(codes(table.concat({
      RESOURCE,
      "local function leak(borrows value: resource*): resource*",
      "   return value",
      "end",
      "return leak",
   }, "\n")), "NUPP2608")
end

function M.loopBackEdgesCannotConsumeAnOuterCapabilityConditionally()
   local _, diags = checked(table.concat({
      RESOURCE,
      "local function run(flag: boolean): nil",
      "   local value = resource_new()",
      "   while flag do",
      "      drop(value)",
      "   end",
      "end",
   }, "\n"))
   assertEq(diags[1] and diags[1].code, "NUPP2609")
   assertEq(#(diags[1].related or {}), 1, "loop diagnostic names its back edge")
end

function M.generalRegionsDistinguishSiblingFieldsAndExactIndexes()
   local prelude = table.concat({
      "local record Pair",
      "   left: table",
      "   right: table",
      "end",
      "local function together(exclusive left: table, exclusive right: table): nil end",
      "local pair = new Pair(left = {}, right = {})",
   }, "\n")
   assertClean(prelude .. "\ntogether(pair.left, pair.right)")
   assertEq(codes(prelude .. "\ntogether(pair.left, pair.left)"), "NUPP2607")

   local indexed = table.concat({
      "local function together(exclusive left: table, exclusive right: table): nil end",
      "local values: {table} = {{}, {}}",
   }, "\n")
   assertClean(indexed .. "\ntogether(values[1], values[2])")
   assertEq(codes(indexed .. "\nlocal i: integer = 1\ntogether(values[i], values[i])"), "NUPP2607")
   assertEq(codes(indexed .. "\nlocal i: integer = 1\ntogether(values[i], values[1])"), "NUPP2607")
   assertEq(codes(indexed .. "\nlocal value = {}\ntogether(value, value)"), "NUPP2607")
end

function M.checkedRegionIntervalsProveOnlyActualDisjointness()
   local prelude = table.concat({
      "local function together(exclusive left: int32[?], exclusive right: int32[?]): nil end",
      "local values = ffi.new<int32[4]>()",
      "unsafe do",
   }, "\n")
   assertClean(prelude .. table.concat({
      "",
      "   local left = nupp.region(values, values, 1, 2)",
      "   local right = nupp.region(values, values, 3, 4)",
      "   together(left, right)",
      "end",
   }, "\n"))
   local result, diags = checked(prelude .. table.concat({
      "",
      "   local left = nupp.region(values, values, 1, 3)",
      "   local right = nupp.region(values, values, 3, 4)",
      "   together(left, right)",
      "end",
   }, "\n"))
   assert(result)
   assertEq(diags[1] and diags[1].code, "NUPP2607")
   assertEq(#(diags[1].related or {}), 1, "overlap names the earlier checked region")
end

function M.publicContractsAreExplicitOnlyForCapabilityBearingParameters()
   assertClean(table.concat({
      "local m = {}",
      "function m.length(value: string): integer return #value end",
      "return m",
   }, "\n"))
   assertEq(codes(table.concat({
      "local m = {}",
      "function m.forward<T>(value: T): T return value end",
      "return m",
   }, "\n")), "NUPP2610")
   assertEq(codes(table.concat({
      "local m = {}",
      "function m.forward<T>(takes value: T): T return value end",
      "return m",
   }, "\n")), "NUPP2610 NUPP2603")
   assertClean(table.concat({
      "local m = {}",
      "function m.forward<T>(takes value: T): T preserves value return value end",
      "return m",
   }, "\n"))
end

function M.aliasRecoveryChecksTheStoredCapabilityPolicy()
   local source = table.concat({
      "local record File is nupp.Closeable",
      "   function flush(exclusive self): nil end",
      "   function close(takes self): nil end",
      "end",
      "local record Socket is nupp.Closeable",
      "   function flush(exclusive self): nil end",
      "   function close(takes self): nil end",
      "end",
      "local owner = nupp.manage(new File())",
      "local erased: any = owner:alias()",
      "local recovered, problem = nupp.recoverAlias(erased)",
      "assert(recovered ~= nil and problem == nil)",
      "local file, fileProblem = recovered:downcast<File>()",
      "assert(file ~= nil and fileProblem == nil)",
      "local mismatch, mismatchProblem = recovered:downcast<Socket>()",
      "return mismatch, mismatchProblem and mismatchProblem.code",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-alias-recovery")
   assertEq(#genDiags, 0)
   local chunk, loadErr = loadstring(code, "@ownership-alias-recovery")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   local mismatch, mismatchCode = chunk()
   assertEq(mismatch, nil)
   assertEq(mismatchCode, "NUPP2613")
end

function M.managedCallbackBorrowsReleaseOnErrorsAndRejectConflicts()
   local source = table.concat({
      "local record Client is nupp.Closeable",
      "   value: integer",
      "   function flush(exclusive self): nil end",
      "   function close(takes self): nil end",
      "end",
      "local owner = nupp.manage(new Client(value = 1))",
      "local handle = owner:alias()",
      "local conflict: string? = nil",
      "local _, outerProblem = handle:with(function(borrows value)",
      "   local _, problem = handle:withExclusive(function(exclusive item) return item.value end)",
      "   conflict = problem and problem.code",
      "   return value.value",
      "end)",
      "assert(outerProblem == nil)",
      "local raised = pcall(function(): nil",
      "   handle:with(function(borrows value): nil error('callback failed') end)",
      "end)",
      "local answer, finalProblem = handle:withExclusive(function(exclusive value)",
      "   value.value = value.value + 1",
      "   return value.value",
      "end)",
      "return conflict, raised, answer, finalProblem",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-managed-borrows")
   assertEq(#genDiags, 0)
   local chunk, loadErr = loadstring(code, "@ownership-managed-borrows")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   local conflict, raised, answer, finalProblem = chunk()
   assertEq(conflict, "NUPP2620")
   assertEq(raised, false)
   assertEq(answer, 2)
   assertEq(finalProblem, nil)
end
function M.spansCarryBoundsRootsAndAnAffineWriteExtent()
   assertClean(table.concat({
      "local spans = require('nupp.mem.span')",
      "local text = 'bytes'",
      "local whole = spans.fromString(text)",
      "local part = whole:slice(2, 4)",
      "local byte: uint32 = part[1]",
      "print(byte)",
      "local storage: uint8[?] = ffi.new('uint8_t[4]') as any",
      "do",
      "   local writable = spans.writeCarray(storage, 4)",
      "   writable[1] = 65",
      "   drop writable",
      "end",
   }, "\n"))
end

function M.spansPreserveTheCArrayElementType()
   assertClean(table.concat({
      "local spans = require('nupp.mem.span')",
      "local storage = ffi.new<int32[4]>()",
      "do",
      "   local view = spans.fromCarray(storage, 4)",
      "   local value: int32 = view[1]",
      "end",
      "local writable = spans.writeCarray(storage, 4)",
      "writable[2] = 42 as int32",
      "drop writable",
   }, "\n"))
end

function M.spansExportANameableGenericWithoutTheirRepresentation()
   assertClean(table.concat({
      "local spans = require('nupp.mem.span')",
      "local function first(borrows view: spans.Span<int32>): int32",
      "   return view[1]",
      "end",
      "local storage = ffi.new<int32[4]>()",
      "local view = spans.fromCarray(storage, 4)",
      "local value: int32 = first(view)",
      "print(value)",
   }, "\n"))

   assertEq(codes(table.concat({
      "local spans = require('nupp.mem.span')",
      "local storage = ffi.new<int32[4]>()",
      "local view = spans.fromCarray(storage, 4)",
      "print(view.pointer)",
   }, "\n")), "NUPP2004", "the span interface does not expose its representation")

   assertEq(codes(table.concat({
      "local spans = require('nupp.mem.span')",
      "local made = new spans.Span()",
      "print(made)",
   }, "\n")), "NUPP2004", "the interface has no public representation to construct")
end

function M.fixedSpansRefineDynamicSpansWithoutLengthChecks()
   assertClean(table.concat({
      "local spans = require('nupp.mem.span')",
      "local function exact(borrows view: spans.FixedSpan<int32, 4>): integer",
      "   return #view as integer",
      "end",
      "local function dynamic(borrows view: spans.Span<int32>): integer",
      "   return #view",
      "end",
      "local storage = ffi.new<int32[4]>()",
      "do",
      "   local view = spans.fromFixedCarray(storage, 4)",
      "   print(exact(view), dynamic(view), view[1])",
      "end",
      "local writable = spans.writeFixedCarray(storage, 4)",
      "do",
      "   local shared = writable:shared()",
      "   print(exact(shared))",
      "end",
      "writable[1] = 42 as int32",
      "drop writable",
   }, "\n"))

   assertEq(codes(table.concat({
      "local spans = require('nupp.mem.span')",
      "local storage = ffi.new<int32[4]>()",
      "local view = spans.fromFixedCarray(storage, 3)",
      "print(#view)",
   }, "\n")), "NUPP2006", "the literal count must match the fixed C array")

   assertEq(codes(table.concat({
      "local spans = require('nupp.mem.span')",
      "local record Forged is spans.Span<int32>",
      "end",
   }, "\n")), "NUPP2136", "callers cannot implement the sealed span contract")
end

function M.spanRefsExposeOnlyTheCapabilityTheirViewOwns()
   local cdecls = table.concat({
      "cdef function read_values(borrows values: const int32*, count: integer)",
      "cdef function write_values(borrows values: int32*, count: integer)",
   }, "\n")
   assertClean(table.concat({
      cdecls,
      "local spans = require('nupp.mem.span')",
      "local storage = ffi.new<int32[4]>()",
      "do",
      "   local view = spans.fromCarray(storage, 4):slice(2, 3)",
      "   local pointer, count = view:ref()",
      "   read_values(pointer, count)",
      "end",
      "do",
      "   local writable = spans.writeCarray(storage, 4)",
      "   do",
      "      local pointer, count = writable:ref()",
      "      write_values(pointer, count)",
      "   end",
      "   writable[1] = 7 as int32",
      "   drop writable",
      "end",
   }, "\n"))

   assertEq(codes(table.concat({
      cdecls,
      "local spans = require('nupp.mem.span')",
      "local storage = ffi.new<int32[4]>()",
      "local view = spans.fromCarray(storage, 4)",
      "local pointer, count = view:ref()",
      "write_values(pointer, count)",
   }, "\n")), "NUPP2006", "a shared span cannot supply a mutable C parameter")
end

function M.writeSpanDowngradesAndRefsHoldItsExclusiveBarrier()
   assertEq(codes(table.concat({
      "local spans = require('nupp.mem.span')",
      "local storage = ffi.new<int32[4]>()",
      "local writable = spans.writeCarray(storage, 4)",
      "local pointer, count = writable:ref()",
      "drop writable",
      "print(pointer, count)",
   }, "\n")), "NUPP2602", "a live mutable ref blocks consuming its writer")

   assertEq(codes(table.concat({
      "local spans = require('nupp.mem.span')",
      "local storage = ffi.new<int32[4]>()",
      "local writable = spans.writeCarray(storage, 4)",
      "local shared = writable:shared()",
      "writable[1] = 1 as int32",
      "print(shared[1])",
      "drop writable",
   }, "\n")), "NUPP2607 NUPP2602", "a shared downgrade blocks mutation and drop")
end

function M.writableSlicesAreAffineChildrenOfTheirWriter()
   assertClean(table.concat({
      "local spans = require('nupp.mem.span')",
      "local storage = ffi.new<int32[6]>()",
      "local writable = spans.writeCarray(storage, 6)",
      "do",
      "   local middle = writable:slice(2, 4)",
      "   middle[1] = 11 as int32",
      "   do",
      "      local nested = middle:slice(2, 2)",
      "      nested[1] = 12 as int32",
      "   end",
      "   middle[3] = 13 as int32",
      "end",
      "do",
      "   local empty = writable:slice(4, 3)",
      "   drop empty",
      "end",
      "writable[6] = 14 as int32",
      "drop writable",
   }, "\n"))

   assertEq(codes(table.concat({
      "local spans = require('nupp.mem.span')",
      "local storage = ffi.new<int32[4]>()",
      "local writable = spans.writeCarray(storage, 4)",
      "local child = writable:slice(2, 3)",
      "writable[1] = 1 as int32",
      "print(#child)",
   }, "\n")), "NUPP2607", "a live child blocks exclusive parent use")

   assertClean(table.concat({
      "local spans = require('nupp.mem.span')",
      "local storage = ffi.new<int32[4]>()",
      "local writable = spans.writeFixedCarray(storage, 4)",
      "local child: spans.Writable<int32> = writable:slice(2, 3)",
      "child[1] = 7 as int32",
      "drop child",
      "drop writable",
   }, "\n"))
end

function M.commonSpanRangesBorrowEveryInputWithoutBoxingOrConsumption()
   assertClean(table.concat({
      "local spans = require('nupp.mem.span')",
      "local indexed = require('nupp.mem.indexed')",
      "local inputStorage = ffi.new<int32[4]>()",
      "local outputStorage = ffi.new<int32[4]>()",
      "const input = spans.fromFixedCarray(inputStorage, 4)",
      "const output = spans.writeFixedCarray(outputStorage, 4)",
      "local indices = indexed.range(1, 4, input, output)",
      "for index = indices.first, indices.last do",
      "   output[index] = input[index]",
      "end",
      "drop output",
   }, "\n"))

   assertClean(table.concat({
      "local spans = require('nupp.mem.span')",
      "local indexed = require('nupp.mem.indexed')",
      "local storage = ffi.new<int32[1]>()",
      "const view = spans.fromCarray(storage, 1)",
      "local empty = indexed.range(1, 0, view)",
      "print(empty.first, empty.last)",
   }, "\n"))

   assertEq(codes(table.concat({
      "local indexed = require('nupp.mem.indexed')",
      "const fake = {count = 4}",
      "local indices = indexed.range(1, 4, fake)",
      "print(indices.first)",
   }, "\n")), "NUPP2403", "an arbitrary count-shaped table cannot forge the sealed contract")
end

function M.heapArraysAreOwnedAndBecomeCheckedSpans()
   assertClean(table.concat({
      "local heap = require('nupp.mem.heap')",
      "local values = heap.allocate(ffi.typeof<int32>(), 1000000)",
      "print(values.count)",
      "do",
      "   local writable = values:write()",
      "   writable[1] = 42 as int32",
      "   print(#writable)",
      "   drop writable",
      "end",
      "local readable = values:read()",
      "local value: int32 = readable[1]",
      "print(value, #readable)",
   }, "\n"))

   assertEq(codes(table.concat({
      "local heap = require('nupp.mem.heap')",
      "local values = heap.allocate(ffi.typeof<int32>(), 4)",
      "local readable = values:read()",
      "local writable = values:write()",
      "print(readable, writable)",
   }, "\n")), "NUPP2607", "a live array read blocks a writer")

   assertEq(codes(table.concat({
      "local heap = require('nupp.mem.heap')",
      "local values = heap.allocate(ffi.typeof<int32>(), 4)",
      "local writable = values:write()",
      "local readable = values:read()",
      "print(readable, writable)",
   }, "\n")), "NUPP2607", "a live array writer blocks a reader")

   assertEq(codes(table.concat({
      "local heap = require('nupp.mem.heap')",
      "local values = heap.allocate(ffi.typeof<int32>(), 4)",
      "print(values.pointer)",
   }, "\n")), "NUPP2209", "an array's allocation pointer is private")
end

function M.heapArraysPreserveCountsAndCleanUpAtRuntime()
   local source = table.concat({
      "local heap = require('nupp.mem.heap')",
      "local function exercise(count: integer): (integer, int32)",
      "   local values = heap.allocate(ffi.typeof<int32>(), count)",
      "   if count > 0 then",
      "      local writable = values:write()",
      "      writable[count] = 73 as int32",
      "      drop writable",
      "   end",
      "   local readable = values:read()",
      "   local value: int32 = 0",
      "   if count > 0 then value = readable[count] end",
      "   return #readable, value",
      "end",
      "local zero = exercise(0)",
      "local one, value = exercise(1)",
      "local negative = pcall(function()",
      "   local values = heap.allocate(ffi.typeof<int32>(), -1)",
      "   values:close()",
      "end)",
      "local overflow = pcall(function()",
      "   local values = heap.allocate(ffi.typeof<int32>(), 9007199254740991 as integer)",
      "   values:close()",
      "end)",
      "local unwound = pcall(function()",
      "   local values = heap.allocate(ffi.typeof<int32>(), 2)",
      "   local writable = values:write()",
      "   writable[1] = 1 as int32",
      "   error('unwind')",
      "end)",
      "return zero, one, value, negative, overflow, unwound",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   local chunk, loadErr = loadstring(code, "@ownership-heap-array")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   local zero, one, value, negative, overflow, unwound = chunk()
   assertEq(zero, 0, "zero-length allocation retains count")
   assertEq(one, 1, "one-element allocation retains count")
   assertEq(tonumber(value), 73, "write and read views address the allocation")
   assertEq(negative, false, "negative allocation is rejected")
   assertEq(overflow, false, "overflowing allocation is rejected")
   assertEq(unwound, false, "error unwinding discharges writer before array")
end

function M.writeSpansProveSiblingPartitionsAndRejectOverlap()
   local prelude = table.concat({
      "local spans = require('nupp.mem.span')",
      "local function pair(exclusive a: spans.WriteSpan<int32>, exclusive b: spans.WriteSpan<int32>): nil",
      "   if #a > 0 then a[1] = 1 as int32 end",
      "   if #b > 0 then b[1] = 2 as int32 end",
      "end",
      "local storage = ffi.new<int32[8]>()",
      "local writable = spans.writeCarray(storage, 8)",
      "local split = writable:splitAt(4)",
   }, "\n")

   assertClean(prelude .. "\npair(split.left, split.right)")
   assertEq(codes(prelude .. "\npair(split.left, split.left)"), "NUPP2607", "one child is not two regions")
   assertEq(codes(prelude .. "\nwritable[1] = 1 as int32"), "NUPP2607", "a split blocks its parent")
   assertEq(codes(prelude .. table.concat({
      "",
      "local nested = split.left:splitAt(2)",
      "pair(split.left, nested.right)",
   }, "\n")), "NUPP2607 NUPP2607", "an ancestor overlaps its descendant")

   assertClean(table.concat({
      prelude,
      "do",
      "   local nested = split.right:splitAt(2)",
      "   pair(nested.left, nested.right)",
      "end",
      "pair(split.left, split.right)",
   }, "\n"))

   assertClean(table.concat({
      "local spans = require('nupp.mem.span')",
      "local storage = ffi.new<int32[2]>()",
      "local writable = spans.writeCarray(storage, 2)",
      "do",
      "   local split = writable:splitAt(1)",
      "   split.left[1] = 1 as int32",
      "end",
      "writable[2] = 2 as int32",
      "drop writable",
   }, "\n"))
end

function M.exclusiveParametersCanBeForwardedWithoutAStoredBorrow()
   local prelude = table.concat({
      "local spans = require('nupp.mem.span')",
      "local function inner(exclusive values: spans.WriteSpan<int32>): nil end",
      "local function outer(exclusive values: spans.WriteSpan<int32>): nil",
      "   inner(values)",
      "end",
   }, "\n")
   assertClean(prelude)

   assertClean(table.concat({
      "local spans = require('nupp.mem.span')",
      "local function inner(exclusive values: spans.WriteSpan<int32>): nil end",
      "local function outer(exclusive values: spans.WriteSpan<int32>): nil",
      "   local element = values[1]",
      "   inner(values)",
      "   print(element)",
      "end",
   }, "\n"))

   assertClean(table.concat({
      "local spans = require('nupp.mem.span')",
      "local function inspect(borrows values: spans.WriteSpan<int32>): nil end",
      "local function outer(exclusive values: spans.WriteSpan<int32>): nil",
      "   local element = values[1]",
      "   inspect(values)",
      "   print(element)",
      "end",
   }, "\n"))
end

function M.writeSpanPartitionsKeepCountsOffsetsAndBoundsAtRuntime()
   local source = table.concat({
      "local heap = require('nupp.mem.heap')",
      "local function exercise(mid: integer): (integer, integer, int32, int32)",
      "   local values = heap.allocate(ffi.typeof<int32>(), 4)",
      "   local leftCount: integer = -1 as integer",
      "   local rightCount: integer = -1 as integer",
      -- heap.allocate does not promise zeroed memory, and the assertions below read an
      -- element no split ever writes, so without this they see whatever was there.
      "   do",
      "      local zeroing = values:write()",
      "      for i = 1, #zeroing do zeroing[i] = 0 as int32 end",
      "      drop zeroing",
      "   end",
      "   do",
      "      local writable = values:write()",
      "      do",
      "         local split = writable:splitAt(mid)",
      "         leftCount, rightCount = #split.left, #split.right",
      "         if #split.left > 0 then split.left[#split.left] = 11 as int32 end",
      "         if #split.right > 0 then split.right[1] = 22 as int32 end",
      "         if #split.right > 1 then",
      "            local nested = split.right:splitAt(1)",
      "            nested.right[1] = 33 as int32",
      "         end",
      "      end",
      "      drop writable",
      "   end",
      "   local readable = values:read()",
      "   return leftCount, rightCount, readable[1], readable[4]",
      "end",
      "local l0, r0 = exercise(0)",
      "local l1, r1 = exercise(1)",
      "local l3, r3 = exercise(3)",
      "local l4, r4, first4, last4 = exercise(4)",
      "local low = pcall(function() exercise(-1) end)",
      "local high = pcall(function() exercise(5) end)",
      "return l0, r0, l1, r1, l3, r3, l4, r4, first4, last4, low, high",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-partitions")
   assertEq(#genDiags, 0)
   local chunk, loadErr = loadstring(code, "@ownership-partitions")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   local l0, r0, l1, r1, l3, r3, l4, r4, first4, last4, low, high = chunk()
   assertEq(table.concat({l0, r0, l1, r1, l3, r3, l4, r4}, ","), "0,4,1,3,3,1,4,0")
   assertEq(tonumber(first4), 0, "an empty right half writes nothing")
   assertEq(tonumber(last4), 11, "the left boundary write reaches the original last element")
   assertEq(low, false, "negative split points raise")
   assertEq(high, false, "split points beyond count raise")
end

function M.tecsShapedColumnsPartitionIntoCheckedNativeKernelInputs()
   assertClean(table.concat({
      "local heap = require('nupp.mem.heap')",
      "cdef struct Transform2D",
      "   x: float",
      "   y: float",
      "   rotation: float",
      "   scaleX: float",
      "   scaleY: float",
      "   originX: float",
      "   originY: float",
      "end",
      "cdef function update_transforms(",
      "   borrows values: Transform2D* countedBy(count), count: uint64",
      ")",
      "local column = heap.allocate(ffi.typeof<Transform2D>(), 1024)",
      "do",
      "   local writable = column:write()",
      "   do",
      "      local halves = writable:splitAt(512)",
      "      update_transforms(halves.left)",
      "      update_transforms(halves.right)",
      "   end",
      "   drop writable",
      "end",
      "local readable = column:read()",
      "print(#readable)",
   }, "\n"))
end

function M.borrowedCArrayIndexingStillNeedsABound()
   assertEq(codes(table.concat({
      "local text = 'bytes'",
      "local pointer = ffi.cast<const uint8[?]>(text)",
      "local byte = pointer[0]",
   }, "\n")), "NUPP2604")
end

function M.aFixedCArrayAdmitsOnlyAStaticallyInBoundsIndex()
   assertClean(table.concat({
      "local bytes = ffi.new<uint8[4]>()",
      "bytes[3] = 1",
   }, "\n"))
   assertEq(codes(table.concat({
      "local bytes = ffi.new<uint8[4]>()",
      "bytes[4] = 1",
   }, "\n")), "NUPP2604")
end

-- A result declared `borrows p` is tied to the argument passed for p: that
-- argument cannot be released while the result is live, and the result cannot
-- outlive it. `borrows self` says the same about a method's receiver, which is
-- what lets a container hand out an element without giving up ownership.

local POOL = table.concat({
   "local record Res",
   "   name: string",
   "end",
   "local record Pool",
   "   items: {Res}",
   "end",
   "local function close_pool(takes p: Pool): nil end",
   "local function open_pool(): affine(Pool, close_pool)",
   "   return new Pool(items = {})",
   "end",
   "function Pool:get(index: integer): Res borrows (self)",
   "   return self.items[index]",
   "end",
   "local function peek(borrows p: Pool): Pool borrows (p)",
   "   return p",
   "end",
}, "\n")

function M.aBorrowedResultBlocksReleasingItsSource()
   assertEq(codes(POOL .. table.concat({
      "",
      "local pool = open_pool()",
      "local held = peek(pool)",
      "drop(pool)",
      "print(held.items)",
   }, "\n")), "NUPP2602")
end

function M.aMethodResultCanBorrowTheReceiver()
   assertEq(codes(POOL .. table.concat({
      "",
      "local pool = open_pool()",
      "local item = pool:get(1)",
      "drop(pool)",
      "print(item.name)",
   }, "\n")), "NUPP2602")
end

function M.aBorrowedResultIsReleasedWithItsScope()
   assertClean(POOL .. table.concat({
      "",
      "local pool = open_pool()",
      "do",
      "   local item = pool:get(1)",
      "   print(item.name)",
      "end",
      "drop(pool)",
   }, "\n"))
end

function M.anElementCanBeBorrowedThroughAnAutomaticOwner()
   assertClean(POOL .. table.concat({
      "",
      "local function use(): string",
      "   do",
      "      local pool = open_pool()",
      "      local item = pool:get(1)",
      "      return item.name",
      "   end",
      "end",
   }, "\n"))
end

function M.aBorrowedResultCannotOutliveItsSource()
   assertEq(codes(POOL .. table.concat({
      "",
      "local function leak(): Pool",
      "   do",
      "      local pool = open_pool()",
      "      return peek(pool)",
      "   end",
      "end",
   }, "\n")), "NUPP2608")
end

function M.borrowingAConsumedParameterIsRejected()
   assertEq(codes(POOL .. table.concat({
      "",
      "local function eat(takes p: Pool): Pool borrows (p)",
      "   return p",
      "end",
   }, "\n")), "NUPP2618 NUPP2603")
end

function M.borrowingSomethingThatIsNotAParameterIsRejected()
   assertEq(codes(POOL .. table.concat({
      "",
      "local function odd(borrows p: Pool): Pool borrows (q)",
      "   return p",
      "end",
   }, "\n")), "NUPP2109")
end

function M.returningABorrowStillNeedsTheAnnotation()
   assertEq(codes(POOL .. table.concat({
      "",
      "local function sneak(borrows p: Pool): Pool",
      "   return p",
      "end",
   }, "\n")), "NUPP2608")
end

-- Borrowing a borrow needs no separate machinery: a borrow can only be bound
-- in the scope that creates it — it cannot be assigned outward, stored, or
-- returned without a declaration — so a derived borrow can never outlive the
-- one it came from, and the intermediate keeps the root borrowed meanwhile.

-- On a method there is only one thing a source-less borrow could mean, so
-- A borrowed method result elides to `borrows self`, the way Rust elides an output
-- lifetime to `&self`. The result is still explicitly a borrow, so nothing
-- returning a plain value is affected.

-- An owning result may also retain a borrow of its input, which is what a
-- layered resource is: the session owns itself and holds the socket, so the
-- socket cannot be released until the session is.

local LAYERED = table.concat({
   "local record Socket",
   "   fd: integer",
   "end",
   "local record TLS",
   "   s: Socket",
   "end",
   "local function close_socket(takes s: Socket): nil end",
   "local function close_tls(takes t: TLS): nil end",
   "local function open_socket(): affine(Socket, close_socket)",
   "   return new Socket(fd = 1)",
   "end",
   "local function open_tls(borrows s: Socket): affine(TLS, close_tls) borrows (s)",
   "   return new TLS(s = s)",
   "end",
}, "\n")

function M.anOwningResultCanRetainAnInputBorrow()
   assertClean(LAYERED .. table.concat({
      "",
      "local sock = open_socket()",
      "local tls = open_tls(sock)",
      "drop(tls)",
      "drop(sock)",
   }, "\n"))
end

function M.theHeldSourceCannotBeReleasedFirst()
   assertEq(codes(LAYERED .. table.concat({
      "",
      "local sock = open_socket()",
      "local tls = open_tls(sock)",
      "drop(sock)",
      "drop(tls)",
   }, "\n")), "NUPP2602")
end

-- Reverse automatic cleanup releases the session before the socket, which is exactly
-- the order the borrow requires.
function M.layeredResourcesHoldTogetherInAScope()
   assertClean(LAYERED .. table.concat({
      "",
      "local function use()",
      "   do",
      "      local sock = open_socket()",
      "      local tls = open_tls(sock)",
      "      print(tls.s.fd)",
      "   end",
      "end",
   }, "\n"))
end

function M.anOwningResultThatBorrowsIsStillOwned()
   assertEq(codes(LAYERED .. table.concat({
      "",
      "local sock = open_socket()",
      "local tls = open_tls(sock)",
      "drop(sock)",
   }, "\n")), "NUPP2602")
end

function M.aMethodBorrowedReturnElidesToTheReceiver()
   assertEq(codes(POOL .. table.concat({
      "",
      "function Pool:first(): Res borrows (self)",
      "   return self.items[1]",
      "end",
      "local pool = open_pool()",
      "local item = pool:first()",
      "drop(pool)",
      "print(item.name)",
   }, "\n")), "NUPP2602")
end

-- The member type callers read was derived from the annotations before the body was
-- checked, and that pass never worked out what a `borrows` result borrows from. The
-- result kept its qualifier and lost its source, so a call had nothing to tie the value
-- to and handed back the raw one, which reported at the first dereference instead of at
-- the method.
function M.anInlineMethodsBorrowedResultKeepsItsSource()
   assertEq(codes(POOL .. table.concat({
      "",
      "local record Holder",
      "   items: {Res}",
      "   function first(self): Res borrows (self)",
      "      return self.items[1]",
      "   end",
      "end",
      "local function close_holder(takes h: Holder): nil end",
      "local function open_holder(): affine(Holder, close_holder) return new Holder(items = {}) end",
      "local h = open_holder()",
      "local item = h:first()",
      "drop(h)",
      "print(item.name)",
   }, "\n")), "NUPP2602")
end

-- The same method declared and defined apart, which always carried its source. Both
-- spellings have to agree, since the difference is where the body is written.
function M.aDeclaredMethodsBorrowedResultKeepsItsSource()
   assertEq(codes(POOL .. table.concat({
      "",
      "local record Holder",
      "   items: {Res}",
      "   first: function(self: Holder): Res borrows (self)",
      "end",
      "function Holder.first(self): Res borrows (self)",
      "   return self.items[1]",
      "end",
      "local function close_holder(takes h: Holder): nil end",
      "local function open_holder(): affine(Holder, close_holder) return new Holder(items = {}) end",
      "local h = open_holder()",
      "local item = h:first()",
      "drop(h)",
      "print(item.name)",
   }, "\n")), "NUPP2602")
end

function M.aMethodReturningAPlainValueDoesNotBorrow()
   assertClean(POOL .. table.concat({
      "",
      "function Pool:count(): integer",
      "   return #self.items",
      "end",
      "local pool = open_pool()",
      "local n = pool:count()",
      "drop(pool)",
      "print(n)",
   }, "\n"))
end

function M.anExplicitSourceStillWinsOverElision()
   assertEq(codes(POOL .. table.concat({
      "",
      "function Pool:other(borrows p: Pool): Res borrows (p)",
      "   return p.items[1]",
      "end",
   }, "\n")), "")
end

function M.aChainOfBorrowsStillHoldsTheRoot()
   assertEq(codes(POOL .. table.concat({
      "",
      "local pool = open_pool()",
      "local first = peek(pool)",
      "local second = peek(first)",
      "drop(pool)",
      "print(second.items)",
   }, "\n")), "NUPP2602")
end

function M.aDerivedBorrowCannotOutliveItsIntermediate()
   assertEq(codes(POOL .. table.concat({
      "",
      "local pool = open_pool()",
      "local held = peek(pool)",
      "do",
      "   local inner = peek(pool)",
      "   held = peek(inner)",
      "end",
      "drop(pool)",
   }, "\n")), "NUPP2608")
end

function M.aDerivedBorrowCannotBeStored()
   assertEq(codes(POOL .. table.concat({
      "",
      "local pool = open_pool()",
      "local sink: {Pool} = {}",
      "local first = peek(pool)",
      "sink[1] = peek(first)",
      "drop(pool)",
   }, "\n")), "NUPP2603 NUPP2602")
end

-- The declaration is the contract: a result declared `borrows p` may be
-- derived through any number of intermediates, and the checker takes the
-- annotation's word for what it roots at, exactly as it does for an owning result.
function M.aBorrowMayBeDerivedThroughAnIntermediate()
   assertClean(POOL .. table.concat({
      "",
      "local function deep(borrows p: Pool): Pool borrows (p)",
      "   local mid = peek(p)",
      "   return peek(mid)",
      "end",
   }, "\n"))
end

function M.liveDroppableOwnersAreDestroyedAutomatically()
   assertEq(codes(RESOURCE .. "\nlocal value = resource_new()"), "")
   assertEq(codes(RESOURCE .. "\nresource_new()"), "NUPP2605")
end

function M.opaqueOwnersAreTransferOnly()
   local opaque = table.concat({
      "cdef function resource_new_c(): voidptr",
      "local function resource_new(): affine(voidptr)",
      "   return resource_new_c()",
      "end",
      "cdef function resource_take(takes value: voidptr)",
   }, "\n")
   assertClean(opaque .. "\nlocal value = resource_new()\nresource_take(value)")
   assertEq(codes(opaque .. "\nlocal value = resource_new()\ndrop(value)"),
      "NUPP2602")
end

function M.affineUsesItsExactCleanupFunction()
   local source = table.concat({
      "local calls = ''",
      "local record File",
      "   closed: boolean",
      "   function drop(takes self): nil",
      "      calls = calls .. 'close'",
      "      self.closed = true",
      "   end",
      "end",
      "local function closeFile(takes file: File): nil",
      "   calls = calls .. 'close'",
      "   file.closed = true",
      "   unsafe do local _raw = unsafe release file end",
      "end",
      "local function openFile(): affine(File, closeFile)",
      "   return new File(closed = false)",
      "end",
      "local file = openFile()",
      "drop(file)",
      "return calls",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   local chunk, loadErr = loadstring(code, "@ownership-default-drop")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   assertEq(chunk(), "close", "default drop operation runs")
end

function M.anExplicitDropAfterACallIsASeparateStatement()
   local source = table.concat({
      "local calls = ''",
      "local record File",
      "   function drop(takes self): nil calls = calls .. 'stop' end",
      "end",
      "local function closeFile(takes file: File): nil unsafe do local _raw = unsafe release file end end",
      "local function openFile(): affine(File, closeFile) return new File() end",
      "local file = openFile()",
      "print('before')",
      "file:drop()",
      "return calls",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   local chunk, loadErr = loadstring(code, "@ownership-explicit-drop")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   assertEq(chunk(), "stop", "the terminal call runs once after another call statement")
end

function M.aCleanupFunctionCanBeConstrainedByAnInterface()
   assertClean(table.concat({
      "local interface Closeable",
      "   drop: nosuspend function(takes value: self): nil",
      "end",
      "local record File is Closeable",
      "   closed: boolean",
      "end",
      "function File.drop(takes self): nil self.closed = true end",
      "local function close<T is Closeable>(takes value: T): nil value:drop() end",
      "local function openFile(): affine(File, close)",
      "   return new File(closed = false)",
      "end",
      "do local file = openFile(); print(file.closed) end",
   }, "\n"))
end

function M.ownedFieldsApplyToEveryOverload()
   assertClean(table.concat({
      "local record File",
      "   function drop(takes self): nil end",
      "end",
      "local function closeFile(takes file: File): nil unsafe do local _raw = unsafe release file end end",
      "local record Library",
      "   open: function(name: string): affine(File, closeFile) & function(id: integer): affine(File, closeFile)",
      "end",
      "local library = nil as any as Library",
      "do local named = library.open('name') end",
      "do local numbered = library.open(1) end",
   }, "\n"))
end

function M.affineRejectsMissingAndInexactCleanupFunctions()
   assertEq(codes(table.concat({
      "local record File",
      "   closed: boolean",
      "end",
      "local function openFile(): affine(File, missingCleanup) return new File(closed = false) end",
   }, "\n")), "NUPP2131")

   assertEq(codes(table.concat({
      "local record File",
      "   closed: boolean",
      "end",
      "local function closeFile(file: File): nil end",
      "local function openFile(): affine(File, closeFile) return new File(closed = false) end",
   }, "\n")), "NUPP2615")
end

function M.affineTerminalsMustTakeTheirResource()
   assertEq(codes(table.concat({
      "local record File end",
      "local function closeFile(borrows file: File): nil end",
      "local type FileOwner = affine(File, closeFile)",
   }, "\n")), "NUPP2615")
end

function M.ownershipQualifiersAndParameterModesAreTyped()
   assertClean(RESOURCE .. table.concat({
      "",
      "local function inspect(borrows value: resource*): int32",
      "   return value.value",
      "end",
      "local value: affine(resource*, resource_free) = resource_new()",
      "inspect(value)",
      "resource_free(value)",
   }, "\n"))
end

function M.readOnlyHelpersInferBorrowContracts()
   assertClean(RESOURCE .. table.concat({
      "",
      "local function inspect(value: resource*): int32",
      "   return value.value",
      "end",
      "local value = resource_new()",
      "do",
      "   local view = borrow(value)",
      "   inspect(view)",
      "end",
      "resource_free(value)",
   }, "\n"))
end

function M.escapingHelpersCannotLaunderBorrows()
   assertEq(codes(RESOURCE .. table.concat({
      "",
      "local saved: resource*?",
      "local function stash(value: resource*)",
      "   saved = value",
      "end",
      "local value = resource_new()",
      "do",
      "   local view = borrow(value)",
      "   stash(view)",
      "end",
      "resource_free(value)",
   }, "\n")), "NUPP2603")
end

function M.explicitBorrowContractsPinEscapeErrorsToTheBody()
   assertEq(codes(RESOURCE .. table.concat({
      "",
      "local saved: resource*?",
      "local function stash(borrows value: resource*)",
      "   saved = value",
      "end",
   }, "\n")), "NUPP2608")
end

function M.sharedBorrowsPermitStableMutation()
   assertClean(RESOURCE .. table.concat({
      "",
      "local function rename(borrows value: resource*)",
      "   value.value = 1",
      "end",
   }, "\n"))
end

function M.exclusiveRequiresCallDurationExclusivity()
   assertEq(codes(RESOURCE .. table.concat({
      "",
      "local function reset(exclusive value: resource*)",
      "   value.value = 0",
      "end",
      "local value = resource_new()",
      "do",
      "   local view = borrow(value)",
      "   reset(value)",
      "   print(view.value)",
      "end",
      "resource_free(value)",
   }, "\n")), "NUPP2607")

   assertClean(RESOURCE .. table.concat({
      "",
      "local function reset(exclusive value: resource*)",
      "   value.value = 0",
      "end",
      "local value = resource_new()",
      "do",
      "   local view = borrow(value)",
      "   reset(view)",
      "end",
      "resource_free(value)",
   }, "\n"))

   assertEq(codes(RESOURCE .. table.concat({
      "",
      "local function reset(exclusive value: resource*)",
      "   value.value = 0",
      "end",
      "local value = resource_new()",
      "do",
      "   local first = borrow(value)",
      "   local second = borrow(value)",
      "   reset(first)",
      "   print(second.value)",
      "end",
      "resource_free(value)",
   }, "\n")), "NUPP2607")
end

function M.consumeMovesAndRejectsLaterUse()
   local source = RESOURCE .. table.concat({
      "",
      "local value = resource_new()",
      "resource_free(value)",
      "print(value)",
   }, "\n")
   assertEq(codes(source), "NUPP2601")
   local _, diags = checked(source)
   assertEq(#(diags[1].related or {}), 1, "move origin is attached")
   assertEq(diags[1].related[1].message, "owner was moved here")
   assert(diags[1].help and diags[1].help:find("borrow", 1, true),
      "move diagnostic explains the alternative")
end

function M.doubleConsumeIsRejected()
   local got = codes(RESOURCE .. table.concat({
      "",
      "local value = resource_new()",
      "resource_free(value)",
      "resource_free(value)",
   }, "\n"))
   assert(got:find("NUPP2601", 1, true), "double consume reports a move: " .. got)
end

function M.movesInsideNarrowedBranchesReachTheOuterOwner()
   assertEq(codes(RESOURCE .. table.concat({
      "",
      "local value = resource_new()",
      "if value then",
      "   resource_free(value)",
      "end",
      "print(value)",
   }, "\n")), "NUPP2601")
end

function M.nullableOwnersNarrowWithoutLosingOwnership()
   assertClean(table.concat({
      "cdef struct maybe_resource",
      "   value: int32",
      "end",
      "cdef function free(takes value: maybe_resource*)",
      "cdef function maybe_new_c(): maybe_resource*?",
      "local function maybe_new(): affine(maybe_resource*?, free)",
      "   return maybe_new_c()",
      "end",
      "local value = maybe_new()",
      "if value then",
      "   print(value.value)",
      "   drop(value)",
      "end",
   }, "\n"))
end

function M.assignmentMovesAndProtectsLiveOwners()
   assertEq(codes(RESOURCE .. table.concat({
      "",
      "local first = resource_new()",
      "local second = first",
      "print(first)",
      "resource_free(second)",
   }, "\n")), "NUPP2601")
   assertEq(codes(RESOURCE .. table.concat({
      "",
      "local first = resource_new()",
      "local second = resource_new()",
      "second = first",
      "resource_free(second)",
   }, "\n")), "NUPP2602")
end

function M.ownershipCannotDisappearIntoRawAnnotations()
   assertEq(codes(RESOURCE .. table.concat({
      "",
      "local ownedValue = resource_new()",
      "local rawValue: resource* = ownedValue",
   }, "\n")), "NUPP2603")
end

function M.ownershipQualifiersSupportManagedValuesButPinsRequirePointers()
   assertEq(codes(table.concat({
      "local function closeText(takes value: string): nil end",
      "local value: affine(number, closeText)",
   }, "\n")), "NUPP2615")
   assertEq(codes("local value: affine(number)"), "")
   assertEq(codes("local value: Borrowed<string>"), "NUPP2101")
   assertEq(codes("local value: pinned(boolean)"), "NUPP2602")
end

function M.liveBorrowPreventsMoveUntilScopeEnds()
   assertEq(codes(RESOURCE .. table.concat({
      "",
      "local value = resource_new()",
      "do",
      "   local view = borrow(value)",
      "   resource_free(value)",
      "end",
      "resource_free(value)",
   }, "\n")), "NUPP2602")
   assertClean(RESOURCE .. table.concat({
      "",
      "local value = resource_new()",
      "do",
      "   local view = borrow(value)",
      "   print(view.value)",
      "end",
      "resource_free(value)",
   }, "\n"))
end

function M.borrowedValuesCannotEscape()
   local returned = RESOURCE .. table.concat({
      "",
      "local function bad(borrows value: resource*): resource*",
      "   return value",
      "end",
   }, "\n")
   assertEq(codes(returned), "NUPP2608")

   local stored = RESOURCE .. table.concat({
      "",
      "local value = resource_new()",
      "do",
      "   local view = borrow(value)",
      "   local box = { value = view }",
      "end",
      "resource_free(value)",
   }, "\n")
   assertEq(codes(stored), "NUPP2603")
end

function M.aBorrowingClosureCannotEraseProvenanceOnReturn()
   local got = codes(RESOURCE .. table.concat({
      "",
      "local function callback(borrows value: resource*): function(): int32",
      "   return function(): int32",
      "      return value.value",
      "   end",
      "end",
   }, "\n"))
   assertEq(got, "NUPP2608")
end

function M.rawReconstructionRequiresUnsafe()
   assertClean(RESOURCE .. table.concat({
      "",
      "local raw: resource*",
      "local value = unsafe adopt raw as affine(resource*, resource_free)",
      "resource_free(value)",
   }, "\n"))

   assertClean(RESOURCE .. table.concat({
      "",
      "local raw: resource*",
      "unsafe do",
      "   local value = unsafe adopt raw as affine(resource*, resource_free)",
      "   drop(value)",
      "end",
   }, "\n"))
   assertEq(codes(table.concat({
      "local raw: voidptr",
      "local function wrong(takes value: string): nil end",
      "unsafe do",
      "   local value = unsafe adopt raw as affine(voidptr, wrong)",
      "end",
   }, "\n")), "NUPP2615")
end

function M.rawAbandonmentRequiresUnsafe()
   assertClean(RESOURCE .. table.concat({
      "",
      "local value = resource_new()",
      "local raw = unsafe release value",
      "print(raw)",
   }, "\n"))
end

function M.unsafeDoesNotSuppressOwnershipObligations()
   assertEq(codes(RESOURCE .. table.concat({
      "",
      "local value = resource_new()",
      "unsafe do",
      "   local box = {value = value}",
      "end",
      "resource_free(value)",
   }, "\n")), "NUPP2603")

   assertEq(codes(RESOURCE .. table.concat({
      "",
      "local value = resource_new()",
      "unsafe do",
      "   ffi.cast<voidptr>(value)",
      "end",
      "resource_free(value)",
   }, "\n")), "NUPP2603")
end

function M.bodyfulBorrowContractsNeedProvenanceProof()
   assertEq(codes(RESOURCE .. table.concat({
      "",
      "local function fake(borrows source: resource*): resource* borrows (source)",
      "   local raw: resource*",
      "   return raw",
      "end",
   }, "\n")), "NUPP2619")
end

function M.borrowFromRestoresOpaqueProvenanceExplicitly()
   assertClean(RESOURCE .. table.concat({
      "",
      "local function recover(borrows source: resource*, raw: resource*): resource* borrows (source)",
      "   unsafe do",
      "      return borrowFrom(raw, source)",
      "   end",
      "end",
   }, "\n"))
   assertEq(codes(RESOURCE .. table.concat({
      "",
      "local function recover(borrows source: resource*, raw: resource*): resource* borrows (source)",
      "   return borrowFrom(raw, source)",
      "end",
   }, "\n")), "NUPP2604")
end

function M.borrowedResultsCanNameMultipleSources()
   local source = RESOURCE .. table.concat({
      "",
      "local record Pair",
      "   left: resource*",
      "   right: resource*",
      "end",
      "local function closePair(takes pair: Pair): nil end",
      "local function pair(borrows left: resource*, borrows right: resource*)",
      "   : affine(Pair, closePair) borrows(left, right)",
      "   return new Pair(left = left, right = right)",
      "end",
   }, "\n")
   assertClean(source .. table.concat({
      "",
      "local left = resource_new()",
      "local right = resource_new()",
      "local joined = pair(left, right)",
      "drop(joined)",
      "resource_free(right)",
      "resource_free(left)",
   }, "\n"))
   assertEq(codes(source .. table.concat({
      "",
      "local left = resource_new()",
      "local right = resource_new()",
      "local joined = pair(left, right)",
      "resource_free(left)",
      "drop(joined)",
      "resource_free(right)",
   }, "\n")), "NUPP2602")
end

function M.affineRecordsDropOwnedFieldsInReverseOrder()
   local source = table.concat({
      "local calls = ''",
      "local record Res",
      "   name: string",
      "end",
      "local function closeRes(takes value: Res): nil",
      "   calls = calls .. value.name",
      "end",
      "local function openRes(name: string): affine(Res, closeRes)",
      "   return new Res(name = name)",
      "end",
      "local record Bundle",
      "   first: affine(Res, closeRes)",
      "   second: affine(Res, closeRes)",
      "end",
      "local bundle = new Bundle(first = openRes('a'), second = openRes('b'))",
      "drop(bundle)",
      "return calls",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   local chunk, loadErr = loadstring(code, "@ownership-affine-record")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   assertEq(chunk(), "ba", "fields close in reverse declaration order")
end

function M.affineRecordsTrackPartialFieldMoves()
   assertClean(table.concat({
      "local record Res end",
      "local function closeRes(takes value: Res): nil end",
      "local function openRes(): affine(Res, closeRes) return new Res() end",
      "local record Bundle",
      "   value: affine(Res, closeRes)",
      "end",
      "local bundle = new Bundle(value = openRes())",
      "local value = bundle.value",
      "drop(value)",
      "drop(bundle)",
   }, "\n"))
   assertEq(codes(table.concat({
      "local record Res end",
      "local function closeRes(takes value: Res): nil end",
      "local function openRes(): affine(Res, closeRes) return new Res() end",
      "local record Bundle",
      "   value: affine(Res, closeRes)",
      "end",
      "local bundle = new Bundle(value = openRes())",
      "local value = bundle.value",
      "print(bundle.value)",
      "drop(value)",
      "drop(bundle)",
   }, "\n")), "NUPP2601")
end

function M.customDropOperationsMustDischargeEveryOwnedField()
   local prefix = table.concat({
      "local record Res end",
      "local function closeRes(takes value: Res): nil end",
      "local function openRes(): affine(Res, closeRes) return new Res() end",
   }, "\n")
   assertClean(prefix .. "\n" .. table.concat({
      "local record Bundle",
      "   first: affine(Res, closeRes)",
      "   second: affine(Res, closeRes)",
      "   function drop(takes self): nil",
      "      closeRes(self.second)",
      "      closeRes(self.first)",
      "   end",
      "end",
      "local bundle = new Bundle(first = openRes(), second = openRes())",
      "drop(bundle)",
   }, "\n"))
   assertEq(codes(prefix .. "\n" .. table.concat({
      "local record Bundle",
      "   first: affine(Res, closeRes)",
      "   second: affine(Res, closeRes)",
      "   function drop(takes self): nil",
      "      closeRes(self.second)",
      "   end",
      "end",
   }, "\n")), "NUPP2603")
end

function M.contextualCleanupUsesExplicitOwnerFields()
   local source = table.concat({
      "local released = ''",
      "local record Arena",
      "   name: string",
      "end",
      "local record Allocation",
      "   arena: Arena",
      "   value: string",
      "   function drop(takes self): nil",
      "      released = self.arena.name .. ':' .. self.value",
      "   end",
      "end",
      "local function releaseAllocation(takes allocation: Allocation): nil",
      "   released = allocation.arena.name .. ':' .. allocation.value",
      "   unsafe do local _raw = unsafe release allocation end",
      "end",
      "local function allocate(arena: Arena, value: string): affine(Allocation, releaseAllocation)",
      "   return new Allocation(arena = arena, value = value)",
      "end",
      "local arena = new Arena(name = 'frame')",
      "local allocation = allocate(arena, 'buffer')",
      "drop(allocation)",
      "return released",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   local chunk, loadErr = loadstring(code, "@ownership-context")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   assertEq(chunk(), "frame:buffer", "the drop operation reads its explicit context")
end

function M.rawCoroutinesCannotSuspendTemporalObligations()
   assertEq(codes(RESOURCE .. table.concat({
      "",
      "local function pause()",
      "   local value = resource_new()",
      "   coroutine.yield()",
      "   resource_free(value)",
      "end",
   }, "\n")), "NUPP2603")
   assertEq(codes(RESOURCE .. table.concat({
      "",
      "local function pause(borrows value: resource*)",
      "   coroutine.yield()",
      "   print(value.value)",
      "end",
   }, "\n")), "NUPP2603")
   assertClean(table.concat({
      "local function pause()",
      "   coroutine.yield()",
      "end",
   }, "\n"))
end

function M.aRawYieldThroughAnAliasIsRefused()
   -- `local co = coroutine` is common enough that leaving it unrecognized would be a
   -- hole anyone falls into by accident.
   assertEq(codes(RESOURCE .. table.concat({
      "",
      "local co = coroutine",
      "local function pause()",
      "   local value = resource_new()",
      "   co.yield()",
      "   resource_free(value)",
      "end",
   }, "\n")), "NUPP2603")
end

function M.aRawYieldThroughAChainOfAliasesIsRefused()
   assertEq(codes(RESOURCE .. table.concat({
      "",
      "local co = coroutine",
      "local also = co",
      "local function pause()",
      "   local value = resource_new()",
      "   also.yield()",
      "   resource_free(value)",
      "end",
   }, "\n")), "NUPP2603")
end

function M.rebindingTheNameToItselfIsStillTheLibrary()
   -- `local coroutine = coroutine` reads the outer binding and rebinds the name, so
   -- resolving that name afterwards can answer with the binding being made. The
   -- initializer's own token still points at what it read, which is what tells them
   -- apart.
   assertEq(codes(RESOURCE .. table.concat({
      "",
      "local coroutine = coroutine",
      "local function pause()",
      "   local value = resource_new()",
      "   coroutine.yield()",
      "   resource_free(value)",
      "end",
   }, "\n")), "NUPP2603")
end
-- A C function states ownership in the type: `affine(T, cleanup)` on the slot an
-- `out` parameter writes, and `Success<T, N>` on the return saying which status
-- means those slots hold values. The ABI is unchanged -- the wrapper says who
-- discharges the value, not how it is passed.
function M.cdefOwnedOutputsBecomeLuaReturns()
   local source = table.concat({
      "cdef function free(takes value: voidptr)",
      "cdef function posix_memalign(out result: affine(voidptr, free)*,"
         .. " alignment: uint64, size: uint64): Success<int32, 0>",
      "local status, pointer = posix_memalign(16, 64)",
      "if pointer then drop(pointer) end",
      "return status == 0",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   assert(code:find('__nuppFfi.new("void *[1]")', 1, true),
      "allocates the logical out slot")
   assert(code:find("const posix_memalign = __nuppFfi.C.posix_memalign", 1, true), code)
   if require("ffi").os == "Windows" then return end
   local chunk, loadErr = loadstring(code, "@ownership-cdef-out")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   assertEq(chunk(), true, "owned out pointer is returned and dropped")
end

function M.failedOwnedOutputsAreNil()
   if require("ffi").os == "Windows" then return end
   local source = table.concat({
      "cdef function free(takes value: voidptr)",
      "cdef function posix_memalign(out result: affine(voidptr, free)*,"
         .. " alignment: uint64, size: uint64): Success<int32, 0>",
      "local status, pointer = posix_memalign(3, 64)",
      "local failed = pointer == nil",
      "if pointer then drop(pointer) end",
      "return status ~= 0 and failed",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code = gen.generate(result, "ownership-test")
   local chunk, loadErr = loadstring(code, "@ownership-cdef-out-failure")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   assertEq(chunk(), true, "failed output is nil")
end

function M.ignoredOwnedOutputsAreRejected()
   assertEq(codes(table.concat({
      "cdef function free(takes value: voidptr)",
      "cdef function posix_memalign(out result: affine(voidptr, free)*,"
         .. " alignment: uint64, size: uint64): Success<int32, 0>",
      "posix_memalign(16, 64)",
   }, "\n")), "NUPP2605")
end

-- `Failure<T, N>` is the other direction: every status but N means the outputs
-- hold values. One statement on the return covers both of them, where two
-- contracts could disagree about the same call.
function M.multipleOwnedOutputsPreserveCAndLuaOrder()
   local source = table.concat({
      "cdef function free(takes value: voidptr)",
      "cdef function make_pair(out first: affine(voidptr, free)*, seed: int32,"
         .. " out second: affine(voidptr, free)*): Success<int32, 7>",
      "local status, first, second = make_pair(1)",
      "if second then drop(second) end",
      "if first then drop(first) end",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   -- The call is made inside the declared sequence, so the C order is read there: the two
   -- cells sit at the positions the declaration gave them, with the seed between them.
   assert(code:find("__nuppFn(__nuppH1,__nuppA1,__nuppH2)", 1, true),
      "holders remain in their declared C parameter positions\n" .. code)
   assert(code:find("==7 and", 1, true),
      "the return's success predicate guards every output")
end

-- An owning C return is the same statement in the same place: the wrapper is on
-- the result type, so a caller's obligation begins where the pointer arrives.
function M.cdefReturnsMayOwnTheirResult()
   assertClean(table.concat({
      "cdef function free(takes value: voidptr)",
      "cdef function malloc(size: uint64): affine(voidptr, free)",
      "local value = malloc(8)",
      "drop(value)",
   }, "\n"))
   assertEq(codes(table.concat({
      "cdef function free(takes value: voidptr)",
      "cdef function malloc(size: uint64): affine(voidptr, free)",
      "malloc(8)",
   }, "\n")), "NUPP2605")
end

-- A status wrapper is about a C call's outputs, so it says nothing anywhere else.
function M.statusWrappersBelongOnACdefReturn()
   assertEq(codes(table.concat({
      "local function make(): Success<integer, 0>",
      "   return 0",
      "end",
      "return make",
   }, "\n")), "NUPP2602")
end

-- An ordered list of operations, as one terminal. `drop` stops where a cleanup
-- raises, which is right for one and wrong for a list: the steps after the
-- failure are obligations of their own. This is the contract automatic
-- destruction and resource sets already keep, reached from a terminal.
function M.attemptAllRunsEveryStepAfterAFailure()
   local source = table.concat({
      "local record Resource id: integer end",
      "local calls = ''",
      "local function stop(value: Resource): nil",
      "   calls = calls .. 'stop'",
      "   error('stop failed')",
      "end",
      "local function release(value: Resource): nil",
      "   calls = calls .. ',release'",
      "end",
      "local function finish(takes value: Resource): nil",
      "   nupp.attemptAll(value, stop, release)",
      "end",
      "local function open(): affine(Resource, finish)",
      "   return new Resource(id = 1)",
      "end",
      "local ok = pcall(function()",
      "   local value = open()",
      "   drop(value)",
      "end)",
      "return calls, ok",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   local chunk, loadErr = loadstring(code, "@ownership-attempt-all")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   local calls, ok = chunk()
   assertEq(calls, "stop,release", "every step is attempted")
   assertEq(ok, false, "and the failure still propagates")
end

-- A step that consumes the value leaves every later one running on something
-- already released, so only the last may take it.
function M.onlyTheFinalAttemptAllOperationMayTakeTheValue()
   local declaration = table.concat({
      "local record Resource id: integer end",
      "local function first(takes value: Resource): nil end",
      "local function second(value: Resource): nil end",
      "local function finish(takes value: Resource): nil",
   }, "\n")
   -- `first` consuming its own parameter is NUPP2603 in its empty body; the
   -- ordering rule is the second diagnostic.
   assertEq(codes(declaration .. table.concat({
      "",
      "   nupp.attemptAll(value, first, second)",
      "end",
   }, "\n")), "NUPP2615")
   assertClean(table.concat({
      "local record Resource id: integer end",
      "local function first(value: Resource): nil end",
      "local function second(takes value: Resource): nil",
      "   unsafe do local _raw = unsafe release value end",
      "end",
      "local function finish(takes value: Resource): nil",
      "   nupp.attemptAll(value, first, second)",
      "end",
      "return finish",
   }, "\n"))
end

-- LuaJIT does not record `FNEW`. A loop containing one aborts recording, is blacklisted
-- after enough attempts, and then never compiles -- so a function built where it is used
-- costs the whole enclosing loop its trace. These lowerings all sat inside loops and all
-- built one, and none of them had to: what an out parameter needs depends only on the C
-- signature, what a `drop` runs depends only on its argument, and the mark a move leaves
-- is a statement at statement root.
--
-- The cleanup region's own `xpcall` wrapper is the one that remains. It closes over the
-- region's per-iteration locals, so it is not this kind of problem.
function M.hotLoweringsBuildNoFunctionWhereTheyAreUsed()
   local outParameter = table.concat({
      "cdef function strtol(borrows text: cstring,",
      "   out rest: voidptr* borrows (text), base: int32): Failure<int64, 0>",
      "local text = '123abc'",
      "local total = 0",
      "for i = 1, 10 do",
      "   local n, rest = strtol(text, 10)",
      "   total = total + n",
      "end",
   }, "\n")
   local result, diags = checked(outParameter)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   local loop = assert(code:match("for i = 1(.-)\nend"), "generated loop\n" .. code)
   assert(not loop:find("function", 1, true),
      "the out-parameter sequence is built in the loop:\n" .. loop)
   assert(code:find("const __nuppOut%d+ = function%(__nuppFn"),
      "the sequence is declared once for the module:\n" .. code)

   local dropped = table.concat({
      "cdef function free(takes value: voidptr)",
      "cdef function malloc(size: uint64): voidptr",
      "local function ownedMalloc(size: uint64): affine(voidptr, free)",
      "   return malloc(size)",
      "end",
      "local n = 0",
      "for i = 1, 10 do",
      "   local value = ownedMalloc(8)",
      "   n = n + 1",
      "   drop(value)",
      "end",
   }, "\n")
   result, diags = checked(dropped)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   assert(not code:find("(function() __nupp", 1, true),
      "the move is marked by a function built round the value:\n" .. code)
   assert(code:find("=false; __nuppDrop%d+%("),
      "the move is marked by a statement ahead of the drop:\n" .. code)
   assert(code:find("const __nuppDrop%d+ = function%(__nuppV%)"),
      "the cleanups a drop runs are declared once for the module:\n" .. code)
end

function M.cdefBorrowedOutputsTrackTheirInputOwner()
   local declarations = table.concat({
      "cdef function free(takes value: voidptr)",
      "cdef function make_owner_c(): voidptr",
      "local function make_owner(): affine(voidptr, free)",
      "   return make_owner_c()",
      "end",
      "cdef function get_view(borrows owner: voidptr,",
      "   out view: voidptr* borrows (owner)): Success<int32, 0>",
   }, "\n")
   assertEq(codes(declarations .. "\n" .. table.concat({
      "local owner = make_owner()",
      "local status, view = get_view(owner)",
      "drop(owner)",
   }, "\n")), "NUPP2602")
   assertClean(declarations .. "\n" .. table.concat({
      "local owner = make_owner()",
      "do",
      "   local status, view = get_view(owner)",
      "end",
      "drop(owner)",
   }, "\n"))
end

function M.cdefBorrowedOutputSourcesMustBeSharedInputs()
   assertEq(codes(table.concat({
      "cdef function get_view(owner: voidptr,",
      "   out view: voidptr* borrows (owner)): int32",
   }, "\n")), "NUPP2602")
end

function M.cdefBorrowRelationsBelongOnOutputs()
   assertEq(codes(table.concat({
      "cdef function get_view(borrows owner: voidptr borrows (owner)): int32",
   }, "\n")), "NUPP2602")
end

function M.cdefBorrowedOutputsMayNameSeveralSharedInputs()
   local declarations = table.concat({
      "cdef function free(takes value: voidptr)",
      "cdef function make_owner_c(): voidptr",
      "local function make_owner(): affine(voidptr, free)",
      "   return make_owner_c()",
      "end",
      "cdef function combine(borrows left: voidptr, borrows right: voidptr,",
      "   out view: voidptr* borrows (left, right)): int32",
   }, "\n")
   assertEq(codes(declarations .. "\n" .. table.concat({
      "local left = make_owner()",
      "local right = make_owner()",
      "local _, view = combine(left, right)",
      "drop(left)",
   }, "\n")), "NUPP2602")
   assertEq(codes(declarations .. "\n" .. table.concat({
      "local left = make_owner()",
      "local right = make_owner()",
      "local _, view = combine(left, right)",
      "drop(right)",
   }, "\n")), "NUPP2602")
end

function M.borrowedIsNotACompilerAnnotation()
   assertEq(codes(table.concat({
      "@borrowed(out = view, from = owner)",
      "cdef function get_view(borrows owner: voidptr,",
      "   out view: voidptr* borrows (owner)): int32",
   }, "\n")), "NUPP2111")
end

function M.stringDerivedPointersCannotEscape()
   assertEq(codes(table.concat({
      "local text = 'hello'",
      "local pointer = ffi.cast<cstring>(text)",
      "return pointer",
   }, "\n")), "NUPP2608")
   assertClean(table.concat({
      "cdef function strlen(value: cstring): uint64",
      "local text = 'hello'",
      "strlen(text)",
   }, "\n"))
   assertEq(codes(table.concat({
      "local text = 'hello'",
      "local pointer = ffi.cast<cstring>(text)",
      "text = 'other'",
      "print(pointer)",
   }, "\n")), "NUPP2602")
end

function M.callbackPointersRequireUnsafe()
   assertEq(codes("local cb = ffi.cast<voidptr>(function() end)"), "NUPP2604")
   -- Inside `unsafe` the cast is permitted, and what is left to say is the cost:
   -- the callback stays registered and a trace cannot compile through it. That
   -- is advice, so it is a lint and a project may wave it away.
   local permitted = table.concat({
      "unsafe do",
      "   local callback = function() end",
      "   local cb = ffi.cast<voidptr>(callback)",
      "   local handle = pin(cb, callback)",
      "end",
   }, "\n")
   assertEq(codes(permitted), "NUPP2502")
   assertClean('@allow("jit-callback")\n' .. permitted)
end

function M.rawPointerAccessRequiresUnsafe()
   local declarations = table.concat({
      "cdef struct RawBox",
      "   value: int32",
      "end",
      "local pointer = ffi.cast<RawBox*>(1)",
   }, "\n")
   assertEq(codes(declarations .. "\nprint(pointer.value)"), "NUPP2604")
   assertClean(declarations .. table.concat({
      "",
      "unsafe do",
      "   print(pointer.value)",
      "end",
   }, "\n"))
end

function M.rawPointerCallsRequireUnsafeOrAContract()
   local source = table.concat({
      "cdef function opaque_use(value: voidptr)",
      "local pointer = ffi.cast<voidptr>(1)",
   }, "\n")
   assertEq(codes(source .. "\nopaque_use(pointer)"), "NUPP2604")
   assertClean(source .. table.concat({
      "",
      "unsafe do",
      "   opaque_use(pointer)",
      "end",
   }, "\n"))
   assertClean(table.concat({
      "cdef function checked_use(borrows value: voidptr)",
      "local function inspect(borrows value: voidptr)",
      "   checked_use(value)",
      "end",
   }, "\n"))
end

function M.inferredBorrowsPermitSharedMutation()
   assertClean(table.concat({
      "cdef struct MutableBox",
      "   value: int32",
      "end",
      "local function increment(box: MutableBox*)",
      "   box.value = box.value + 1",
      "end",
   }, "\n"))
end

function M.pinsProveAndAnchorManagedPointers()
   assertClean(table.concat({
      "cdef function remember(retains value: cstring)",
      "cdef function forget(releases value: cstring)",
      "local text = 'hello'",
      "local pointer = ffi.cast<cstring>(text)",
      "local handle: pinned(cstring) = nupp.pin(pointer, text)",
      "remember(handle)",
      "forget(handle)",
   }, "\n"))

   assertEq(codes(table.concat({
      "local first = 'first'",
      "local second = 'second'",
      "local pointer = ffi.cast<cstring>(first)",
      "local handle = nupp.pin(pointer, second)",
   }, "\n")), "NUPP2604")
end

function M.retainedPinsMustFollowReleaseContracts()
   local prelude = table.concat({
      "cdef function remember(retains value: cstring)",
      "cdef function forget(releases value: cstring)",
      "local text = 'hello'",
      "local pointer = ffi.cast<cstring>(text)",
      "local handle = nupp.pin(pointer, text)",
   }, "\n")
   assertEq(codes(prelude .. "\nremember(handle)"), "NUPP2603")
   assertEq(codes(prelude .. "\nforget(handle)"), "NUPP2602")

   local got = codes(prelude .. table.concat({
      "",
      "remember(handle)",
      "remember(handle)",
      "forget(handle)",
   }, "\n"))
   assertEq(got, "NUPP2602")

   assertEq(codes(table.concat({
      "cdef function remember(retains value: cstring)",
      "local text = 'hello'",
      "local pointer = ffi.cast<cstring>(text)",
      "remember(pointer)",
   }, "\n")), "NUPP2602")
end

function M.pinnedArgumentsLowerToTheirCPointers()
   local source = table.concat({
      "cdef function remember(retains value: cstring)",
      "cdef function forget(releases value: cstring)",
      "local text = 'hello'",
      "local pointer = ffi.cast<cstring>(text)",
      "local handle = nupp.pin(pointer, text)",
      "remember(handle)",
      "forget(handle)",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   assert(code:find("{pointer=", 1, true)
      and code:find(",anchor=", 1, true),
      "pin keeps a strong anchor")
   assert(code:find("remember") and code:find(").pointer", 1, true),
      "retains passes the C pointer")
   assert(code:find("forget") and code:find(").pointer", 1, true),
      "releases passes the C pointer")
end

function M.rawTransferAndDropAreStaticAndDeterministic()
   local source = table.concat({
      "cdef function free(takes value: voidptr)",
      "cdef function malloc(size: uint64): voidptr",
      "local function ownedMalloc(size: uint64): affine(voidptr, free)",
      "   return malloc(size)",
      "end",
      "local value = ownedMalloc(8)",
      "local raw",
      "unsafe do",
      "   raw = unsafe release value",
      "   local restored = unsafe adopt raw as affine(voidptr, free)",
      "   drop(restored)",
      "end",
      "return true",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   assert(not code:find(".gc(", 1, true), "ownership emits no ffi.gc calls")
   assert(code:find("return cleanup(value)", 1, true),
      "drop calls the resolved cleanup")
   local chunk, loadErr = loadstring(code, "@ownership-runtime")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   assertEq(chunk(), true, "raw transfer runs without a double free")
end
function M.sameSpelledCleanupBindingsKeepDistinctReferences()
   local source = table.concat({
      "local calls = ''",
      "local record Resource end",
      "do",
      "   local function close(takes value: Resource): nil calls = calls .. 'a' end",
      "   local function open(): affine(Resource, close) return new Resource() end",
      "   local value = open()",
      "   drop(value)",
      "end",
      "do",
      "   local function close(takes value: Resource): nil calls = calls .. 'b' end",
      "   local function open(): affine(Resource, close) return new Resource() end",
      "   local value = open()",
      "   drop(value)",
      "end",
      "return calls",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   local chunk, loadErr = loadstring(code, "@ownership-cleanup-identity")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   assertEq(chunk(), "ab", "each contract kept its resolved binding")
end

function M.consumingCFunctionsNeedNoRuntimeDetachment()
   local source = table.concat({
      "cdef function free(takes value: voidptr)",
      "cdef function malloc(size: uint64): voidptr",
      "local function ownedMalloc(size: uint64): affine(voidptr, free)",
      "   return malloc(size)",
      "end",
      "local value = ownedMalloc(8)",
      "free(value)",
      "return true",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   assert(not code:find(".gc(", 1, true),
      "consuming C call has no finalizer detachment")
   local chunk, loadErr = loadstring(code, "@ownership-takes")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   assertEq(chunk(), true, "C consumption runs without a double free")
end

function M.ownershipLoweringEmitsLoadableTransparentValues()
   local source = table.concat({
      "cdef function free(takes value: voidptr)",
      "cdef function malloc(size: uint64): voidptr",
      "local function ownedMalloc(size: uint64): affine(voidptr, free)",
      "   return malloc(size)",
      "end",
      "local value = ownedMalloc(8)",
      "local raw",
      "unsafe do",
      "   raw = unsafe release value",
      "   local restored = unsafe adopt raw as affine(voidptr, free)",
      "   drop(restored)",
      "end",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0)
   local code = gen.generate(result, "ownership-test")
   assert(not code:find("__nuppRegisterOwner", 1, true),
      "affine introduction must not allocate or register a value wrapper")
   local chunk, loadErr = loadstring(code, "@ownership-transparent-lowering")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
end

-- `function m.f()` has to put f on the table the way `m.f = ...` does, which
-- means recording the path a later reference reads back. It did not, so `m.f`
-- resolved through an open table as `any`, and every annotation on it was
-- accepted and then meant nothing. An owning result is how that was noticed: the
-- obligation simply never existed.
function M.aQualifiedFunctionCarriesAnAutomaticallyDischargedOwnedContract()
   assertEq(codes(table.concat({
      "local m = {}",
      "local function closeFile(takes file: LuaFile): nil",
      "   file:close()",
      "end",
      "function m.open(path: string): affine(LuaFile, closeFile)",
      "   local file = io.stdin",
      "   return file",
      "end",
      "local handle = m.open('x')",
   }, "\n")), "",
      "the owner from m.open is tracked for automatic discharge")
end

function M.aFunctionValuedFieldCanDeclareAnOwningProducer()
   assertClean(table.concat({
      RESOURCE,
      "local record Api",
      "   open: function(): affine(resource*, resource_free)",
      "end",
      "local api: Api = nil as any",
      "local value = api.open()",
      "drop(value)",
   }, "\n"))
end

local MIGRATABLE_SESSION = table.concat({
   "local record Session",
   "   id: integer",
   "   function drop(takes self): nil",
   "      print(self.id)",
   "   end",
   "end",
   "local function closeSession(takes session: Session): nil unsafe do local _raw = unsafe release session end end",
}, "\n")
function M.ownedBorrowingCallableFieldKeepsItsDischargeObligation()
   assertClean(table.concat({
      MIGRATABLE_SESSION,
      "local record Pool",
      "   open: function(exclusive self: Pool): affine(Session, closeSession) borrows(self)",
      "end",
      "local pool: Pool = nil as any",
      "local session = pool:open()",
      "drop(session)",
   }, "\n"))
end

-- The same fix without the ownership: a qualified function is a typed function,
-- so its argument and its result are checked at the call.
function M.aQualifiedFunctionIsTypedAtItsCallSite()
   assertEq(codes(table.concat({
      "local m = {}",
      "function m.width(text: string): integer",
      "   return #text",
      "end",
      "local n: string = m.width(1)",
   }, "\n")), "NUPP2001 NUPP2006",
      "both the result and the argument are checked")
end

function M.aQualifiedFunctionAcquiresIntoAnAutomaticLocal()
   assertClean(table.concat({
      "local m = {}",
      "local function closeFile(takes file: LuaFile): nil",
      "   file:close()",
      "end",
      "function m.open(path: string): affine(LuaFile, closeFile)",
      "   local file = io.stdin",
      "   return file",
      "end",
      "function m.slurp(path: string): string",
      "   do",
      "      local file = m.open(path)",
      "      return file:read('*a')",
      "   end",
      "end",
   }, "\n"))
end

-- Every intrinsic is spelled bare or qualified with `nupp.`, and the two mean
-- the same thing: same diagnostics, same lowering.

function M.remainingOwnershipHelpersAnswerToTheirQualifiedSpelling()
   assertClean(table.concat({
      RESOURCE,
      "local value = resource_new()",
      "do",
      "   local view = nupp.borrow(value)",
      "end",
      "drop(value)",
   }, "\n"))
   assertClean(table.concat({
      "cdef function free(takes value: voidptr)",
      "cdef function malloc(size: uint64): voidptr",
      "local function ownedMalloc(size: uint64): affine(voidptr, free)",
      "   return malloc(size)",
      "end",
      "local value = ownedMalloc(8)",
      "unsafe do",
      "   local raw = unsafe release value",
      "   local owner = unsafe adopt raw as affine(voidptr, free)",
      "   do",
      "      local view = nupp.borrowFrom(raw, owner)",
      "   end",
      "   drop(owner)",
      "end",
   }, "\n"))
   assertClean(table.concat({
      "cdef function remember(retains value: cstring)",
      "cdef function forget(releases value: cstring)",
      "local text = 'hello'",
      "local pointer = ffi.cast<cstring>(text)",
      "local handle: pinned(cstring) = nupp.pin(pointer, text)",
      "remember(handle)",
      "forget(handle)",
   }, "\n"))
end

function M.disposeIsNotAnAnnotationAliasForDrop()
   assertEq(codes(table.concat({
      RESOURCE,
      "@dispose",
      "local function close(takes value: resource*)",
      "   resource_free(value)",
      "end",
   }, "\n")), "NUPP2111")
end

function M.qualifiedDisposeIsNotAnIntrinsicAliasForDrop()
   assertEq(codes(table.concat({
      RESOURCE,
      "local value = resource_new()",
      "nupp.dispose(value)",
   }, "\n")), "NUPP2004 NUPP2611")
end

function M.bothSpellingsOfDropLowerTheSameWay()
   local function lowered(call)
      local source = table.concat({
         "local calls = ''",
         "local record File",
         "   closed: boolean",
         "   function drop(takes self): nil",
         "      calls = calls .. 'close'",
         "   end",
         "end",
         "local function closeFile(takes file: File): nil",
         "   calls = calls .. 'close'",
         "   unsafe do local _raw = unsafe release file end",
         "end",
         "local function openFile(): affine(File, closeFile)",
         "   return new File(closed = false)",
         "end",
         "local file = openFile()",
         call,
         "return calls",
      }, "\n")
      local result, diags = checked(source)
      assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
      local code, genDiags = gen.generate(result, "ownership-test")
      assertEq(#genDiags, 0)
      local chunk, loadErr = loadstring(code, "@ownership-qualified-drop")
      assert(chunk, tostring(loadErr) .. "\n" .. code)
      assertEq(chunk(), "close", "the drop operation runs")
      return code
   end

   lowered("drop file")
   lowered("drop(file)")
end

function M.aBindingNamedNuppShadowsTheQualifiedSpelling()
   -- The intrinsic is reached through the compiler's own `nupp`, so a local of
   -- that name means what the program says it means, as any other name would.
   assertClean(table.concat({
      "local nupp = {",
      "   drop = function(value: integer): integer return value end",
      "}",
      "local answer = drop(3)",
   }, "\n"))
   -- and a local named after a bare intrinsic shadows it the same way
   assertClean(table.concat({
      "local function drop(value: integer): integer return value end",
      "local answer = drop(3)",
   }, "\n"))
end

function M.aQualifiedIntrinsicGivesItsParameterTheSameMode()
   -- Parameter modes are read out of a body before the names in it resolve, so
   -- both spellings have to be recognized by their spelling alone. Without that
   -- the helper below infers a plain parameter and the double release goes
   -- unreported.
   assertEq(codes(table.concat({
      RESOURCE,
      "local function release(value: resource*)",
      "   drop(value)",
      "end",
      "local value = resource_new()",
      "release(value)",
      "release(value)",
   }, "\n")), codes(table.concat({
      RESOURCE,
      "local function release(value: resource*)",
      "   drop(value)",
      "end",
      "local value = resource_new()",
      "release(value)",
      "release(value)",
   }, "\n")))
end

local CLOSURE_RESOURCE = table.concat({
   "local calls = 0",
   "local record ClosureResource",
   "   value: integer",
   "end",
   "local function closeClosureResource(takes value: ClosureResource): nil",
   "   calls = calls + 1",
   "end",
   "local function openClosureResource(value: integer): affine(ClosureResource, closeClosureResource)",
   "   return new ClosureResource(value = value)",
   "end",
}, "\n")

function M.aTakingClosureMovesItsCaptureAndIsSingleShot()
   assertEq(codes(CLOSURE_RESOURCE .. table.concat({
      "",
      "local resource = openClosureResource(7)",
      "local callback = function(): integer takes (resource)",
      "   return resource.value",
      "end",
      "print(resource.value)",
      "print(callback())",
      "print(callback())",
   }, "\n")), "NUPP2601 NUPP2601",
      "construction moves the capture and invocation moves the closure")
end

function M.aCalledTakingClosureCleansItsCapture()
   local source = CLOSURE_RESOURCE .. table.concat({
      "",
      "local resource = openClosureResource(7)",
      "local callback = function(): integer takes (resource)",
      "   return resource.value",
      "end",
      "local answer = callback()",
      "return answer, calls",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   local chunk, loadErr = loadstring(code, "@taking-closure-call")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   local answer, calls = chunk()
   assertEq(answer, 7)
   assertEq(calls, 1, "a called closure releases its capture once")
end

function M.anUncalledTakingClosureCleansItsCapture()
   local source = CLOSURE_RESOURCE .. table.concat({
      "",
      "do",
      "   local resource = openClosureResource(7)",
      "   local callback = function(): integer takes (resource)",
      "      return resource.value",
      "   end",
      "end",
      "return calls",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   local chunk, loadErr = loadstring(code, "@taking-closure-drop")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   assertEq(chunk(), 1, "an uncalled closure releases its capture once")
end

function M.aBorrowingClosureKeepsItsSourceLive()
   assertEq(codes(CLOSURE_RESOURCE .. table.concat({
      "",
      "local resource = openClosureResource(7)",
      "local callback = function() borrows (resource)",
      "   print(resource.value)",
      "end",
      "drop(resource)",
      "callback()",
   }, "\n")), "NUPP2602",
      "the source cannot be released while its closure remains live")
end

function M.aBorrowingClosureEndsItsBorrowWithItsScope()
   assertClean(CLOSURE_RESOURCE .. table.concat({
      "",
      "local resource = openClosureResource(7)",
      "do",
      "   local callback = function() borrows (resource)",
      "      print(resource.value)",
      "   end",
      "   callback()",
      "end",
      "drop(resource)",
   }, "\n"))
end

function M.borrowedClosureTypesNameTheirSiblingSource()
   assertClean(CLOSURE_RESOURCE .. table.concat({
      "",
      "local record ClosureHolder",
      "   source: affine(ClosureResource, closeClosureResource)",
      "   callback: function(): integer borrows (source)",
      "end",
   }, "\n"))
end

function M.aResultAnnotatedClosureInfersItsBorrowCapture()
   assertClean(CLOSURE_RESOURCE .. table.concat({
      "",
      "local resource = openClosureResource(7)",
      "do",
      "   local callback = function(): integer",
      "      return resource.value",
      "   end",
      "   print(callback())",
      "end",
      "drop(resource)",
   }, "\n"))
end

function M.resultAnnotatedClosuresComposeTakingAndBorrowedCaptures()
   assertClean(CLOSURE_RESOURCE .. table.concat({
      "",
      "local taken = openClosureResource(7)",
      "local borrowed = openClosureResource(5)",
      "local callback = function(): integer takes (taken) borrows (borrowed)",
      "   return taken.value + borrowed.value",
      "end",
      "print(callback())",
      "drop(borrowed)",
   }, "\n"))
end

function M.aTakingClosureReturnNeedsANameableAffineAnnotation()
   assertEq(codes(CLOSURE_RESOURCE .. table.concat({
      "",
      "local function make()",
      "   local resource = openClosureResource(7)",
      "   return function(): integer takes (resource)",
      "      return resource.value",
      "   end",
      "end",
      "local callback = make()",
      "print(callback())",
   }, "\n")), "NUPP2603")
end

function M.aTakesCallbackCannotEraseBorrowedClosureProvenance()
   assertEq(codes(CLOSURE_RESOURCE .. table.concat({
      "",
      "local function retain(takes callback: function(): any): affine(function(): any)",
      "   return callback",
      "end",
      "local resource = openClosureResource(7)",
      "local retained = retain(function(): any borrows (resource)",
      "   print(resource.value)",
      "end)",
      "drop(resource)",
      "retained()",
   }, "\n")), "NUPP2602",
      "only a scoped overload may accept a borrowed callback")
end

function M.pcallConsumesATakingClosure()
   local source = CLOSURE_RESOURCE .. table.concat({
      "",
      "local resource = openClosureResource(7)",
      "local ok, answer = pcall(function(): integer takes (resource)",
      "   return resource.value",
      "end)",
      "return ok, answer, calls",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   local chunk, loadErr = loadstring(code, "@taking-closure-pcall")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   local ok, answer, calls = chunk()
   assertEq(ok, true)
   assertEq(answer, 7)
   assertEq(calls, 1, "pcall's invoked closure releases its capture")
end

function M.raceDropsATakingLoserThatWasNeverEntered()
   local source = CLOSURE_RESOURCE .. table.concat({
      "",
      "local suspension = require('nupp.suspension')",
      "local entered = 0",
      "local first = openClosureResource(1)",
      "local second = openClosureResource(2)",
      "local answer, winner = suspension.race({",
      "   function(): integer takes (first)",
      "      return first.value",
      "   end,",
      "   function(): integer takes (second)",
      "      entered = entered + 1",
      "      return second.value",
      "   end,",
      "})",
      "return answer, winner, entered, calls",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   local chunk, loadErr = loadstring(code, "@taking-closure-race")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   local answer, winner, entered, calls = chunk()
   assertEq(answer, 1)
   assertEq(winner, 1)
   assertEq(entered, 0, "race did not enter the losing closure")
   assertEq(calls, 2, "race cleaned both the winner and unentered loser")
end

function M.raceAcceptsBorrowedClosuresWithoutRetainingThem()
   assertClean(CLOSURE_RESOURCE .. table.concat({
      "",
      "local suspension = require('nupp.suspension')",
      "local resource = openClosureResource(7)",
      "local answer = suspension.race({",
      "   function(): integer borrows (resource)",
      "      return resource.value",
      "   end,",
      "})",
      "print(answer)",
      "drop(resource)",
   }, "\n"))
end

-- A named cleanup identity can delegate to an ordinary method without giving the
-- method or its spelling compiler privilege.
local DROPPING_RECORD = table.concat({
   "local record Session",
   "   id: integer",
   "",
   "   drop: nosuspend function(takes self: Session): nil",
   "end",
   "function Session.drop(takes self): nil",
   "   unsafe do",
   "      local _raw = unsafe release self",
   "   end",
   "end",
   "local function closeSession(takes session: Session): nil unsafe do local _raw = unsafe release session end end",
}, "\n")

function M.anOwnedResultUsesTheTypesStructuralDropOperation()
   assertClean(DROPPING_RECORD .. table.concat({
      "",
      "local function open(id: integer): affine(Session, closeSession)",
      "   return new Session(id = id)",
      "end",
      "do",
      "   local session = open(7)",
      "   print(session.id)",
      "end",
   }, "\n"))
end

function M.anOwnedResultUsesALaterQualifiedStructuralDropOperation()
   local source = table.concat({
      "local m = {}",
      "record m.Session",
      "   id: integer",
      "   drop: nosuspend function(takes self: m.Session): nil",
      "end",
      "record m.Factory",
      "end",
      "function m.Session.drop(takes self): nil",
      "   local _raw = unsafe release self",
      "end",
      "function m.closeSession(takes session: m.Session): nil session:drop() end",
      "record m.Pool",
      "   open: function(): affine(m.Session, m.closeSession)",
      "end",
      "function m.Factory:open(): affine(m.Session, m.closeSession)",
      "   return new m.Session(id = 1)",
      "end",
      "do",
      "   local factory = new m.Factory()",
      "   local session = factory:open()",
      "   print(session.id)",
      "end",
      "return m",
   }, "\n")
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
   local path = dir .. "/src/main.nupp"
   local file = assert(io.open(path, "wb"))
   file:write(source)
   file:close()
   local project = envMod.new(dir, {config = {include = {"src"}}})
   local result = parser.parse(source, path)
   local diags = check.check(result, path, project)
   os.execute("rm -rf '" .. dir .. "'")
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-qualified-order-test")
   assertEq(#genDiags, 0)
   local chunk, loadErr = loadstring(code, "@ownership-qualified-order")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   assert(chunk())
end

function M.anOwnedResultCanNameAQualifiedFreeTerminal()
   local source = table.concat({
      "local m = {}",
      "m.closed = 0",
      "record m.Session",
      "   id: integer",
      "end",
      "function m.closeSession(takes session: m.Session): nil",
      "   m.closed = m.closed + 1",
      "   unsafe do",
      "      local _raw = unsafe release session",
      "   end",
      "end",
      "record m.Pool",
      "   open: function(): affine(m.Session, m.closeSession)",
      "end",
      "local pool = new m.Pool(",
      "   open = function(): affine(m.Session, m.closeSession)",
      "      return new m.Session(id = 1)",
      "   end",
      ")",
      "drop(pool.open())",
      "return m",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-qualified-free-drop-test")
   assertEq(#genDiags, 0)
   local chunk, loadErr = loadstring(code, "@ownership-qualified-free-drop")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   local module = chunk()
   assertEq(module.closed, 1, "the qualified terminal is registered and runs")
end

function M.aTransferFieldDoesNotInvokeItsValuesStructuralDropOperation()
   assertClean(table.concat({
      "local record Session",
      "   function drop(takes self): nil",
      "      local _raw = unsafe release self",
      "   end",
      "end",
      "local record Box",
      "   value: affine(Session)",
      "end",
      "local function open(): affine(Session)",
      "   return new Session()",
      "end",
      "local function box(takes value: Session): nil",
      "   local stored = new Box(value = value)",
      "   unsafe do",
      "      local _raw = unsafe release stored",
      "   end",
      "end",
      "box(open())",
   }, "\n"))
end

function M.anAffineResultNeedsOneCleanupOrExplicitTransferOnlyPolicy()
   assertEq(codes(table.concat({
      "local function allocate(): affine(voidptr, missingCleanup)",
      "   return nil as any",
      "end",
   }, "\n")), "NUPP2131", "a missing cleanup function is reported once")

   assertClean(table.concat({
      "local function allocate(): affine(voidptr)",
      "   return nil as any",
      "end",
      "local value = allocate()",
      "unsafe do",
      "   local _raw = unsafe release value",
      "end",
   }, "\n"))
end

function M.anOwnedResultCannotSilentlyDiscardExtraTerminals()
   local _, diagnostics = checked(table.concat({
      "cdef function stop(takes value: voidptr)",
      "cdef function release(takes value: voidptr)",
      "local allocate: function(): affine(voidptr, stop, release)",
   }, "\n"))
   assertEq(#diagnostics, 1, diagnostics[2] and diagnostics[2].msg or "one diagnostic")
   assertEq(diagnostics[1].code, "NUPP2421")
end

-- Every result position is resolved, so a function may own its second result and
-- not only its first.
function M.aNonFirstResultMayBeOwned()
   assertClean(DROPPING_RECORD .. table.concat({
      "",
      "local function openLogged(id: integer): (integer, affine(Session, closeSession))",
      "   return id * 2, new Session(id = id)",
      "end",
      "do",
      "   local code, session = openLogged(7)",
      "   print(code + session.id)",
      "end",
   }, "\n"))
end

function M.anOwnedNonFirstResultIsDestroyedAtItsScope()
   local source = DROPPING_RECORD .. table.concat({
      "",
      "local function openLogged(id: integer): (integer, affine(Session, closeSession))",
      "   return id * 2, new Session(id = id)",
      "end",
      "local function use(): integer",
      "   local code, session = openLogged(7)",
      "   return code",
      "end",
      "return use",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   assert(code:find("__nuppCleanup", 1, true),
      "the second result is discharged at scope exit: " .. code)
end

function M.anOwnedResultDeclaresAnOwningResult()
   assertClean(DROPPING_RECORD .. table.concat({
      "",
      "local function open(id: integer): affine(Session, closeSession)",
      "   return new Session(id = id)",
      "end",
      "do",
      "   local session = open(7)",
      "   print(session.id)",
      "end",
   }, "\n"))
end

-- A cleanup key names the function in the generated registry and reaches the
-- interned identity of every owned type discharged by it. Deriving it from a byte
-- offset moved it whenever unrelated text above the declaration moved, so a type
-- built after an edit stopped matching the same type read from the cache.
function M.aCleanupKeyDoesNotMoveWithTextAboveIt()
   local body = table.concat({
      "local function use(): integer",
      "   do",
      "      local value = resource_new()",
      "      return value.value",
      "   end",
      "end",
      "return use",
   }, "\n")
   local function keysOf(source)
      local result, diags = checked(source)
      assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
      local code, genDiags = gen.generate(result, "ownership-test")
      assertEq(#genDiags, 0)
      local found = {}
      for key in code:gmatch('"([%w%-%._]+#[%w_#]+)"') do
         found[#found + 1] = key
      end
      table.sort(found)
      assert(#found > 0, "no cleanup key was emitted: " .. code)
      return table.concat(found, ",")
   end

   local plain = keysOf(RESOURCE .. "\n" .. body)
   local shifted = keysOf("-- a comment that shifts every offset below it\n"
      .. "-- and a second line of it\n" .. RESOURCE .. "\n" .. body)
   assertEq(shifted, plain, "the cleanup key moved with text above the declaration")
end

-- A terminal named only in a type still has to publish the function before a
-- top-level owner can leave the module scope and ask the lazy resolver for it.
function M.aTerminalNamedInATypeIsRegisteredAtItsDeclaration()
   local source = table.concat({
      "cdef function malloc(size: uint64): voidptr",
      "cdef function free(takes value: voidptr)",
      "local function allocate(): affine(voidptr, free)",
      "   return malloc(8)",
      "end",
      "local value = allocate()",
      "return true",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   assert(code:find('["ownership-test.g.nupp#free"]=free', 1, true),
      "the cleanup declaration did not publish its function: " .. code)

   local previous = _G.__nuppCleanupRegistry
   _G.__nuppCleanupRegistry = nil
   local ok, answer = pcall(assert(loadstring(code)))
   _G.__nuppCleanupRegistry = previous
   assert(ok, tostring(answer) .. "\n" .. code)
   assertEq(answer, true, "the top-level owner was not discharged")
end

function M.closeableTypesCarryAnInherentCloseObligation()
   assertClean(table.concat({
      "local record Client is nupp.Closeable",
      "   function flush(exclusive self): nil end",
      "   function close(takes self): nil end",
      "end",
      "local client = new Client()",
      "client:flush()",
   }, "\n"))
end

function M.affineOfAnAffineInterfaceSelectsItsInherentTerminal()
   assertClean(table.concat({
      "local affine interface Sink is nupp.Closeable",
      "   terminal close: nosuspend function(takes self: Sink): nil",
      "end",
      "local record BufferSink is Sink",
      "   anchor: any",
      "   function close(takes self): nil end",
      "end",
      "local function open(borrows anchor: any): affine(Sink) borrows (anchor)",
      "   return new BufferSink(anchor = anchor)",
      "end",
      "local anchor = {}",
      "local sink = open(anchor)",
      "sink:close()",
   }, "\n"))
end

function M.constructorsMayInitializeCloseableFields()
   assertClean(table.concat({
      "local record Resource is nupp.Closeable",
      "   function close(takes self): nil end",
      "end",
      "local record Pair",
      "   first: Resource?",
      "   second: Resource?",
      "   constructor(self, first: boolean, second: boolean)",
      "      if first then self.first = new Resource() end",
      "      if second then self.second = new Resource() end",
      "   end",
      "end",
      "local pair = new Pair(true, true)",
   }, "\n"))
end

function M.consumingAggregatesMayForwardTheWholeOwner()
   assertClean(table.concat({
      "local record Resource is nupp.Closeable",
      "   function close(takes self): nil end",
      "end",
      "local record Box",
      "   value: Resource",
      "   function finish(takes self): nil",
      "      self.value:close()",
      "   end",
      "   function close(takes self): nil",
      "      self:finish()",
      "   end",
      "end",
      "local box = new Box(value = new Resource())",
      "box:close()",
   }, "\n"))
end

function M.aggregatesOwnTheAffineMemberActuallyStoredInAUnionField()
   local source = table.concat({
      "local calls = ''",
      "local record Resource is nupp.Closeable",
      "   name: string",
      "   function close(takes self): nil calls = calls .. self.name end",
      "end",
      "local type Item = Resource | string",
      "local record Box",
      "   item: Item",
      "end",
      "do",
      "   local box = new Box(item = new Resource(name = 'r'))",
      "   print(box.item)",
      "end",
      "do",
      "   local box = new Box(item = 'plain')",
      "   print(box.item)",
      "end",
      "return calls",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   local chunk, loadErr = loadstring(code, "@ownership-affine-union-field")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   assertEq(chunk(), "r", "only the affine union member is closed")
end

function M.affineInterfacesRequireOneValidTerminal()
   assertEq(codes(table.concat({
      "local affine interface Broken",
      "   terminal close: function(self: Broken): boolean",
      "end",
   }, "\n")), "NUPP2615")

   local conflicts = codes(table.concat({
      "local affine interface First",
      "   terminal close: nosuspend function(takes self: First): nil",
      "end",
      "local affine interface Second",
      "   terminal destroy: nosuspend function(takes self: Second): nil",
      "end",
      "interface Both is First, Second end",
   }, "\n"))
   assert(conflicts:find("NUPP2615", 1, true), conflicts)
end

return M
