/* The first block of every generated C file: the standard headers, the
 * attribute and export macros, and the small fixed-width helpers every body
 * may reach for. Appended verbatim; nothing here depends on the program. */
#include <math.h>
#include <string.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#if defined(__aarch64__)
#include <arm_neon.h>
#if defined(__clang__) || defined(__GNUC__)
typedef float ks_alias_float __attribute__((may_alias));
typedef double ks_alias_double __attribute__((may_alias));
typedef int32_t ks_alias_i32 __attribute__((may_alias));
typedef uint32_t ks_alias_u32 __attribute__((may_alias));
#endif
#elif defined(__x86_64__) || defined(_M_X64)
#include <immintrin.h>
#endif
/* Windows exports nothing from a shared library unless it is asked to,
 * so a wrapper that loaded one would find no symbol in it. Everywhere
 * else a definition is exported by being one. */
#if defined(_WIN32)
#define KS_API __declspec(dllexport)
#else
#define KS_API
#endif
/* Clang targeting MSVC defines neither __GNUC__ nor the MSVC warning set,
 * so keying this on __GNUC__ alone left the attribute empty on the one
 * compiler that still warns about an unused static function. */
#if defined(__GNUC__) || defined(__clang__)
#define KS_UNUSED __attribute__((unused))
#define KS_COLD __attribute__((noinline, cold))
#define KS_UNLIKELY(cond) __builtin_expect(!!(cond), 0)
#else
#define KS_UNUSED
#define KS_COLD
#define KS_UNLIKELY(cond) (cond)
#endif
/* What a local array of lanes may be assumed to sit on.
 *
 * Its element's own alignment, on Windows, said out loud. GCC widens a local
 * array to the vector register it means to move it with, which is a fair
 * trade everywhere the frame can be widened to match -- and the Windows x64
 * frame cannot: sixteen bytes is all a caller leaves, and GCC neither rounds
 * a pointer for these nor realigns, yet still reaches for `vmovaps` at a
 * thirty-two byte offset into one. Saying the alignment explicitly is what
 * holds it to the element, because an alignment the source asked for is one
 * the backend stops widening. Every other target leaves the choice alone. */
#if (defined(_WIN32) || defined(_WIN64)) && (defined(__GNUC__) || defined(__clang__))
#define KS_LANE_ARRAY_ALIGN(type) __attribute__((aligned(__alignof__(type))))
#else
#define KS_LANE_ARRAY_ALIGN(type)
#endif
/* A partial vector moves through general registers rather than a stack
 * array: fewer than eight bytes are gathered by their bits of width,
 * so a tail is a few loads and no call. The layout is little-endian's,
 * which every target here has; anything else keeps the array copy. */
#if defined(__BYTE_ORDER__) && defined(__ORDER_LITTLE_ENDIAN__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#define KS_WORD_TAIL 1
static inline KS_UNUSED uint64_t ks_gather_word(const uint8_t *source, size_t n) {
    uint64_t word = 0u; size_t at = 0u;
    if (n & 4u) { uint32_t part; memcpy(&part, source, 4u); word = part; at = 4u; }
    if (n & 2u) { uint16_t part; memcpy(&part, source + at, 2u); word |= (uint64_t)part << (at * 8u); at += 2u; }
    if (n & 1u) { word |= (uint64_t)source[at] << (at * 8u); }
    return word;
}
static inline KS_UNUSED void ks_scatter_word(uint8_t *destination, size_t n, uint64_t word) {
    size_t at = 0u;
    if (n & 4u) { uint32_t part = (uint32_t)word; memcpy(destination, &part, 4u); word >>= 32u; at = 4u; }
    if (n & 2u) { uint16_t part = (uint16_t)word; memcpy(destination + at, &part, 2u); word >>= 16u; at += 2u; }
    if (n & 1u) { destination[at] = (uint8_t)word; }
}
#else
#define KS_WORD_TAIL 0
#endif
/* Scalar oracles and their helpers keep their arithmetic unoptimized.
 * GCC x86 excludes AVX instructions from aggregate copies so stack
 * temporaries require only the platform ABI's alignment. */
#if defined(__clang__)
#define KS_SCALAR_ORACLE __attribute__((optnone))
#elif defined(__GNUC__) && (defined(__x86_64__) || defined(__i386__))
#define KS_SCALAR_ORACLE __attribute__((optimize("O0"), target("no-avx")))
#elif defined(__GNUC__)
#define KS_SCALAR_ORACLE __attribute__((optimize("O0")))
#else
#define KS_SCALAR_ORACLE
#endif
/* A count that came in as a uint32_t can only overflow the byte product
 * where size_t is no wider than it is. On a 64-bit size_t the comparison
 * is provably false, which is a -Wtype-limits error rather than a guard. */
#if SIZE_MAX <= 0xFFFFFFFFu
#define KS_COUNT_OVERFLOWS(n, size) ((size_t)(n) > SIZE_MAX / (size))
#else
#define KS_COUNT_OVERFLOWS(n, size) (0)
#endif
#ifndef M_PI
#define M_PI 3.14159265358979323846264338327950288
#endif
typedef struct { uint32_t low, high; } KsMaskBits64;
typedef struct { uint8_t lane[16]; } KsTableU8x16;
static KS_UNUSED KsMaskBits64 ks_mask64(uint32_t low, uint32_t high) { KsMaskBits64 out = {low, high}; return out; }
static KS_UNUSED KsMaskBits64 ks_mask64_add(KsMaskBits64 a, KsMaskBits64 b) { uint32_t low = a.low + b.low; return ks_mask64(low, a.high + b.high + (low < a.low ? 1u : 0u)); }
static KS_UNUSED KsMaskBits64 ks_mask64_and(KsMaskBits64 a, KsMaskBits64 b) { return ks_mask64(a.low & b.low, a.high & b.high); }
static KS_UNUSED KsMaskBits64 ks_mask64_or(KsMaskBits64 a, KsMaskBits64 b) { return ks_mask64(a.low | b.low, a.high | b.high); }
static KS_UNUSED KsMaskBits64 ks_mask64_xor(KsMaskBits64 a, KsMaskBits64 b) { return ks_mask64(a.low ^ b.low, a.high ^ b.high); }
static KS_UNUSED KsMaskBits64 ks_mask64_not(KsMaskBits64 a) { return ks_mask64(~a.low, ~a.high); }
static KS_UNUSED bool ks_mask64_any(KsMaskBits64 a) { return a.low != 0u || a.high != 0u; }
static KS_UNUSED uint32_t ks_mask64_count(KsMaskBits64 a) { return (uint32_t)(__builtin_popcount(a.low) + __builtin_popcount(a.high)); }
static KS_UNUSED uint32_t ks_mask64_first(KsMaskBits64 a) { return a.low != 0u ? (uint32_t)__builtin_ctz(a.low) : (a.high != 0u ? UINT32_C(32) + (uint32_t)__builtin_ctz(a.high) : UINT32_C(64)); }
static KS_UNUSED KsMaskBits64 ks_mask64_clear_first(KsMaskBits64 a) { return a.low != 0u ? ks_mask64(a.low & (a.low - 1u), a.high) : ks_mask64(0u, a.high & (a.high - 1u)); }
static KS_UNUSED KsMaskBits64 ks_mask64_shl(KsMaskBits64 a, uint32_t n) { if (n >= 64u) { return ks_mask64(0u, 0u); } if (n == 0u) { return a; } if (n >= 32u) { return ks_mask64(0u, a.low << (n - 32u)); } return ks_mask64(a.low << n, (a.high << n) | (a.low >> (32u - n))); }
static KS_UNUSED KsMaskBits64 ks_mask64_shr(KsMaskBits64 a, uint32_t n) { if (n >= 64u) { return ks_mask64(0u, 0u); } if (n == 0u) { return a; } if (n >= 32u) { return ks_mask64(a.high >> (n - 32u), 0u); } return ks_mask64((a.low >> n) | (a.high << (32u - n)), a.high >> n); }
static KS_UNUSED KsMaskBits64 ks_mask64_prefix_xor(KsMaskBits64 a, bool carry) { uint32_t lo = a.low, hi = a.high; lo ^= lo << 1; lo ^= lo << 2; lo ^= lo << 4; lo ^= lo << 8; lo ^= lo << 16; hi ^= hi << 1; hi ^= hi << 2; hi ^= hi << 4; hi ^= hi << 8; hi ^= hi << 16; if ((lo & UINT32_C(0x80000000)) != 0u) { hi = ~hi; } if (carry) { lo = ~lo; hi = ~hi; } return ks_mask64(lo, hi); }
/* C's usual arithmetic conversions decide a mixed signed/unsigned
 * comparison in unsigned arithmetic. These compare by mathematical
 * value, which is what the source wrote and the folder answers. */
static KS_UNUSED bool ks_lt_i64_u64(int64_t l, uint64_t r) { return l < 0 || (uint64_t)l < r; }
static KS_UNUSED bool ks_le_i64_u64(int64_t l, uint64_t r) { return l < 0 || (uint64_t)l <= r; }
static KS_UNUSED bool ks_gt_i64_u64(int64_t l, uint64_t r) { return l >= 0 && (uint64_t)l > r; }
static KS_UNUSED bool ks_ge_i64_u64(int64_t l, uint64_t r) { return l >= 0 && (uint64_t)l >= r; }
static KS_UNUSED bool ks_eq_i64_u64(int64_t l, uint64_t r) { return l >= 0 && (uint64_t)l == r; }
static KS_UNUSED bool ks_ne_i64_u64(int64_t l, uint64_t r) { return l < 0 || (uint64_t)l != r; }
/* The 32-bit pairing widens exactly into int64_t, so these are the bare
 * operator over the widened values and nothing more. They are functions
 * rather than that expression written at the site because a widened int32
 * cannot reach the upper half of uint32's range: against a constant up
 * there the comparison is provably constant, which is the right answer and
 * a -Wtype-limits error to write inline. Across a parameter the operands
 * are int64_t, which is the type the comparison is defined over. */
static KS_UNUSED bool ks_lt_i32_u32(int64_t l, int64_t r) { return l < r; }
static KS_UNUSED bool ks_le_i32_u32(int64_t l, int64_t r) { return l <= r; }
static KS_UNUSED bool ks_gt_i32_u32(int64_t l, int64_t r) { return l > r; }
static KS_UNUSED bool ks_ge_i32_u32(int64_t l, int64_t r) { return l >= r; }
static KS_UNUSED bool ks_eq_i32_u32(int64_t l, int64_t r) { return l == r; }
static KS_UNUSED bool ks_ne_i32_u32(int64_t l, int64_t r) { return l != r; }

