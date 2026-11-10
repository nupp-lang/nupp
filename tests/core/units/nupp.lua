-- The runtime unit project: the units and the heap fixtures beside the
-- repository's sources, the core and the owned backend (nupp.compiler.s0)
-- among them. Run with ../../../bin/nupp run run.lua.
return {
    include = {
        ".",
        "../../../tests/fixtures/nativeheap",
        "../../../src",
        "../../../native/crates/vm/lib",
        "../../../native/crates/vm/decls"
    }
}
