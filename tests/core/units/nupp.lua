-- The runtime unit project: core sources and the owned backend, which the
-- repository's own project does not include. Run with ../../../../bin/nupp run run.lua.
return {
    include = {
        ".",
        "../../../../tests/fixtures/nativeheap",
        "../../../../src",
        "../../src",
        "../../../../spike/native-lowering/src",
        "../../../../spike/native-lowering/nativegraph/src",
        "../../../../native/crates/vm/lib",
        "../../../../native/crates/vm/decls"
    }
}
