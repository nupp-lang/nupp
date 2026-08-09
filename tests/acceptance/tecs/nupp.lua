-- The tecs FFI subsystem port, as its own project so the modules resolve each
-- other by name the way they do in tecs. Run from this directory:
--
--     nupp check --strict
--     nupp run run.nupp
return {
   include = { "." },
   strict = true,

   build = {
      outDir = "build",
      default = "port",
      targets = {
         port = {
            kind = "modules",
            description = "Check and build the ported tecs FFI subsystem",
            entries = { "run" },
         },
      },
   },
}
