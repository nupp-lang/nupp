/* Times bench/base64simd's generated encoder against bench/base64's
 * hand-written NEON encoder and its scalar one, for the Base64 table in
 * bench/simd11/README.md. The two vector encoders must write the same bytes
 * before either is timed; each figure is the fastest of SAMPLES interleaved
 * samples.
 *
 * Both benches, and the CPU AOT backend that compiled base64simd, left the
 * tree in 68f4d7f08, so build the comparison in a checkout of that commit's
 * parent. The generated library is the base64simd module compiled with the
 * harness flags:
 *
 *   ./bin/nupp aot --emit c --features neon \
 *       bench/base64simd/src/base64simd.nupp > /tmp/b64.c
 *   clang -std=c11 -O3 -ffp-contract=off -fno-fast-math -fPIC -dynamiclib \
 *       /tmp/b64.c -o /tmp/b64.dylib
 *   clang -std=c11 -O3 -D_POSIX_C_SOURCE=200809L -Ibench/base64 \
 *       bench/base64/base64_control.c bench/simd11/handwritten/base64.c \
 *       -o /tmp/base64-compare
 *   /tmp/base64-compare /tmp/b64.dylib */

#include "nupp_base64.h"

#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* Bytes in the Base64 alphabet. */
#define ALPHABET_SIZE 64

/* Spare bytes past each output's encoded length. */
#define OUTPUT_SLACK 16

/* Interleaved samples of each encoder; the fastest is reported. */
#define SAMPLES 101

/* Each sample makes enough calls to encode about this many bytes. */
#define BYTES_PER_SAMPLE 20000000

/* A best time slower than any sample. */
#define UNSAMPLED 1e30

/* The encoders, in the order of `best`. */
enum { GENERATED, HAND_NEON, SCALAR, ENCODERS };

/* The generated ks_encode: output, input, alphabet, then the length of each
 * of the three spans, as the AOT backend passes them. It answers the bytes
 * written. */
typedef uint32_t (*gen_fn)(uint8_t *, const uint8_t *, const uint8_t *, size_t,
                           size_t, size_t);

static double now (void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);

  return t.tv_sec + t.tv_nsec * 1e-9;
}

int main (int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "usage: base64-compare LIBRARY\n");

    return 2;
  }

  void *library = dlopen(argv[1], RTLD_NOW);

  if (!library) {
    fprintf(stderr, "%s\n", dlerror());

    return 1;
  }

  gen_fn generated = (gen_fn)dlsym(library, "ks_encode");

  if (!generated) {
    fprintf(stderr, "the library lacks ks_encode\n");

    return 1;
  }

  const uint8_t *alphabet =
      (const uint8_t
           *)"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  size_t sizes[] = {64, 1024, 65536};
  printf("vectorized control: %d\n", nuppBase64Vectorized());

  for (int s = 0; s < 3; s++) {
    size_t n = sizes[s], encoded = 4 * ((n + 2) / 3);
    uint8_t *input = malloc(n), *genOutput = malloc(encoded + OUTPUT_SLACK),
            *handOutput = malloc(encoded + OUTPUT_SLACK);

    for (size_t i = 0; i < n; i++) {
      input[i] = (uint8_t)(i * 131 + 7);
    }

    uint32_t written =
        generated(genOutput, input, alphabet, encoded, n, ALPHABET_SIZE);
    size_t handWritten = nuppBase64EncodeVector(input, n, (char *)handOutput);

    if (written != handWritten || memcmp(genOutput, handOutput, handWritten)) {
      printf("MISMATCH %zu %u %zu\n", n, written, handWritten);

      return 1;
    }

    size_t calls = BYTES_PER_SAMPLE / n + 1;
    double best[ENCODERS] = {UNSAMPLED, UNSAMPLED, UNSAMPLED};

    /* Reverse the order on odd samples, so no encoder always runs on a
     * cache another warmed. */
    for (int sample = 0; sample < SAMPLES; sample++) {
      for (int step = 0; step < ENCODERS; step++) {
        int which = (sample & 1) ? ENCODERS - 1 - step : step;
        double start = now();

        for (size_t c = 0; c < calls; c++) {
          if (which == GENERATED) {
            generated(genOutput, input, alphabet, encoded, n, ALPHABET_SIZE);
          }
          else if (which == HAND_NEON) {
            nuppBase64EncodeVector(input, n, (char *)handOutput);
          }
          else {
            nuppBase64EncodeScalar(input, n, (char *)handOutput);
          }

          __asm__ volatile("" ::: "memory");
        }

        double each = (now() - start) / calls * 1e9;

        if (each < best[which]) {
          best[which] = each;
        }
      }
    }

    printf("%6zu generated %9.1fns  hand NEON %9.1fns  scalar C %9.1fns  "
           "gen/hand %.3fx\n",
           n, best[GENERATED], best[HAND_NEON], best[SCALAR],
           best[GENERATED] / best[HAND_NEON]);
  }
}
