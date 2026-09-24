// lld's Wasm driver as a library: `wasm-ld` without a process.
#include "lld/Common/Driver.h"
#include "llvm/Support/raw_ostream.h"

LLD_HAS_DRIVER(wasm)

extern "C" int nupp_wasm_ld(int argc, const char **argv) {
    llvm::ArrayRef<const char *> args(argv, argc);
    lld::Result r = lld::lldMain(args, llvm::outs(), llvm::errs(), {{lld::Wasm, &lld::wasm::link}});
    return r.retCode;
}

// Homebrew's LLVM links Polly into LLVMLTO as a static extension; a product
// LLVM would be configured without it. An empty plugin stands in for it so
// the probe measures what that build would carry.
#include "llvm/Plugins/PassPlugin.h"
llvm::PassPluginLibraryInfo getPollyPluginInfo() {
    return {LLVM_PLUGIN_API_VERSION, "no-polly", "0", [](llvm::PassBuilder &) {}};
}
