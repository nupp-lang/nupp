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
    -- Reaches Windows-specific process, path and loader behaviour. Run before
    -- the broad suite on that platform so a loader failure names the last case
    -- instead of arriving twenty minutes later as unrun shards.
    [
        "windows-preflight"
    ] = {"netnativetest", "runnertest", "rusttoolchaintest", "soatest", "toolchaintest", "worktreetest",},

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
        "hostbinarytest",
        "hostembeddingtest",
        "httpnativetest",
        "nativefoundationstest",
        "netnativetest",
        "processnativetest",
        "rustabitest",
        "tlstest",
    },

    -- What `.github/scripts/test-rust-native-platform.sh` runs after it has
    -- built the executable host and both embedding SDKs. Named so the broad
    -- suite can leave it out rather than run it a second time against the same
    -- artifacts, and so that what the script runs is visible from here.
    ["rust-native-gate"] = {"hostembeddingtest"},

    -- Everything that reads or regenerates published documentation, including
    -- the diagnostic reference a `docs` anchor points at.
    [
        "docs"
    ] = {
        "clidoctest",
        "diagnosticgoldentest",
        "docheadingstest",
        "doclinkstest",
        "doctest",
        "examplestest",
        "explaintest",
        "homesampletest",
        "overloaddoctest",
        "referencetest",
    },

    ["fmt"] = {"fmt*test"},

    ["aot"] = {"aot*test"},

    -- Browser delivery: the worker seam, checked compatibility and generated
    -- browser templates.
    [
        "browser"
    ] = {
        "browserhosttest",
        "browserprovidertest",
        "browserworkerstest",
        "lua51compattest",
        "portableiocontractstest",
        "targetprofiletest",
        "templatetest",
    },

    ["gpu"] = {"gputest"},

    -- Compact native and Wasm packs, their executable obligation ledger, and
    -- the structural checks which keep the replacement corpus bounded.
    ["simd-conformance"] = {"aotsimdconditiontest", "simd*test"},

    -- The Wasm packs through wasmtime and the browser: a cargo-built host and
    -- hundreds of modules, a quarter of an hour on a fast machine. The SIMD
    -- conformance workflow runs the same harness sharded, so the per-push
    -- matrix leaves these to it.
    [
        "wasm-conformance"
    ] = {"simdwasmtimeconformancetest", "simdwasmalgorithmdifferentialtest", "simdwasmbrowsersmoketest",},

    -- Packaging and release delivery.
    [
        "packaging"
    ] = {
        "bundlefactorytest",
        "bundlecomponenttest",
        "bundlebootstraptest",
        "bundleprovidertest",
        "bundlesignaturetest",
        "bundlepayloadtest",
        "bundleworkertest",
        "bundleschedulertest",
        "bundlefailuretest",
        "bundlescopetest",
        "bundleregiontest",
        "bundlebuffertest",
        "bundleforktest",
        "bundlelifetimetest",
        "bundletest",
        "bundlechanneltest",
        "bundlededicatedtest",
        "compilerpacktest",
        "releasetest",
        "rocktest",
        "spipackagetest",
        "spitest",
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
        "benchrunnertest",
        "benchpilotprocesstest",
        "benchselectionprocesstest"
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
tier2test zoneintrinsictest analysisquerytest bundleddeclstest interfaceimagetest
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
coregraphcatalogtest coregraphcodectest coregraphcontractstest coregraphexecutabletest coregraphshapetest
coretaskownershiptest corewarnlogtest declaredborrowtest densecstwalktest filesystemcallstest
functioncleanuptest graphcallfronttest graphclosuretest graphguestbranchtest graphinvoketest
guestartifactcallstest guestshardtest imagebytestest iofileargumenttest iopathargumenttest
nativecatalogbudgettest nativeclosurestest nativefloatingcontracttest nativegraphcliftest nativegraphcontracttest
nativegraphswitchtest nativegraphtest nativeheaptest nativejittest nativelowerscalarhelpertest
nativelowertest nativenumbermodeltest nativeobjecthashtest nativeospagetest nativeownerviewtest
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
    "bootstrapresourcestest bootstrapseedtest targetmanifesttest vmclibuildtest vmclilaunchertest"
):gmatch("%S+") do
    scopes[name] = "delivery"
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

return groups, {
    scopes = scopes,
    packages = {
        ["stdlib/io/cache"] = {cache = true},
        ["compiler/syntax/lexer"] = {cache = true},
        -- Checker execution can start comptime children; keep it uncached.
        ["compiler/check/effects/channel"] = {cache = false},
    },
}
