-- The runtime unit project: core sources, which the repository's own project
-- does not include, beside the compiler's (the owned backend is
-- nupp.compiler.s0). Run with ../../../../bin/nupp run run.lua.
return {
    include = {
        ".",
        "../../../../tests/fixtures/nativeheap",
        "../../../../src",
        "../../src",
        "../../../../native/crates/vm/lib",
        "../../../../native/crates/vm/decls"
    }
}
