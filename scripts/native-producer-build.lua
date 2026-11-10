local root = assert(os.getenv("NUPP_COMPILER_ROOT"))
os.exit(require("nupp.tools.vm.privateproducer").main({root}))
