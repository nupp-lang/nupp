/* The CRC adapter's probe, only in tests. .github/scripts/test-crc-isal.sh
 * builds it against the installed static library and runs it: it checks the
 * dispatching adapter, the adapter forced onto ISA-L's portable entries and
 * onto a tiny chunk limit, and, when this CPU has them, its SIMD entries
 * (force.c), all against an independent bit-at-a-time model. Then it prints
 * throughput for the dispatching and portable builds. */

#include "nuppcrc.h"

#include <assert.h>
#include <inttypes.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#if defined(NUPP_TEST_X86) && defined(_MSC_VER)

#include <intrin.h>

#elif defined(NUPP_TEST_ARM) && defined(__APPLE__)

#include <sys/sysctl.h>

#elif defined(NUPP_TEST_ARM) && defined(__linux__)

#include <sys/auxv.h>
#include <asm/hwcap.h>

#endif

/* The algorithm ids nuppcrc.h documents. */
enum algorithm {
  CRC32_IEEE = 1,
  CRC32_CASTAGNOLI = 2,
  CRC64_ECMA_182 = 3,
  CRC64_NVME = 4,
};

/* What CPUID leaf 1 reports in ECX for the instructions ISA-L's x86 entries
 * use: PCLMULQDQ, SSSE3 and SSE4.2. */
enum {
  CPUID_FEATURES = 1,
  CPUID_ECX = 2,
  ECX_PCLMULQDQ = 1 << 1,
  ECX_SSSE3 = 1 << 9,
  ECX_SSE42 = 1 << 20,
};

/* check's TRIALS messages per algorithm: up to MAX_MESSAGE bytes, starting
 * below MAX_OFFSET into its buffer, the first SHORT_MESSAGES of every length
 * from zero, and fed again in chunks of up to MAX_CHUNK bytes. */
enum {
  TRIALS = 160,
  MAX_MESSAGE = 16384,
  MAX_OFFSET = 32,
  SHORT_MESSAGES = 65,
  MAX_CHUNK = 513,
};

/* The bytes each throughput measurement feeds through. */
enum { BENCH_BYTES = 64 * 1024 * 1024 };

typedef int32_t (*updatefn)(uint32_t, int32_t, uint64_t *, const uint8_t *,
                            size_t);

/* The adapter built by force.c, once per choice of ISA-L entries. */
int32_t crcbase (uint32_t, int32_t, uint64_t *, const uint8_t *, size_t);
int32_t crcsmall (uint32_t, int32_t, uint64_t *, const uint8_t *, size_t);

#if defined(NUPP_TEST_X86) || defined(NUPP_TEST_ARM)

int32_t crcsimd (uint32_t, int32_t, uint64_t *, const uint8_t *, size_t);

#endif

/* Whether this CPU can run the SIMD entries crcsimd was forced onto. */
static int hassimd (void) {
#if defined(NUPP_TEST_X86) && defined(_MSC_VER)
  int regs[4];
  __cpuid(regs, CPUID_FEATURES);

  return (regs[CPUID_ECX] & (ECX_PCLMULQDQ | ECX_SSSE3 | ECX_SSE42)) ==
         (ECX_PCLMULQDQ | ECX_SSSE3 | ECX_SSE42);
#elif defined(NUPP_TEST_X86)

  return __builtin_cpu_supports("pclmul") && __builtin_cpu_supports("ssse3") &&
         __builtin_cpu_supports("sse4.2");
#elif defined(NUPP_TEST_ARM) && defined(__APPLE__)
  int enabled = 0;
  size_t size = sizeof(enabled);

  return !sysctlbyname("hw.optional.arm.FEAT_PMULL", &enabled, &size, NULL,
                       0) &&
         enabled;
#elif defined(NUPP_TEST_ARM) && defined(__linux__)

  return (getauxval(AT_HWCAP) & HWCAP_PMULL) != 0;
#else

  return 0;
#endif
}

/* Independent bit-at-a-time model, only in tests. Polynomial parameters are
 * CRC RevEng's ISO-HDLC, iSCSI, ECMA-182 and NVME catalogue definitions.
 * https://reveng.sourceforge.io/crc-catalogue/all.htm
 * ECMA-182 shifts left, most significant bit first; the others are
 * reflected and shift right. The state is the raw register.
 */
static uint64_t reference (unsigned id, uint64_t state, const uint8_t *p,
                           size_t n) {
  const uint64_t poly[] = {0, 0xedb88320, 0x82f63b78, 0x42f0e1eba9ea3693,
                           0x9a6c9329ac4bc9b5};

  while (n--) {
    state ^= id == CRC64_ECMA_182 ? (uint64_t)*p++ << 56 : *p++;

    for (int bit = 0; bit < 8; ++bit) {
      state = id == CRC64_ECMA_182
                  ? (state << 1) ^ ((state >> 63) ? poly[id] : 0)
                  : (state >> 1) ^ ((state & 1) ? poly[id] : 0);
    }
  }

  return id < CRC64_ECMA_182 ? state & UINT32_MAX : state;
}

/* A fixed xorshift sequence, so every run checks the same input. */
static uint64_t randomword (void) {
  static uint64_t state = 0x250dc6b5f65d8c4b;
  state ^= state << 13;
  state ^= state >> 7;
  state ^= state << 17;

  return state;
}

/* Checks one build of the adapter: each algorithm's check value, resetting
 * and empty updates, raw seeds, every short length and random long ones at
 * every offset, the same messages fed in random chunks, and that each
 * invalid call is refused without touching its state. */
static void check (updatefn update) {
  /* Each algorithm's CRC of "123456789", indexed by its id. */
  const uint64_t known[] = {0, 0xcbf43926, 0xe3069283, 0x6c40df5f0b497347,
                            0xae8b14860a799888};
  uint8_t bytes[MAX_MESSAGE + 2 * MAX_OFFSET];

  for (size_t i = 0; i < sizeof(bytes); ++i) {
    bytes[i] = (uint8_t)randomword();
  }

  for (unsigned id = CRC32_IEEE; id <= CRC64_NVME; ++id) {
    const uint64_t mask = id <= CRC32_CASTAGNOLI ? UINT32_MAX : UINT64_MAX;
    const uint64_t xorout = id == CRC64_ECMA_182 ? 0 : mask;
    uint64_t words[2] = {0, 99};
    assert(!update(id, 1, words, NULL, 0));
    assert(words[0] == xorout && words[1] == 0);
    assert(!update(id, 0, words, (const uint8_t *)"123456789", 9));
    assert(words[1] == known[id] && words[0] == (known[id] ^ xorout));
    /* The old ABI accepts any uint64 raw word, even above a 32-bit width.
     * Empty updates must not silently truncate that saved word.
     */
    words[0] = UINT64_MAX;
    assert(!update(id, 0, words, NULL, 0));
    assert(words[0] == UINT64_MAX && words[1] == (UINT64_MAX ^ xorout));

    for (unsigned trial = 0; trial < TRIALS; ++trial) {
      const size_t n = trial < SHORT_MESSAGES
                           ? trial
                           : (size_t)(randomword() % (MAX_MESSAGE + 1));
      const uint8_t *p = bytes + trial % MAX_OFFSET;
      const uint64_t seed = randomword() & mask;
      const uint64_t want = reference(id, seed, p, n);
      words[0] = seed;
      words[1] = 99;
      assert(!update(id, 0, words, p, n));
      assert(words[0] == want && words[1] == (want ^ xorout));
      words[0] = seed;
      size_t offset = 0;

      while (offset < n) {
        size_t count = (size_t)(randomword() % MAX_CHUNK + 1);

        if (count > n - offset) {
          count = n - offset;
        }

        assert(!update(id, 0, words, p + offset, count));
        uint64_t saved[2];
        memcpy(saved, words, sizeof(saved));
        assert(!update(id, 0, words, NULL, 0));
        assert(!memcmp(saved, words, sizeof(saved)));
        /* Resume a copy, never a finalized value. */
        memcpy(words, saved, sizeof(saved));
        offset += count;
      }

      assert(!update(id, 0, words, NULL, 0));
      assert(words[0] == want && words[1] == (want ^ xorout));
    }
  }

  uint64_t words[] = {12, 34};
  assert(update(0, 0, words, NULL, 0) == 1);
  assert(update(1, 2, words, NULL, 0) == 1);
  assert(update(1, 0, words, NULL, 1) == 1);
  assert(update(1, 0, NULL, NULL, 0) == 1);
  assert(update(1, 0, words, bytes, SIZE_MAX) == 1);
  assert(words[0] == 12 && words[1] == 34);
}

/* Prints each algorithm's throughput over a short, a page-sized and a
 * megabyte message, each fed BENCH_BYTES in all. */
static void bench (updatefn update, const char *path) {
  static uint8_t bytes[1048576];

  for (size_t i = 0; i < sizeof(bytes); ++i) {
    bytes[i] = (uint8_t)(i * 73 + i / 5);
  }

  const size_t sizes[] = {16, 4096, sizeof(bytes)};

  for (unsigned id = CRC32_IEEE; id <= CRC64_NVME; ++id) {
    for (unsigned s = 0; s < 3; ++s) {
      size_t n = sizes[s], rounds = BENCH_BYTES / n;
      uint64_t words[2] = {0, 0};
      clock_t began = clock();

      for (size_t r = 0; r < rounds; ++r) {
        assert(!update(id, 1, words, bytes, n));
      }

      double seconds = (double)(clock() - began) / CLOCKS_PER_SEC;
      printf("%s id=%u bytes=%zu MiB/s=%.1f checksum=%016" PRIx64 "\n", path,
             id, n, 64.0 / seconds, words[1]);
    }
  }
}

int main (void) {
  check(nuppCrcUpdate);
  check(crcbase);
  check(crcsmall);
  int simd = hassimd();
#if defined(NUPP_TEST_X86) || defined(NUPP_TEST_ARM)

  if (simd) {
    check(crcsimd);
  }

#endif
  printf("CRC vectors/raw seeds/chunks/offsets/tails: dispatch=pass base=pass "
         "bounded-chunks=pass SIMD=%s\n",
         simd ? "pass" : "unsupported");
  bench(nuppCrcUpdate, "dispatch");
  bench(crcbase, "base");

  return 0;
}
