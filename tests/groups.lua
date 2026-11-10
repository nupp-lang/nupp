-- Named sets of suites, so a workflow can say what coverage it wants rather
-- than repeating a list of suite names on a command line. Two steps that name
-- overlapping lists are how the same suite came to run twice in one CI job:
-- the second list was written months after the first and nothing compared them.
--
-- An entry is either a suite name or a `*` glob over suite names. A glob is
-- there so a group tracks new suites in an area instead of going quietly stale
-- when one is added; a name is there where the members have nothing in common
-- but the reason CI runs them together.
--
-- Every name and every glob is checked against the discovered suites when a
-- group is used. A group that matches nothing is an error rather than an empty
-- run, because "the step passed" and "the step ran no test" look identical in a
-- log and only one of them is a result.
local groups = {
    project = {"project*test"},
    derive = {"derive*test"},
    template = {"template*test"},
    bundle = {"bundle*test"},
    -- Reaches Windows-specific process, path and loader behaviour. Run before
    -- the broad suite on that platform so a loader failure names the last case
    -- instead of arriving twenty minutes later as unrun shards.
    ["windows-preflight"] = {"netnativetest", "runnertest", "worktreetest",},

    -- Fixtures whose inputs come from outside the repository. Kept nameable
    -- because a configured corpus used to be absent and silently skipped.
    ["external-corpus"] = {"corpustest", "importctest"},

    -- The Rust-native platform boundary: resource owners, the aggregate C ABI,
    -- and C consumers of the executable and embedding SDKs.
    [
        "native-platform"
    ] = {
        "cabitest",
        "ffitest",
        "httpnativetest",
        "nativefoundationstest",
        "netnativetest",
        "processnativetest",
        "rustabitest",
        "tlstest",
    },

    -- Everything that reads or regenerates published documentation, including
    -- the diagnostic reference a `docs` anchor points at.
    [
        "docs"
    ] = {
        "clidoctest",
        "diagnosticgoldentest",
        "doctest",
        "examplestest",
        "explaintest",
        "homesampletest",
        "overloaddoctest",
        "referencetest",
    },

    ["fmt"] = {"fmt*test"},

    -- Browser delivery: the worker seam and generated browser templates.
    [
        "browser"
    ] = {
        "portableiocontractstest",
        "templategametest",
        "templatelibtest",
        "templatemanifesttest",
        "templatepathtest",
        "templateremotetest",
        "templateresolutiontest",
        "templateresourcetest",
        "templatesandboxtest",
        "templatesubstitutiontest",
        "templatetest",
        "templatetreetest",
        "templatevariabletest",
    },

    ["gpu"] = {"gputest"},

    -- Packaging and release delivery.
    [
        "packaging"
    ] = {
        "bundlebuffertest",
        "bundlechanneltest",
        "bundlededicatedtest",
        "bundleforktest",
        "bundlelifetimetest",
        "bundleprovidertest",
        "bundleschedulertest",
        "bundlescopetest",
        "bundlesignaturetest",
        "bundletest",
        "compilerpacktest",
        "targetmanifesttest",
    },

    -- The benchmark runner's process boundary. Every case starts children and the
    -- replicated one starts twelve, so the suite costs about three minutes where the
    -- rest of the bench surface costs seconds.
    --
    -- Named so CI can run it only when the classifier reports the `measurement`
    -- surface. The unit cover for the same area -- the `keep` intrinsic, the allocation
    -- account, the statistics, the fork merge rules -- stays in `benchtest` and runs on
    -- every change, so what this gates is the cost of starting processes rather than
    -- the cover for anything a compiler change can reach.
    [
        "measurement"
    ] = {
        "benchgpuprocesstest",
        "benchrecordsprocesstest",
        "benchschemaprocesstest",
        "benchprotocolprocesstest",
        "benchsuiteprocesstest",
        "benchhistoryprocesstest",
        "benchpilotprocesstest",
        "benchrunnertest",
        "benchselectionprocesstest"
    },

    -- The Nupp-authored interpreter core: the lowering, the glue and the object
    -- it links. Both build Rust; the second runs the runtime crate's tests.
    [
        "native-runtime"
    ] = {
        "nativelowertest",
        "nativelowerscalarhelpertest",
        "nativegraphcontracttest",
        "nativefloatingcontracttest",
        "nativenumbermodeltest",
        "vmfornumtest",
        "nativegraphtest",
        "nativegraphcliftest",
        "nativeobjecthashtest",
        "nativeruntimetest",
        "nativejittest",
        "nativestringstest",
        "nativetablestest",
        "nativerecordstest",
        "nativeclosurestest",
        "nativeheaptest",
        "specializationcontracttest",
        "residualtest"
    },
}

-- Scope is a coverage obligation, independent of execution lanes.
-- A new repository suite must choose an obligation here.
local scopes = {}
for name in (
    [[
asserttest base64test bitsettest bufferapitest compressionprovidertest
digestprovidertest digesttest sustest taskfailuretest taskstest
workerstartuptest workersupporttest boundedcachetest clifacadetest portablefiletest
processfiletest processprovidertest processtest scalaradapterstest jsonfuseddifferentialtest
jsonpolicytest valuebuildertest standardtabletest typefactoriestest
]]
):gmatch("%S+") do
    scopes[name] = "unit"
end
for name in (
    [[
aotinstructionstest aotrelationstest aotsimdindicestest aottest aottexttest
aotverifytest aotvisittest allowtest apishortnamestest argumentplucktest
associatedcompletetest associatedcomposetest associatedconformancetest associatedcycletest associateddecltest
associatedgradualtest associatedlookuptest associatedmetadatatest associatedprojectiontest associatedsyntaxtest
bindingpatterntest callableconstructiontest checktest declarationwitnessestest discardtest
doexpressiontest channelcontracttest nosuspendlooptest nosuspendtest raisestest
sendabletest exhausttest indexedassignmenttest inlinemethodtest memberstest
methodtest orexittest automaticdestructiontest ownershipflowtest ownershipregiontest
packtest privateexporttest reifiablerecordtest structtest unusedtest
conststrtest deriveacceptancetest derivematerializetest derivetest fieldcodecmaterializetest
materializeobservetest prefercomptimetest typeprovidertest cabitest carraytest
cdecltest layouttest targetvectorlayouttest bulkcolumntest concatbuffertest
gentest loopclosuretest loweringinvarianttest neutralpolicytest optimizetest
passpermutationtest runtimereflectiontest spanloweringtest switchplantest tableintrinsictest
tier2test zoneintrinsictest analysisquerytest bundleddeclstest interfaceimagetest plaincodectest
parallelcheckprotocoltest providerbundledtest annotationtest elseiftest lexertest
parsertest switchtest typedtest binderidentitytest intersectiontest
narrowingtest narrowtest normalizetest operatortest reflectiontest
substitutiontest typeleveltest bytestest susinstallationtest benchtest
logtest cliargtest fileviewstest nettest mathnamespacetest
quaterniontest soatest standardostest spiinterfacetest serdetest
stringbuffernamespacetest reflectionnamestest storetest warntest bytecodelistingtest
docheadingstest doclinkstest overloaddoctest duplicatestest fmtfuzztest
fmttest fmtwidthtest moduleexportstest spinavigationtest cichangeclassifiertest
toollayeringtest testrunnertest
]]
):gmatch("%S+") do
    scopes[name] = "component"
end
for name in (
    [[
aotblockguardtest aotbudgettest aotbuildtest aotchecktest aotclitest
aotdifferentialtest aotexpressiontest aotincrementaltest aotmixedwidthtest aotnativeonlytest
aotsimdconditiontest aotsymboltest aotvectorfieldtest apiidentitytest builtinextensiontest
effectregiontest effecttransporttest eventschecktest ownershiptest comptimetest
deriveprovidertest materializeirtest cdeftest cheadertest importctest
perfbudgettest cachestamptest declaredmoduletest incrementaltest parallelchecktest
preludecachetest projectlinktest projecttest targetprofiletest annotatedluatest
fixedwidthtest browserhosttest browserprovidertest browserworkerstest lua51compattest
corpustest evalstest selfhosttest timerstest fleettest
lpegtest ffitest nativefoundationstest rustabitest profiletest
providerconformancetest spirepresentationtest hotreloadguaranteetest hotreloadtest generatedloadtest
runtimetest simdapiidentitytest simdequivalencedrivertest simdequivalencetest simdfixedlanestest
simdfleetequivalencetest simdlanetest simdmapinventorytest simdmatrixreporttest simdnativealgorithmdifferentialtest
simdobligationtest simdpackbudgettest simdprimitivedifferentialtest simdreducerdifferentialtest simdreducertest
simdruntimeboundarytest simdruntimeidentitytest simdwasmalgorithmdifferentialtest simdwasmbrowsersmoketest simdwasmtimeconformancetest
hostfacadestest stdlibtest templatetest publicclitest filecomponenttest
httpnativetest netnativetest tlstest pathtest processnativetest
uritest filestest hostchanneltest jsonfacadedefaulttest jsonschematest
serdecontracttest benchprojectstest benchrunnertest bctest absoluteentrytest
clitest duplicateclitest coveragereporttest coveragetest clidoctest
diagnosticgoldentest doctest examplestest explaintest homesampletest
referencetest fmtclitest fmtcorpustest fmtimportstest fmttreetest
associatedtoolingtest lspclitest lsptest constructionmigrationtest repositoryscriptstest
runnertest testtimingstest buildprogresstest buildtest
]]
):gmatch("%S+") do
    scopes[name] = "integration"
end
for name in (
    [[
hostbinarytest hostembeddingtest spitest bootstraptest bundletest
compilerpacktest releasetest rocktest spipackagetest worktreetest
rusttoolchaintest toolchaintest
]]
):gmatch("%S+") do
    scopes[name] = "delivery"
end

for name in (
    "compressiontest digestboundarytest eventstest gputest hashstreamtest portableiocontractstest processcompat_test streamadapterstest"
):gmatch("%S+") do
    scopes[name] = "integration"
end
for name in ("pooltest structpooltest randomtest nuppsuitetest"):gmatch("%S+") do
    scopes[name] = "component"
end
scopes.serdecheckcontracttest = "component"
scopes.testcachetest = "integration"
for name in (
    "serdecapabilitycontracttest serdedocumentcontracttest serdeprotocolcontracttest serdebindingcontracttest"
):gmatch("%S+") do
    scopes[name] = "integration"
end

-- The surviving core runner uses the same policy after integration.
for name in (
    [[
bootstrapresourcestest bootstrapseedtest callargumenttest compilerbackendtest coregraphbudgettest
corebuildoutputtest coregraphcatalogtest coregraphcodectest coregraphcontractstest coregraphexecutabletest coregraphshapetest corepiecetest
coretaskownershiptest ownedcallablestest corewarnlogtest declaredborrowtest densecstwalktest filesystemcallstest
functioncleanuptest graphcallfronttest graphclosuretest graphguestbranchtest graphinvoketest
guestartifactcallstest guestshardtest imagebytestest iofileargumenttest iopathargumenttest
nativecatalogbudgettest nativeclosurestest nativefloatingcontracttest nativegraphcliftest nativegraphcontracttest
nativegraphswitchtest nativegraphtest nativeheaptest nativejittest nativelowerscalarhelpertest
nativelowertest nativenumbermodeltest nativeobjecthashtest nativeospagetest nativeownerviewtest nativeproducertest
nativephysicalgraphtest nativephysicallocaltest nativephysicaltest nativepointercalltest nativepointertransporttest
nativerecordstest nativeruntimetest nativestringstest nativetablestest nativeunittest
nativevoidleaftest nominaleffectpublicationtest optionalmethodcleanuptest processargumenttest processcallstest
programgraphtest regextest residualtest scalaraliastest scalartypeoftest
shellsyntaxtest specializationcontracttest taggedtransporttest targetmanifesttest vmalternativeresulttest
vmasserttest vmclibuildtest vmclilaunchertest vmcolumnarsimdtest vmdefaultmethodtest
vmemitcachetest vmfornumtest vmimagecachetest vmindexkeytest vmopcodetabletest
vmpredicatecalltest vmqualifiedcleanuptest vmsimdbindingtest vmspanindextest vmspanlengthtest
vmspanwritetest vmstandardrootloadertest workerreporttest
]]
):gmatch("%S+") do
    scopes[name] = "integration"
end
for name in (
    "bootstrapresourcestest bootstrapseedtest targetmanifesttest vmaotpartstest vmbuildstepstest vmclibuildtest vmclilaunchertest"
):gmatch("%S+") do
    scopes[name] = "delivery"
end
scopes.advancestage0test = "delivery"

-- The owned native backend's own cases (nupp.compiler.s0).
for name in ("s0allocationtest s0arm64test s0framepairtest s0oracletest s0readertest s0selectiontest"):gmatch("%S+") do
    scopes[name] = "component"
end

-- Independent packages retain the original suite obligations.
scopes.derivemanifesttest = "component"
scopes.derivetecstest = "component"

-- Independent packages retain the original suite obligations.
scopes.derivediagnostictest = "component"
scopes.deriveidentitytest = "component"
scopes.derivelimittest = "component"
scopes.deriveemissiontest = "component"

-- Independent packages retain the original suite obligations.
scopes.deriveinternalprovidertest = "integration"
scopes.deriveexportprovidertest = "component"
scopes.derivepublicprovidertest = "component"
scopes.deriveexternalprovidertest = "integration"

-- Independent packages retain the original suite obligations.
scopes.projecthashtest = "component"
scopes.projectaotscopetest = "integration"
scopes.projectmoduletest = "component"
scopes.projectpathtest = "integration"
scopes.projectprocesstest = "integration"
scopes.projectmaterializationtest = "integration"
scopes.projectmanifesttest = "component"
scopes.projectcrosstest = "integration"
scopes.projectnativetest = "integration"
scopes.projectchecktest = "integration"
scopes.projectinvalidationtest = "integration"
scopes.projectctest = "integration"
scopes.projectbinarytest = "integration"
scopes.projectfixpointtest = "integration"
scopes.projectaottest = "integration"
scopes.projectclinktest = "integration"
scopes.projectcargotest = "integration"
scopes.projectgeneratortest = "integration"
scopes.projectfilesystemtest = "integration"
scopes.projectrocktest = "integration"
scopes.projecttestcommandtest = "integration"
scopes.projecttasktest = "integration"
scopes.projectsyntaxtest = "component"

scopes.deriveprovidertest = "component"

-- Independent packages retain the original suite obligations.
scopes.benchgpuprocesstest = "integration"
scopes.benchrecordsprocesstest = "integration"
scopes.benchschemaprocesstest = "integration"
scopes.benchprotocolprocesstest = "integration"
scopes.benchsuiteprocesstest = "integration"
scopes.benchhistoryprocesstest = "integration"
scopes.benchpilotprocesstest = "integration"
scopes.benchselectionprocesstest = "integration"

-- Independent packages retain the original suite obligations.
scopes.bundlefactorytest = "delivery"
scopes.bundlecomponenttest = "delivery"
scopes.bundlebootstraptest = "delivery"
scopes.bundleprovidertest = "delivery"
scopes.bundlesignaturetest = "delivery"
scopes.bundlepayloadtest = "delivery"
scopes.bundleworkertest = "delivery"
scopes.bundleschedulertest = "delivery"
scopes.bundlefailuretest = "delivery"
scopes.bundlescopetest = "delivery"
scopes.bundleregiontest = "delivery"
scopes.bundlebuffertest = "delivery"
scopes.bundleforktest = "delivery"
scopes.bundlelifetimetest = "delivery"
scopes.bundlechanneltest = "delivery"
scopes.bundlededicatedtest = "delivery"

-- Independent packages retain the original suite obligations.
scopes.templateresolutiontest = "component"
scopes.templatesubstitutiontest = "component"
scopes.templatemanifesttest = "component"
scopes.templatevariabletest = "component"
scopes.templatetreetest = "integration"
scopes.templatesandboxtest = "integration"
scopes.templatepathtest = "integration"
scopes.templateresourcetest = "integration"
scopes.templateremotetest = "integration"
scopes.templatelibtest = "integration"
scopes.templatebrowsertest = "integration"
scopes.templatesimdtest = "integration"
scopes.templatelovetest = "integration"
scopes.templategametest = "integration"

-- Independent packages retain the original suite obligations.
scopes.fmtlayouttest = "component"
scopes.fmttypetest = "component"
scopes.fmtselflexertest = "component"
scopes.fmtselfcsttest = "component"
scopes.fmtselfparsertest = "component"
scopes.fmtselfdisplaywidthtest = "component"
scopes.fmtselfformattertest = "component"
scopes.fmtselfmaintest = "component"

-- Independent packages retain the original suite obligations.
scopes.fmtoptionclitest = "integration"
scopes.fmtcacheclitest = "integration"

-- Independent packages retain the original suite obligations.
scopes.fmttree2test = "integration"
scopes.fmttree3test = "integration"
scopes.fmttree4test = "integration"

-- Independent packages retain the original suite obligations.
scopes.buildprogressspecializationtest = "integration"
scopes.buildprogressclitest = "integration"

scopes.buildprogresstest = "unit"

scopes.evalsemanticstest = "component"

scopes.evalstest = "integration"

scopes.evalcatalogtest = "integration"

scopes.evalfilesystemtest = "integration"

scopes.projectprocessbinarytest = "integration"

scopes.projectbinarytest = "integration"

scopes.projectmaterializationtest = "integration"

scopes.projectlayoutcachetest = "integration"

scopes.projectaotlinktest = "integration"

scopes.projectaottest = "integration"

scopes.projectcrosstest = "integration"

scopes.projectcrossrefusaltest = "integration"

scopes.contractprojecttest = "component"

scopes.projectbundlelayouttest = "integration"

scopes.projectprocessbinarytest = "integration"

scopes.projectbinaryfilesystemtest = "integration"

scopes.projectbinarytest = "integration"

scopes.projectlayoutcachetest = "integration"

scopes.projectexportedlayouttest = "integration"

scopes.projectcrosstest = "integration"

scopes.projectcrosscontracttest = "integration"

scopes.projectcrossaggregatetest = "integration"

scopes.serdedebugcontracttest = "integration"

-- Closed repository contracts cover generated modules and ordinary child CLI
-- checks. Git supplies source membership, including untracked source files but
-- excluding generated build/cache output. Executed artifacts are hashed too.
local repositoryInputs = {
    "tests/helpers",
    "tests/fixtures",
    "nupp.lua",
    "bin",
    "scripts",
    "templates",
    "native",
    "runtime",
    "host",
    "Cargo.toml",
    "Cargo.lock",
    "rust-toolchain.toml",
    "bench/serde-spike/contracts",
}
local commands = {
    "sh",
    "git",
    "luajit",
    "mkdir",
    "rm",
    "cp",
    "mv",
    "ln",
    "cat",
    "pwd",
    "find",
    "diff",
    "env",
    "sed",
    "grep",
    "sort",
    "touch",
    "chmod",
    "uname",
    "node",
    "lua",
    "lua51",
    "lua5.1",
    "luac",
    "tar",
    "gzip",
    "head",
    "tail",
    "tr",
    "wc",
    "ls",
    "tee",
    "printf",
    "cut",
    "awk",
    "basename",
    "dirname",
    "readlink",
    "realpath",
    "rmdir",
    "date",
    "test",
    "bin/nupp",
    "scripts/toolchain"
}

local function contract(extra, inputs)
    local sources = {}
    for _, path in ipairs(repositoryInputs) do
        sources[#sources + 1] = path
    end
    for _, path in ipairs(extra or {}) do
        sources[#sources + 1] = path
    end

    local files = {"src"}
    for _, path in ipairs(inputs or {}) do
        files[#files + 1] = path
    end

    return {
        cache = true,
        closed = true,
        toolchain = true,
        compiled = "src",
        images = os.getenv("NUPP_VM_CLI_IMAGE") and {os.getenv("NUPP_VM_CLI_IMAGE")} or nil,
        optionalInputs = {"editors/playground/src/examples"},
        sources = sources,
        inputs = files,
        commands = commands
    }
end

local profiles = {
    pure = {cache = true},
    repository = contract(),
    formatting = contract({
        "tests/tools/fmt",
        "tests/compiler/syntax",
        "tests/run.lua"
    }),
    documentation = contract({
        "docs",
        "evals"
    }),
    runner = contract({
        "tests"
    }),
    benchmark = contract({
        "bench"
    }),
    evaluations = contract({"evals"}),
}
local packages = {}

local function enable(profile, paths)
    for path in paths:gmatch("%S+") do
        packages[path] = profiles[profile]
    end
end

enable("pure", [[
stdlib/io/cache
]])
enable(
    "repository",
    [[
compiler/syntax/lexer
compiler/check
compiler/check/associated
compiler/check/effects
compiler/check/effects/channel
compiler/check/ownership
compiler/comptime
compiler/comptime/derive/acceptance/configuration
compiler/comptime/derive/acceptance/manifest
compiler/comptime/derive/acceptance/tecs
compiler/comptime/derive/diagnostics
compiler/comptime/derive/emission
compiler/comptime/derive/identity
compiler/comptime/derive/limits
compiler/comptime/derive/providers/exported
compiler/comptime/derive/providers/external
compiler/comptime/derive/providers/forwarding
compiler/comptime/derive/providers/internal
compiler/comptime/derive/providers/public
compiler/comptime/derive/runtime
compiler/lua
compiler/project
compiler/project/contracts/compilation
compiler/project/contracts/check
compiler/project/contracts/cross/aggregate
compiler/project/contracts/cross/contracts
compiler/project/contracts/filesystem
compiler/project/contracts/hash
compiler/project/contracts/invalidation
compiler/project/contracts/manifest
compiler/project/contracts/materialization/layout/annotations
compiler/project/contracts/materialization/layout/readers
compiler/project/contracts/materialization/products
compiler/project/contracts/modules
compiler/project/contracts/paths
compiler/project/contracts/process
compiler/project/contracts/syntax
compiler/project/contracts/tasks
compiler/project/contracts/test
compiler/types
integration/providers
integration/stdlib
integration/templates/contracts/app
integration/templates/contracts/lib
integration/templates/contracts/manifest
integration/templates/contracts/paths
integration/templates/contracts/resolution
integration/templates/contracts/resources
integration/templates/contracts/sandbox
integration/templates/contracts/substitution
integration/templates/contracts/tree
integration/templates/contracts/variables
stdlib
stdlib/assert
stdlib/bytes
stdlib/coroutine
stdlib/events
stdlib/io
stdlib/io/cli
stdlib/io/path
stdlib/io/process
stdlib/io/uri
stdlib/math
stdlib/nupp
stdlib/os
stdlib/package/nupp
stdlib/serde
stdlib/serde/contract/bindings
stdlib/serde/contract/capabilities
stdlib/serde/contract/checker
stdlib/serde/contract/debug
stdlib/serde/contract/documents
stdlib/serde/contract/protocol
stdlib/serde/json
stdlib/string
stdlib/table
stdlib/types
stdlib/warn
tools
tools/coverage
tools/lsp
tools/packaging/bundle/signature
tools/toolchain/progress/cli
tools/toolchain/progress/reporter
]]
)
enable(
    "formatting",
    [[
compiler/syntax
tools/fmt
tools/fmt/cli/cache
tools/fmt/cli/options
tools/fmt/cli/project
tools/fmt/contracts/cst
tools/fmt/contracts/displaywidth
tools/fmt/contracts/formatter
tools/fmt/contracts/layout
tools/fmt/contracts/lexer
tools/fmt/contracts/main
tools/fmt/contracts/parser
tools/fmt/contracts/syntax
tools/fmt/contracts/types
tools/fmt/tree/1
tools/fmt/tree/2
tools/fmt/tree/3
tools/fmt/tree/4
]]
)
enable("documentation", [[
tools/docs
]])
enable("runner", [[
tools/test
]])
enable(
    "benchmark",
    [[
stdlib/debug
tools/bench/process/gpu
tools/bench/process/history
tools/bench/process/pilot
tools/bench/process/protocol
tools/bench/process/records
tools/bench/process/replication
tools/bench/process/schema
tools/bench/process/selection
tools/bench/process/suite
]]
)
enable(
    "evaluations",
    [[
integration/compiler/evals/catalog
integration/compiler/evals/compiler
integration/compiler/evals/filesystem
integration/compiler/evals/semantics
]]
)

packages[
    "compiler/interop"
] = {cache = false, reason = "C headers, SDKs and system link libraries are external inputs."}

packages["compiler/project/contracts/c"] = {cache = false, reason = "External C compiler, SDK and link libraries."}
packages[
    "compiler/project/contracts/cargo"
] = {cache = false, reason = "External Cargo installation and registry state."}
packages["compiler/project/contracts/clink"] = {cache = false, reason = "External C compiler, SDK and link libraries."}

packages[
    "compiler/project/contracts/fixpoint"
] = {cache = false, reason = "Delivery verification always executes from stage zero."}
packages["compiler/project/contracts/native"] = {cache = false, reason = "External native compiler and link libraries."}

packages[
    "integration/compiler"
] = {cache = false, reason = "Self-hosting and external corpus delivery checks always execute."}
packages["integration/coroutine"] = {cache = false, reason = "Timer scheduling depends on current host load."}

packages[
    "integration/native"
] = {cache = false, reason = "Embedding toolchains and system libraries are external inputs."}

packages["integration/simd"] = {cache = false, reason = "Retiring backend; external GPU, Wasm and native toolchains."}
packages[
    "integration/templates/contracts/game"
] = {cache = false, reason = "Builds game dependencies with external native toolchains."}
packages[
    "integration/templates/contracts/remote"
] = {cache = false, reason = "Local Git transport also reads external Git configuration."}
packages["stdlib/io/gpu"] = {cache = false, reason = "Live GPU capability and driver conformance."}
packages["stdlib/io/net"] = {cache = false, reason = "Live network, TLS and socket-provider conformance."}
packages["tools/bench"] = {cache = false, reason = "Builds benchmark projects against external pkg-config libraries."}
packages["tools/packaging"] = {cache = false, reason = "Release and external packaging/toolchain state."}
packages[
    "tools/packaging/bundle/buffers"
] = {cache = false, reason = "Runs a toolchain-produced Rust host; external toolchain inputs."}
packages[
    "tools/packaging/bundle/channels"
] = {cache = false, reason = "Runs a toolchain-produced Rust host; external toolchain inputs."}
packages[
    "tools/packaging/bundle/dedicated"
] = {cache = false, reason = "Runs a toolchain-produced Rust host; external toolchain inputs."}

packages[
    "tools/packaging/bundle/forking"
] = {cache = false, reason = "Runs a toolchain-produced Rust host; external toolchain inputs."}
packages[
    "tools/packaging/bundle/lifetime"
] = {cache = false, reason = "Runs a toolchain-produced Rust host; external toolchain inputs."}

packages[
    "tools/packaging/bundle/scheduler"
] = {cache = false, reason = "Runs a toolchain-produced Rust host; external toolchain inputs."}
packages[
    "tools/packaging/bundle/scope"
] = {cache = false, reason = "Runs a toolchain-produced Rust host; external toolchain inputs."}
packages["tools/repository"] = {cache = false, reason = "Git branches, index and worktree state are test inputs."}
packages["tools/toolchain"] = {cache = false, reason = "External compiler installations and provisioning state."}

packages["integration/runtime"] = {cache = false, reason = "Compiles dynamic libraries against an external C SDK."}

packages["integration/reload"] = {cache = false, reason = "Compiles replacement libraries against an external C SDK."}

packages["tools/cli"] = {cache = false, reason = "CLI integration includes external C compiler and SDK conformance."}

packages[
    "tools/packaging/bundle/delivery"
] = {cache = false, reason = "Builds a rock through the external LuaRocks installation."}

packages[
    "compiler/types/oracle"
] = {cache = false, reason = "Independent binary32 C oracle uses an external compiler and SDK."}

packages[
    "compiler/lua/budget"
] = {cache = false, reason = "Native binary budget uses the external native link toolchain."}

packages[
    "tools/packaging/bundle/providers"
] = {cache = false, reason = "Builds an exact-feature native host with an external Rust SDK."}

packages[
    "compiler/project/contracts/generators"
] = {cache = false, reason = "Local generator rocks also read external LuaRocks configuration."}

enable("repository", [[
nupp/compiler/s0
nupp/test
]])
packages["."] = {cache = false, reason = "Native compiler, core ABI and external C oracle inputs share this package."}

return groups, {scopes = scopes, packages = packages}
