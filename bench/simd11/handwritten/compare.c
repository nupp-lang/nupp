/* Times the generated explicit kernels in the harness library against their
 * hand-written NEON versions and the scalar-source C, over the harness's
 * inputs and sizes. Every implementation must agree bit for bit with the
 * scalar entry before anything is timed. Each figure is the fastest of 101
 * interleaved samples of about a millisecond, which is what a deterministic
 * loop on a shared machine measures best.
 *
 * usage: compare LIBRARY   (bench/simd11/build/native.dylib after --prepare) */
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef void (*map_fn)(double *, const double *, double, double, size_t, size_t);
typedef void (*refine_fn)(double *, const double *, size_t, size_t);
void hand_map(double *restrict output, const double *input, double scale, double bias, size_t count);
void hand_refine(double *restrict output, const double *input, size_t count);
void hand_refine_tuned(double *restrict output, const double *input, size_t count);

static map_fn generated_map, scalar_map;
static refine_fn generated_refine, scalar_refine;

static void run_map(int which, double *out, const double *in, size_t n) {
    if (which == 0) scalar_map(out, in, 1.25, -0.5, n, n);
    else if (which == 1) generated_map(out, in, 1.25, -0.5, n, n);
    else hand_map(out, in, 1.25, -0.5, n);
}

static void run_refine(int which, double *out, const double *in, size_t n) {
    if (which == 0) scalar_refine(out, in, n, n);
    else if (which == 1) generated_refine(out, in, n, n);
    else if (which == 2) hand_refine(out, in, n);
    else hand_refine_tuned(out, in, n);
}

static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec + (double)t.tv_nsec * 1e-9;
}

int main(int argc, char **argv) {
    if (argc != 2) { fprintf(stderr, "usage: compare LIBRARY\n"); return 2; }
    void *library = dlopen(argv[1], RTLD_NOW);
    if (!library) { fprintf(stderr, "%s\n", dlerror()); return 1; }
    scalar_map = (map_fn)dlsym(library, "ks_map");
    generated_map = (map_fn)dlsym(library, "ks_explicit_map");
    scalar_refine = (refine_fn)dlsym(library, "ks_refine");
    generated_refine = (refine_fn)dlsym(library, "ks_explicit_refine");
    if (!scalar_map || !generated_map || !scalar_refine || !generated_refine) {
        fprintf(stderr, "the library lacks a kernel\n");
        return 1;
    }
    const size_t sizes[] = {63, 64, 1024, 65539};
    printf("%-7s %7s %12s %12s %12s %12s %10s\n", "kernel", "n", "scalar C", "generated", "hand NEON", "hand tuned", "gen/best");
    for (int kernel = 0; kernel < 2; kernel++) {
        for (size_t s = 0; s < sizeof sizes / sizeof sizes[0]; s++) {
            size_t n = sizes[s];
            double *in = malloc(n * sizeof *in), *out = malloc((n + 4) * sizeof *out), *want = malloc(n * sizeof *want);
            for (size_t i = 0; i < n; i++) in[i] = (double)(i % 97 + 1) * 0.125;
            if (kernel == 0) run_map(0, want, in, n); else run_refine(0, want, in, n);
            int kinds = kernel == 0 ? 3 : 4;
            for (int which = 1; which < kinds; which++) {
                for (int k = 0; k < 4; k++) out[n + k] = -777.0;
                if (kernel == 0) run_map(which, out, in, n); else run_refine(which, out, in, n);
                if (memcmp(out, want, n * sizeof *want) != 0 || out[n] != -777.0) {
                    fprintf(stderr, "%s %zu: implementation %d disagrees with scalar C\n", kernel ? "refine" : "map", n, which);
                    return 1;
                }
            }
            size_t calls = (kernel == 0 ? 4000000 : 400000) / n + 1;
            double best[4] = {1e30, 1e30, 1e30, 1e30};
            for (int sample = 0; sample < 101; sample++) {
                for (int step = 0; step < kinds; step++) {
                    int which = (sample & 1) ? kinds - 1 - step : step;
                    double start = now();
                    for (size_t c = 0; c < calls; c++) {
                        if (kernel == 0) run_map(which, out, in, n); else run_refine(which, out, in, n);
                        __asm__ volatile("" ::: "memory");
                    }
                    double each = (now() - start) / (double)calls * 1e9;
                    if (each < best[which]) best[which] = each;
                }
            }
            double hand = best[2] < best[3] ? best[2] : best[3];
            if (kernel == 0) {
                printf("%-7s %7zu %10.2fns %10.2fns %10.2fns %12s %9.3fx\n", "map", n, best[0], best[1], best[2], "", best[1] / hand);
            } else {
                printf("%-7s %7zu %10.2fns %10.2fns %10.2fns %10.2fns %9.3fx\n", "refine", n, best[0], best[1], best[2], best[3], best[1] / hand);
            }
            free(in); free(out); free(want);
        }
    }
    return 0;
}
