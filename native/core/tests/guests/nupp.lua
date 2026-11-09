-- The guest proof project: core sources beside the compiler's, whose
-- nupp.compiler.s0 carries the owned backend. Run with
-- ../../../../bin/nupp run run.lua from this directory.
return {
    include = {
        ".",
        "../../../../src",
        "../../src",
        "../../../../native/crates/vm/lib",
        "../../../../native/crates/vm/decls"
    }
}
