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
    ["browser"] = {"portableiocontractstest", "templatetest",},

    ["gpu"] = {"gputest"},

    -- Packaging and release delivery.
    ["packaging"] = {"bundletest", "compilerpacktest", "targetmanifesttest",},

    -- The benchmark runner's process boundary. Every case starts children and the
    -- replicated one starts twelve, so the suite costs about three minutes where the
    -- rest of the bench surface costs seconds.
    --
    -- Named so CI can run it only when the classifier reports the `measurement`
    -- surface. The unit cover for the same area -- the `keep` intrinsic, the allocation
    -- account, the statistics, the fork merge rules -- stays in `benchtest` and runs on
    -- every change, so what this gates is the cost of starting processes rather than
    -- the cover for anything a compiler change can reach.
    ["measurement"] = {"benchrunnertest"},

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
scopes.advancestage0test = "delivery"

return groups, {
    scopes = scopes,
    packages = {
        ["stdlib/io/cache"] = {cache = true},
        ["compiler/syntax/lexer"] = {cache = true},
        -- Checker execution can start comptime children; keep it uncached.
        ["compiler/check/effects/channel"] = {cache = false},
    },
}
