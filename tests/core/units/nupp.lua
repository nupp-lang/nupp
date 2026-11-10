-- The runtime unit project: the units, the heap fixtures and the owned
-- backend, which the repository's own project does not include, beside its
-- sources. Run with ../../../bin/nupp run run.lua.
return {
    include = {
        ".",
        "../../../tests/fixtures/nativeheap",
        "../../../src",
        "../../../spike/native-lowering/src",
        "../../../spike/native-lowering/nativegraph/src",
        "../../../native/crates/vm/lib",
        "../../../native/crates/vm/decls"
    }
}
