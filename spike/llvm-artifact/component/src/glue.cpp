// lld in process, and COFF import libraries: the two things the artifact
// component does beside compiling that the LLVM C API cannot reach.
#include "lld/Common/Driver.h"
#include "llvm/Object/COFFImportFile.h"
#include "llvm/Support/raw_ostream.h"
#include <string>
#include <vector>

#ifdef NUPP_LLD_MACHO
LLD_HAS_DRIVER(macho)
#endif
#ifdef NUPP_LLD_ELF
LLD_HAS_DRIVER(elf)
#endif
#ifdef NUPP_LLD_COFF
LLD_HAS_DRIVER(coff)
LLD_HAS_DRIVER(mingw)
#endif
#ifdef NUPP_LLD_WASM
LLD_HAS_DRIVER(wasm)
#endif

// argv[0] picks the flavor: ld64.lld, ld.lld, lld-link, wasm-ld.
#if defined(NUPP_LLD_MACHO) || defined(NUPP_LLD_ELF) || defined(NUPP_LLD_COFF) || defined(NUPP_LLD_WASM)
extern "C" int nupp_lld(int argc, const char **argv) {
    std::vector<lld::DriverDef> drivers = {
#ifdef NUPP_LLD_MACHO
        {lld::Darwin, &lld::macho::link},
#endif
#ifdef NUPP_LLD_ELF
        {lld::Gnu, &lld::elf::link},
#endif
#ifdef NUPP_LLD_COFF
        {lld::WinLink, &lld::coff::link},
        {lld::MinGW, &lld::mingw::link},
#endif
#ifdef NUPP_LLD_WASM
        {lld::Wasm, &lld::wasm::link},
#endif
    };
    llvm::ArrayRef<const char *> args(argv, argc);
    lld::Result r = lld::lldMain(args, llvm::outs(), llvm::errs(), drivers);
    llvm::outs().flush();
    llvm::errs().flush();
    return r.retCode;
}
#else
// The size baseline: compiling, and no linker to finish the job.
extern "C" int nupp_lld(int, const char **) { return 99; }
#endif

// An import library naming `dll` as the provider of `names`: what a MinGW
// link against that DLL reads. llvm-dlltool writes the same.
extern "C" int nupp_import_library(const char *dll, const char *path, const char **names, int n) {
    std::vector<llvm::object::COFFShortExport> exports;
    for (int i = 0; i < n; i++) {
        llvm::object::COFFShortExport e;
        e.Name = names[i];
        exports.push_back(e);
    }
    if (auto err = llvm::object::writeImportLibrary(dll, path, exports, llvm::COFF::IMAGE_FILE_MACHINE_AMD64, true)) {
        llvm::errs() << "import library " << path << ": " << llvm::toString(std::move(err)) << "\n";
        return 1;
    }
    return 0;
}

// Homebrew's LLVMLTO references Polly; a product LLVM has none. Harmless
// against the size-built tree, which never asks for it.
#ifdef NUPP_NEEDS_POLLY_STUB
#include "llvm/Plugins/PassPlugin.h"
llvm::PassPluginLibraryInfo getPollyPluginInfo() {
    return {LLVM_PLUGIN_API_VERSION, "no-polly", "0", [](llvm::PassBuilder &) {}};
}
#endif
