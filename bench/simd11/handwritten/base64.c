/* Times bench/base64simd's generated encoder against bench/base64's
 * hand-written NEON encoder and its scalar one. The generated library is the
 * base64simd module compiled with the harness flags:
 *
 *   ./bin/nupp aot --emit c --features neon bench/base64simd/src/base64simd.nupp > /tmp/b64.c
 *   clang -std=c11 -O3 -ffp-contract=off -fno-fast-math -fPIC -dynamiclib /tmp/b64.c -o /tmp/b64.dylib
 *   clang -std=c11 -O3 -D_POSIX_C_SOURCE=200809L -Ibench/base64 bench/base64/base64_control.c \
 *       bench/simd11/handwritten/base64.c -o /tmp/base64-compare
 *   /tmp/base64-compare /tmp/b64.dylib
 *
 * The two vector encoders must write the same bytes before either is timed;
 * each figure is the fastest of 101 interleaved samples. */
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "nupp_base64.h"
typedef uint32_t (*gen_fn)(uint8_t *, const uint8_t *, const uint8_t *, size_t, size_t, size_t);
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }
int main(int argc, char **argv) {
    if (argc != 2) { fprintf(stderr, "usage: base64-compare LIBRARY\n"); return 2; }
    void *lib = dlopen(argv[1], RTLD_NOW); if (!lib) { fprintf(stderr, "%s\n", dlerror()); return 1; }
    gen_fn gen = (gen_fn)dlsym(lib, "ks_encode"); if (!gen) { fprintf(stderr, "the library lacks ks_encode\n"); return 1; }
    const uint8_t *alphabet = (const uint8_t *)"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    size_t sizes[] = {64, 1024, 65536};
    printf("vectorized control: %d\n", nuppBase64Vectorized());
    for (int s = 0; s < 3; s++) {
        size_t n = sizes[s], m = 4 * ((n + 2) / 3);
        uint8_t *in = malloc(n), *a = malloc(m + 16), *b = malloc(m + 16);
        for (size_t i = 0; i < n; i++) in[i] = (uint8_t)(i * 131 + 7);
        uint32_t written = gen(a, in, alphabet, m, n, 64); size_t hw = nuppBase64EncodeVector(in, n, (char *)b);
        if (written != hw || memcmp(a, b, hw)) { printf("MISMATCH %zu %u %zu\n", n, written, hw); return 1; }
        size_t calls = 20000000 / n + 1; double best[3] = {1e30, 1e30, 1e30};
        for (int r = 0; r < 101; r++) for (int k = 0; k < 3; k++) {
            int f = (r & 1) ? 2 - k : k; double t = now();
            for (size_t c = 0; c < calls; c++) {
                if (f == 0) gen(a, in, alphabet, m, n, 64); else if (f == 1) nuppBase64EncodeVector(in, n, (char *)b); else nuppBase64EncodeScalar(in, n, (char *)b);
                __asm__ volatile("" ::: "memory");
            }
            double each = (now() - t) / calls * 1e9; if (each < best[f]) best[f] = each;
        }
        printf("%6zu generated %9.1fns  hand NEON %9.1fns  scalar C %9.1fns  gen/hand %.3fx\n", n, best[0], best[1], best[2], best[0] / best[1]);
    }
}
