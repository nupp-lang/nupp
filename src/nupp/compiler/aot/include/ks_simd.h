/* The SIMD prelude of an AOT program: the packed u8 vector its string
 * scanners run on, the scalar oracle beside it, and the explicit vector
 * elements of `nupp.simd`. Appended verbatim after the scalar prelude,
 * once per vector width the program uses, with `KS_SIMD_WIDTH` set to
 * 16 or 32 around each copy and `KS_LUA_BUILDER` defined to 1 when the
 * Lua builder prelude is present. The reusable part sits under the
 * include guard and runs once; the per-width block at the end runs for
 * every copy.
 *
 * Bodies that pick an instruction set are chosen here, at top level,
 * because a directive cannot sit inside a macro body. Every count that
 * is pasted into a name or spelt as a literal in a body arrives as a
 * literal token from the per-width block, never as an expression. */
#ifndef KS_SIMD_H
#define KS_SIMD_H

#define KS_CAT_(a, b) a##b
#define KS_CAT(a, b) KS_CAT_(a, b)

/* `v` repeated N times, comma separated: a splat or zero initialiser. */
#define KS_REP_2(v) v, v
#define KS_REP_4(v) KS_REP_2(v), KS_REP_2(v)
#define KS_REP_8(v) KS_REP_4(v), KS_REP_4(v)
#define KS_REP_16(v) KS_REP_8(v), KS_REP_8(v)
#define KS_REP_32(v) KS_REP_16(v), KS_REP_16(v)

/* `X(a, i)` for each lane index i, comma separated. */
#define KS_LANES_2(X, a) X(a, 0), X(a, 1)
#define KS_LANES_4(X, a) KS_LANES_2(X, a), X(a, 2), X(a, 3)
#define KS_LANES_8(X, a) KS_LANES_4(X, a), X(a, 4), X(a, 5), X(a, 6), X(a, 7)
#define KS_LANES_16(X, a) KS_LANES_8(X, a), X(a, 8), X(a, 9), X(a, 10), X(a, 11), X(a, 12), X(a, 13), X(a, 14), X(a, 15)
#define KS_LANES_32(X, a) KS_LANES_16(X, a), X(a, 16), X(a, 17), X(a, 18), X(a, 19), X(a, 20), X(a, 21), X(a, 22), X(a, 23), X(a, 24), X(a, 25), X(a, 26), X(a, 27), X(a, 28), X(a, 29), X(a, 30), X(a, 31)
#define KS_INDEX_LANE(a, i) i
#define KS_CAST_LANE(type, i) (type)i
#define KS_IOTA_LANE(ctype, i) first + (ctype)i * step

/* The scalar oracle is compiled without vector instructions where the
 * compiler can be told so, which keeps it an oracle rather than a
 * second copy of the same code. */
#if defined(__GNUC__) && !defined(__clang__) && (defined(__x86_64__) || defined(__i386__))
#define KS_SCALAR_REGION_BEGIN _Pragma("GCC push_options") _Pragma("GCC optimize (\"O0\")") _Pragma("GCC target (\"no-avx\")")
#define KS_SCALAR_REGION_END _Pragma("GCC pop_options")
#else
#define KS_SCALAR_REGION_BEGIN
#define KS_SCALAR_REGION_END
#endif

KS_SCALAR_REGION_BEGIN
static __attribute__((unused)) void ks_scalar_copy_bytes(void *destination, const void *source, size_t count) {
    uint8_t *out = (uint8_t *)destination; const uint8_t *in = (const uint8_t *)source;
    for (size_t i = 0u; i < count; ++i) out[i] = in[i];
}
KS_SCALAR_REGION_END

/* ---- The packed u8 vector ------------------------------------------ */

/* A 16-lane table lookup: NEON and x86 have the byte shuffle, wasm has
 * a swizzle, and a 32-byte vector without AVX2 walks its lanes. */
#define KS_LOOKUP16_PORTABLE(W) \
    for (uint32_t i = 0; i < W##u; ++i) { uint8_t index = ((const uint8_t *)&indexes)[i]; ((uint8_t *)&out)[i] = index < 16u ? table.lane[index] : 0u; }
#define KS_LOOKUP16_SSSE3 \
    __m128i input, lookup, high, shuffled; memcpy(&input, &indexes, 16u); memcpy(&lookup, table.lane, 16u); high = _mm_and_si128(input, _mm_set1_epi8((char)0xf0)); shuffled = _mm_shuffle_epi8(lookup, input); shuffled = _mm_and_si128(shuffled, _mm_cmpeq_epi8(high, _mm_setzero_si128())); memcpy(&out, &shuffled, 16u);
#if defined(__aarch64__)
#define KS_LOOKUP16_BODY_16 \
    uint8x16_t lookup = vld1q_u8(table.lane); \
    uint8x16_t input; memcpy(&input, &indexes, 16u); input = vqtbl1q_u8(lookup, input); memcpy(&out, &input, 16u);
#define KS_LOOKUP16_BODY_32 \
    uint8x16_t lookup = vld1q_u8(table.lane); \
    uint8x16_t lo, hi; memcpy(&lo, &indexes, 16u); memcpy(&hi, ((const uint8_t *)&indexes) + 16u, 16u); lo = vqtbl1q_u8(lookup, lo); hi = vqtbl1q_u8(lookup, hi); memcpy(&out, &lo, 16u); memcpy(((uint8_t *)&out) + 16u, &hi, 16u);
#elif defined(__AVX2__)
#define KS_LOOKUP16_BODY_16 KS_LOOKUP16_SSSE3
#define KS_LOOKUP16_BODY_32 \
    __m256i input, lookup, high, shuffled; __m128i table128; memcpy(&input, &indexes, 32u); memcpy(&table128, table.lane, 16u); lookup = _mm256_broadcastsi128_si256(table128); high = _mm256_and_si256(input, _mm256_set1_epi8((char)0xf0)); shuffled = _mm256_shuffle_epi8(lookup, input); shuffled = _mm256_and_si256(shuffled, _mm256_cmpeq_epi8(high, _mm256_setzero_si256())); memcpy(&out, &shuffled, 32u);
#elif defined(__SSSE3__)
#define KS_LOOKUP16_BODY_16 KS_LOOKUP16_SSSE3
#define KS_LOOKUP16_BODY_32 KS_LOOKUP16_PORTABLE(32)
#elif defined(__wasm_simd128__)
/* `i8x16.swizzle` is this operation, zero for an out-of-range
 * index included, so the mask the x86 paths need is not wanted. */
#define KS_LOOKUP16_BODY_16 \
    typedef signed char KsSwizzle __attribute__((vector_size(16))); \
    KsSwizzle lookup, input, shuffled; memcpy(&lookup, table.lane, 16u); memcpy(&input, &indexes, 16u); \
    shuffled = __builtin_wasm_swizzle_i8x16(lookup, input); memcpy(&out, &shuffled, 16u);
#define KS_LOOKUP16_BODY_32 KS_LOOKUP16_PORTABLE(32)
#else
#define KS_LOOKUP16_BODY_16 KS_LOOKUP16_PORTABLE(16)
#define KS_LOOKUP16_BODY_32 KS_LOOKUP16_PORTABLE(32)
#endif

/* A stride-3 gather has a NEON instruction; everywhere else is the
 * lane loop that also serves a partial vector on NEON. */
#if defined(__aarch64__)
#define KS_LOAD_STRIDE3_FAST_16 \
    if ((size_t)offset + 48u <= count) { \
        uint8x16x3_t in = vld3q_u8(source + offset); uint8x16_t picked = lane == 0u ? in.val[0] : (lane == 1u ? in.val[1] : in.val[2]); memcpy(&out, &picked, 16u); return out; \
    }
#define KS_LOAD_STRIDE3_FAST_32 \
    if ((size_t)offset + 96u <= count) { \
        uint8x16x3_t lo = vld3q_u8(source + offset); uint8x16x3_t hi = vld3q_u8(source + offset + 48u); uint8x16_t a = lane == 0u ? lo.val[0] : (lane == 1u ? lo.val[1] : lo.val[2]); uint8x16_t b = lane == 0u ? hi.val[0] : (lane == 1u ? hi.val[1] : hi.val[2]); memcpy(&out, &a, 16u); memcpy(((uint8_t *)&out) + 16u, &b, 16u); return out; \
    }
#else
#define KS_LOAD_STRIDE3_FAST_16
#define KS_LOAD_STRIDE3_FAST_32
#endif

/* A 64-entry lookup from four 16-entry tables. */
#define KS_LOOKUP64_PORTABLE(W) \
    const uint8_t *lanes[4]; lanes[0] = t0.lane; lanes[1] = t1.lane; lanes[2] = t2.lane; lanes[3] = t3.lane; \
    for (uint32_t i = 0; i < W##u; ++i) { uint8_t index = ((const uint8_t *)&indexes)[i]; ((uint8_t *)&out)[i] = index < 64u ? lanes[index >> 4][index & 15u] : 0u; }
/* One `pshufb` per quarter. It reads only the low four bits of an
 * index, so each quarter answers everywhere and a comparison on
 * bits four and five says which answer to keep. An index of 64 or
 * more matches no quarter and keeps none, which is the contract. */
#define KS_LOOKUP64_SSSE3 \
    __m128i input, quarter, chosen, combined, selector; memcpy(&input, &indexes, 16u); \
    selector = _mm_and_si128(input, _mm_set1_epi8(0x30)); \
    combined = _mm_setzero_si128(); \
    memcpy(&quarter, t0.lane, 16u); chosen = _mm_shuffle_epi8(quarter, input); \
    combined = _mm_or_si128(combined, _mm_and_si128(chosen, _mm_cmpeq_epi8(selector, _mm_set1_epi8(0x00)))); \
    memcpy(&quarter, t1.lane, 16u); chosen = _mm_shuffle_epi8(quarter, input); \
    combined = _mm_or_si128(combined, _mm_and_si128(chosen, _mm_cmpeq_epi8(selector, _mm_set1_epi8(0x10)))); \
    memcpy(&quarter, t2.lane, 16u); chosen = _mm_shuffle_epi8(quarter, input); \
    combined = _mm_or_si128(combined, _mm_and_si128(chosen, _mm_cmpeq_epi8(selector, _mm_set1_epi8(0x20)))); \
    memcpy(&quarter, t3.lane, 16u); chosen = _mm_shuffle_epi8(quarter, input); \
    combined = _mm_or_si128(combined, _mm_and_si128(chosen, _mm_cmpeq_epi8(selector, _mm_set1_epi8(0x30)))); \
    combined = _mm_and_si128(combined, _mm_cmpeq_epi8(_mm_and_si128(input, _mm_set1_epi8((char)0xc0)), _mm_setzero_si128())); \
    memcpy(&out, &combined, 16u);
#if defined(__aarch64__)
#define KS_LOOKUP64_BODY_16 \
    uint8x16x4_t lookup; lookup.val[0] = vld1q_u8(t0.lane); lookup.val[1] = vld1q_u8(t1.lane); lookup.val[2] = vld1q_u8(t2.lane); lookup.val[3] = vld1q_u8(t3.lane); \
    uint8x16_t input; memcpy(&input, &indexes, 16u); input = vqtbl4q_u8(lookup, input); memcpy(&out, &input, 16u);
#define KS_LOOKUP64_BODY_32 \
    uint8x16x4_t lookup; lookup.val[0] = vld1q_u8(t0.lane); lookup.val[1] = vld1q_u8(t1.lane); lookup.val[2] = vld1q_u8(t2.lane); lookup.val[3] = vld1q_u8(t3.lane); \
    uint8x16_t lo, hi; memcpy(&lo, &indexes, 16u); memcpy(&hi, ((const uint8_t *)&indexes) + 16u, 16u); lo = vqtbl4q_u8(lookup, lo); hi = vqtbl4q_u8(lookup, hi); memcpy(&out, &lo, 16u); memcpy(((uint8_t *)&out) + 16u, &hi, 16u);
#elif defined(__AVX2__)
#define KS_LOOKUP64_BODY_16 KS_LOOKUP64_SSSE3
/* The same construction as the 16-byte one, with each quarter
 * broadcast to both 128-bit halves because `pshufb` shuffles within
 * a half rather than across the register. */
#define KS_LOOKUP64_BODY_32 \
    __m256i winput, wquarter, wchosen, wcombined, wselector; __m128i whalf; \
    memcpy(&winput, &indexes, 32u); \
    wselector = _mm256_and_si256(winput, _mm256_set1_epi8(0x30)); \
    wcombined = _mm256_setzero_si256(); \
    memcpy(&whalf, t0.lane, 16u); wquarter = _mm256_broadcastsi128_si256(whalf); wchosen = _mm256_shuffle_epi8(wquarter, winput); \
    wcombined = _mm256_or_si256(wcombined, _mm256_and_si256(wchosen, _mm256_cmpeq_epi8(wselector, _mm256_set1_epi8(0x00)))); \
    memcpy(&whalf, t1.lane, 16u); wquarter = _mm256_broadcastsi128_si256(whalf); wchosen = _mm256_shuffle_epi8(wquarter, winput); \
    wcombined = _mm256_or_si256(wcombined, _mm256_and_si256(wchosen, _mm256_cmpeq_epi8(wselector, _mm256_set1_epi8(0x10)))); \
    memcpy(&whalf, t2.lane, 16u); wquarter = _mm256_broadcastsi128_si256(whalf); wchosen = _mm256_shuffle_epi8(wquarter, winput); \
    wcombined = _mm256_or_si256(wcombined, _mm256_and_si256(wchosen, _mm256_cmpeq_epi8(wselector, _mm256_set1_epi8(0x20)))); \
    memcpy(&whalf, t3.lane, 16u); wquarter = _mm256_broadcastsi128_si256(whalf); wchosen = _mm256_shuffle_epi8(wquarter, winput); \
    wcombined = _mm256_or_si256(wcombined, _mm256_and_si256(wchosen, _mm256_cmpeq_epi8(wselector, _mm256_set1_epi8(0x30)))); \
    wcombined = _mm256_and_si256(wcombined, _mm256_cmpeq_epi8(_mm256_and_si256(winput, _mm256_set1_epi8((char)0xc0)), _mm256_setzero_si256())); \
    memcpy(&out, &wcombined, 32u);
#elif defined(__SSSE3__)
#define KS_LOOKUP64_BODY_16 KS_LOOKUP64_SSSE3
#define KS_LOOKUP64_BODY_32 KS_LOOKUP64_PORTABLE(32)
#elif defined(__wasm_simd128__)
/* One swizzle per quarter. An index outside a swizzle's own table
 * gives zero, and subtracting the quarter's base puts exactly one
 * of the four in range, so the four results combine by or. */
#define KS_LOOKUP64_BODY_16 \
    typedef signed char KsSwizzle __attribute__((vector_size(16))); \
    KsSwizzle input, q0, q1, q2, q3, bias, combined; \
    memcpy(&input, &indexes, 16u); \
    memcpy(&q0, t0.lane, 16u); memcpy(&q1, t1.lane, 16u); \
    memcpy(&q2, t2.lane, 16u); memcpy(&q3, t3.lane, 16u); \
    bias = (KsSwizzle){16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16}; \
    combined = __builtin_wasm_swizzle_i8x16(q0, input); \
    input -= bias; combined |= __builtin_wasm_swizzle_i8x16(q1, input); \
    input -= bias; combined |= __builtin_wasm_swizzle_i8x16(q2, input); \
    input -= bias; combined |= __builtin_wasm_swizzle_i8x16(q3, input); \
    memcpy(&out, &combined, 16u);
#define KS_LOOKUP64_BODY_32 KS_LOOKUP64_PORTABLE(32)
#else
#define KS_LOOKUP64_BODY_16 KS_LOOKUP64_PORTABLE(16)
#define KS_LOOKUP64_BODY_32 KS_LOOKUP64_PORTABLE(32)
#endif

/* Shifting the previous vector's last bytes in front of the current one. */
#define KS_ALIGN_PORTABLE(W) \
    memcpy(&out, ((const uint8_t *)&previous) + W##u - offset, offset); memcpy(((uint8_t *)&out) + offset, &current, W##u - offset);
#define KS_ALIGN_SSSE3 \
    __m128i a, b, r; memcpy(&a, &previous, 16u); memcpy(&b, &current, 16u); if (offset == 1u) { r = _mm_alignr_epi8(b, a, 15); } else if (offset == 2u) { r = _mm_alignr_epi8(b, a, 14); } else { r = _mm_alignr_epi8(b, a, 13); } memcpy(&out, &r, 16u);
#if defined(__aarch64__)
#define KS_ALIGN_BODY_16 \
    uint8x16_t a, b, r; memcpy(&a, &previous, 16u); memcpy(&b, &current, 16u); if (offset == 1u) r = vextq_u8(a, b, 15); else if (offset == 2u) r = vextq_u8(a, b, 14); else r = vextq_u8(a, b, 13); memcpy(&out, &r, 16u);
#define KS_ALIGN_BODY_32 \
    uint8x16_t p1, c0, c1, r0, r1; memcpy(&p1, ((const uint8_t *)&previous) + 16u, 16u); memcpy(&c0, &current, 16u); memcpy(&c1, ((const uint8_t *)&current) + 16u, 16u); if (offset == 1u) { r0 = vextq_u8(p1, c0, 15); r1 = vextq_u8(c0, c1, 15); } else if (offset == 2u) { r0 = vextq_u8(p1, c0, 14); r1 = vextq_u8(c0, c1, 14); } else { r0 = vextq_u8(p1, c0, 13); r1 = vextq_u8(c0, c1, 13); } memcpy(&out, &r0, 16u); memcpy(((uint8_t *)&out) + 16u, &r1, 16u);
#elif defined(__AVX2__)
#define KS_ALIGN_BODY_16 KS_ALIGN_SSSE3
#define KS_ALIGN_BODY_32 \
    __m256i a, b, bridge, r; memcpy(&a, &previous, 32u); memcpy(&b, &current, 32u); bridge = _mm256_permute2x128_si256(a, b, 0x21); if (offset == 1u) { r = _mm256_alignr_epi8(b, bridge, 15); } else if (offset == 2u) { r = _mm256_alignr_epi8(b, bridge, 14); } else { r = _mm256_alignr_epi8(b, bridge, 13); } memcpy(&out, &r, 32u);
#elif defined(__SSSE3__)
#define KS_ALIGN_BODY_16 KS_ALIGN_SSSE3
#define KS_ALIGN_BODY_32 KS_ALIGN_PORTABLE(32)
#else
#define KS_ALIGN_BODY_16 KS_ALIGN_PORTABLE(16)
#define KS_ALIGN_BODY_32 KS_ALIGN_PORTABLE(32)
#endif

/* The lane mask as a bitmap. A lane's high bit is what decides, which
 * every branch here honours and the portable one states outright. */
#define KS_BITS_PORTABLE(WORDS) \
    uint32_t bits = 0u; \
    const uint64_t high_bits = UINT64_C(0x8080808080808080); \
    const uint64_t pack_bits = UINT64_C(0x0002040810204081); \
    for (uint32_t i = 0; i < WORDS##u; ++i) { \
        uint64_t word; \
        memcpy(&word, ((const uint8_t *)&mask) + i * 8u, 8u); \
        bits |= (uint32_t)(((word & high_bits) * pack_bits) >> 56u) << (i * 8u); \
    } \
    return bits;
#if defined(__aarch64__)
#define KS_BITS_NEON_HEAD \
    static const uint8_t ks_lane_powers[16] = { 1, 2, 4, 8, 16, 32, 64, 128, 1, 2, 4, 8, 16, 32, 64, 128 }; \
    const uint8x16_t selectors = vld1q_u8(ks_lane_powers); \
    const uint8x16_t highBits = vdupq_n_u8(0x80u); \
    uint32_t bits;
#define KS_BITS_BODY_16 \
    KS_BITS_NEON_HEAD \
    uint8x16_t v0; memcpy(&v0, &mask, 16u); v0 = vandq_u8(vtstq_u8(v0, highBits), selectors); bits = (uint32_t)vaddv_u8(vget_low_u8(v0)) << 0u | (uint32_t)vaddv_u8(vget_high_u8(v0)) << 8u; \
    return bits;
#define KS_BITS_BODY_32 \
    KS_BITS_NEON_HEAD \
    uint8x16_t v0, v1; memcpy(&v0, &mask, 16u); memcpy(&v1, ((const uint8_t *)&mask) + 16u, 16u); v0 = vandq_u8(vtstq_u8(v0, highBits), selectors); v1 = vandq_u8(vtstq_u8(v1, highBits), selectors); bits = ((uint32_t)vaddv_u8(vget_low_u8(v0)) << 0u | (uint32_t)vaddv_u8(vget_high_u8(v0)) << 8u) | ((uint32_t)vaddv_u8(vget_low_u8(v1)) << 16u | (uint32_t)vaddv_u8(vget_high_u8(v1)) << 24u); \
    return bits;
#elif defined(__AVX2__)
#define KS_BITS_BODY_16 \
    __m128i v0; memcpy(&v0, &mask, 16u); return (uint32_t)(uint16_t)_mm_movemask_epi8(v0);
#define KS_BITS_BODY_32 \
    __m256i v0; memcpy(&v0, &mask, 32u); return (uint32_t)_mm256_movemask_epi8(v0);
#elif defined(__SSE2__)
#define KS_BITS_BODY_16 \
    __m128i v0; memcpy(&v0, &mask, 16u); return (uint32_t)(uint16_t)_mm_movemask_epi8(v0);
#define KS_BITS_BODY_32 \
    __m128i v0, v1; memcpy(&v0, &mask, 16u); memcpy(&v1, ((const uint8_t *)&mask) + 16u, 16u); return (uint32_t)(uint16_t)_mm_movemask_epi8(v0) | ((uint32_t)(uint16_t)_mm_movemask_epi8(v1) << 16u);
#else
#define KS_BITS_BODY_16 KS_BITS_PORTABLE(2)
#define KS_BITS_BODY_32 KS_BITS_PORTABLE(4)
#endif

/* Whether any lane is set does not need the bitmap that finding
 * which one would. A horizontal maximum keeps a high bit if any
 * lane has one, and that is the whole question. Everywhere else the
 * bitmap is already one instruction. */
#if defined(__aarch64__)
#define KS_ANY_BODY_16 \
    uint8x16_t v0; memcpy(&v0, &mask, 16u); return (uint32_t)((vmaxvq_u8(v0) & 0x80u) != 0u);
#define KS_ANY_BODY_32 \
    uint8x16_t v0, v1; memcpy(&v0, &mask, 16u); memcpy(&v1, ((const uint8_t *)&mask) + 16u, 16u); return (uint32_t)((vmaxvq_u8(vorrq_u8(v0, v1)) & 0x80u) != 0u);
#else
#define KS_ANY_BODY_16 return (uint32_t)(ks_bits_u8x16(mask) != 0u);
#define KS_ANY_BODY_32 return (uint32_t)(ks_bits_u8x32(mask) != 0u);
#endif

/* A 64-byte block is PARTS vectors of width W, the last at index LAST. */
#define KS_BLOCK_BITS(W) if (i * W##u < 32u) { out.low |= bits << (i * W##u); } else { out.high |= bits << (i * W##u - 32u); }
#define KS_U8_PACKED(W, PARTS, LAST) \
typedef uint8_t ks_u8x##W __attribute__((vector_size(W))); \
typedef struct { const uint8_t *source; size_t source_length; uint32_t length, full_length, tail_length; ks_u8x##W tail; } KsPaddedStringU8x##W; \
typedef struct { ks_u8x##W part[PARTS]; } KsBlockU8x64x##W; \
static inline __attribute__((unused)) ks_u8x##W ks_splat_u8x##W(uint8_t value) { \
    return (ks_u8x##W){ KS_REP_##W(value) }; \
} \
static inline __attribute__((unused)) ks_u8x##W ks_shr_u8x##W(ks_u8x##W value, uint32_t count) { \
    if (count >= 8u) return ks_splat_u8x##W(0u); \
    return value >> ks_splat_u8x##W((uint8_t)count); \
} \
static inline __attribute__((unused)) ks_u8x##W ks_shl_u8x##W(ks_u8x##W value, uint32_t count) { \
    if (count >= 8u) return ks_splat_u8x##W(0u); \
    return value << ks_splat_u8x##W((uint8_t)count); \
} \
static inline __attribute__((unused)) ks_u8x##W ks_load_u8x##W(const uint8_t *source, size_t count, uint32_t offset) { \
    ks_u8x##W out = (ks_u8x##W){ KS_REP_##W(0) }; \
    if ((size_t)offset < count) { \
        size_t active = count - (size_t)offset; \
        if (active > W##u) active = W##u; \
        memcpy(&out, source + offset, active); \
    } \
    return out; \
} \
static inline __attribute__((unused)) KsPaddedStringU8x##W ks_padded_string_u8x##W(const uint8_t *source, size_t count) { \
    KsPaddedStringU8x##W out; memset(&out, 0, sizeof(out)); \
    if (count > (size_t)UINT32_MAX) { return out; } \
    out.source = source; out.source_length = count; out.length = (uint32_t)count; \
    out.tail_length = (uint32_t)(count % W##u); \
    out.full_length = (uint32_t)(count - out.tail_length); \
    if (out.tail_length != 0u) { memcpy(&out.tail, source + out.full_length, out.tail_length); } \
    return out; \
} \
static inline __attribute__((unused)) ks_u8x##W ks_padded_load_full_u8x##W(const KsPaddedStringU8x##W *view, uint32_t offset) { \
    ks_u8x##W out = (ks_u8x##W){ KS_REP_##W(0) }; \
    if (offset >= view->full_length || offset % W##u != 0u) { return out; } \
    memcpy(&out, view->source + offset, W##u); return out; \
} \
static inline __attribute__((unused)) ks_u8x##W ks_padded_load_tail_u8x##W(const KsPaddedStringU8x##W *view) { return view->tail; } \
static inline __attribute__((unused)) ks_u8x##W ks_lookup16_u8x##W(ks_u8x##W indexes, KsTableU8x16 table) { \
    ks_u8x##W out = (ks_u8x##W){ KS_REP_##W(0) }; \
    KS_LOOKUP16_BODY_##W \
    return out; \
} \
static inline __attribute__((unused)) ks_u8x##W ks_load_stride3_u8x##W(const uint8_t *source, size_t count, uint32_t offset, uint32_t lane) { \
    ks_u8x##W out = (ks_u8x##W){ KS_REP_##W(0) }; \
    if (lane > 2u) { return out; } \
    KS_LOAD_STRIDE3_FAST_##W \
    for (uint32_t i = 0; i < W##u; ++i) { \
        size_t at = (size_t)offset + (size_t)i * 3u + (size_t)lane; \
        if (at < count) { ((uint8_t *)&out)[i] = source[at]; } \
    } \
    return out; \
} \
static inline __attribute__((unused)) ks_u8x##W ks_lookup64_u8x##W(ks_u8x##W indexes, KsTableU8x16 t0, KsTableU8x16 t1, KsTableU8x16 t2, KsTableU8x16 t3) { \
    ks_u8x##W out; \
    KS_LOOKUP64_BODY_##W \
    return out; \
} \
static inline __attribute__((unused)) ks_u8x##W ks_align_u8x##W(ks_u8x##W previous, ks_u8x##W current, uint32_t offset) { \
    ks_u8x##W out = (ks_u8x##W){ KS_REP_##W(0) }; \
    if (offset < 1u || offset > 3u) { return out; } \
    KS_ALIGN_BODY_##W \
    return out; \
} \
static inline __attribute__((unused)) ks_u8x##W ks_tail_u8x##W(uint32_t active) { \
    /* An ordinary vector comparison against the lane indexes. Every \
     * target has a byte compare, and saying it this way lets each one \
     * choose its own rather than leaving a per-lane loop for the \
     * backend to rediscover on every block. */ \
    const ks_u8x##W indexes = { KS_LANES_##W(KS_INDEX_LANE, _) }; \
    if (active > W##u) active = W##u; \
    return (ks_u8x##W)(indexes < ks_splat_u8x##W((uint8_t)active)); \
} \
static inline __attribute__((unused)) uint32_t ks_bits_u8x##W(ks_u8x##W mask) { \
    KS_BITS_BODY_##W \
} \
static inline __attribute__((unused)) KsBlockU8x64x##W ks_block64_load_u8x##W(const KsPaddedStringU8x##W *view, uint32_t offset) { \
    KsBlockU8x64x##W out = {{{0}}}; \
    if ((size_t)offset > view->source_length || view->source_length - (size_t)offset < 64u || offset % W##u != 0u) { return out; } \
    memcpy(&out, view->source + offset, 64u); return out; \
} \
static inline __attribute__((unused)) KsBlockU8x64x##W ks_block64_and_byte_u8x##W(KsBlockU8x64x##W block, uint8_t value) { \
    KsBlockU8x64x##W out; ks_u8x##W mask = ks_splat_u8x##W(value); \
    for (uint32_t i = 0u; i < PARTS##u; ++i) { out.part[i] = block.part[i] & mask; } return out; \
} \
static inline __attribute__((unused)) KsBlockU8x64x##W ks_block64_and_u8x##W(KsBlockU8x64x##W left, KsBlockU8x64x##W right) { \
    KsBlockU8x64x##W out; \
    for (uint32_t i = 0u; i < PARTS##u; ++i) { out.part[i] = left.part[i] & right.part[i]; } return out; \
} \
static inline __attribute__((unused)) KsBlockU8x64x##W ks_block64_shr_u8x##W(KsBlockU8x64x##W block, uint32_t count) { \
    KsBlockU8x64x##W out; \
    for (uint32_t i = 0u; i < PARTS##u; ++i) { out.part[i] = ks_shr_u8x##W(block.part[i], count); } return out; \
} \
static inline __attribute__((unused)) KsBlockU8x64x##W ks_block64_lookup16_u8x##W(KsBlockU8x64x##W block, KsTableU8x16 table) { \
    KsBlockU8x64x##W out; \
    for (uint32_t i = 0u; i < PARTS##u; ++i) { out.part[i] = ks_lookup16_u8x##W(block.part[i], table); } return out; \
} \
static inline __attribute__((unused)) KsMaskBits64 ks_block64_any_bits_u8x##W(KsBlockU8x64x##W block, uint8_t value) { \
    KsMaskBits64 out = {0u, 0u}; ks_u8x##W mask = ks_splat_u8x##W(value); ks_u8x##W zero = ks_splat_u8x##W(0u); \
    for (uint32_t i = 0u; i < PARTS##u; ++i) { uint32_t bits = ks_bits_u8x##W(~((block.part[i] & mask) == zero)); KS_BLOCK_BITS(W) } return out; \
} \
static inline __attribute__((unused)) ks_u8x##W ks_block64_last_u8x##W(KsBlockU8x64x##W block) { return block.part[LAST]; } \
static inline __attribute__((unused)) KsMaskBits64 ks_block64_utf8_errors_u8x##W(KsBlockU8x64x##W block, ks_u8x##W previous, KsTableU8x16 byte1_high, KsTableU8x16 byte1_low, KsTableU8x16 byte2_high) { \
    KsMaskBits64 out = {0u, 0u}; ks_u8x##W nibble = ks_splat_u8x##W(15u), continuation = ks_splat_u8x##W(128u), zero = ks_splat_u8x##W(0u); \
    for (uint32_t i = 0u; i < PARTS##u; ++i) { \
        ks_u8x##W current = block.part[i], previous1 = ks_align_u8x##W(previous, current, 1u), previous2 = ks_align_u8x##W(previous, current, 2u), previous3 = ks_align_u8x##W(previous, current, 3u); \
        ks_u8x##W special = ks_lookup16_u8x##W(ks_shr_u8x##W(previous1, 4u), byte1_high) & ks_lookup16_u8x##W(previous1 & nibble, byte1_low) & ks_lookup16_u8x##W(ks_shr_u8x##W(current, 4u), byte2_high); \
        ks_u8x##W must = (previous2 >= ks_splat_u8x##W(224u)) | (previous3 >= ks_splat_u8x##W(240u)); uint32_t bits = ks_bits_u8x##W(~(((must & continuation) ^ special) == zero)); \
        KS_BLOCK_BITS(W) previous = current; \
    } return out; \
} \
static inline __attribute__((unused)) KsMaskBits64 ks_block64_eq_u8x##W(KsBlockU8x64x##W block, uint8_t value) { \
    KsMaskBits64 out = {0u, 0u}; \
    for (uint32_t i = 0u; i < PARTS##u; ++i) { uint32_t bits = ks_bits_u8x##W(block.part[i] == ks_splat_u8x##W(value)); KS_BLOCK_BITS(W) } return out; \
} \
static inline __attribute__((unused)) KsMaskBits64 ks_block64_range_u8x##W(KsBlockU8x64x##W block, uint8_t low, uint8_t high) { \
    KsMaskBits64 out = {0u, 0u}; \
    for (uint32_t i = 0u; i < PARTS##u; ++i) { uint32_t bits = ks_bits_u8x##W((block.part[i] >= ks_splat_u8x##W(low)) & (block.part[i] <= ks_splat_u8x##W(high))); KS_BLOCK_BITS(W) } return out; \
} \
static inline __attribute__((unused)) KsMaskBits64 ks_block64_outside_range_u8x##W(KsBlockU8x64x##W block, uint8_t low, uint8_t high) { \
    KsMaskBits64 out = {0u, 0u}; \
    for (uint32_t i = 0u; i < PARTS##u; ++i) { uint32_t bits = ks_bits_u8x##W((block.part[i] < ks_splat_u8x##W(low)) | (block.part[i] > ks_splat_u8x##W(high))); KS_BLOCK_BITS(W) } return out; \
} \
static inline __attribute__((unused)) uint32_t ks_any_u8x##W(ks_u8x##W mask) { \
    KS_ANY_BODY_##W \
}

/*KS_SIMD_CONTINUE*/
