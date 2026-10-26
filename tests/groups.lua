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
return {
    -- Reaches Windows-specific process, path and loader behaviour. Run before
    -- the broad suite on that platform so a loader failure names the last case
    -- instead of arriving twenty minutes later as unrun shards.
    [
        "windows-preflight"
    ] = {"netnativetest", "runnertest", "worktreetest",},

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
        "templatetest",
    },

    ["gpu"] = {"gputest"},

    -- Packaging and release delivery.
    ["packaging"] = {"bundletest", "compilerpacktest", "spipackagetest", "spitest",},

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
    ["native-runtime"] = {"nativelowertest", "nativeruntimetest", "nativejittest", "nativestringstest", "nativetablestest", "nativeclosurestest", "nativeheaptest"},
}
