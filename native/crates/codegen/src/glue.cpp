// What the LLVM C API cannot reach: strict floating-point fusion on a target
// machine, lld's drivers in process, COFF import libraries and archives.
#include "lld/Common/Driver.h"
#include "llvm/Object/ArchiveWriter.h"
#include "llvm/Object/COFFImportFile.h"
#include "llvm/Support/CrashRecoveryContext.h"
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
//
// lld ends a fatal error through `Process::Exit`, which returns to lldMain's
// recovery context only while crash recovery is enabled; otherwise it ends
// nupp, silently. It is enabled for the link alone, so the handlers it
// installs are the process's own again afterwards.
extern "C" int nupp_codegen_lld(int argc, const char **argv, char **out) {
    std::string text;
    llvm::raw_string_ostream stream(text);
    llvm::ArrayRef<const char *> args(argv, argc);
    llvm::CrashRecoveryContext::Enable();
    lld::Result r = lld::lldMain(args, stream, stream, LLD_ALL_DRIVERS);
    llvm::CrashRecoveryContext::Disable();
    stream.flush();
    if (r.retCode != 0 && text.empty()) {
        text = "lld stopped with status " + std::to_string(r.retCode) + " and no message";
    }
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

// A static archive of `members` at `path`, with a symbol index, in the format
// `kind` names: 0 GNU, 1 BSD, 2 Darwin, 3 COFF. Deterministic: no times,
// owners or modes, so equal members give equal bytes.
extern "C" int nupp_codegen_archive(const char *path, const char **members, int n, int kind, char **error) {
    std::vector<llvm::NewArchiveMember> entries;
    for (int i = 0; i < n; i++) {
        auto member = llvm::NewArchiveMember::getFile(members[i], /*Deterministic=*/true);
        if (!member) {
            *error = strdup(llvm::toString(member.takeError()).c_str());
            return 1;
        }
        entries.push_back(std::move(*member));
    }
    llvm::object::Archive::Kind format = kind == 1   ? llvm::object::Archive::K_BSD
                                         : kind == 2 ? llvm::object::Archive::K_DARWIN
                                         : kind == 3 ? llvm::object::Archive::K_COFF
                                                     : llvm::object::Archive::K_GNU;
    if (auto err = llvm::writeArchive(path, entries, llvm::SymtabWritingMode::NormalSymtab, format,
                                      /*Deterministic=*/true, /*Thin=*/false)) {
        *error = strdup(llvm::toString(std::move(err)).c_str());
        return 1;
    }
    *error = nullptr;
    return 0;
}
