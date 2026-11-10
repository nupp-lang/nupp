-- The guest proof project: core sources and the owned backend. Run with
-- ../../../bin/nupp run run.lua from this directory.
return {
    include = {
        ".",
        "../../../src",
        "../../../spike/native-lowering/src",
        "../../../spike/native-lowering/nativegraph/src",
        "../../../native/crates/vm/lib",
        "../../../native/crates/vm/decls"
    }
}
