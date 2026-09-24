// The one setting the LLVM C API cannot reach: floating-point fusion. Strict
// means no fused multiply-add is ever formed, even from `fmuladd`.
#include "llvm/Target/TargetMachine.h"

extern "C" int nupp_llvm_strict_fp(void *tm) {
    auto *machine = reinterpret_cast<llvm::TargetMachine *>(tm);
    machine->Options.AllowFPOpFusion = llvm::FPOpFusion::Strict;
    return machine->Options.AllowFPOpFusion == llvm::FPOpFusion::Strict;
}

// The default O2/O3 pipeline built directly, not parsed from text: the parser
// references every registered pass, so avoiding it lets the linker drop the
// passes no default pipeline uses. Only the size probe's `cxx-pipeline`
// feature calls it.
#include "llvm/IR/Module.h"
#include "llvm/Passes/PassBuilder.h"

extern "C" void nupp_llvm_optimize(void *module, void *tm, int level) {
    using namespace llvm;
    auto *m = reinterpret_cast<Module *>(module);
    PipelineTuningOptions pto;
    pto.LoopVectorization = true;
    pto.SLPVectorization = true;
    pto.LoopInterleaving = true;
    pto.LoopUnrolling = true;
    LoopAnalysisManager lam;
    FunctionAnalysisManager fam;
    CGSCCAnalysisManager cgam;
    ModuleAnalysisManager mam;
    PassBuilder pb(reinterpret_cast<TargetMachine *>(tm), pto);
    pb.registerModuleAnalyses(mam);
    pb.registerCGSCCAnalyses(cgam);
    pb.registerFunctionAnalyses(fam);
    pb.registerLoopAnalyses(lam);
    pb.crossRegisterProxies(lam, fam, cgam, mam);
    ModulePassManager mpm = pb.buildPerModuleDefaultPipeline(level == 3 ? OptimizationLevel::O3 : OptimizationLevel::O2);
    mpm.run(*m, mam);
}
