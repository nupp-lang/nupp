return {
   include = {"src"},
   build = {
      default = "worker-benchmark",
      targets = {
         ["worker-benchmark"] = {
            kind = "binary",
            stub = "nupp",
            entries = {"main"},
            outDir = "build",
            output = "worker-benchmark",
         },
      },
   },
}
