return {
   include = {"src", "../../src"},
   build = {
      default = "native-runtime-benchmark",
      targets = {
         ["native-runtime-benchmark"] = {
            kind = "binary",
            stub = "nupp",
            entries = {"main"},
            nativeFeatures = {http = true, net = true, process = true, time = true, tls = true, uri = true},
            outDir = "build",
         },
      },
   },
}
