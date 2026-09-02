-- Reading instructions out of what the C compiler wrote.
--
-- Over fixed assembly rather than over a compilation, because what is being
-- tested is the rules: which mnemonics are a load, which operands make an
-- instruction vector, and which labels are the assembler's own. A test that
-- compiled something first would answer those only for whatever the compiler on
-- this machine happened to emit today.
--
-- Both architectures are here for the same reason. `nupp aot --emit asm` reads
-- one of them wherever it runs, so a rule broken for the other one is a rule
-- nothing on that machine would notice.

local test = require("assert")
local instructions = require("nupp.compiler.aot.instructions")

local M = {}

-- Mach-O, as Clang writes it for aarch64: symbols carry a leading underscore,
-- private labels begin with `L`, and comments begin with `;` because `#` is
-- already an immediate.
local ARM = table.concat(
    {
        "\t.section\t__TEXT,__text,regular,pure_instructions",
        "\t.globl\t_ks_scale                       ; -- Begin function ks_scale",
        "\t.p2align\t2",
        "_ks_scale:                              ; @ks_scale",
        "\t.cfi_startproc",
        "; %bb.0:",
        "\tcbz\tx2, LBB1_2",
        "LBB1_1:                                 ; =>This Inner Loop Header: Depth=1",
        "\tldp\tq1, q2, [x9, #-32]",
        "\tfmul.4s\tv1, v1, v0[0]",
        "\tstp\tq1, q2, [x10, #-32]",
        "\tldr\ts1, [x1], #4",
        "\tstr\ts1, [x0], #4",
        "\tbl\t_nupp_f32_min",
        "\tstr\tx19, [sp, #16]",
        "\tsubs\tx2, x2, #1",
        "\tb.ne\tLBB1_1",
        "LBB1_2:",
        "\tret",
        "\t.cfi_endproc",
        "\t.section\t__DATA,__const",
        "_ks_length_table:",
        "\t.quad\t8",
        "",
    },
    "\n"
)

-- ELF, as GCC writes it for x86-64: no underscore, private labels begin with
-- `.L`, comments begin with `#`, and the destination operand is last.
local X86 = table.concat(
    {
        "\t.text",
        "\t.globl\tks_scale",
        "\t.type\tks_scale, @function",
        "ks_scale:",
        ".LFB0:",
        "\t.cfi_startproc",
        "\tpushq\t%rbp",
        "\tmovq\t%rsp, %rbp\t# the frame",
        "# %bb.0:",
        "\tvbroadcastss\t%xmm0, %ymm1",
        "\tvmulps\t(%rsi,%rcx,4), %ymm1, %ymm2",
        "\tvmovups\t%ymm2, (%rdi,%rcx,4)",
        "\tvmulss\t(%rsi,%rax,4), %xmm0, %xmm1",
        "\tmovl\t-4(%rbp), %eax",
        "\tleaq\t(%rax,%rax,2), %rdx",
        "\tcall\tnupp_f32_min@PLT",
        "\tje\t.L2",
        "\tpopq\t%rbp",
        "\tret",
        "\t.cfi_endproc",
        "",
    },
    "\n"
)

-- ELF again, with the private labels GCC and Clang write there -- `.L2` and
-- `.LBB0_2` -- and comparisons whose memory operand sits where a destination
-- would.
local X86_LABELS = table.concat(
    {
        "\t.text",
        "\t.globl\tks_scale",
        "ks_scale:",
        ".LFB0:",
        "\tcmpq\t%rax, -16(%rbp)",
        "\tje\t.L2",
        ".LBB0_2:",
        "\ttestb\t$1, (%rdi)",
        "\tvucomisd\t%xmm1, (%rsi)",
        "\tmovq\t%rax, -8(%rbp)",
        ".L2:",
        "\tret",
        "",
    },
    "\n"
)

local function only(assembly, architecture, system)
    local listings = instructions.parse(assembly, architecture, system)
    test.equal(#listings, 1, "one symbol has instructions")
    return listings[1]
end

local function kindsOf(listing, mnemonic)
    for _, one in ipairs(listing.instructions) do
        if one.mnemonic == mnemonic then
            local named = {}
            for _, kind in ipairs(one.kinds) do
                named[kind] = true
            end
            return named
        end
    end
    error("no " .. mnemonic .. " in the listing", 2)
end

function M.aSymbolIsTheOnlyThingThatStartsAListing()
    local listing = only(ARM, "aarch64", "darwin")
    test.equal(listing.symbol, "ks_scale")
    test.equal(listing.instructions[1].mnemonic, "cbz")
    test.equal(#listing.instructions, 11)
end

-- The underscore is the assembler's, not the program's. A symbol spelled one
-- way on one platform and another way on another would make two runs on two
-- machines incomparable for a reason that has nothing to do with the code.
function M.machOSymbolsLoseTheAssemblersUnderscore()
    test.equal(only(ARM, "aarch64", "darwin").symbol, "ks_scale")
    test.equal(only(X86, "x86_64", "linux").symbol, "ks_scale")
end

-- Data is not a function body. The constant pools and lengths beside a kernel
-- carry real symbols, and a listing that reported them would be reporting
-- `.quad` as instructions.
function M.aSymbolWithNoInstructionsIsNotAListing()
    for _, listing in ipairs(instructions.parse(ARM, "aarch64", "darwin")) do
        assert(listing.symbol ~= "ks_length_table", "a data symbol is not a body")
    end
end

-- The label a back edge names, kept beside the instruction it precedes. A
-- listing without them shows a branch to nowhere.
function M.aLocalLabelStaysWithTheInstructionItPrecedes()
    local listing = only(ARM, "aarch64", "darwin")
    test.equal(listing.instructions[2].label, "LBB1_1")
    test.equal(listing.instructions[1].label, nil)
end

function M.anElfLocalLabelIsALabelRatherThanADirective()
    -- `.L2:` begins with the directive prefix and used to be dropped with the
    -- directives, so the instruction it named lost its label.
    local listing = only(X86_LABELS, "x86_64", "linux")
    test.equal(#listing.instructions, 6, "the labels are not instructions")
    test.equal(listing.instructions[3].label, ".LBB0_2")
    test.equal(listing.instructions[6].label, ".L2")
    test.equal(listing.instructions[4].label, nil)
end

-- A tab is what the compiler put between the two halves, and a listing that
-- kept it would differ from one written by a compiler that used spaces.
function M.anInstructionIsRespelledFromItsHalves()
    local listing = only(ARM, "aarch64", "darwin")
    test.equal(listing.instructions[1].text, "cbz x2, LBB1_2")
    test.equal(listing.instructions[#listing.instructions].text, "ret")
end

function M.armCountsAreOverTheMnemonicAndTheOperands()
    local counts = only(ARM, "aarch64", "darwin").counts
    test.equal(counts.total, 11)
    test.equal(counts.vector, 3, "the two q-register accesses and the lane multiply")
    test.equal(counts.loads, 2)
    test.equal(counts.stores, 3)
    test.equal(counts.branches, 2, "`bl` is a call rather than a branch")
    test.equal(counts.calls, 1)
    test.equal(counts.stack, 1)
end

-- `s` and `d` registers are scalar floating point. Counting them would report a
-- loop that fell back to one element at a time as vectorised, which is the one
-- answer these counts exist to distinguish.
function M.armScalarFloatingPointIsNotVector()
    local listing = only(ARM, "aarch64", "darwin")
    assert(not kindsOf(listing, "ldr").vector, "a single-precision load is scalar")
    assert(kindsOf(listing, "ldp").vector, "a pair of q registers is not")
end

function M.x86CountsAreOverTheMnemonicAndTheOperands()
    local counts = only(X86, "x86_64", "linux").counts
    test.equal(counts.total, 12)
    test.equal(counts.vector, 3, "the broadcast and the two packed operations")
    test.equal(counts.loads, 4)
    test.equal(counts.stores, 2)
    test.equal(counts.branches, 1)
    test.equal(counts.calls, 1)
    test.equal(counts.stack, 3, "the frame push, the frame read, and the pop")
end

-- Scalar floating point on x86-64 lives in the low lane of a vector register,
-- so the register alone says nothing. The suffix does.
function M.x86ScalarFloatingPointIsNotVector()
    local listing = only(X86, "x86_64", "linux")
    assert(not kindsOf(listing, "vmulss").vector, "a scalar multiply is not vectorised")
    assert(kindsOf(listing, "vmulps").vector, "a packed one is")
    assert(
        kindsOf(listing, "vbroadcastss").vector,
        "a broadcast is spelled with the scalar's suffix and fills the lanes"
    )
end

-- AT&T puts the destination last, which is the whole of the rule.
function M.x86ReadsLoadFromStoreByOperandPosition()
    local listing = only(X86, "x86_64", "linux")
    assert(kindsOf(listing, "vmulps").load, "the memory operand is a source")
    assert(kindsOf(listing, "vmovups").store, "the memory operand is the destination")
end

-- `lea` computes an address and touches nothing. Counting it would report
-- address arithmetic as memory traffic, and the spill question is exactly the
-- one that distinction is being asked for.
function M.x86AddressArithmeticIsNotAnAccess()
    local listing = only(X86, "x86_64", "linux")
    local lea = kindsOf(listing, "leaq")
    assert(not lea.load and not lea.store, "lea is not an access")
end

-- `#` begins a comment on x86-64 and an immediate on aarch64, which is why the
-- architecture decides what one is rather than the object format.
function M.aCommentIsNotAnOperand()
    test.equal(only(X86, "x86_64", "linux").instructions[2].text, "movq %rsp, %rbp")
    test.equal(
        only(ARM, "aarch64", "darwin").instructions[9].text,
        "subs x2, x2, #1",
        "an aarch64 immediate is not read as the start of a comment"
    )
end

-- Nothing claims a symbol by default, and a symbol nothing claims is a helper
-- the compiler declined to inline rather than an error.
function M.anUnclaimedSymbolIsAHelper()
    test.equal(only(ARM, "aarch64", "darwin").role, "helper")
end

function M.aClaimNamesTheFunctionASymbolBelongsTo()
    local listings = instructions.parse(ARM, "aarch64", "darwin")
    instructions.claim(listings, {ks_scale = {name = "scale", role = "kernel"}})
    test.equal(listings[1].name, "scale")
    test.equal(listings[1].role, "kernel")
end

-- A layout reporter is the one symbol the emitter derives from another symbol
-- rather than from a program, so it is claimed by that prefix.
function M.aLayoutReporterIsClaimedByTheBodyItReportsFor()
    local assembly = table.concat({"_ks_scale_layout_Point_offset_x:", "\tmov\tw0, #4", "\tret",}, "\n")
    local listings = instructions.parse(assembly, "aarch64", "darwin")
    instructions.claim(listings, {ks_scale = {name = "scale", role = "kernel"}})
    test.equal(listings[1].role, "reporter")
    test.equal(listings[1].name, "scale")
end

-- What the reader came for goes first. The compiler emits the oracle before the
-- body it is the oracle for, which is an artifact of how the C was assembled.
function M.listingsAreOrderedByRole()
    local ordered = instructions.order({
        {symbol = "a", role = "helper"},
        {symbol = "b", role = "oracle"},
        {symbol = "c", role = "kernel"},
        {symbol = "d", role = "helper"},
    })
    local shown = {}
    for index, listing in ipairs(ordered) do
        shown[index] = listing.symbol
    end
    test.equal(table.concat(shown, ","), "c,b,a,d", "kernel, oracle, then helpers in order")
end

function M.aRoleTheOrderDoesNotKnowIsStillListed()
    local ordered = instructions.order({{symbol = "a", role = "invented"}})
    test.equal(#ordered, 1)
end

function M.selectMatchesEitherSpelling()
    local listings = instructions.parse(ARM, "aarch64", "darwin")
    instructions.claim(listings, {ks_scale = {name = "scale", role = "kernel"}})
    test.equal(#instructions.select(listings, "scale"), 1, "the source name")
    test.equal(#instructions.select(listings, "ks_scale"), 1, "the symbol")
    test.equal(#instructions.select(listings, "other"), 0)
end

function M.namesSayBothSpellingsOnce()
    local listings = instructions.parse(ARM, "aarch64", "darwin")
    instructions.claim(listings, {ks_scale = {name = "scale", role = "kernel"}})
    test.equal(table.concat(instructions.names(listings), ", "), "scale, ks_scale")
end

-- A total with six zeroes beside it reads as a kernel that touches no memory
-- rather than as a question nothing answered, so an architecture with no rules
-- is refused before it can produce one.
function M.onlyTheArchitecturesWithRulesAreRead()
    assert(instructions.reads("aarch64"))
    assert(instructions.reads("x86_64"))
    assert(not instructions.reads("wasm32"))
end

return M
