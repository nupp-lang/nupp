/* Times the generated explicit kernels in the harness library against their
 * hand-written NEON versions in neon.c and the scalar-source C, over the
 * harness's inputs and sizes, for the tables in bench/simd11/README.md.
 * Every implementation must agree bit for bit with the scalar entry before
 * anything is timed; the algebraic dot product, which may reassociate, need
 * only come within the harness's relative bound. Each figure is the fastest
 * of SAMPLES interleaved samples of about a millisecond, which is what a
 * deterministic loop on a shared machine measures best.
 *
 * usage: compare LIBRARY [UTF8-LIBRARY]
 *
 * LIBRARY is bench/simd11/build/native.dylib, which `measure.py --prepare`
 * builds, and UTF8-LIBRARY bench/simd11/build/utf8/native.dylib. Both come
 * from the CPU AOT backend, which left the tree in 68f4d7f08, so build them
 * in a checkout of that commit's parent. */

#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* The map kernel's coefficients: output = input * MAP_SCALE + MAP_BIAS. */
#define MAP_SCALE 1.25
#define MAP_BIAS -0.5

/* Written past the end of each output and checked afterward, to catch a
 * kernel that stores beyond its count. */
#define CANARY -777.0
#define CANARY_SLOTS 4

/* The algebraic dot product's error bound, relative to the scalar answer. */
#define ALGEBRAIC_BOUND 1e-12

/* Interleaved samples of each implementation; the fastest is reported. */
#define SAMPLES 101

/* Each sample makes enough calls to cover about this many elements: fewer
 * for refine, whose elements each loop up to 32 times. */
#define ELEMENTS_PER_SAMPLE 4000000
#define REFINE_ELEMENTS_PER_SAMPLE 400000

/* A best time slower than any sample. */
#define UNSAMPLED 1e30

/* The map and refine implementations, in the order of `best`. Map has no
 * tuned hand version. */
enum { SCALAR_C, GENERATED, HAND, HAND_TUNED };

enum { MAP_IMPLEMENTATIONS = 3, REFINE_IMPLEMENTATIONS = 4 };

/* The kernels of the first table, then the dot products of the second. */
enum { MAP, REFINE };

enum { ORDERED, PAIRWISE, ALGEBRAIC, DOT_KERNELS };

/* The harness library's entries take each span's length after its pointers;
 * the hand versions take one count. */
typedef void (*mapfn)(double *, const double *, double, double, size_t, size_t);
typedef void (*refinefn)(double *, const double *, size_t, size_t);
typedef double (*librarydot)(const double *, const double *, size_t, size_t);
typedef double (*dotfn)(const double *, const double *, size_t);
typedef uint32_t (*utf8fn)(const uint8_t *, size_t);

/* neon.c */
double handordered (const double *left, const double *right, size_t count);
double handpairwise (const double *left, const double *right, size_t count);
double handalgebraic (const double *left, const double *right, size_t count);
uint32_t handutf8prefix (const uint8_t *source, size_t count);
void handmap (double *restrict output, const double *input, double scale,
              double bias, size_t count);
void handrefine (double *restrict output, const double *input, size_t count);
void handrefinetuned (double *restrict output, const double *input,
                      size_t count);

static mapfn generatedmap, scalarmap;
static refinefn generatedrefine, scalarrefine;

/* Runs implementation `which` of map over `n` elements. */
static void runmap (int which, double *out, const double *in, size_t n) {
  if (which == SCALAR_C) {
    scalarmap(out, in, MAP_SCALE, MAP_BIAS, n, n);
  }
  else if (which == GENERATED) {
    generatedmap(out, in, MAP_SCALE, MAP_BIAS, n, n);
  }
  else {
    handmap(out, in, MAP_SCALE, MAP_BIAS, n);
  }
}

/* Runs implementation `which` of refine over `n` elements. */
static void runrefine (int which, double *out, const double *in, size_t n) {
  if (which == SCALAR_C) {
    scalarrefine(out, in, n, n);
  }
  else if (which == GENERATED) {
    generatedrefine(out, in, n, n);
  }
  else if (which == HAND) {
    handrefine(out, in, n);
  }
  else {
    handrefinetuned(out, in, n);
  }
}

static double now (void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);

  return (double)t.tv_sec + (double)t.tv_nsec * 1e-9;
}

/* Three tables, one after another: map and refine, the dot products, and
 * UTF-8 validation when a second library is named. Odd samples run the
 * implementations in reverse, so none always runs on a cache another
 * warmed. */
int main (int argc, char **argv) {
  if (argc != 2 && argc != 3) {
    fprintf(stderr, "usage: compare LIBRARY [UTF8-LIBRARY]\n");

    return 2;
  }

  void *library = dlopen(argv[1], RTLD_NOW);

  if (!library) {
    fprintf(stderr, "%s\n", dlerror());

    return 1;
  }

  scalarmap = (mapfn)dlsym(library, "ks_map");
  generatedmap = (mapfn)dlsym(library, "ks_explicit_map");
  scalarrefine = (refinefn)dlsym(library, "ks_refine");
  generatedrefine = (refinefn)dlsym(library, "ks_explicit_refine");

  if (!scalarmap || !generatedmap || !scalarrefine || !generatedrefine) {
    fprintf(stderr, "the library lacks a kernel\n");

    return 1;
  }

  const size_t sizes[] = {63, 64, 1024, 65539};
  printf("%-7s %7s %12s %12s %12s %12s %10s\n", "kernel", "n", "scalar C",
         "generated", "hand NEON", "hand tuned", "gen/best");

  /* Map and refine: the scalar entry writes the answer the others must
   * match, canaries included. */
  for (int kernel = MAP; kernel <= REFINE; kernel++) {
    for (size_t s = 0; s < sizeof sizes / sizeof sizes[0]; s++) {
      size_t n = sizes[s];
      double *in = malloc(n * sizeof *in),
             *out = malloc((n + CANARY_SLOTS) * sizeof *out),
             *want = malloc(n * sizeof *want);

      for (size_t i = 0; i < n; i++) {
        in[i] = (double)(i % 97 + 1) * 0.125;
      }

      if (kernel == MAP) {
        runmap(SCALAR_C, want, in, n);
      }
      else {
        runrefine(SCALAR_C, want, in, n);
      }

      int kinds = kernel == MAP ? MAP_IMPLEMENTATIONS : REFINE_IMPLEMENTATIONS;

      for (int which = GENERATED; which < kinds; which++) {
        for (int k = 0; k < CANARY_SLOTS; k++) {
          out[n + k] = CANARY;
        }

        if (kernel == MAP) {
          runmap(which, out, in, n);
        }
        else {
          runrefine(which, out, in, n);
        }

        if (memcmp(out, want, n * sizeof *want) != 0 || out[n] != CANARY) {
          fprintf(stderr, "%s %zu: implementation %d disagrees with scalar C\n",
                  kernel ? "refine" : "map", n, which);

          return 1;
        }
      }

      size_t elements =
          kernel == MAP ? ELEMENTS_PER_SAMPLE : REFINE_ELEMENTS_PER_SAMPLE;
      size_t calls = elements / n + 1;
      double best[REFINE_IMPLEMENTATIONS] = {UNSAMPLED, UNSAMPLED, UNSAMPLED,
                                             UNSAMPLED};

      for (int sample = 0; sample < SAMPLES; sample++) {
        for (int step = 0; step < kinds; step++) {
          int which = (sample & 1) ? kinds - 1 - step : step;
          double start = now();

          for (size_t c = 0; c < calls; c++) {
            if (kernel == MAP) {
              runmap(which, out, in, n);
            }
            else {
              runrefine(which, out, in, n);
            }

            __asm__ volatile("" ::: "memory");
          }

          double each = (now() - start) / (double)calls * 1e9;

          if (each < best[which]) {
            best[which] = each;
          }
        }
      }

      double hand =
          best[HAND] < best[HAND_TUNED] ? best[HAND] : best[HAND_TUNED];

      if (kernel == MAP) {
        printf("%-7s %7zu %10.2fns %10.2fns %10.2fns %12s %9.3fx\n", "map", n,
               best[SCALAR_C], best[GENERATED], best[HAND], "",
               best[GENERATED] / hand);
      }
      else {
        printf("%-7s %7zu %10.2fns %10.2fns %10.2fns %10.2fns %9.3fx\n",
               "refine", n, best[SCALAR_C], best[GENERATED], best[HAND],
               best[HAND_TUNED], best[GENERATED] / hand);
      }

      free(in);
      free(out);
      free(want);
    }
  }

  /* The dot products: here `best` holds scalar C, generated and hand. */
  const char *names[DOT_KERNELS] = {"ordered", "pairwise", "algebraic"};
  const char *scalars[DOT_KERNELS] = {"ks_ordered", "ks_pairwise",
                                      "ks_algebraic"};
  const char *generated[DOT_KERNELS] = {
      "ks_explicit_ordered", "ks_explicit_pairwise", "ks_explicit_algebraic"};
  dotfn hands[DOT_KERNELS] = {handordered, handpairwise, handalgebraic};

  for (int kernel = ORDERED; kernel < DOT_KERNELS; kernel++) {
    librarydot scalar = (librarydot)dlsym(library, scalars[kernel]);
    librarydot mine = (librarydot)dlsym(library, generated[kernel]);

    if (!scalar || !mine) {
      fprintf(stderr, "the library lacks %s\n", names[kernel]);

      return 1;
    }

    for (size_t s = 0; s < sizeof sizes / sizeof sizes[0]; s++) {
      size_t n = sizes[s];
      double *left = malloc(n * sizeof *left),
             *right = malloc(n * sizeof *right);

      for (size_t i = 0; i < n; i++) {
        left[i] = (double)(i % 97 + 1) * 0.125;
        right[i] = (double)(i % 17 + 1) * 0.0625;
      }

      double want = scalar(left, right, n, n);
      double got[2] = {mine(left, right, n, n), hands[kernel](left, right, n)};

      for (int which = 0; which < 2; which++) {
        double error = got[which] - want;

        if (error < 0) {
          error = -error;
        }

        double bound = kernel == ALGEBRAIC
                           ? ALGEBRAIC_BOUND * (want < 0 ? -want : want)
                           : 0.0;

        if (error > bound) {
          fprintf(stderr, "%s %zu: %s answers %.17g, scalar C %.17g\n",
                  names[kernel], n, which ? "hand" : "generated", got[which],
                  want);

          return 1;
        }
      }

      size_t calls = ELEMENTS_PER_SAMPLE / n + 1;
      double best[3] = {UNSAMPLED, UNSAMPLED, UNSAMPLED};
      volatile double sink = 0.0;

      for (int sample = 0; sample < SAMPLES; sample++) {
        for (int step = 0; step < 3; step++) {
          int which = (sample & 1) ? 2 - step : step;
          double start = now();

          for (size_t c = 0; c < calls; c++) {
            sink = which == 0   ? scalar(left, right, n, n)
                   : which == 1 ? mine(left, right, n, n)
                                : hands[kernel](left, right, n);
            __asm__ volatile("" ::: "memory");
          }

          double each = (now() - start) / (double)calls * 1e9;

          if (each < best[which]) {
            best[which] = each;
          }
        }
      }

      (void)sink;
      printf("%-9s %7zu %10.2fns %10.2fns %10.2fns %12s %9.3fx\n",
             names[kernel], n, best[0], best[1], best[2], "",
             best[1] / best[2]);
      free(left);
      free(right);
    }
  }

  /* UTF-8 validation: the generated and hand validators must answer the
   * same prefix, over ASCII and over a mix of two-, three- and four-byte
   * scalars. */
  if (argc == 3) {
    void *utf8 = dlopen(argv[2], RTLD_NOW);

    if (!utf8) {
      fprintf(stderr, "%s\n", dlerror());

      return 1;
    }

    utf8fn generatedutf8 = (utf8fn)dlsym(utf8, "ks_valid_prefix");

    if (!generatedutf8) {
      fprintf(stderr, "the UTF-8 library lacks ks_valid_prefix\n");

      return 1;
    }

    const char *kinds[2] = {"utf8-ascii", "utf8-unicode"};
    const char *units[2] = {"abcdefg", "\xc3\xa9\xe2\x82\xac\xf0\x9f\x98\x80"};
    const size_t lengths[] = {63, 1024, 65539};

    for (int kind = 0; kind < 2; kind++) {
      for (size_t s = 0; s < sizeof lengths / sizeof lengths[0]; s++) {
        size_t n = lengths[s];
        size_t unit = strlen(units[kind]);
        uint8_t *bytes = malloc(n);

        for (size_t i = 0; i < n; i++) {
          bytes[i] = (uint8_t)units[kind][i % unit];
        }

        uint32_t want = generatedutf8(bytes, n), got = handutf8prefix(bytes, n);

        if (want != got) {
          fprintf(stderr, "%s %zu: generated %u, hand %u\n", kinds[kind], n,
                  want, got);

          return 1;
        }

        size_t calls = ELEMENTS_PER_SAMPLE / n + 1;
        double best[2] = {UNSAMPLED, UNSAMPLED};
        volatile uint32_t sink = 0;

        for (int sample = 0; sample < SAMPLES; sample++) {
          for (int step = 0; step < 2; step++) {
            int which = (sample & 1) ? 1 - step : step;
            double start = now();

            for (size_t c = 0; c < calls; c++) {
              sink = which == 0 ? generatedutf8(bytes, n)
                                : handutf8prefix(bytes, n);
              __asm__ volatile("" ::: "memory");
            }

            double each = (now() - start) / (double)calls * 1e9;

            if (each < best[which]) {
              best[which] = each;
            }
          }
        }

        (void)sink;
        printf("%-12s %7zu %10s %10.2fns %10.2fns %12s %9.3fx\n", kinds[kind],
               n, "", best[0], best[1], "", best[0] / best[1]);
        free(bytes);
      }
    }
  }

  return 0;
}
