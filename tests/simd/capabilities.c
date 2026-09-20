/* Compile at the host baseline; probing never executes an unsupported tier. */
#include <stdio.h>
int main(void) {
#if defined(__aarch64__) || defined(_M_ARM64)
    puts("neon");
#elif defined(__x86_64__) || defined(_M_X64)
    puts("baseline");
    __builtin_cpu_init();
    if (__builtin_cpu_supports("avx2")) puts("avx2");
    if (__builtin_cpu_supports("avx512f")) puts("avx512f");
#else
#error SIMD execution matrix needs an explicitly modeled host architecture
#endif
    return 0;
}
