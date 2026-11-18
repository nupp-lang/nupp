#include "nupp_crc.h"
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

typedef int32_t (*update_fn)(uint32_t, int32_t, uint64_t *, const uint8_t *,
                             size_t);
int32_t crc_base(uint32_t, int32_t, uint64_t *, const uint8_t *, size_t);
int32_t crc_small_chunks(uint32_t, int32_t, uint64_t *, const uint8_t *,
                         size_t);
#if defined(NUPP_TEST_X86) || defined(NUPP_TEST_ARM)
int32_t crc_simd(uint32_t, int32_t, uint64_t *, const uint8_t *, size_t);
#endif

static int has_simd(void)
{
#if defined(NUPP_TEST_X86) && defined(_MSC_VER)
  int regs[4];
  __cpuid(regs, 1);
  return (regs[2] & ((1 << 1) | (1 << 9) | (1 << 20))) ==
         ((1 << 1) | (1 << 9) | (1 << 20));
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
 */
static uint64_t reference(unsigned id, uint64_t state, const uint8_t *p,
                          size_t n)
{
  const uint64_t poly[] = {0, 0xedb88320, 0x82f63b78, 0x42f0e1eba9ea3693,
                           0x9a6c9329ac4bc9b5};
  while (n--) {
    state ^= id == 3 ? (uint64_t)*p++ << 56 : *p++;
    for (int bit = 0; bit < 8; ++bit)
      state = id == 3 ? (state << 1) ^ ((state >> 63) ? poly[id] : 0)
                      : (state >> 1) ^ ((state & 1) ? poly[id] : 0);
  }
  return id < 3 ? state & UINT32_MAX : state;
}

static uint64_t random_word(void)
{
  static uint64_t state = 0x250dc6b5f65d8c4b;
  state ^= state << 13;
  state ^= state >> 7;
  state ^= state << 17;
  return state;
}

static void check(update_fn update)
{
  const uint64_t known[] = {0, 0xcbf43926, 0xe3069283, 0x6c40df5f0b497347,
                            0xae8b14860a799888};
  uint8_t bytes[16448];
  for (size_t i = 0; i < sizeof(bytes); ++i)
    bytes[i] = (uint8_t)random_word();
  for (unsigned id = 1; id <= 4; ++id) {
    const uint64_t mask = id <= 2 ? UINT32_MAX : UINT64_MAX;
    const uint64_t xorout = id == 3 ? 0 : mask;
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
    for (unsigned trial = 0; trial < 160; ++trial) {
      const size_t n = trial < 65 ? trial : (size_t)(random_word() % 16385);
      const uint8_t *p = bytes + trial % 32;
      const uint64_t seed = random_word() & mask;
      const uint64_t want = reference(id, seed, p, n);
      words[0] = seed;
      words[1] = 99;
      assert(!update(id, 0, words, p, n));
      assert(words[0] == want && words[1] == (want ^ xorout));
      words[0] = seed;
      size_t offset = 0;
      while (offset < n) {
	size_t count = (size_t)(random_word() % 513 + 1);
	if (count > n - offset)
	  count = n - offset;
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

static void bench(update_fn update, const char *path)
{
  static uint8_t bytes[1048576];
  for (size_t i = 0; i < sizeof(bytes); ++i)
    bytes[i] = (uint8_t)(i * 73 + i / 5);
  const size_t sizes[] = {16, 4096, sizeof(bytes)};
  for (unsigned id = 1; id <= 4; ++id) {
    for (unsigned s = 0; s < 3; ++s) {
      size_t n = sizes[s], rounds = 67108864 / n;
      uint64_t words[2] = {0, 0};
      clock_t began = clock();
      for (size_t r = 0; r < rounds; ++r)
	assert(!update(id, 1, words, bytes, n));
      double seconds = (double)(clock() - began) / CLOCKS_PER_SEC;
      printf("%s id=%u bytes=%zu MiB/s=%.1f checksum=%016" PRIx64 "\n", path,
             id, n, 64.0 / seconds, words[1]);
    }
  }
}

int main(void)
{
  check(nuppCrcUpdate);
  check(crc_base);
  check(crc_small_chunks);
  int simd = has_simd();
#if defined(NUPP_TEST_X86) || defined(NUPP_TEST_ARM)
  if (simd)
    check(crc_simd);
#endif
  printf("CRC vectors/raw seeds/chunks/offsets/tails: dispatch=pass base=pass "
         "bounded-chunks=pass SIMD=%s\n",
         simd ? "pass" : "unsupported");
  bench(nuppCrcUpdate, "dispatch");
  bench(crc_base, "base");
  return 0;
}
