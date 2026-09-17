/* The baseline runtime detector shared by every wrapper in one AOT library.
 *
 * Appended after ks_prelude.h as the whole of one translation unit, which is
 * compiled without an optional tier so that asking the question cannot itself
 * execute the instructions it is asking about. Compiler builtins account for
 * the processor and the operating system's enabled register state.
 *
 * `__builtin_cpu_supports` is answered at run time by a support routine in
 * the compiler's own runtime library -- `__cpu_model` and
 * `__cpu_indicator_init`. Targeting the MSVC ABI links against the Microsoft
 * runtime instead, which has neither, so the builtin compiles and then fails
 * to link. There the same question is asked of CPUID directly, which needs no
 * runtime library at all. */
#if defined(_MSC_VER) && (defined(_M_X64) || defined(_M_IX86))
#include <intrin.h>
#endif

KS_API int ks_aot_feature_tier(void) {
#if defined(_MSC_VER) && (defined(_M_X64) || defined(_M_IX86))
    int regs[4];
    unsigned int enabled;
    __cpuid(regs, 0);
    /* Leaf 7 is where both extended feature bits live. */
    if (regs[0] < 7) return 0;
    __cpuid(regs, 1);
    /* Without OSXSAVE the operating system has enabled no wider register
     * state and XGETBV is not available to ask which. */
    if ((regs[2] & (1 << 27)) == 0) return 0;
    enabled = (unsigned int)_xgetbv(0);
    /* XMM and YMM state. A processor that has AVX2 while the operating
     * system saves neither cannot run it. */
    if ((enabled & 0x6u) != 0x6u) return 0;
    __cpuidex(regs, 7, 0);
    /* And opmask, ZMM_Hi256 and Hi16_ZMM on top of those for AVX-512. */
    if ((enabled & 0xE6u) == 0xE6u && (regs[1] & (1 << 16)) != 0) return 2;
    if ((regs[1] & (1 << 5)) != 0) return 1;
#elif defined(__x86_64__) || defined(_M_X64)
    __builtin_cpu_init();
    if (__builtin_cpu_supports("avx512f")) return 2;
    if (__builtin_cpu_supports("avx2")) return 1;
#endif
    return 0;
}
