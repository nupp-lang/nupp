fn main() {
    println!("cargo:rerun-if-changed=csrc/threaded.c");
    cc::Build::new().file("csrc/threaded.c").opt_level(3).flag("-fomit-frame-pointer").compile("threaded");
}
