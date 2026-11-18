/* Compile the exact adapter against selected upstream entries, only in tests.
 * The test checks CPU features before calling any forced SIMD entry.
 */
#include "crc.h"
#include "crc64.h"
#if defined(NUPP_FORCE_BASE)
static uint32_t gzip_base(uint32_t seed, const uint8_t *data, uint64_t length)
{
    return crc32_gzip_refl_base(seed, (uint8_t *)data, length);
}
#define crc32_gzip_refl gzip_base
#define crc32_iscsi crc32_iscsi_base
#define crc64_ecma_norm crc64_ecma_norm_base
#define crc64_rocksoft_refl crc64_rocksoft_refl_base
#elif defined(NUPP_FORCE_X86)
uint32_t crc32_gzip_refl_by8(uint32_t, const uint8_t *, uint64_t);
uint32_t crc32_iscsi_by8_02(unsigned char *, int, uint32_t);
#define crc32_gzip_refl crc32_gzip_refl_by8
#define crc32_iscsi crc32_iscsi_by8_02
#define crc64_ecma_norm crc64_ecma_norm_by8
#define crc64_rocksoft_refl crc64_rocksoft_refl_by8
#elif defined(NUPP_FORCE_ARM)
uint32_t crc32_gzip_refl_pmull(uint32_t, const uint8_t *, uint64_t);
uint32_t crc32_iscsi_refl_pmull(unsigned char *, int, uint32_t);
uint64_t crc64_ecma_norm_pmull(uint64_t, const uint8_t *, uint64_t);
uint64_t crc64_rocksoft_refl_pmull(uint64_t, const uint8_t *, uint64_t);
#define crc32_gzip_refl crc32_gzip_refl_pmull
#define crc32_iscsi crc32_iscsi_refl_pmull
#define crc64_ecma_norm crc64_ecma_norm_pmull
#define crc64_rocksoft_refl crc64_rocksoft_refl_pmull
#endif
#ifdef NUPP_FORCE_SMALL_CHUNKS
#include <limits.h>
/* Exercise the same bounded-length loop without allocating two gigabytes. */
#undef INT_MAX
#define INT_MAX 31
#endif
#include "../../../../native/crc/crc.c"
