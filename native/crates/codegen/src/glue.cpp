// What the LLVM C API cannot reach: strict floating-point fusion on a target
// machine, lld's drivers in process, and COFF import libraries.
#include "lld/Common/Driver.h"
#include "llvm/Object/COFFImportFile.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Target/TargetMachine.h"
#include <string>
#include <vector>

LLD_HAS_DRIVER(macho)
LLD_HAS_DRIVER(elf)
LLD_HAS_DRIVER(coff)
LLD_HAS_DRIVER(mingw)
LLD_HAS_DRIVER(wasm)

// Strict: no multiply-add is formed except from an explicit `llvm.fmuladd`,
// which Nupp emits only inside `@relax("fp-contract")` functions. Per-instruction
// `contract` flags still fuse where they appear.
extern "C" int nupp_codegen_strict_fp(void *tm) {
    auto *machine = reinterpret_cast<llvm::TargetMachine *>(tm);
    machine->Options.AllowFPOpFusion = llvm::FPOpFusion::Strict;
    return machine->Options.AllowFPOpFusion == llvm::FPOpFusion::Strict;
}

// argv[0] picks the flavor: ld64.lld, ld.lld, lld-link, wasm-ld. Output and
// diagnostics are returned in `out` (caller frees with nupp_codegen_free).
extern "C" int nupp_codegen_lld(int argc, const char **argv, char **out) {
    std::string text;
    llvm::raw_string_ostream stream(text);
    llvm::ArrayRef<const char *> args(argv, argc);
    lld::Result r = lld::lldMain(args, stream, stream, LLD_ALL_DRIVERS);
    stream.flush();
    *out = strdup(text.c_str());
    return r.retCode;
}

extern "C" void nupp_codegen_free(char *p) { free(p); }

// An import library naming `dll` as the provider of `names`; a non-empty
// `renames[i]` imports `names[i]` under that export name instead.
extern "C" int nupp_codegen_import_library(const char *dll, const char *path, const char **names,
                                           const char **renames, int n, char **error) {
    std::vector<llvm::object::COFFShortExport> exports;
    for (int i = 0; i < n; i++) {
        llvm::object::COFFShortExport e;
        e.Name = names[i];
        e.ImportName = renames[i];
        exports.push_back(e);
    }
    if (auto err = llvm::object::writeImportLibrary(dll, path, exports, llvm::COFF::IMAGE_FILE_MACHINE_AMD64, true)) {
        *error = strdup(llvm::toString(std::move(err)).c_str());
        return 1;
    }
    *error = nullptr;
    return 0;
}
