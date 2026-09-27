-- A standalone program with AOT code, linked for another platform from that
-- platform's link kit: `nupp build --platform TRIPLE` with NUPP_KIT_DIR naming
-- the kit. CI builds it on one host and runs it on the other.
return {
   include = {"src"},
   build = {
      kind = "binary",
      stub = "nupp",
      standalone = true,
      aot = "require",
      entries = {"main"},
      platforms = {
         "x86_64-unknown-linux-gnu",
         "aarch64-apple-darwin",
      },
   },
}
