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
    ["windows-preflight"] = {
        "netnativetest",
        "runnertest",
        "rusttoolchaintest",
        "soatest",
        "toolchaintest",
        "worktreetest",
    },

    -- Fixtures whose inputs come from outside the repository. Kept nameable
    -- because a configured corpus used to be absent and silently skipped.
    ["external-corpus"] = {"corpustest", "importctest"},

    -- The Rust-native platform boundary: resource owners, the aggregate C ABI,
    -- and C consumers of the executable and embedding SDKs.
    ["native-platform"] = {
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

    -- Everything that reads or regenerates published documentation, including
    -- the diagnostic reference a `docs` anchor points at.
    ["docs"] = {
        "clidoctest",
        "diagnosticgoldentest",
        "doctest",
        "explaintest",
        "homesampletest",
        "overloaddoctest",
        "referencetest",
    },

    ["fmt"] = {"fmt*test"},

    ["aot"] = {"aot*test"},

    -- Browser and Wasm delivery: the worker seam, the portable dialect the
    -- playground compiles under, and the generated browser templates.
    ["browser"] = {
        "browserworkerstest",
        "portabledialecttest",
        "portableiocontractstest",
        "targetprofiletest",
        "templatetest",
    },

    ["gpu"] = {"gputest"},

    -- Packaging and release delivery.
    ["packaging"] = {
        "bundletest",
        "compilerpacktest",
        "releasetest",
        "rocktest",
        "servicepackagetest",
    },
}
