local parser = require("compiler.parser")
local check = require("fragment")
local gen = require("compiler.gen")
local envMod = require("compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function checked(source)
   local result = parser.parse(source, "ownership-test.g.nupp")
   assertEq(#result.errors, 0, "syntax: "
      .. (result.errors[1] and result.errors[1].msg or ""))
   local diags = check.check(result, "ownership-test.g.nupp", env)
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
   "@owned(resource_free)",
   "cdef function resource_new(): resource*",
   "cdef function resource_free(takes value: resource*)",
}, "\n")

local M = {}

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
   "local function close_pool(p: Pool) end",
   "@owned(close_pool)",
   "local function open_pool(): Pool",
   "   return new Pool {items = {}}",
   "end",
   "function Pool:get(index: integer): Res borrows self",
   "   return self.items[index]",
   "end",
   "local function peek(borrows p: Pool): Pool borrows p",
   "   return p",
   "end",
}, "\n")

function M.aBorrowedResultBlocksReleasingItsSource()
   assertEq(codes(POOL .. table.concat({
      "",
      "local pool = open_pool()",
      "local held = peek(pool)",
      "dispose(pool)",
      "print(held.items)",
   }, "\n")), "NUPP2603 NUPP2602")
end

function M.aMethodResultCanBorrowTheReceiver()
   assertEq(codes(POOL .. table.concat({
      "",
      "local pool = open_pool()",
      "local item = pool:get(1)",
      "dispose(pool)",
      "print(item.name)",
   }, "\n")), "NUPP2603 NUPP2602")
end

function M.aBorrowedResultIsReleasedWithItsScope()
   assertClean(POOL .. table.concat({
      "",
      "local pool = open_pool()",
      "do",
      "   local item = pool:get(1)",
      "   print(item.name)",
      "end",
      "dispose(pool)",
   }, "\n"))
end

-- The container case reaches the pool through a `with` binding, which is
-- itself a borrow, so this only works if borrowing a borrow is allowed.
function M.anElementCanBeBorrowedThroughAWithBinding()
   assertClean(POOL .. table.concat({
      "",
      "local function use(): string",
      "   with pool = open_pool() do",
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
      "   with pool = open_pool() do",
      "      return peek(pool)",
      "   end",
      "end",
   }, "\n")), "NUPP2603")
end

function M.borrowingAConsumedParameterIsRejected()
   assertEq(codes(POOL .. table.concat({
      "",
      "local function eat(takes p: Pool): Pool borrows p",
      "   return p",
      "end",
   }, "\n")), "NUPP2603 NUPP2618 NUPP2603")
end

function M.borrowingSomethingThatIsNotAParameterIsRejected()
   assertEq(codes(POOL .. table.concat({
      "",
      "local function odd(borrows p: Pool): Pool borrows q",
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
   }, "\n")), "NUPP2603")
end

-- Borrowing a borrow needs no separate machinery: a borrow can only be bound
-- in the scope that creates it — it cannot be assigned outward, stored, or
-- returned without a declaration — so a derived borrow can never outlive the
-- one it came from, and the intermediate keeps the root borrowed meanwhile.

-- On a method there is only one thing a source-less borrow could mean, so
-- `borrowed<T>` elides to `borrows self`, the way Rust elides an output
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
   "local function close_socket(s: Socket) end",
   "local function close_tls(t: TLS) end",
   "@owned(close_socket)",
   "local function open_socket(): Socket",
   "   return new Socket {fd = 1}",
   "end",
   "@owned(close_tls)",
   "local function open_tls(borrows s: Socket): TLS borrows s",
   "   return new TLS {s = s}",
   "end",
}, "\n")

function M.anOwningResultCanRetainAnInputBorrow()
   assertClean(LAYERED .. table.concat({
      "",
      "local sock = open_socket()",
      "local tls = open_tls(sock)",
      "dispose(tls)",
      "dispose(sock)",
   }, "\n"))
end

function M.theHeldSourceCannotBeReleasedFirst()
   assertEq(codes(LAYERED .. table.concat({
      "",
      "local sock = open_socket()",
      "local tls = open_tls(sock)",
      "dispose(sock)",
      "dispose(tls)",
   }, "\n")), "NUPP2603 NUPP2602")
end

-- The layered case a `with` was always meant to express. Reverse cleanup
-- already releases the session before the socket, which is exactly the order
-- the borrow requires.
function M.layeredResourcesHoldTogetherInAScope()
   assertClean(LAYERED .. table.concat({
      "",
      "local function use()",
      "   with sock = open_socket(), tls = open_tls(sock) do",
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
      "dispose(sock)",
   }, "\n")), "NUPP2603 NUPP2603 NUPP2602")
end

function M.aMethodBorrowedReturnElidesToTheReceiver()
   assertEq(codes(POOL .. table.concat({
      "",
      "function Pool:first(): borrowed<Res>",
      "   return self.items[1]",
      "end",
      "local pool = open_pool()",
      "local item = pool:first()",
      "dispose(pool)",
      "print(item.name)",
   }, "\n")), "NUPP2603 NUPP2602")
end

function M.aMethodReturningAPlainValueDoesNotBorrow()
   assertClean(POOL .. table.concat({
      "",
      "function Pool:count(): integer",
      "   return #self.items",
      "end",
      "local pool = open_pool()",
      "local n = pool:count()",
      "dispose(pool)",
      "print(n)",
   }, "\n"))
end

function M.anExplicitSourceStillWinsOverElision()
   assertEq(codes(POOL .. table.concat({
      "",
      "function Pool:other(borrows p: Pool): Res borrows p",
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
      "dispose(pool)",
      "print(second.items)",
   }, "\n")), "NUPP2603 NUPP2602")
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
      "dispose(pool)",
   }, "\n")), "NUPP2603 NUPP2603 NUPP2602")
end

function M.aDerivedBorrowCannotBeStored()
   assertEq(codes(POOL .. table.concat({
      "",
      "local pool = open_pool()",
      "local sink: {Pool} = {}",
      "local first = peek(pool)",
      "sink[1] = peek(first)",
      "dispose(pool)",
   }, "\n")), "NUPP2603 NUPP2603 NUPP2602")
end

-- The declaration is the contract: a result declared `borrows p` may be
-- derived through any number of intermediates, and the checker takes the
-- annotation's word for what it roots at, exactly as it does for @owned.
function M.aBorrowMayBeDerivedThroughAnIntermediate()
   assertClean(POOL .. table.concat({
      "",
      "local function deep(borrows p: Pool): Pool borrows p",
      "   local mid = peek(p)",
      "   return peek(mid)",
      "end",
   }, "\n"))
end

function M.liveOwnersMustBeDischarged()
   assertEq(codes(RESOURCE .. "\nlocal value = resource_new()"), "NUPP2603")
   assertEq(codes(RESOURCE .. "\nresource_new()"), "NUPP2605")
end

function M.opaqueOwnersAreTransferOnly()
   local opaque = table.concat({
      "@owned(opaque = true)",
      "cdef function resource_new(): voidptr",
      "cdef function resource_take(takes value: voidptr)",
   }, "\n")
   assertClean(opaque .. "\nlocal value = resource_new()\nresource_take(value)")
   assertEq(codes(opaque .. "\nlocal value = resource_new()\ndispose(value)"),
      "NUPP2602")
end

function M.bareOwnedUsesTheDeclaredDefaultDisposer()
   local source = table.concat({
      "local calls = ''",
      "local record File",
      "   closed: boolean",
      "   @dispose",
      "   function close()",
      "      calls = calls .. 'close'",
      "      self.closed = true",
      "   end",
      "end",
      "@owned",
      "local function openFile(): File",
      "   return new File {closed = false}",
      "end",
      "local file = openFile()",
      "dispose(file)",
      "return calls",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   local chunk, loadErr = loadstring(code, "@ownership-default-dispose")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   assertEq(chunk(), "close", "default disposer runs")
end

function M.defaultDisposersAreInheritedFromInterfaces()
   assertClean(table.concat({
      "local interface Closeable",
      "   @dispose",
      "   close: function(takes value: self): nil",
      "end",
      "local record File is Closeable",
      "   closed: boolean",
      "end",
      "function File:close() self.closed = true end",
      "@owned",
      "local function openFile(): File",
      "   return new File {closed = false}",
      "end",
      "with file = openFile() do print(file.closed) end",
   }, "\n"))
end

function M.bareOwnedRejectsMissingAndAmbiguousDefaults()
   assertEq(codes(table.concat({
      "local record File",
      "   closed: boolean",
      "end",
      "@owned",
      "local function openFile(): File return new File {closed = false} end",
   }, "\n")), "NUPP2602")

   assertEq(codes(table.concat({
      "local interface Stops",
      "   @dispose",
      "   stop: function(takes value: self): nil",
      "end",
      "local interface Closes",
      "   @dispose",
      "   close: function(takes value: self): nil",
      "end",
      "local record File is Stops, Closes",
      "   closed: boolean",
      "end",
      "@owned",
      "local function openFile(): File return new File {closed = false} end",
   }, "\n")), "NUPP2602")
end

function M.disposeContractsMustTakeTheirResource()
   assertEq(codes(table.concat({
      "local record File end",
      "@dispose",
      "local function closeFile(borrows file: File) end",
   }, "\n")), "NUPP2602")
end

function M.ownershipQualifiersAndParameterModesAreTyped()
   assertClean(RESOURCE .. table.concat({
      "",
      "local function inspect(borrows value: resource*): int32",
      "   return value.value",
      "end",
      "local value: owned<resource*> = resource_new()",
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
   }, "\n")), "NUPP2603")
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
   }, "\n")), "NUPP2602")

   assertEq(codes(RESOURCE .. table.concat({
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
   }, "\n")), "NUPP2602")
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
      "cdef function free(takes value: voidptr)",
      "@owned(free)",
      "cdef function maybe_new(): maybe_resource*?",
      "local value = maybe_new()",
      "if value then",
      "   print(value.value)",
      "   dispose(value)",
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
   assertEq(codes("local value: owned<number>"), "")
   assertEq(codes("local value: borrowed<string>"), "")
   assertEq(codes("local value: pinned<boolean>"), "NUPP2602")
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
      "local function bad(borrows value: resource*): borrowed<resource*>",
      "   return value",
      "end",
   }, "\n")
   assertEq(codes(returned), "NUPP2603")

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

function M.ownersAndBorrowsCannotBeCaptured()
   local got = codes(RESOURCE .. table.concat({
      "",
      "local function callback(borrows value: resource*): function(): int32",
      "   return function(): int32",
      "      return value.value",
      "   end",
      "end",
   }, "\n"))
   assertEq(got, "NUPP2603")
end

function M.rawReconstructionRequiresUnsafe()
   assertEq(codes(RESOURCE .. table.concat({
      "",
      "local raw: resource*",
      "local value = fromRaw(raw, resource_free)",
      "resource_free(value)",
   }, "\n")), "NUPP2604")

   assertClean(RESOURCE .. table.concat({
      "",
      "local raw: resource*",
      "unsafe do",
      "   local value = fromRaw(raw, resource_free)",
      "   dispose(value)",
      "end",
   }, "\n"))
   assertEq(codes(table.concat({
      "local raw: voidptr",
      "local function wrong(value: string) end",
      "unsafe do",
      "   local value = fromRaw(raw, wrong)",
      "end",
   }, "\n")), "NUPP2603 NUPP2602")
end

function M.rawAbandonmentRequiresUnsafe()
   assertEq(codes(RESOURCE .. table.concat({
      "",
      "local value = resource_new()",
      "local raw = intoRaw(value)",
      "print(raw)",
   }, "\n")), "NUPP2604")
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
      "local function fake(borrows source: resource*): resource* borrows source",
      "   local raw: resource*",
      "   return raw",
      "end",
   }, "\n")), "NUPP2619")
end

function M.borrowFromRestoresOpaqueProvenanceExplicitly()
   assertClean(RESOURCE .. table.concat({
      "",
      "local function recover(borrows source: resource*, raw: resource*): resource* borrows source",
      "   unsafe do",
      "      return borrowFrom(raw, source)",
      "   end",
      "end",
   }, "\n"))
   assertEq(codes(RESOURCE .. table.concat({
      "",
      "local function recover(borrows source: resource*, raw: resource*): resource* borrows source",
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
      "local function closePair(pair: Pair) end",
      "@owned(closePair)",
      "local function pair(borrows left: resource*, borrows right: resource*)",
      "   : Pair borrows(left, right)",
      "   return new Pair {left = left, right = right}",
      "end",
   }, "\n")
   assertClean(source .. table.concat({
      "",
      "local left = resource_new()",
      "local right = resource_new()",
      "local joined = pair(left, right)",
      "dispose(joined)",
      "resource_free(right)",
      "resource_free(left)",
   }, "\n"))
   assertEq(codes(source .. table.concat({
      "",
      "local left = resource_new()",
      "local right = resource_new()",
      "local joined = pair(left, right)",
      "resource_free(left)",
      "dispose(joined)",
      "resource_free(right)",
   }, "\n")), "NUPP2603 NUPP2602")
end

function M.affineRecordsDisposeOwnedFieldsInReverseOrder()
   local source = table.concat({
      "local calls = ''",
      "local record Res",
      "   name: string",
      "end",
      "local function closeRes(value: Res)",
      "   calls = calls .. value.name",
      "end",
      "@owned(closeRes)",
      "local function openRes(name: string): Res",
      "   return new Res {name = name}",
      "end",
      "local record Bundle",
      "   first: owned<Res>",
      "   second: owned<Res>",
      "end",
      "local bundle = new Bundle {first = openRes('a'), second = openRes('b')}",
      "dispose(bundle)",
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

function M.affineRecordsRejectPartialFieldMoves()
   local got = codes(table.concat({
      "local record Res end",
      "local function closeRes(value: Res) end",
      "@owned(closeRes)",
      "local function openRes(): Res return new Res {} end",
      "local record Bundle",
      "   value: owned<Res>",
      "end",
      "local bundle = new Bundle {value = openRes()}",
      "local value = bundle.value",
   }, "\n"))
   assert(got:find("NUPP2602", 1, true),
      "partial field move is rejected: " .. got)
end

function M.customDisposersMustDischargeEveryOwnedField()
   local prefix = table.concat({
      "local record Res end",
      "@dispose",
      "local function closeRes(takes value: Res) end",
      "@owned(closeRes)",
      "local function openRes(): Res return new Res {} end",
   }, "\n")
   assertClean(prefix .. "\n" .. table.concat({
      "local record Bundle",
      "   first: owned<Res>",
      "   second: owned<Res>",
      "   @dispose",
      "   function close()",
      "      closeRes(self.second)",
      "      closeRes(self.first)",
      "   end",
      "end",
      "local bundle = new Bundle {first = openRes(), second = openRes()}",
      "dispose(bundle)",
   }, "\n"))
   assertEq(codes(prefix .. "\n" .. table.concat({
      "local record Bundle",
      "   first: owned<Res>",
      "   second: owned<Res>",
      "   @dispose",
      "   function close()",
      "      closeRes(self.second)",
      "   end",
      "end",
   }, "\n")), "NUPP2603")
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

function M.cdefOwnedOutputsBecomeLuaReturns()
   local source = table.concat({
      "cdef function free(takes value: voidptr)",
      "@owned(out = result, cleanup = free, success = zero)",
      "cdef function posix_memalign(out result: voidptr*, alignment: uint64, size: uint64): int32",
      "local status, pointer = posix_memalign(16, 64)",
      "if pointer then dispose(pointer) end",
      "return status == 0",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   assert(code:find('__nuppFfi.new("void *[1]")', 1, true),
      "allocates the logical out slot")
   assert(code:find('const __nuppFfi = require("ffi")', 1, true), code)
   assert(code:find("const posix_memalign = __nuppFfi.C.posix_memalign", 1, true),
      code)
   assert(code:find('const __nuppT', 1, true),
      "out holders and status are const: " .. code)
   local chunk, loadErr = loadstring(code, "@ownership-cdef-out")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   assertEq(chunk(), true, "owned out pointer is returned and disposed")
end

function M.failedOwnedOutputsAreNil()
   local source = table.concat({
      "cdef function free(takes value: voidptr)",
      "@owned(out = result, cleanup = free, success = zero)",
      "cdef function posix_memalign(out result: voidptr*, alignment: uint64, size: uint64): int32",
      "local status, pointer = posix_memalign(3, 64)",
      "local failed = pointer == nil",
      "if pointer then dispose(pointer) end",
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
      "@owned(out = result, cleanup = free, success = zero)",
      "cdef function posix_memalign(out result: voidptr*, alignment: uint64, size: uint64): int32",
      "posix_memalign(16, 64)",
   }, "\n")), "NUPP2605")
end

function M.multipleOwnedOutputsPreserveCAndLuaOrder()
   local source = table.concat({
      "cdef function free(takes value: voidptr)",
      "@owned(out = first, cleanup = free, success = 7)",
      "@owned(out = second, cleanup = free, success = 7)",
      "cdef function make_pair(out first: voidptr*, seed: int32, out second: voidptr*): int32",
      "local status, first, second = make_pair(1)",
      "if second then dispose(second) end",
      "if first then dispose(first) end",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   assert(code:find("make_pair%s*%(%s*__nupp")
      and code:find(",%s*1%s*,%s*__nupp"),
      "holders remain in their declared C parameter positions\n" .. code)
   assert(code:find("==7 and", 1, true),
      "literal success predicates guard outputs")
end

function M.cdefBorrowedOutputsTrackTheirInputOwner()
   local declarations = table.concat({
      "cdef function free(takes value: voidptr)",
      "@owned(free)",
      "cdef function make_owner(): voidptr",
      "@borrowed(out = view, from = owner, success = zero)",
      "cdef function get_view(borrows owner: voidptr, out view: voidptr*): int32",
   }, "\n")
   assertEq(codes(declarations .. "\n" .. table.concat({
      "local owner = make_owner()",
      "local status, view = get_view(owner)",
      "dispose(owner)",
   }, "\n")), "NUPP2603 NUPP2602")
   assertClean(declarations .. "\n" .. table.concat({
      "local owner = make_owner()",
      "do",
      "   local status, view = get_view(owner)",
      "end",
      "dispose(owner)",
   }, "\n"))
end

function M.cdefBorrowedOutputSourcesMustBeSharedInputs()
   assertEq(codes(table.concat({
      "@borrowed(out = view, from = owner)",
      "cdef function get_view(owner: voidptr, out view: voidptr*): int32",
   }, "\n")), "NUPP2602")
end

function M.stringDerivedPointersCannotEscape()
   assertEq(codes(table.concat({
      "local text = 'hello'",
      "local pointer = ffi.cast<cstring>(text)",
      "return pointer",
   }, "\n")), "NUPP2603")
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
      "local handle: pinned<cstring> = pin(pointer, text)",
      "remember(handle)",
      "forget(handle)",
   }, "\n"))

   assertEq(codes(table.concat({
      "local first = 'first'",
      "local second = 'second'",
      "local pointer = ffi.cast<cstring>(first)",
      "local handle = pin(pointer, second)",
   }, "\n")), "NUPP2604")
end

function M.retainedPinsMustFollowReleaseContracts()
   local prelude = table.concat({
      "cdef function remember(retains value: cstring)",
      "cdef function forget(releases value: cstring)",
      "local text = 'hello'",
      "local pointer = ffi.cast<cstring>(text)",
      "local handle = pin(pointer, text)",
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
      "local handle = pin(pointer, text)",
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

function M.rawTransferAndDisposalAreStaticAndDeterministic()
   local source = table.concat({
      "cdef function free(takes value: voidptr)",
      "@owned(free)",
      "cdef function malloc(size: uint64): voidptr",
      "local value = malloc(8)",
      "local raw",
      "unsafe do",
      "   raw = intoRaw(value)",
      "   local restored = fromRaw(raw, free)",
      "   dispose(restored)",
      "end",
      "return true",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   assert(not code:find(".gc(", 1, true), "ownership emits no ffi.gc calls")
   assert(code:find("free(__p)", 1, true), "dispose calls cleanup directly")
   local chunk, loadErr = loadstring(code, "@ownership-runtime")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   assertEq(chunk(), true, "raw transfer runs without a double free")
end

function M.multipleCleanupsRunInAnnotationOrder()
   local source = table.concat({
      "local calls = ''",
      "local function stop(value: voidptr) calls = calls .. 'stop' end",
      "local function release(value: voidptr) calls = calls .. ',release' end",
      "@owned(stop, release)",
      "local function make(): voidptr",
      "   local raw = ffi.cast<voidptr>(1)",
      "   unsafe do return fromRaw(raw, stop, release) end",
      "end",
      "local value = make()",
      "dispose(value)",
      "return calls",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
   local code, genDiags = gen.generate(result, "ownership-test")
   assertEq(#genDiags, 0)
   assert(not code:find(".gc(", 1, true), "@owned emits no ffi.gc call")
   local chunk, loadErr = loadstring(code, "@ownership-cleanup-order")
   assert(chunk, tostring(loadErr) .. "\n" .. code)
   assertEq(chunk(), "stop,release", "cleanup order")
end

function M.consumingCFunctionsNeedNoRuntimeDetachment()
   local source = table.concat({
      "cdef function free(takes value: voidptr)",
      "@owned(free)",
      "cdef function malloc(size: uint64): voidptr",
      "local value = malloc(8)",
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

function M.ownershipLoweringPreservesLineCount()
   local source = table.concat({
      "cdef function free(takes value: voidptr)",
      "@owned(free)",
      "cdef function malloc(size: uint64): voidptr",
      "local value = malloc(8)",
      "local raw",
      "unsafe do",
      "   raw = intoRaw(value)",
      "   local restored = fromRaw(raw, free)",
      "   dispose(restored)",
      "end",
   }, "\n")
   local result, diags = checked(source)
   assertEq(#diags, 0)
   local code = gen.generate(result, "ownership-test")
   local _, sourceLines = source:gsub("\n", "")
   local _, codeLines = code:gsub("\n", "")
   assertEq(codeLines, sourceLines + 1,
      "generated output has the source line count plus terminal newline")
end

-- `function m.f()` has to put f on the table the way `m.f = ...` does, which
-- means recording the path a later reference reads back. It did not, so `m.f`
-- resolved through an open table as `any`, and every annotation on it was
-- accepted and then meant nothing. `@owned` is how that was noticed: the
-- obligation simply never existed.
function M.aQualifiedFunctionCarriesItsOwnedContract()
   assertEq(codes(table.concat({
      "local m = {}",
      "local function closeFile(file: LuaFile)",
      "   file:close()",
      "end",
      "@owned(closeFile)",
      "function m.open(path: string): LuaFile",
      "   local file = io.open(path, 'r')",
      "   if not file then error('cannot open') end",
      "   return file",
      "end",
      "local handle = m.open('x')",
   }, "\n")), "NUPP2603",
      "the owner from m.open still has to be discharged")
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

function M.aQualifiedFunctionAcquiresIntoAWith()
   assertClean(table.concat({
      "local m = {}",
      "local function closeFile(file: LuaFile)",
      "   file:close()",
      "end",
      "@owned(closeFile)",
      "function m.open(path: string): LuaFile",
      "   local file = io.open(path, 'r')",
      "   if not file then error('cannot open') end",
      "   return file",
      "end",
      "function m.slurp(path: string): string",
      "   with file = m.open(path) do",
      "      return file:read('*a')",
      "   end",
      "end",
   }, "\n"))
end

-- Every intrinsic is spelled bare or qualified with `nupp.`, and the two mean
-- the same thing: same diagnostics, same lowering.

function M.everyIntrinsicAnswersToItsQualifiedSpelling()
   assertClean(RESOURCE .. "\nlocal value = resource_new()\nnupp.dispose(value)")
   assertClean(table.concat({
      RESOURCE,
      "local value = resource_new()",
      "do",
      "   local view = nupp.borrow(value)",
      "end",
      "dispose(value)",
   }, "\n"))
   assertClean(table.concat({
      "cdef function free(takes value: voidptr)",
      "@owned(free)",
      "cdef function malloc(size: uint64): voidptr",
      "local value = malloc(8)",
      "unsafe do",
      "   local raw = nupp.intoRaw(value)",
      "   local owner = nupp.fromRaw(raw, free)",
      "   do",
      "      local view = nupp.borrowFrom(raw, owner)",
      "   end",
      "   nupp.dispose(owner)",
      "end",
   }, "\n"))
   assertClean(table.concat({
      "cdef function remember(retains value: cstring)",
      "cdef function forget(releases value: cstring)",
      "local text = 'hello'",
      "local pointer = ffi.cast<cstring>(text)",
      "local handle: pinned<cstring> = nupp.pin(pointer, text)",
      "remember(handle)",
      "forget(handle)",
   }, "\n"))
   -- and it is refused for the same reasons the bare spelling is
   assertEq(codes(table.concat({
      "cdef function free(takes value: voidptr)",
      "@owned(free)",
      "cdef function malloc(size: uint64): voidptr",
      "local value = malloc(8)",
      "local raw = nupp.intoRaw(value)",
   }, "\n")), "NUPP2604")
end

function M.bothSpellingsOfDisposeLowerTheSameWay()
   local function lowered(call)
      local source = table.concat({
         "local calls = ''",
         "local record File",
         "   closed: boolean",
         "   @dispose",
         "   function close(self: File)",
         "      calls = calls .. 'close'",
         "   end",
         "end",
         "@owned",
         "local function openFile(): File",
         "   return new File {closed = false}",
         "end",
         "local file = openFile()",
         call,
         "return calls",
      }, "\n")
      local result, diags = checked(source)
      assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
      local code, genDiags = gen.generate(result, "ownership-test")
      assertEq(#genDiags, 0)
      local chunk, loadErr = loadstring(code, "@ownership-qualified-dispose")
      assert(chunk, tostring(loadErr) .. "\n" .. code)
      assertEq(chunk(), "close", "the disposer runs")
      return code
   end

   assertEq(lowered("nupp.dispose(file)"), lowered("dispose(file)"),
      "the qualified spelling generated different code")
end

function M.aBindingNamedNuppShadowsTheQualifiedSpelling()
   -- The intrinsic is reached through the compiler's own `nupp`, so a local of
   -- that name means what the program says it means, as any other name would.
   assertClean(table.concat({
      "local nupp = {",
      "   dispose = function(value: integer): integer return value end",
      "}",
      "local answer = nupp.dispose(3)",
   }, "\n"))
   -- and a local named after a bare intrinsic shadows it the same way
   assertClean(table.concat({
      "local function dispose(value: integer): integer return value end",
      "local answer = dispose(3)",
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
      "   nupp.dispose(value)",
      "end",
      "local value = resource_new()",
      "release(value)",
      "release(value)",
   }, "\n")), codes(table.concat({
      RESOURCE,
      "local function release(value: resource*)",
      "   dispose(value)",
      "end",
      "local value = resource_new()",
      "release(value)",
      "release(value)",
   }, "\n")))
end

return M
