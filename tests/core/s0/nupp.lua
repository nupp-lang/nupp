-- The owned backend's code cases (run.lua): the working tree's
-- nupp.compiler.s0, staged under build/s0cases as s0lab, beside the core.
return {
    include = {
        ".",
        "../../../build/s0cases",
        "../../../src",
        "../../../native/crates/vm/lib",
        "../../../native/crates/vm/decls"
    }
}
