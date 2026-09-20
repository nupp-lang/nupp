/* The SIMD prelude of an AOT program: the explicit vector elements of
 * `nupp.simd` and their scalar oracle. Appended verbatim after the scalar prelude,
 * once per vector width the program uses, with `KS_SIMD_WIDTH` set to
 * 16, 32 or 64 around each copy and `KS_LUA_BUILDER` defined to 1 when the
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

/* `v` repeated N times, comma separated: a splat or zero initialiser. */
#define KS_REP_2(v) v, v
#define KS_REP_4(v) KS_REP_2(v), KS_REP_2(v)
#define KS_REP_8(v) KS_REP_4(v), KS_REP_4(v)
#define KS_REP_16(v) KS_REP_8(v), KS_REP_8(v)
#define KS_REP_32(v) KS_REP_16(v), KS_REP_16(v)
#define KS_REP_64(v) KS_REP_32(v), KS_REP_32(v)

/* `X(a, i)` for each lane index i, comma separated. */
#define KS_LANES_2(X, a) X(a, 0), X(a, 1)
#define KS_LANES_4(X, a) KS_LANES_2(X, a), X(a, 2), X(a, 3)
#define KS_LANES_8(X, a) KS_LANES_4(X, a), X(a, 4), X(a, 5), X(a, 6), X(a, 7)
#define KS_LANES_16(X, a) KS_LANES_8(X, a), X(a, 8), X(a, 9), X(a, 10), X(a, 11), X(a, 12), X(a, 13), X(a, 14), X(a, 15)
#define KS_LANES_32(X, a) KS_LANES_16(X, a), X(a, 16), X(a, 17), X(a, 18), X(a, 19), X(a, 20), X(a, 21), X(a, 22), X(a, 23), X(a, 24), X(a, 25), X(a, 26), X(a, 27), X(a, 28), X(a, 29), X(a, 30), X(a, 31)
#define KS_LANES_64(X, a) KS_LANES_32(X, a), X(a, 32), X(a, 33), X(a, 34), X(a, 35), X(a, 36), X(a, 37), X(a, 38), X(a, 39), X(a, 40), X(a, 41), X(a, 42), X(a, 43), X(a, 44), X(a, 45), X(a, 46), X(a, 47), X(a, 48), X(a, 49), X(a, 50), X(a, 51), X(a, 52), X(a, 53), X(a, 54), X(a, 55), X(a, 56), X(a, 57), X(a, 58), X(a, 59), X(a, 60), X(a, 61), X(a, 62), X(a, 63)
#define KS_INDEX_LANE(a, i) i
#define KS_CAST_LANE(type, i) (type)i
#define KS_IOTA_LANE(ctype, i) first + (ctype)i * step

/* The scalar oracle is compiled without vector instructions where the
 * compiler can be told so, which keeps it an oracle rather than a
 * second copy of the same code. The region is opened at file scope only:
 * GCC does not apply a push_options pragma reached through _Pragma inside
 * a macro body to the definitions that follow it in the same expansion,
 * and quietly drops them instead. The helpers a macro defines are static
 * inline, so an oracle compiled at O0 calls them out of line and they
 * need no options of their own. */
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

/* What a vector may claim about where it sits.
 *
 * Nothing, on Windows. Its x64 convention hands an aggregate wider than
 * eight bytes to a call by reference, and returns one through a pointer the
 * caller supplies; both of those live in the caller's frame, and a frame is
 * only ever sixteen-byte aligned there. GCC rounds a pointer into the frame
 * for a declared local that needs more and does not for either of those two,
 * yet still moves them with `vmovdqa` -- so half of all calls that are not
 * inlined away fault on a thirty-two byte vector. Which calls survive
 * inlining is the compiler's choice and changes with its version: a cold
 * path it splits out of an inline helper is a real call returning a real
 * vector, and no spelling of these helpers can prevent that.
 *
 * Saying the alignment is one is what takes the assumption away, and it
 * costs nothing that can be measured: an unaligned move to an address that
 * happens to be aligned runs at the same rate on every x86 that has AVX.
 * Every other target keeps the natural alignment, where the same by-value
 * vector is passed in registers or on a stack slot the ABI aligns. */
#if defined(_WIN32) || defined(_WIN64)
#define KS_VECTOR_ABI_ALIGN , __aligned__(1)
#else
#define KS_VECTOR_ABI_ALIGN
#endif

/* ---- Explicit vectors: nupp.simd elements ------------------------- */

/* A vector of width W is this many 64-bit words. */
#define KS_WORDS_16 2
#define KS_WORDS_32 4
#define KS_WORDS_64 8
#define KS_WORD_COUNT_16 2u
#define KS_WORD_COUNT_32 4u
#define KS_WORD_COUNT_64 8u
#define KS_WORDS_OR_16 words[0] | words[1]
#define KS_WORDS_OR_32 words[0] | words[1] | words[2] | words[3]
#define KS_WORDS_OR_64 words[0] | words[1] | words[2] | words[3] | words[4] | words[5] | words[6] | words[7]

/* A partial vector moves through 64-bit words on a little-endian
 * target, whole words first and the odd bytes gathered or scattered
 * by the prelude's helpers; elsewhere it goes through a lane array. */
#define KS_LOAD_WORDS_16 uint64_t w0 = 0u, w1 = 0u; \
    if (n >= 8u) memcpy(&w0, p + 0u, 8u);
#define KS_LOAD_WORDS_32 uint64_t w0 = 0u, w1 = 0u, w2 = 0u, w3 = 0u; \
    if (n >= 8u) memcpy(&w0, p + 0u, 8u); \
    if (n >= 16u) memcpy(&w1, p + 8u, 8u); \
    if (n >= 24u) memcpy(&w2, p + 16u, 8u);
#define KS_GATHER_WORDS_16 switch (n >> 3u) { case 0u: w0 |= ks_gather_word(p + 0u, n & 7u); break; case 1u: w1 |= ks_gather_word(p + 8u, n & 7u); break; default: break; }
#define KS_GATHER_WORDS_32 switch (n >> 3u) { case 0u: w0 |= ks_gather_word(p + 0u, n & 7u); break; case 1u: w1 |= ks_gather_word(p + 8u, n & 7u); break; case 2u: w2 |= ks_gather_word(p + 16u, n & 7u); break; case 3u: w3 |= ks_gather_word(p + 24u, n & 7u); break; default: break; }
#define KS_LOAD_WORDS_64 uint64_t w0 = 0u, w1 = 0u, w2 = 0u, w3 = 0u, w4 = 0u, w5 = 0u, w6 = 0u, w7 = 0u; \
    if (n >= 8u) memcpy(&w0, p + 0u, 8u); \
    if (n >= 16u) memcpy(&w1, p + 8u, 8u); \
    if (n >= 24u) memcpy(&w2, p + 16u, 8u); \
    if (n >= 32u) memcpy(&w3, p + 24u, 8u); \
    if (n >= 40u) memcpy(&w4, p + 32u, 8u); \
    if (n >= 48u) memcpy(&w5, p + 40u, 8u); \
    if (n >= 56u) memcpy(&w6, p + 48u, 8u);
#define KS_GATHER_WORDS_64 switch (n >> 3u) { case 0u: w0 |= ks_gather_word(p + 0u, n & 7u); break; case 1u: w1 |= ks_gather_word(p + 8u, n & 7u); break; case 2u: w2 |= ks_gather_word(p + 16u, n & 7u); break; case 3u: w3 |= ks_gather_word(p + 24u, n & 7u); break; case 4u: w4 |= ks_gather_word(p + 32u, n & 7u); break; case 5u: w5 |= ks_gather_word(p + 40u, n & 7u); break; case 6u: w6 |= ks_gather_word(p + 48u, n & 7u); break; case 7u: w7 |= ks_gather_word(p + 56u, n & 7u); break; default: break; }
#define KS_ASSEMBLE_WORDS_16 memcpy((uint8_t *)&out + 0u, &w0, 8u); memcpy((uint8_t *)&out + 8u, &w1, 8u);
#define KS_ASSEMBLE_WORDS_32 memcpy((uint8_t *)&out + 0u, &w0, 8u); memcpy((uint8_t *)&out + 8u, &w1, 8u); memcpy((uint8_t *)&out + 16u, &w2, 8u); memcpy((uint8_t *)&out + 24u, &w3, 8u);
#define KS_ASSEMBLE_WORDS_64 KS_ASSEMBLE_WORDS_32 memcpy((uint8_t *)&out + 32u, &w4, 8u); memcpy((uint8_t *)&out + 40u, &w5, 8u); memcpy((uint8_t *)&out + 48u, &w6, 8u); memcpy((uint8_t *)&out + 56u, &w7, 8u);
#define KS_SPLIT_WORDS_16 uint64_t w0, w1; memcpy(&w0, (const uint8_t *)&value + 0u, 8u); memcpy(&w1, (const uint8_t *)&value + 8u, 8u); \
    if (n >= 8u) memcpy(p + 0u, &w0, 8u);
#define KS_SPLIT_WORDS_32 uint64_t w0, w1, w2, w3; memcpy(&w0, (const uint8_t *)&value + 0u, 8u); memcpy(&w1, (const uint8_t *)&value + 8u, 8u); memcpy(&w2, (const uint8_t *)&value + 16u, 8u); memcpy(&w3, (const uint8_t *)&value + 24u, 8u); \
    if (n >= 8u) memcpy(p + 0u, &w0, 8u); \
    if (n >= 16u) memcpy(p + 8u, &w1, 8u); \
    if (n >= 24u) memcpy(p + 16u, &w2, 8u);
#define KS_SCATTER_WORDS_16 switch (n >> 3u) { case 0u: ks_scatter_word(p + 0u, n & 7u, w0); break; case 1u: ks_scatter_word(p + 8u, n & 7u, w1); break; default: break; }
#define KS_SCATTER_WORDS_32 switch (n >> 3u) { case 0u: ks_scatter_word(p + 0u, n & 7u, w0); break; case 1u: ks_scatter_word(p + 8u, n & 7u, w1); break; case 2u: ks_scatter_word(p + 16u, n & 7u, w2); break; case 3u: ks_scatter_word(p + 24u, n & 7u, w3); break; default: break; }
#define KS_SPLIT_WORDS_64 uint64_t w0, w1, w2, w3, w4, w5, w6, w7; memcpy(&w0, (const uint8_t *)&value + 0u, 8u); memcpy(&w1, (const uint8_t *)&value + 8u, 8u); memcpy(&w2, (const uint8_t *)&value + 16u, 8u); memcpy(&w3, (const uint8_t *)&value + 24u, 8u); memcpy(&w4, (const uint8_t *)&value + 32u, 8u); memcpy(&w5, (const uint8_t *)&value + 40u, 8u); memcpy(&w6, (const uint8_t *)&value + 48u, 8u); memcpy(&w7, (const uint8_t *)&value + 56u, 8u); \
    if (n >= 8u) memcpy(p + 0u, &w0, 8u); \
    if (n >= 16u) memcpy(p + 8u, &w1, 8u); \
    if (n >= 24u) memcpy(p + 16u, &w2, 8u); \
    if (n >= 32u) memcpy(p + 24u, &w3, 8u); \
    if (n >= 40u) memcpy(p + 32u, &w4, 8u); \
    if (n >= 48u) memcpy(p + 40u, &w5, 8u); \
    if (n >= 56u) memcpy(p + 48u, &w6, 8u);
#define KS_SCATTER_WORDS_64 switch (n >> 3u) { case 0u: ks_scatter_word(p + 0u, n & 7u, w0); break; case 1u: ks_scatter_word(p + 8u, n & 7u, w1); break; case 2u: ks_scatter_word(p + 16u, n & 7u, w2); break; case 3u: ks_scatter_word(p + 24u, n & 7u, w3); break; case 4u: ks_scatter_word(p + 32u, n & 7u, w4); break; case 5u: ks_scatter_word(p + 40u, n & 7u, w5); break; case 6u: ks_scatter_word(p + 48u, n & 7u, w6); break; case 7u: ks_scatter_word(p + 56u, n & 7u, w7); break; default: break; }
/* An eight-byte lane never leaves a partial word behind. */
#define KS_GATHER_TAIL_1(W) KS_GATHER_WORDS_##W
#define KS_GATHER_TAIL_2(W) KS_GATHER_WORDS_##W
#define KS_GATHER_TAIL_4(W) KS_GATHER_WORDS_##W
#define KS_GATHER_TAIL_8(W)
#define KS_SCATTER_TAIL_1(W) KS_SCATTER_WORDS_##W
#define KS_SCATTER_TAIL_2(W) KS_SCATTER_WORDS_##W
#define KS_SCATTER_TAIL_4(W) KS_SCATTER_WORDS_##W
#define KS_SCATTER_TAIL_8(W)
#if KS_WORD_TAIL
#define KS_EXP_LOAD_PART_BODY(W, ELEM, CTYPE, LANES, BYTES) \
    size_t n = room * BYTES##u; const uint8_t *p = (const uint8_t *)source; KS_LOAD_WORDS_##W \
    KS_GATHER_TAIL_##BYTES(W) \
    ks_exp_##ELEM out; KS_ASSEMBLE_WORDS_##W return out;
#define KS_EXP_STORE_PART_BODY(W, ELEM, CTYPE, LANES, BYTES) \
    size_t n = room * BYTES##u; uint8_t *p = (uint8_t *)destination; KS_SPLIT_WORDS_##W \
    KS_SCATTER_TAIL_##BYTES(W)
#else
#define KS_EXP_LOAD_PART_BODY(W, ELEM, CTYPE, LANES, BYTES) \
    CTYPE lanes[LANES##u] KS_LANE_ARRAY_ALIGN(CTYPE) = {0}; memcpy(lanes, source, room * sizeof lanes[0]); ks_exp_##ELEM out; memcpy(&out, lanes, sizeof out); return out;
#define KS_EXP_STORE_PART_BODY(W, ELEM, CTYPE, LANES, BYTES) \
    CTYPE lanes[LANES##u] KS_LANE_ARRAY_ALIGN(CTYPE); memcpy(lanes, &value, sizeof lanes); memcpy(destination, lanes, room * sizeof lanes[0]);
#endif

/* The mask bitmap, one bit per lane of BYTES bytes. NEON sums a
 * power-of-two selector per lane; SSE has a movemask per lane width;
 * the portable path packs each word's sign bits with a multiply. */
#define KS_LANE_POWERS_1 1, 2, 4, 8, 16, 32, 64, 128, 1, 2, 4, 8, 16, 32, 64, 128
#define KS_LANE_POWERS_2 0, 1, 0, 2, 0, 4, 0, 8, 0, 1, 0, 2, 0, 4, 0, 8
#define KS_LANE_POWERS_4 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 1, 0, 0, 0, 2
#define KS_LANE_POWERS_8 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1
#define KS_LANE_SIGNS_1 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80
#define KS_LANE_SIGNS_2 0, 0x80, 0, 0x80, 0, 0x80, 0, 0x80, 0, 0x80, 0, 0x80, 0, 0x80, 0, 0x80
#define KS_LANE_SIGNS_4 0, 0, 0, 0x80, 0, 0, 0, 0x80, 0, 0, 0, 0x80, 0, 0, 0, 0x80
#define KS_LANE_SIGNS_8 0, 0, 0, 0, 0, 0, 0, 0x80, 0, 0, 0, 0, 0, 0, 0, 0x80
#define KS_LANES_PER_HALF_1 8u
#define KS_LANES_PER_HALF_2 4u
#define KS_LANES_PER_HALF_4 2u
#define KS_LANES_PER_HALF_8 1u
#define KS_LANES_PER_REGISTER_1 16u
#define KS_LANES_PER_REGISTER_2 8u
#define KS_LANES_PER_REGISTER_4 4u
#define KS_LANES_PER_REGISTER_8 2u
#define KS_SSE_MOVEMASK_1(v) (uint64_t)(uint16_t)_mm_movemask_epi8(v)
#define KS_SSE_MOVEMASK_2(v) (uint64_t)(uint8_t)_mm_movemask_epi8(_mm_packs_epi16(v, _mm_setzero_si128()))
#define KS_SSE_MOVEMASK_4(v) (uint64_t)_mm_movemask_ps(_mm_castsi128_ps(v))
#define KS_SSE_MOVEMASK_8(v) (uint64_t)_mm_movemask_pd(_mm_castsi128_pd(v))
#define KS_PACK_SIGNS_1 word = (word >> 7u) & UINT64_C(0x0101010101010101); \
        out |= ((word * UINT64_C(0x0002040810204081)) >> 49u & UINT64_C(0xFF)) << (i * 8u);
#define KS_PACK_SIGNS_2 word = (word >> 15u) & UINT64_C(0x0001000100010001); \
        out |= ((word * UINT64_C(0x0000200040008001)) >> 45u & UINT64_C(0xF)) << (i * 4u);
#define KS_PACK_SIGNS_4 word = (word >> 31u) & UINT64_C(0x0000000100000001); \
        out |= ((word * UINT64_C(0x0000000080000001)) >> 31u & UINT64_C(0x3)) << (i * 2u);
#define KS_PACK_SIGNS_8 word = (word >> 63u) & UINT64_C(0x0000000000000001); \
        out |= ((word * UINT64_C(0x0000000000000001)) >> 0u & UINT64_C(0x1)) << (i * 1u);
#if defined(__aarch64__)
#define KS_EXP_BITS_REGISTER(BYTES, offset, shift) \
    memcpy(&v, ((const uint8_t *)&value) + offset, 16u); v = vandq_u8(vtstq_u8(v, highBits), selectors); out |= ((uint64_t)vaddv_u8(vget_low_u8(v)) | (uint64_t)vaddv_u8(vget_high_u8(v)) << KS_LANES_PER_HALF_##BYTES) << shift;
#define KS_EXP_BITS_BODY(W, ELEM, BYTES) \
    static const uint8_t ks_lane_powers[16] = { KS_LANE_POWERS_##BYTES }; \
    const uint8x16_t selectors = vld1q_u8(ks_lane_powers); \
    const uint8x16_t highBits = vdupq_n_u8(0x80u); \
    uint64_t out = 0u; uint8x16_t v; \
    KS_EXP_BITS_REGISTERS_##W(BYTES) \
    return out;
#define KS_EXP_ANY_BODY(W, ELEM, BYTES) \
    static const uint8_t ks_lane_signs[16] = { KS_LANE_SIGNS_##BYTES }; \
    const uint8x16_t signs = vld1q_u8(ks_lane_signs); \
    uint8x16_t v, all; \
    KS_EXP_ANY_REGISTERS_##W \
    return vmaxvq_u8(vandq_u8(all, signs)) != 0u;
#define KS_EXP_ANY_REGISTERS_16 memcpy(&v, ((const uint8_t *)&value) + 0u, 16u); all = v;
#define KS_EXP_ANY_REGISTERS_32 memcpy(&v, ((const uint8_t *)&value) + 0u, 16u); all = v; \
    memcpy(&v, ((const uint8_t *)&value) + 16u, 16u); all = vorrq_u8(all, v);
#define KS_EXP_ANY_REGISTERS_64 KS_EXP_ANY_REGISTERS_32 \
    memcpy(&v, ((const uint8_t *)&value) + 32u, 16u); all = vorrq_u8(all, v); \
    memcpy(&v, ((const uint8_t *)&value) + 48u, 16u); all = vorrq_u8(all, v);
#elif defined(__SSE2__)
#define KS_EXP_BITS_REGISTER(BYTES, offset, shift) \
    memcpy(&v, ((const uint8_t *)&value) + offset, 16u); out |= KS_SSE_MOVEMASK_##BYTES(v) << shift;
#define KS_EXP_BITS_BODY(W, ELEM, BYTES) \
    uint64_t out = 0u; __m128i v; \
    KS_EXP_BITS_REGISTERS_##W(BYTES) \
    return out;
#define KS_EXP_ANY_BODY(W, ELEM, BYTES) return ks_exp_bits_##ELEM(value) != UINT64_C(0);
#else
#define KS_EXP_BITS_BODY(W, ELEM, BYTES) \
    uint64_t out = 0u; \
    for (uint32_t i = 0u; i < KS_WORD_COUNT_##W; ++i) { \
        uint64_t word; memcpy(&word, ((const uint8_t *)&value) + i * 8u, 8u); \
        KS_PACK_SIGNS_##BYTES \
    } \
    return out;
#define KS_EXP_ANY_BODY(W, ELEM, BYTES) return ks_exp_bits_##ELEM(value) != UINT64_C(0);
#endif
#define KS_EXP_BITS_REGISTERS_16(BYTES) KS_EXP_BITS_REGISTER(BYTES, 0u, 0u)
#define KS_EXP_BITS_REGISTERS_32(BYTES) KS_EXP_BITS_REGISTER(BYTES, 0u, 0u) \
    KS_EXP_BITS_REGISTER(BYTES, 16u, KS_LANES_PER_REGISTER_##BYTES)
#define KS_EXP_BITS_REGISTERS_64(BYTES) KS_EXP_BITS_REGISTERS_32(BYTES) \
    KS_EXP_BITS_REGISTER(BYTES, 32u, (2u * KS_LANES_PER_REGISTER_##BYTES)) \
    KS_EXP_BITS_REGISTER(BYTES, 48u, (3u * KS_LANES_PER_REGISTER_##BYTES))

/* A byte swizzle has a table instruction on NEON, SSSE3 and wasm; a
 * wider lane, or a 32-byte vector on x86, walks the lanes. */
#define KS_EXP_SWIZZLE_LOOP(CTYPE, LANES) \
    for (uint32_t i = 0u; i < LANES##u; ++i) { uint32_t at = (uint32_t)indices[i]; out[i] = (at - 1u) < LANES##u ? value[at - 1u] : (CTYPE)0; }
#define KS_EXP_SWIZZLE_PAIR_LOOP(CTYPE, LANES) \
    for (uint32_t i = 0u; i < LANES##u; ++i) { uint32_t at = (uint32_t)indices[i] - 1u; out[i] = at < LANES##u ? first[at] : (at - LANES##u) < LANES##u ? second[at - LANES##u] : (CTYPE)0; }
#if defined(__aarch64__)
#define KS_EXP_BYTE_SWIZZLE_BODY_16(CTYPE, LANES) \
    uint8x16_t t, x; memcpy(&t, &value, 16u); memcpy(&x, &zeroBased, 16u); x = vqtbl1q_u8(t, x); memcpy(&out, &x, 16u);
#define KS_EXP_BYTE_SWIZZLE_BODY_32(CTYPE, LANES) \
    uint8x16x2_t t; memcpy(&t.val[0], &value, 16u); memcpy(&t.val[1], ((const uint8_t *)&value) + 16u, 16u); uint8x16_t lo, hi; memcpy(&lo, &zeroBased, 16u); memcpy(&hi, ((const uint8_t *)&zeroBased) + 16u, 16u); lo = vqtbl2q_u8(t, lo); hi = vqtbl2q_u8(t, hi); memcpy(&out, &lo, 16u); memcpy(((uint8_t *)&out) + 16u, &hi, 16u);
/* Two tables in one run of lanes is the two- and four-register forms of
 * the same instruction. */
#define KS_EXP_BYTE_SWIZZLE_PAIR_BODY_16(CTYPE, LANES) \
    uint8x16x2_t t; uint8x16_t x; memcpy(&t.val[0], &first, 16u); memcpy(&t.val[1], &second, 16u); memcpy(&x, &zeroBased, 16u); x = vqtbl2q_u8(t, x); memcpy(&out, &x, 16u);
#define KS_EXP_BYTE_SWIZZLE_PAIR_BODY_32(CTYPE, LANES) \
    uint8x16x4_t t; memcpy(&t.val[0], &first, 16u); memcpy(&t.val[1], ((const uint8_t *)&first) + 16u, 16u); memcpy(&t.val[2], &second, 16u); memcpy(&t.val[3], ((const uint8_t *)&second) + 16u, 16u); uint8x16_t lo, hi; memcpy(&lo, &zeroBased, 16u); memcpy(&hi, ((const uint8_t *)&zeroBased) + 16u, 16u); lo = vqtbl4q_u8(t, lo); hi = vqtbl4q_u8(t, hi); memcpy(&out, &lo, 16u); memcpy(((uint8_t *)&out) + 16u, &hi, 16u);
#elif defined(__SSSE3__)
#define KS_EXP_BYTE_SWIZZLE_BODY_16(CTYPE, LANES) \
    __m128i t, x, high, shuffled; memcpy(&t, &value, 16u); memcpy(&x, &zeroBased, 16u); high = _mm_and_si128(x, _mm_set1_epi8((char)0xf0)); shuffled = _mm_shuffle_epi8(t, x); shuffled = _mm_and_si128(shuffled, _mm_cmpeq_epi8(high, _mm_setzero_si128())); memcpy(&out, &shuffled, 16u);
#define KS_EXP_BYTE_SWIZZLE_BODY_32(CTYPE, LANES) KS_EXP_SWIZZLE_LOOP(CTYPE, LANES)
/* One shuffle per table, each kept only where the index was inside that
 * table: the high nibble is clear for the first sixteen, and clear again
 * once sixteen is taken off for the second. */
#define KS_EXP_BYTE_SWIZZLE_PAIR_BODY_16(CTYPE, LANES) \
    __m128i a, b, x, y, keepA, keepB; memcpy(&a, &first, 16u); memcpy(&b, &second, 16u); memcpy(&x, &zeroBased, 16u); y = _mm_sub_epi8(x, _mm_set1_epi8(16)); keepA = _mm_cmpeq_epi8(_mm_and_si128(x, _mm_set1_epi8((char)0xf0)), _mm_setzero_si128()); keepB = _mm_cmpeq_epi8(_mm_and_si128(y, _mm_set1_epi8((char)0xf0)), _mm_setzero_si128()); x = _mm_or_si128(_mm_and_si128(_mm_shuffle_epi8(a, x), keepA), _mm_and_si128(_mm_shuffle_epi8(b, y), keepB)); memcpy(&out, &x, 16u);
#define KS_EXP_BYTE_SWIZZLE_PAIR_BODY_32(CTYPE, LANES) KS_EXP_SWIZZLE_PAIR_LOOP(CTYPE, LANES)
#elif defined(__wasm_simd128__)
/* `i8x16.swizzle` is exactly this, zero for out of range. */
#define KS_EXP_BYTE_SWIZZLE_BODY_16(CTYPE, LANES) \
    typedef signed char KsSwizzle __attribute__((vector_size(16))); \
    KsSwizzle t, x, y; memcpy(&t, &value, 16u); memcpy(&x, &zeroBased, 16u); \
    y = __builtin_wasm_swizzle_i8x16(t, x); memcpy(&out, &y, 16u);
#define KS_EXP_BYTE_SWIZZLE_BODY_32(CTYPE, LANES) KS_EXP_SWIZZLE_LOOP(CTYPE, LANES)
/* Zero for out of range is what makes the two halves combine with an or:
 * an index past the first table is out of range there, and one inside it
 * wraps out of range once sixteen is taken off. */
#define KS_EXP_BYTE_SWIZZLE_PAIR_BODY_16(CTYPE, LANES) \
    typedef signed char KsSwizzle __attribute__((vector_size(16))); \
    KsSwizzle a, b, x, y; memcpy(&a, &first, 16u); memcpy(&b, &second, 16u); memcpy(&x, &zeroBased, 16u); \
    y = __builtin_wasm_swizzle_i8x16(a, x) | __builtin_wasm_swizzle_i8x16(b, x - 16); memcpy(&out, &y, 16u);
#define KS_EXP_BYTE_SWIZZLE_PAIR_BODY_32(CTYPE, LANES) KS_EXP_SWIZZLE_PAIR_LOOP(CTYPE, LANES)
#else
#define KS_EXP_BYTE_SWIZZLE_BODY_16(CTYPE, LANES) KS_EXP_SWIZZLE_LOOP(CTYPE, LANES)
#define KS_EXP_BYTE_SWIZZLE_BODY_32(CTYPE, LANES) KS_EXP_SWIZZLE_LOOP(CTYPE, LANES)
#define KS_EXP_BYTE_SWIZZLE_PAIR_BODY_16(CTYPE, LANES) KS_EXP_SWIZZLE_PAIR_LOOP(CTYPE, LANES)
#define KS_EXP_BYTE_SWIZZLE_PAIR_BODY_32(CTYPE, LANES) KS_EXP_SWIZZLE_PAIR_LOOP(CTYPE, LANES)
#endif
/* A 64-byte vector exists only under AVX-512F, whose byte shuffle needs
 * the BW extension that tier does not promise; the lanes are walked. Both
 * forms, for the one reason: a table instruction the tier does not have is
 * missing from the paired swizzle exactly as it is from the single one. */
#define KS_EXP_BYTE_SWIZZLE_BODY_64(CTYPE, LANES) KS_EXP_SWIZZLE_LOOP(CTYPE, LANES)
#define KS_EXP_BYTE_SWIZZLE_PAIR_BODY_64(CTYPE, LANES) KS_EXP_SWIZZLE_PAIR_LOOP(CTYPE, LANES)
#define KS_EXP_SWIZZLE_1(W, ELEM, CTYPE, LANES) \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_swizzle_##ELEM(ks_exp_##ELEM value, ks_exp_##ELEM indices) { \
    ks_exp_##ELEM out; ks_exp_##ELEM zeroBased KS_UNUSED = indices - 1; \
    KS_EXP_BYTE_SWIZZLE_BODY_##W(CTYPE, LANES) \
    return out; \
} \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_swizzle_pair_##ELEM(ks_exp_##ELEM first, ks_exp_##ELEM indices, ks_exp_##ELEM second) { \
    ks_exp_##ELEM out; ks_exp_##ELEM zeroBased KS_UNUSED = indices - 1; \
    KS_EXP_BYTE_SWIZZLE_PAIR_BODY_##W(CTYPE, LANES) \
    return out; \
}
#define KS_EXP_SWIZZLE_WIDE(W, ELEM, CTYPE, LANES) \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_swizzle_##ELEM(ks_exp_##ELEM value, ks_exp_##ELEM indices) { ks_exp_##ELEM out; KS_EXP_SWIZZLE_LOOP(CTYPE, LANES) return out; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_swizzle_pair_##ELEM(ks_exp_##ELEM first, ks_exp_##ELEM indices, ks_exp_##ELEM second) { ks_exp_##ELEM out; KS_EXP_SWIZZLE_PAIR_LOOP(CTYPE, LANES) return out; }
#define KS_EXP_SWIZZLE_2 KS_EXP_SWIZZLE_WIDE
#define KS_EXP_SWIZZLE_4 KS_EXP_SWIZZLE_WIDE
#define KS_EXP_SWIZZLE_8 KS_EXP_SWIZZLE_WIDE

/* The explicit vector of one element: the vector type, its mask, the
 * scalar oracle of both, and the lane operations the compiler calls by
 * name. ELEM is the full type suffix (f64x4), so it can be pasted
 * straight into names; W, LANES and BYTES arrive as literal tokens. */
#define KS_EXP_VECTOR(W, ELEM, CTYPE, MASK, LANES, BYTES) \
typedef CTYPE ks_exp_##ELEM __attribute__((vector_size(W) KS_VECTOR_ABI_ALIGN)); \
typedef MASK ks_exp_mask_##ELEM __attribute__((vector_size(W) KS_VECTOR_ABI_ALIGN)); \
typedef struct { CTYPE lane[LANES]; } ks_scalar_exp_##ELEM; \
typedef struct { MASK lane[LANES]; } ks_scalar_exp_mask_##ELEM; \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_splat_##ELEM(CTYPE value) { return (ks_exp_##ELEM){ KS_REP_##LANES(value) }; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_iota_##ELEM(CTYPE first, CTYPE step) { return (ks_exp_##ELEM){ KS_LANES_##LANES(KS_IOTA_LANE, CTYPE) }; } \
static inline __attribute__((unused)) ks_exp_mask_##ELEM ks_exp_tail_##ELEM(uint32_t active) { if (active > LANES##u) active = LANES##u; ks_exp_mask_##ELEM lane = (ks_exp_mask_##ELEM){ KS_LANES_##LANES(KS_CAST_LANE, MASK) }; ks_exp_mask_##ELEM limit = (ks_exp_mask_##ELEM){ KS_REP_##LANES((MASK)active) }; return (ks_exp_mask_##ELEM)(lane < limit); } \
static inline __attribute__((unused)) bool ks_exp_full_##ELEM(ks_exp_mask_##ELEM active) { ks_exp_mask_##ELEM inactive = (ks_exp_mask_##ELEM)(active == (ks_exp_mask_##ELEM){0}); uint64_t words[KS_WORDS_##W]; memcpy(words, &inactive, sizeof words); return (KS_WORDS_OR_##W) == 0u; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_load_part_##ELEM(const CTYPE *source, size_t room) { \
    KS_EXP_LOAD_PART_BODY(W, ELEM, CTYPE, LANES, BYTES) \
} \
static __attribute__((noinline, cold, unused)) void ks_exp_store_masked_part_##ELEM(CTYPE *destination, size_t room, const ks_exp_##ELEM *value, const ks_exp_mask_##ELEM *active) { CTYPE lanes[LANES##u] KS_LANE_ARRAY_ALIGN(CTYPE); memcpy(lanes, value, sizeof lanes); MASK keep[LANES##u] KS_LANE_ARRAY_ALIGN(MASK); memcpy(keep, active, sizeof keep); for (size_t i = 0u; i < room; ++i) if (keep[i]) destination[i] = lanes[i]; } \
static inline __attribute__((unused)) void ks_exp_store_part_##ELEM(CTYPE *destination, size_t room, ks_exp_##ELEM value, ks_exp_mask_##ELEM active) { \
    if (!ks_exp_full_##ELEM(active | ~ks_exp_tail_##ELEM((uint32_t)room))) { ks_exp_store_masked_part_##ELEM(destination, room, &value, &active); return; } \
    KS_EXP_STORE_PART_BODY(W, ELEM, CTYPE, LANES, BYTES) \
} \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_load_full_##ELEM(const CTYPE *source, size_t count, size_t first) { ks_exp_##ELEM out = (ks_exp_##ELEM){0}; if (first >= count) return out; size_t room = count - first; if (room >= LANES##u) { memcpy(&out, source + first, sizeof out); return out; } return ks_exp_load_part_##ELEM(source + first, room); } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_load_##ELEM(const CTYPE *source, size_t count, size_t first, ks_exp_mask_##ELEM active) { return (ks_exp_##ELEM)(active & (ks_exp_mask_##ELEM)ks_exp_load_full_##ELEM(source, count, first)); } \
static inline __attribute__((unused)) void ks_exp_store_full_##ELEM(CTYPE *destination, size_t count, size_t first, ks_exp_##ELEM value) { if (first >= count) return; size_t room = count - first; if (room >= LANES##u) { memcpy(destination + first, &value, sizeof value); return; } ks_exp_store_part_##ELEM(destination + first, room, value, ~(ks_exp_mask_##ELEM){0}); } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_load_at_##ELEM(const CTYPE *source) { ks_exp_##ELEM out; memcpy(&out, source, sizeof out); return out; } \
static inline __attribute__((unused)) void ks_exp_store_at_##ELEM(CTYPE *destination, ks_exp_##ELEM value) { memcpy(destination, &value, sizeof value); } \
static inline __attribute__((unused)) void ks_exp_store_##ELEM(CTYPE *destination, size_t count, size_t first, ks_exp_##ELEM value, ks_exp_mask_##ELEM active) { if (ks_exp_full_##ELEM(active)) { ks_exp_store_full_##ELEM(destination, count, first, value); return; } if (first >= count) return; size_t room = count - first; if (room > LANES##u) room = LANES##u; ks_exp_store_part_##ELEM(destination + first, room, value, active); } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_select_##ELEM(ks_exp_mask_##ELEM active, ks_exp_##ELEM yes, ks_exp_##ELEM no) { return (ks_exp_##ELEM)((active & (ks_exp_mask_##ELEM)yes) | (~active & (ks_exp_mask_##ELEM)no)); } \
static inline __attribute__((unused)) uint64_t ks_exp_bits_##ELEM(ks_exp_mask_##ELEM value) { \
    KS_EXP_BITS_BODY(W, ELEM, BYTES) \
} \
static inline __attribute__((unused)) bool ks_exp_any_##ELEM(ks_exp_mask_##ELEM value) { \
    KS_EXP_ANY_BODY(W, ELEM, BYTES) \
} \
static inline __attribute__((unused)) uint32_t ks_exp_first_##ELEM(ks_exp_mask_##ELEM value) { \
    return ks_exp_any_##ELEM(value) ? (uint32_t)__builtin_ctzll(ks_exp_bits_##ELEM(value)) + 1u : 0u; \
} \
static inline __attribute__((unused)) CTYPE ks_exp_extract_##ELEM(ks_exp_##ELEM value, double lane) { return value[(uint32_t)lane - 1u]; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_insert_##ELEM(ks_exp_##ELEM value, double lane, CTYPE replacement) { value[(uint32_t)lane - 1u] = replacement; return value; } \
KS_EXP_SWIZZLE_##BYTES(W, ELEM, CTYPE, LANES) \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_reverse_##ELEM(ks_exp_##ELEM value) { ks_exp_##ELEM out; for (uint32_t i = 0u; i < LANES##u; ++i) out[i] = value[LANES##u - 1u - i]; return out; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_rotate_left_##ELEM(ks_exp_##ELEM value, double count) { ks_exp_##ELEM out; uint32_t n = (uint32_t)count % LANES##u; for (uint32_t i = 0u; i < LANES##u; ++i) out[i] = value[(i + n) % LANES##u]; return out; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_rotate_right_##ELEM(ks_exp_##ELEM value, double count) { ks_exp_##ELEM out; uint32_t n = (uint32_t)count % LANES##u; for (uint32_t i = 0u; i < LANES##u; ++i) out[i] = value[(i + LANES##u - n) % LANES##u]; return out; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_align_##ELEM(ks_exp_##ELEM previous, ks_exp_##ELEM current, double count) { ks_exp_##ELEM out; uint32_t n = (uint32_t)count; if (n > LANES##u) n = LANES##u; for (uint32_t i = 0u; i < LANES##u; ++i) out[i] = i < n ? previous[LANES##u - n + i] : current[i - n]; return out; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_compress_##ELEM(ks_exp_##ELEM value, ks_exp_mask_##ELEM selected) { ks_exp_##ELEM out = (ks_exp_##ELEM){0}; uint32_t cursor = 0u; for (uint32_t i = 0u; i < LANES##u; ++i) if (selected[i]) out[cursor++] = value[i]; return out; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_expand_##ELEM(ks_exp_##ELEM value, ks_exp_mask_##ELEM selected) { ks_exp_##ELEM out = (ks_exp_##ELEM){0}; uint32_t cursor = 0u; for (uint32_t i = 0u; i < LANES##u; ++i) if (selected[i]) out[i] = value[cursor++]; return out; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_prefix_sum_ordered_##ELEM(ks_exp_##ELEM value) { for (uint32_t i = 1u; i < LANES##u; ++i) value[i] = value[i - 1u] + value[i]; return value; } \
static inline __attribute__((unused)) ks_exp_mask_##ELEM ks_exp_mask_splat_##ELEM(bool value) { return value ? ~(ks_exp_mask_##ELEM){0} : (ks_exp_mask_##ELEM){0}; } \
static inline __attribute__((unused)) ks_exp_mask_##ELEM ks_exp_mask_from_bits_##ELEM(uint64_t bits) { ks_exp_mask_##ELEM out = (ks_exp_mask_##ELEM){0}; for (uint32_t i = 0u; i < LANES##u; ++i) if ((bits >> i) & UINT64_C(1)) out[i] = (MASK)-1; return out; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_field_load_##ELEM(const void *base, size_t count, size_t first, size_t stride, size_t offset, ks_exp_mask_##ELEM active) { ks_exp_##ELEM out = (ks_exp_##ELEM){0}; if (first >= count) return out; for (uint32_t i = 0u; i < LANES##u; ++i) if (active[i] && i < count - first) { CTYPE lane; memcpy(&lane, (const char *)base + (first + i) * stride + offset, sizeof lane); out[i] = lane; } return out; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_field_load_at_##ELEM(const void *base, size_t stride, size_t offset) { ks_exp_##ELEM out; for (uint32_t i = 0u; i < LANES##u; ++i) { CTYPE lane; memcpy(&lane, (const char *)base + i * stride + offset, sizeof lane); out[i] = lane; } return out; } \
static inline __attribute__((unused)) void ks_exp_field_store_##ELEM(void *base, size_t count, size_t first, size_t stride, size_t offset, ks_exp_##ELEM value, ks_exp_mask_##ELEM active) { if (first >= count) return; for (uint32_t i = 0u; i < LANES##u; ++i) if (active[i] && i < count - first) { CTYPE lane = value[i]; memcpy((char *)base + (first + i) * stride + offset, &lane, sizeof lane); } } \
static inline __attribute__((unused)) void ks_exp_field_store_at_##ELEM(void *base, size_t stride, size_t offset, ks_exp_##ELEM value) { for (uint32_t i = 0u; i < LANES##u; ++i) { CTYPE lane = value[i]; memcpy((char *)base + i * stride + offset, &lane, sizeof lane); } }

/* The scalar oracle: the same operations one lane at a time. */
#define KS_EXP_SCALAR(ELEM, CTYPE, MASK, LANES) \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_splat_##ELEM(CTYPE value) { ks_scalar_exp_##ELEM out; for (uint32_t i = 0u; i < LANES##u; ++i) out.lane[i] = value; return out; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_iota_##ELEM(CTYPE first, CTYPE step) { ks_scalar_exp_##ELEM out; for (uint32_t i = 0u; i < LANES##u; ++i) out.lane[i] = first + (CTYPE)i * step; return out; } \
static inline __attribute__((unused)) ks_scalar_exp_mask_##ELEM ks_scalar_exp_tail_##ELEM(uint32_t active) { ks_scalar_exp_mask_##ELEM out; if (active > LANES##u) active = LANES##u; for (uint32_t i = 0u; i < LANES##u; ++i) out.lane[i] = i < active ? (MASK)-1 : 0; return out; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_load_##ELEM(const CTYPE *source, size_t count, size_t first, ks_scalar_exp_mask_##ELEM active) { ks_scalar_exp_##ELEM out = {{0}}; if (first >= count) return out; for (uint32_t i = 0u; i < LANES##u; ++i) if (active.lane[i] && i < count - first) out.lane[i] = source[first + i]; return out; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_load_full_##ELEM(const CTYPE *source, size_t count, size_t first) { return ks_scalar_exp_load_##ELEM(source, count, first, ks_scalar_exp_tail_##ELEM(LANES##u)); } \
static inline __attribute__((unused)) void ks_scalar_exp_store_##ELEM(CTYPE *destination, size_t count, size_t first, ks_scalar_exp_##ELEM value, ks_scalar_exp_mask_##ELEM active) { if (first >= count) return; for (uint32_t i = 0u; i < LANES##u; ++i) if (active.lane[i] && i < count - first) destination[first + i] = value.lane[i]; } \
static inline __attribute__((unused)) void ks_scalar_exp_store_full_##ELEM(CTYPE *destination, size_t count, size_t first, ks_scalar_exp_##ELEM value) { ks_scalar_exp_store_##ELEM(destination, count, first, value, ks_scalar_exp_tail_##ELEM(LANES##u)); } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_load_at_##ELEM(const CTYPE *source) { ks_scalar_exp_##ELEM out; for (uint32_t i = 0u; i < LANES##u; ++i) out.lane[i] = source[i]; return out; } \
static inline __attribute__((unused)) void ks_scalar_exp_store_at_##ELEM(CTYPE *destination, ks_scalar_exp_##ELEM value) { for (uint32_t i = 0u; i < LANES##u; ++i) destination[i] = value.lane[i]; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_select_##ELEM(ks_scalar_exp_mask_##ELEM active, ks_scalar_exp_##ELEM yes, ks_scalar_exp_##ELEM no) { for (uint32_t i = 0u; i < LANES##u; ++i) if (!active.lane[i]) yes.lane[i] = no.lane[i]; return yes; } \
static inline __attribute__((unused)) uint64_t ks_scalar_exp_bits_##ELEM(ks_scalar_exp_mask_##ELEM value) { uint64_t out = 0u; for (uint32_t i = 0u; i < LANES##u; ++i) if (value.lane[i]) out |= UINT64_C(1) << i; return out; } \
static inline __attribute__((unused)) bool ks_scalar_exp_any_##ELEM(ks_scalar_exp_mask_##ELEM value) { \
    return ks_scalar_exp_bits_##ELEM(value) != UINT64_C(0); \
} \
static inline __attribute__((unused)) uint32_t ks_scalar_exp_first_##ELEM(ks_scalar_exp_mask_##ELEM value) { \
    return ks_scalar_exp_any_##ELEM(value) ? (uint32_t)__builtin_ctzll(ks_scalar_exp_bits_##ELEM(value)) + 1u : 0u; \
} \
static inline __attribute__((unused)) CTYPE ks_scalar_exp_extract_##ELEM(ks_scalar_exp_##ELEM value, double lane) { return value.lane[(uint32_t)lane - 1u]; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_insert_##ELEM(ks_scalar_exp_##ELEM value, double lane, CTYPE replacement) { value.lane[(uint32_t)lane - 1u] = replacement; return value; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_swizzle_pair_##ELEM(ks_scalar_exp_##ELEM first, ks_scalar_exp_##ELEM indices, ks_scalar_exp_##ELEM second) { ks_scalar_exp_##ELEM out; for (uint32_t i = 0u; i < LANES##u; ++i) { uint32_t at = (uint32_t)indices.lane[i] - 1u; out.lane[i] = at < LANES##u ? first.lane[at] : (at - LANES##u) < LANES##u ? second.lane[at - LANES##u] : (CTYPE)0; } return out; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_swizzle_##ELEM(ks_scalar_exp_##ELEM value, ks_scalar_exp_##ELEM indices) { ks_scalar_exp_##ELEM out; for (uint32_t i = 0u; i < LANES##u; ++i) { uint32_t at = (uint32_t)indices.lane[i]; out.lane[i] = (at - 1u) < LANES##u ? value.lane[at - 1u] : (CTYPE)0; } return out; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_reverse_##ELEM(ks_scalar_exp_##ELEM value) { ks_scalar_exp_##ELEM out; for (uint32_t i = 0u; i < LANES##u; ++i) out.lane[i] = value.lane[LANES##u - 1u - i]; return out; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_rotate_left_##ELEM(ks_scalar_exp_##ELEM value, double count) { ks_scalar_exp_##ELEM out; uint32_t n = (uint32_t)count % LANES##u; for (uint32_t i = 0u; i < LANES##u; ++i) out.lane[i] = value.lane[(i + n) % LANES##u]; return out; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_rotate_right_##ELEM(ks_scalar_exp_##ELEM value, double count) { ks_scalar_exp_##ELEM out; uint32_t n = (uint32_t)count % LANES##u; for (uint32_t i = 0u; i < LANES##u; ++i) out.lane[i] = value.lane[(i + LANES##u - n) % LANES##u]; return out; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_align_##ELEM(ks_scalar_exp_##ELEM previous, ks_scalar_exp_##ELEM current, double count) { ks_scalar_exp_##ELEM out; uint32_t n = (uint32_t)count; if (n > LANES##u) n = LANES##u; for (uint32_t i = 0u; i < LANES##u; ++i) out.lane[i] = i < n ? previous.lane[LANES##u - n + i] : current.lane[i - n]; return out; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_compress_##ELEM(ks_scalar_exp_##ELEM value, ks_scalar_exp_mask_##ELEM selected) { ks_scalar_exp_##ELEM out = {{0}}; uint32_t cursor = 0u; for (uint32_t i = 0u; i < LANES##u; ++i) if (selected.lane[i]) out.lane[cursor++] = value.lane[i]; return out; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_expand_##ELEM(ks_scalar_exp_##ELEM value, ks_scalar_exp_mask_##ELEM selected) { ks_scalar_exp_##ELEM out = {{0}}; uint32_t cursor = 0u; for (uint32_t i = 0u; i < LANES##u; ++i) if (selected.lane[i]) out.lane[i] = value.lane[cursor++]; return out; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_prefix_sum_ordered_##ELEM(ks_scalar_exp_##ELEM value) { for (uint32_t i = 1u; i < LANES##u; ++i) value.lane[i] = value.lane[i - 1u] + value.lane[i]; return value; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_add_##ELEM(ks_scalar_exp_##ELEM left, ks_scalar_exp_##ELEM right) { for (uint32_t i = 0u; i < LANES##u; ++i) left.lane[i] = left.lane[i] + right.lane[i]; return left; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_sub_##ELEM(ks_scalar_exp_##ELEM left, ks_scalar_exp_##ELEM right) { for (uint32_t i = 0u; i < LANES##u; ++i) left.lane[i] = left.lane[i] - right.lane[i]; return left; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_mul_##ELEM(ks_scalar_exp_##ELEM left, ks_scalar_exp_##ELEM right) { for (uint32_t i = 0u; i < LANES##u; ++i) left.lane[i] = left.lane[i] * right.lane[i]; return left; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_div_##ELEM(ks_scalar_exp_##ELEM left, ks_scalar_exp_##ELEM right) { for (uint32_t i = 0u; i < LANES##u; ++i) left.lane[i] = left.lane[i] / right.lane[i]; return left; } \
static inline __attribute__((unused)) ks_scalar_exp_mask_##ELEM ks_scalar_exp_lt_##ELEM(ks_scalar_exp_##ELEM left, ks_scalar_exp_##ELEM right) { ks_scalar_exp_mask_##ELEM out; for (uint32_t i = 0u; i < LANES##u; ++i) out.lane[i] = left.lane[i] < right.lane[i] ? (MASK)-1 : 0; return out; } \
static inline __attribute__((unused)) ks_scalar_exp_mask_##ELEM ks_scalar_exp_le_##ELEM(ks_scalar_exp_##ELEM left, ks_scalar_exp_##ELEM right) { ks_scalar_exp_mask_##ELEM out; for (uint32_t i = 0u; i < LANES##u; ++i) out.lane[i] = left.lane[i] <= right.lane[i] ? (MASK)-1 : 0; return out; } \
static inline __attribute__((unused)) ks_scalar_exp_mask_##ELEM ks_scalar_exp_gt_##ELEM(ks_scalar_exp_##ELEM left, ks_scalar_exp_##ELEM right) { ks_scalar_exp_mask_##ELEM out; for (uint32_t i = 0u; i < LANES##u; ++i) out.lane[i] = left.lane[i] > right.lane[i] ? (MASK)-1 : 0; return out; } \
static inline __attribute__((unused)) ks_scalar_exp_mask_##ELEM ks_scalar_exp_ge_##ELEM(ks_scalar_exp_##ELEM left, ks_scalar_exp_##ELEM right) { ks_scalar_exp_mask_##ELEM out; for (uint32_t i = 0u; i < LANES##u; ++i) out.lane[i] = left.lane[i] >= right.lane[i] ? (MASK)-1 : 0; return out; } \
static inline __attribute__((unused)) ks_scalar_exp_mask_##ELEM ks_scalar_exp_eq_##ELEM(ks_scalar_exp_##ELEM left, ks_scalar_exp_##ELEM right) { ks_scalar_exp_mask_##ELEM out; for (uint32_t i = 0u; i < LANES##u; ++i) out.lane[i] = left.lane[i] == right.lane[i] ? (MASK)-1 : 0; return out; } \
static inline __attribute__((unused)) ks_scalar_exp_mask_##ELEM ks_scalar_exp_ne_##ELEM(ks_scalar_exp_##ELEM left, ks_scalar_exp_##ELEM right) { ks_scalar_exp_mask_##ELEM out; for (uint32_t i = 0u; i < LANES##u; ++i) out.lane[i] = left.lane[i] != right.lane[i] ? (MASK)-1 : 0; return out; } \
static inline __attribute__((unused)) ks_scalar_exp_mask_##ELEM ks_scalar_exp_mask_and_##ELEM(ks_scalar_exp_mask_##ELEM left, ks_scalar_exp_mask_##ELEM right) { for (uint32_t i = 0u; i < LANES##u; ++i) left.lane[i] = left.lane[i] & right.lane[i]; return left; } \
static inline __attribute__((unused)) ks_scalar_exp_mask_##ELEM ks_scalar_exp_mask_or_##ELEM(ks_scalar_exp_mask_##ELEM left, ks_scalar_exp_mask_##ELEM right) { for (uint32_t i = 0u; i < LANES##u; ++i) left.lane[i] = left.lane[i] | right.lane[i]; return left; } \
static inline __attribute__((unused)) ks_scalar_exp_mask_##ELEM ks_scalar_exp_mask_xor_##ELEM(ks_scalar_exp_mask_##ELEM left, ks_scalar_exp_mask_##ELEM right) { for (uint32_t i = 0u; i < LANES##u; ++i) left.lane[i] = left.lane[i] ^ right.lane[i]; return left; } \
static inline __attribute__((unused)) ks_scalar_exp_mask_##ELEM ks_scalar_exp_mask_eq_##ELEM(ks_scalar_exp_mask_##ELEM left, ks_scalar_exp_mask_##ELEM right) { ks_scalar_exp_mask_##ELEM out; for (uint32_t i = 0u; i < LANES##u; ++i) out.lane[i] = left.lane[i] == right.lane[i] ? (MASK)-1 : 0; return out; } \
static inline __attribute__((unused)) ks_scalar_exp_mask_##ELEM ks_scalar_exp_mask_ne_##ELEM(ks_scalar_exp_mask_##ELEM left, ks_scalar_exp_mask_##ELEM right) { ks_scalar_exp_mask_##ELEM out; for (uint32_t i = 0u; i < LANES##u; ++i) out.lane[i] = left.lane[i] != right.lane[i] ? (MASK)-1 : 0; return out; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_neg_##ELEM(ks_scalar_exp_##ELEM value) { for (uint32_t i = 0u; i < LANES##u; ++i) value.lane[i] = -value.lane[i]; return value; } \
static inline __attribute__((unused)) ks_scalar_exp_mask_##ELEM ks_scalar_exp_mask_not_##ELEM(ks_scalar_exp_mask_##ELEM value) { for (uint32_t i = 0u; i < LANES##u; ++i) value.lane[i] = ~value.lane[i]; return value; } \
static inline __attribute__((unused)) ks_scalar_exp_mask_##ELEM ks_scalar_exp_mask_splat_##ELEM(bool value) { ks_scalar_exp_mask_##ELEM out; for (uint32_t i = 0u; i < LANES##u; ++i) out.lane[i] = value ? (MASK)-1 : 0; return out; } \
static inline __attribute__((unused)) ks_scalar_exp_mask_##ELEM ks_scalar_exp_mask_from_bits_##ELEM(uint64_t bits) { ks_scalar_exp_mask_##ELEM out; for (uint32_t i = 0u; i < LANES##u; ++i) out.lane[i] = ((bits >> i) & UINT64_C(1)) ? (MASK)-1 : 0; return out; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_field_load_##ELEM(const void *base, size_t count, size_t first, size_t stride, size_t offset, ks_scalar_exp_mask_##ELEM active) { ks_scalar_exp_##ELEM out = {{0}}; if (first >= count) return out; for (uint32_t i = 0u; i < LANES##u; ++i) if (active.lane[i] && i < count - first) memcpy(&out.lane[i], (const char *)base + (first + i) * stride + offset, sizeof out.lane[i]); return out; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_field_load_at_##ELEM(const void *base, size_t stride, size_t offset) { ks_scalar_exp_##ELEM out; for (uint32_t i = 0u; i < LANES##u; ++i) memcpy(&out.lane[i], (const char *)base + i * stride + offset, sizeof out.lane[i]); return out; } \
static inline __attribute__((unused)) void ks_scalar_exp_field_store_##ELEM(void *base, size_t count, size_t first, size_t stride, size_t offset, ks_scalar_exp_##ELEM value, ks_scalar_exp_mask_##ELEM active) { if (first >= count) return; for (uint32_t i = 0u; i < LANES##u; ++i) if (active.lane[i] && i < count - first) memcpy((char *)base + (first + i) * stride + offset, &value.lane[i], sizeof value.lane[i]); } \
static inline __attribute__((unused)) void ks_scalar_exp_field_store_at_##ELEM(void *base, size_t stride, size_t offset, ks_scalar_exp_##ELEM value) { for (uint32_t i = 0u; i < LANES##u; ++i) memcpy((char *)base + i * stride + offset, &value.lane[i], sizeof value.lane[i]); }

/* Scalar executable semantics for physical-width integer vector shifts. */
static inline __attribute__((unused)) uint64_t ks_exp_shl_lane(uint64_t value, uint64_t count, uint32_t bits) { return value << (count & (bits - 1u)); }
static inline __attribute__((unused)) uint64_t ks_exp_shr_lane(uint64_t value, uint64_t count, uint32_t bits) { return (value & (UINT64_MAX >> (64u - bits))) >> (count & (bits - 1u)); }
static inline __attribute__((unused)) uint64_t ks_exp_sar_lane(uint64_t value, uint64_t count, uint32_t bits) { uint64_t sign = UINT64_C(1) << (bits - 1u); int64_t signed_value = (int64_t)(((value & (UINT64_MAX >> (64u - bits))) ^ sign) - sign); return (uint64_t)(signed_value >> (count & (bits - 1u))); }

/* What an integer element has that a float does not, over the oracle. */
#define KS_EXP_INT_SCALAR(ELEM, CTYPE, LANES) \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_prefix_xor_##ELEM(ks_scalar_exp_##ELEM value) { for (uint32_t i = 1u; i < LANES##u; ++i) value.lane[i] = value.lane[i - 1u] ^ value.lane[i]; return value; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_and_##ELEM(ks_scalar_exp_##ELEM left, ks_scalar_exp_##ELEM right) { for (uint32_t i = 0u; i < LANES##u; ++i) left.lane[i] = left.lane[i] & right.lane[i]; return left; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_or_##ELEM(ks_scalar_exp_##ELEM left, ks_scalar_exp_##ELEM right) { for (uint32_t i = 0u; i < LANES##u; ++i) left.lane[i] = left.lane[i] | right.lane[i]; return left; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_xor_##ELEM(ks_scalar_exp_##ELEM left, ks_scalar_exp_##ELEM right) { for (uint32_t i = 0u; i < LANES##u; ++i) left.lane[i] = left.lane[i] ^ right.lane[i]; return left; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_shl_##ELEM(ks_scalar_exp_##ELEM left, ks_scalar_exp_##ELEM right) { for (uint32_t i = 0u; i < LANES##u; ++i) left.lane[i] = (CTYPE)ks_exp_shl_lane((uint64_t)left.lane[i], (uint64_t)right.lane[i], sizeof(CTYPE) * 8u); return left; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_shr_##ELEM(ks_scalar_exp_##ELEM left, ks_scalar_exp_##ELEM right) { for (uint32_t i = 0u; i < LANES##u; ++i) left.lane[i] = (CTYPE)ks_exp_shr_lane((uint64_t)left.lane[i], (uint64_t)right.lane[i], sizeof(CTYPE) * 8u); return left; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_sar_##ELEM(ks_scalar_exp_##ELEM left, ks_scalar_exp_##ELEM right) { for (uint32_t i = 0u; i < LANES##u; ++i) left.lane[i] = (CTYPE)ks_exp_sar_lane((uint64_t)left.lane[i], (uint64_t)right.lane[i], sizeof(CTYPE) * 8u); return left; } \
static inline __attribute__((unused)) ks_scalar_exp_##ELEM ks_scalar_exp_not_##ELEM(ks_scalar_exp_##ELEM value) { for (uint32_t i = 0u; i < LANES##u; ++i) value.lane[i] = ~value.lane[i]; return value; }
#define KS_EXP_FLOAT_SCALAR(ELEM, CTYPE, LANES)

/* The same, over the vector. */
#define KS_EXP_INT_ONLY(ELEM, CTYPE, LANES) \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_prefix_xor_##ELEM(ks_exp_##ELEM value) { for (uint32_t i = 1u; i < LANES##u; ++i) value[i] = value[i - 1u] ^ value[i]; return value; } \
KS_EXP_INT_SCALAR(ELEM, CTYPE, LANES)
#define KS_EXP_FLOAT_ONLY(ELEM, CTYPE, LANES)

/* Horizontal reductions, emitted once over the vector (P = exp) and
 * once over the oracle (P = scalar_exp). VIA names how a lane is read
 * and written: VECTOR indexes a native vector, LANE the oracle's array,
 * and CHUNKED goes through the extract and insert helpers of a fixed
 * species spread over several native vectors, which is not an lvalue
 * per lane. The three summation orders are distinct contracts. */
#define KS_AT_VECTOR(ELEM, v, i) v[i]
#define KS_AT_LANE(ELEM, v, i) v.lane[i]
#define KS_AT_CHUNKED(ELEM, v, i) ks_exp_extract_##ELEM(v, (double)((i) + 1u))
#define KS_SET_VECTOR(ELEM, v, i, x) v[i] = x
#define KS_SET_LANE(ELEM, v, i, x) v.lane[i] = x
#define KS_SET_CHUNKED(ELEM, v, i, x) v = ks_exp_insert_##ELEM(v, (double)((i) + 1u), x)
#define KS_EXP_HORIZONTAL(P, ELEM, CTYPE, LANES, VIA) \
static inline __attribute__((unused)) CTYPE ks_##P##_horizontal_ordered_sum_##ELEM(ks_##P##_##ELEM left) { CTYPE out = (CTYPE)0; for (uint32_t i = 0u; i < LANES##u; ++i) out = out + KS_AT_##VIA(ELEM, left, i); return out; } \
static inline __attribute__((unused)) CTYPE ks_##P##_horizontal_pairwise_sum_##ELEM(ks_##P##_##ELEM left) { CTYPE partials[LANES]; for (uint32_t i = 0u; i < LANES##u; ++i) partials[i] = KS_AT_##VIA(ELEM, left, i); uint32_t n = LANES##u; while (n > 1u) { uint32_t out = 0u; uint32_t i = 0u; for (; i + 1u < n; i += 2u) partials[out++] = partials[i] + partials[i + 1u]; if (i < n) partials[out++] = partials[i]; n = out; } return partials[0]; } \
static inline __attribute__((unused)) CTYPE ks_##P##_horizontal_algebraic_sum_##ELEM(ks_##P##_##ELEM left) { CTYPE even = (CTYPE)0, odd = (CTYPE)0; uint32_t i = 0u; for (; i + 1u < LANES##u; i += 2u) { even = even + KS_AT_##VIA(ELEM, left, i); odd = odd + KS_AT_##VIA(ELEM, left, i + 1u); } if (i < LANES##u) even = even + KS_AT_##VIA(ELEM, left, i); return even + odd; } \
static inline __attribute__((unused)) CTYPE ks_##P##_horizontal_ordered_product_##ELEM(ks_##P##_##ELEM left) { CTYPE out = (CTYPE)1; for (uint32_t i = 0u; i < LANES##u; ++i) out = out * KS_AT_##VIA(ELEM, left, i); return out; } \
static inline __attribute__((unused)) CTYPE ks_##P##_horizontal_pairwise_product_##ELEM(ks_##P##_##ELEM left) { CTYPE partials[LANES]; for (uint32_t i = 0u; i < LANES##u; ++i) partials[i] = KS_AT_##VIA(ELEM, left, i); uint32_t n = LANES##u; while (n > 1u) { uint32_t out = 0u; uint32_t i = 0u; for (; i + 1u < n; i += 2u) partials[out++] = partials[i] * partials[i + 1u]; if (i < n) partials[out++] = partials[i]; n = out; } return partials[0]; } \
static inline __attribute__((unused)) CTYPE ks_##P##_horizontal_algebraic_product_##ELEM(ks_##P##_##ELEM left) { CTYPE even = (CTYPE)1, odd = (CTYPE)1; uint32_t i = 0u; for (; i + 1u < LANES##u; i += 2u) { even = even * KS_AT_##VIA(ELEM, left, i); odd = odd * KS_AT_##VIA(ELEM, left, i + 1u); } if (i < LANES##u) even = even * KS_AT_##VIA(ELEM, left, i); return even * odd; } \
static inline __attribute__((unused)) CTYPE ks_##P##_horizontal_ordered_dot_##ELEM(ks_##P##_##ELEM left, ks_##P##_##ELEM right) { CTYPE out = (CTYPE)0; for (uint32_t i = 0u; i < LANES##u; ++i) { CTYPE product = KS_AT_##VIA(ELEM, left, i) * KS_AT_##VIA(ELEM, right, i); out = out + product; } return out; } \
static inline __attribute__((unused)) CTYPE ks_##P##_horizontal_pairwise_dot_##ELEM(ks_##P##_##ELEM left, ks_##P##_##ELEM right) { CTYPE partials[LANES]; for (uint32_t i = 0u; i < LANES##u; ++i) partials[i] = KS_AT_##VIA(ELEM, left, i) * KS_AT_##VIA(ELEM, right, i); uint32_t n = LANES##u; while (n > 1u) { uint32_t out = 0u; uint32_t i = 0u; for (; i + 1u < n; i += 2u) partials[out++] = partials[i] + partials[i + 1u]; if (i < n) partials[out++] = partials[i]; n = out; } return partials[0]; }

/* Lane-wise and horizontal folds over a pair helper that holds the
 * NaN policy, so only the helper and the arg search differ by kind. */
#define KS_EXP_FOLD(P, ELEM, CTYPE, LANES, VIA, contract, which) \
static inline __attribute__((unused)) ks_##P##_##ELEM ks_##P##_##contract##_##which##_##ELEM(ks_##P##_##ELEM left, ks_##P##_##ELEM right) { ks_##P##_##ELEM out = left; for (uint32_t i = 0u; i < LANES##u; ++i) KS_SET_##VIA(ELEM, out, i, ks_##P##_##contract##_##which##2_##ELEM(KS_AT_##VIA(ELEM, left, i), KS_AT_##VIA(ELEM, right, i))); return out; } \
static inline __attribute__((unused)) CTYPE ks_##P##_horizontal_##contract##_##which##_##ELEM(ks_##P##_##ELEM left) { CTYPE out = KS_AT_##VIA(ELEM, left, 0u); for (uint32_t i = 1u; i < LANES##u; ++i) out = ks_##P##_##contract##_##which##2_##ELEM(out, KS_AT_##VIA(ELEM, left, i)); return out; }

/* Floats: the fused dot, a quiet NaN, and min/max that either propagate
 * a NaN or skip it, ordering -0 below +0 either way. */
#define KS_EXP_FMA_double fma
#define KS_EXP_FMA_float fmaf
#define KS_EXP_NAN_double uint64_t b = UINT64_C(0x7ff8000000000000);
#define KS_EXP_NAN_float uint32_t b = UINT32_C(0x7fc00000);
#define KS_EXP_EXTREMES_FLOAT(P, ELEM, CTYPE, LANES, VIA) \
static inline __attribute__((unused)) CTYPE ks_##P##_horizontal_algebraic_dot_##ELEM(ks_##P##_##ELEM left, ks_##P##_##ELEM right) { CTYPE even = (CTYPE)0, odd = (CTYPE)0; uint32_t i = 0u; for (; i + 1u < LANES##u; i += 2u) { even = KS_EXP_FMA_##CTYPE(KS_AT_##VIA(ELEM, left, i), KS_AT_##VIA(ELEM, right, i), even); odd = KS_EXP_FMA_##CTYPE(KS_AT_##VIA(ELEM, left, i + 1u), KS_AT_##VIA(ELEM, right, i + 1u), odd); } if (i < LANES##u) even = KS_EXP_FMA_##CTYPE(KS_AT_##VIA(ELEM, left, i), KS_AT_##VIA(ELEM, right, i), even); return even + odd; } \
static inline __attribute__((unused)) CTYPE ks_##P##_nan_##ELEM(void) { KS_EXP_NAN_##CTYPE CTYPE out; memcpy(&out, &b, sizeof out); return out; } \
static inline __attribute__((unused)) CTYPE ks_##P##_propagating_min2_##ELEM(CTYPE left, CTYPE right) { if (left != left || right != right) { return ks_##P##_nan_##ELEM(); } if (left == right) { return left != (CTYPE)0 ? left : (signbit(left) ? left : right); } return left < right ? left : right; } \
KS_EXP_FOLD(P, ELEM, CTYPE, LANES, VIA, propagating, min) \
static inline __attribute__((unused)) double ks_##P##_horizontal_propagating_arg_min_##ELEM(ks_##P##_##ELEM left) { uint32_t at = 0u; CTYPE best = KS_AT_##VIA(ELEM, left, 0u); for (uint32_t i = 1u; i < LANES##u; ++i) { CTYPE value = KS_AT_##VIA(ELEM, left, i); if (best == best) { if (value != value) { at = i; best = value; } else if (value < best || (value == best && signbit(value) != signbit(best) && signbit(value))) { at = i; best = value; } } } return (double)(at + 1u); } \
static inline __attribute__((unused)) CTYPE ks_##P##_number_min2_##ELEM(CTYPE left, CTYPE right) { if (left != left) { return right != right ? ks_##P##_nan_##ELEM() : right; } if (right != right) { return left; } if (left == right) { return left != (CTYPE)0 ? left : (signbit(left) ? left : right); } return left < right ? left : right; } \
KS_EXP_FOLD(P, ELEM, CTYPE, LANES, VIA, number, min) \
static inline __attribute__((unused)) double ks_##P##_horizontal_number_arg_min_##ELEM(ks_##P##_##ELEM left) { uint32_t at = 0u; CTYPE best = KS_AT_##VIA(ELEM, left, 0u); for (uint32_t i = 1u; i < LANES##u; ++i) { CTYPE value = KS_AT_##VIA(ELEM, left, i); if (value == value) { if (best != best) { at = i; best = value; } else if (value < best || (value == best && signbit(value) != signbit(best) && signbit(value))) { at = i; best = value; } } } return (double)(at + 1u); } \
static inline __attribute__((unused)) CTYPE ks_##P##_propagating_max2_##ELEM(CTYPE left, CTYPE right) { if (left != left || right != right) { return ks_##P##_nan_##ELEM(); } if (left == right) { return left != (CTYPE)0 ? left : (signbit(left) ? right : left); } return left > right ? left : right; } \
KS_EXP_FOLD(P, ELEM, CTYPE, LANES, VIA, propagating, max) \
static inline __attribute__((unused)) double ks_##P##_horizontal_propagating_arg_max_##ELEM(ks_##P##_##ELEM left) { uint32_t at = 0u; CTYPE best = KS_AT_##VIA(ELEM, left, 0u); for (uint32_t i = 1u; i < LANES##u; ++i) { CTYPE value = KS_AT_##VIA(ELEM, left, i); if (best == best) { if (value != value) { at = i; best = value; } else if (value > best || (value == best && signbit(value) != signbit(best) && signbit(best))) { at = i; best = value; } } } return (double)(at + 1u); } \
static inline __attribute__((unused)) CTYPE ks_##P##_number_max2_##ELEM(CTYPE left, CTYPE right) { if (left != left) { return right != right ? ks_##P##_nan_##ELEM() : right; } if (right != right) { return left; } if (left == right) { return left != (CTYPE)0 ? left : (signbit(left) ? right : left); } return left > right ? left : right; } \
KS_EXP_FOLD(P, ELEM, CTYPE, LANES, VIA, number, max) \
static inline __attribute__((unused)) double ks_##P##_horizontal_number_arg_max_##ELEM(ks_##P##_##ELEM left) { uint32_t at = 0u; CTYPE best = KS_AT_##VIA(ELEM, left, 0u); for (uint32_t i = 1u; i < LANES##u; ++i) { CTYPE value = KS_AT_##VIA(ELEM, left, i); if (value == value) { if (best != best) { at = i; best = value; } else if (value > best || (value == best && signbit(value) != signbit(best) && signbit(best))) { at = i; best = value; } } } return (double)(at + 1u); }

/* Integers have no NaN, so both contracts are the plain comparison. */
#define KS_EXP_INT_EXTREME(P, ELEM, CTYPE, LANES, VIA, contract, which, op) \
static inline __attribute__((unused)) CTYPE ks_##P##_##contract##_##which##2_##ELEM(CTYPE left, CTYPE right) { return left op right ? left : right; } \
KS_EXP_FOLD(P, ELEM, CTYPE, LANES, VIA, contract, which) \
static inline __attribute__((unused)) double ks_##P##_horizontal_##contract##_arg_##which##_##ELEM(ks_##P##_##ELEM left) { uint32_t at = 0u; CTYPE best = KS_AT_##VIA(ELEM, left, 0u); for (uint32_t i = 1u; i < LANES##u; ++i) { CTYPE value = KS_AT_##VIA(ELEM, left, i); if (value op best) { at = i; best = value; } } return (double)(at + 1u); }
#define KS_EXP_EXTREMES_INT(P, ELEM, CTYPE, LANES, VIA) \
KS_EXP_INT_EXTREME(P, ELEM, CTYPE, LANES, VIA, propagating, min, <) \
KS_EXP_INT_EXTREME(P, ELEM, CTYPE, LANES, VIA, number, min, <) \
KS_EXP_INT_EXTREME(P, ELEM, CTYPE, LANES, VIA, propagating, max, >) \
KS_EXP_INT_EXTREME(P, ELEM, CTYPE, LANES, VIA, number, max, >)

/* One element, KIND being FLOAT or INT. */
#define KS_EXP_ELEMENT(W, ELEM, CTYPE, MASK, LANES, BYTES, KIND) \
KS_EXP_VECTOR(W, ELEM, CTYPE, MASK, LANES, BYTES) \
KS_EXP_SCALAR(ELEM, CTYPE, MASK, LANES) \
KS_EXP_##KIND##_ONLY(ELEM, CTYPE, LANES) \
KS_EXP_HORIZONTAL(exp, ELEM, CTYPE, LANES, VECTOR) \
KS_EXP_EXTREMES_##KIND(exp, ELEM, CTYPE, LANES, VECTOR) \
KS_EXP_HORIZONTAL(scalar_exp, ELEM, CTYPE, LANES, LANE) \
KS_EXP_EXTREMES_##KIND(scalar_exp, ELEM, CTYPE, LANES, LANE)

/* ---- Fixed logical species ---------------------------------------- */

/* A fixed species whose lane count is not one native register's: ELEM
 * is its suffix (f32x3), NATIVE the preferred species of the same
 * element it is built from (f32x4), NLANES that species' lane count and
 * CHUNKS how many of them cover LANES. Lane i lives in chunk i / NLANES
 * at position i % NLANES, so the lanes of a partial last chunk past
 * LANES are never read: `bits` masks them off, and the whole-vector
 * loads and stores reach the last chunk under a tail mask. Keeping the
 * value an aggregate of native vectors is what makes `Fixed<N>`
 * target-neutral while still executing as vectors when N is smaller,
 * larger, or not a multiple of the register. The compiler instantiates
 * this after the width block, once per fixed species the program
 * mentions, so nothing here reads KS_SIMD_WIDTH. */
#define KS_EXP_FIXED_VECTOR(ELEM, CTYPE, MASK, LANES, NATIVE, NLANES, CHUNKS) \
typedef struct { ks_exp_##NATIVE chunk[CHUNKS]; } ks_exp_##ELEM; \
typedef struct { ks_exp_mask_##NATIVE chunk[CHUNKS]; } ks_exp_mask_##ELEM; \
typedef struct { CTYPE lane[LANES]; } ks_scalar_exp_##ELEM; \
typedef struct { MASK lane[LANES]; } ks_scalar_exp_mask_##ELEM; \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_splat_##ELEM(CTYPE value) { ks_exp_##ELEM out; for (uint32_t c = 0u; c < CHUNKS##u; ++c) out.chunk[c] = ks_exp_splat_##NATIVE(value); return out; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_iota_##ELEM(CTYPE first, CTYPE step) { ks_exp_##ELEM out; for (uint32_t c = 0u; c < CHUNKS##u; ++c) out.chunk[c] = ks_exp_iota_##NATIVE(first + (CTYPE)(c * NLANES##u) * step, step); return out; } \
static inline __attribute__((unused)) ks_exp_mask_##ELEM ks_exp_tail_##ELEM(uint32_t active) { ks_exp_mask_##ELEM out; if (active > LANES##u) active = LANES##u; for (uint32_t c = 0u; c < CHUNKS##u; ++c) { uint32_t base = c * NLANES##u; uint32_t remaining = active > base ? active - base : 0u; out.chunk[c] = ks_exp_tail_##NATIVE(remaining); } return out; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_load_##ELEM(const CTYPE *source, size_t count, size_t first, ks_exp_mask_##ELEM active) { ks_exp_##ELEM out; for (uint32_t c = 0u; c < CHUNKS##u; ++c) out.chunk[c] = ks_exp_load_##NATIVE(source, count, first >= count ? SIZE_MAX : first + (size_t)(c * NLANES##u), active.chunk[c]); return out; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_load_full_##ELEM(const CTYPE *source, size_t count, size_t first) { ks_exp_##ELEM out; for (uint32_t c = 0u; (c + 1u) * NLANES##u <= LANES##u; ++c) out.chunk[c] = ks_exp_load_full_##NATIVE(source, count, first >= count ? SIZE_MAX : first + (size_t)(c * NLANES##u)); if (LANES##u % NLANES##u != 0u) out.chunk[CHUNKS##u - 1u] = ks_exp_load_##NATIVE(source, count, first >= count ? SIZE_MAX : first + (size_t)(LANES##u / NLANES##u * NLANES##u), ks_exp_tail_##NATIVE(LANES##u % NLANES##u)); return out; } \
static inline __attribute__((unused)) void ks_exp_store_##ELEM(CTYPE *destination, size_t count, size_t first, ks_exp_##ELEM value, ks_exp_mask_##ELEM active) { for (uint32_t c = 0u; c < CHUNKS##u; ++c) ks_exp_store_##NATIVE(destination, count, first >= count ? SIZE_MAX : first + (size_t)(c * NLANES##u), value.chunk[c], active.chunk[c]); } \
static inline __attribute__((unused)) void ks_exp_store_full_##ELEM(CTYPE *destination, size_t count, size_t first, ks_exp_##ELEM value) { for (uint32_t c = 0u; (c + 1u) * NLANES##u <= LANES##u; ++c) ks_exp_store_full_##NATIVE(destination, count, first >= count ? SIZE_MAX : first + (size_t)(c * NLANES##u), value.chunk[c]); if (LANES##u % NLANES##u != 0u) ks_exp_store_##NATIVE(destination, count, first >= count ? SIZE_MAX : first + (size_t)(LANES##u / NLANES##u * NLANES##u), value.chunk[CHUNKS##u - 1u], ks_exp_tail_##NATIVE(LANES##u % NLANES##u)); } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_select_##ELEM(ks_exp_mask_##ELEM active, ks_exp_##ELEM yes, ks_exp_##ELEM no) { for (uint32_t c = 0u; c < CHUNKS##u; ++c) yes.chunk[c] = ks_exp_select_##NATIVE(active.chunk[c], yes.chunk[c], no.chunk[c]); return yes; } \
static inline __attribute__((unused)) uint64_t ks_exp_bits_##ELEM(ks_exp_mask_##ELEM value) { uint64_t out = 0u; for (uint32_t c = 0u; c < CHUNKS##u; ++c) out |= ks_exp_bits_##NATIVE(value.chunk[c]) << (c * NLANES##u); out &= UINT64_MAX >> (64u - LANES##u); return out; } \
static inline __attribute__((unused)) bool ks_exp_any_##ELEM(ks_exp_mask_##ELEM value) { \
    return ks_exp_bits_##ELEM(value) != UINT64_C(0); \
} \
static inline __attribute__((unused)) uint32_t ks_exp_first_##ELEM(ks_exp_mask_##ELEM value) { \
    return ks_exp_any_##ELEM(value) ? (uint32_t)__builtin_ctzll(ks_exp_bits_##ELEM(value)) + 1u : 0u; \
} \
static inline __attribute__((unused)) CTYPE ks_exp_extract_##ELEM(ks_exp_##ELEM value, double lane) { uint32_t index = (uint32_t)lane - 1u; return value.chunk[index / NLANES##u][index % NLANES##u]; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_insert_##ELEM(ks_exp_##ELEM value, double lane, CTYPE replacement) { uint32_t index = (uint32_t)lane - 1u; value.chunk[index / NLANES##u][index % NLANES##u] = replacement; return value; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_swizzle_pair_##ELEM(ks_exp_##ELEM first, ks_exp_##ELEM indices, ks_exp_##ELEM second) { ks_exp_##ELEM out = ks_exp_splat_##ELEM((CTYPE)0); for (uint32_t i = 0u; i < LANES##u; ++i) { uint32_t at = (uint32_t)ks_exp_extract_##ELEM(indices, (double)(i + 1u)) - 1u; CTYPE picked = (CTYPE)0; bool found = false; if (at < LANES##u) { picked = ks_exp_extract_##ELEM(first, (double)(at + 1u)); found = true; } else if ((at - LANES##u) < LANES##u) { picked = ks_exp_extract_##ELEM(second, (double)(at - LANES##u + 1u)); found = true; } if (found) { out = ks_exp_insert_##ELEM(out, (double)(i + 1u), picked); } } return out; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_swizzle_##ELEM(ks_exp_##ELEM value, ks_exp_##ELEM indices) { ks_exp_##ELEM out = ks_exp_splat_##ELEM((CTYPE)0); for (uint32_t i = 0u; i < LANES##u; ++i) { uint32_t at = (uint32_t)ks_exp_extract_##ELEM(indices, (double)(i + 1u)); if ((at - 1u) < LANES##u) out = ks_exp_insert_##ELEM(out, (double)(i + 1u), ks_exp_extract_##ELEM(value, (double)at)); } return out; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_reverse_##ELEM(ks_exp_##ELEM value) { ks_exp_##ELEM out = ks_exp_splat_##ELEM((CTYPE)0); for (uint32_t i = 0u; i < LANES##u; ++i) out = ks_exp_insert_##ELEM(out, (double)(i + 1u), ks_exp_extract_##ELEM(value, (double)(LANES##u - 1u - i + 1u))); return out; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_rotate_left_##ELEM(ks_exp_##ELEM value, double count) { ks_exp_##ELEM out = ks_exp_splat_##ELEM((CTYPE)0); uint32_t n = (uint32_t)count % LANES##u; for (uint32_t i = 0u; i < LANES##u; ++i) out = ks_exp_insert_##ELEM(out, (double)(i + 1u), ks_exp_extract_##ELEM(value, (double)((i + n) % LANES##u + 1u))); return out; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_rotate_right_##ELEM(ks_exp_##ELEM value, double count) { ks_exp_##ELEM out = ks_exp_splat_##ELEM((CTYPE)0); uint32_t n = (uint32_t)count % LANES##u; for (uint32_t i = 0u; i < LANES##u; ++i) out = ks_exp_insert_##ELEM(out, (double)(i + 1u), ks_exp_extract_##ELEM(value, (double)((i + LANES##u - n) % LANES##u + 1u))); return out; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_align_##ELEM(ks_exp_##ELEM previous, ks_exp_##ELEM current, double count) { ks_exp_##ELEM out = ks_exp_splat_##ELEM((CTYPE)0); uint32_t n = (uint32_t)count; if (n > LANES##u) n = LANES##u; for (uint32_t i = 0u; i < LANES##u; ++i) out = ks_exp_insert_##ELEM(out, (double)(i + 1u), i < n ? ks_exp_extract_##ELEM(previous, (double)(LANES##u - n + i + 1u)) : ks_exp_extract_##ELEM(current, (double)(i - n + 1u))); return out; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_compress_##ELEM(ks_exp_##ELEM value, ks_exp_mask_##ELEM selected) { ks_exp_##ELEM out = ks_exp_splat_##ELEM((CTYPE)0); uint64_t bits = ks_exp_bits_##ELEM(selected); uint32_t cursor = 0u; for (uint32_t i = 0u; i < LANES##u; ++i) if ((bits & (UINT64_C(1) << i)) != 0u) out = ks_exp_insert_##ELEM(out, (double)(cursor++ + 1u), ks_exp_extract_##ELEM(value, (double)(i + 1u))); return out; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_expand_##ELEM(ks_exp_##ELEM value, ks_exp_mask_##ELEM selected) { ks_exp_##ELEM out = ks_exp_splat_##ELEM((CTYPE)0); uint64_t bits = ks_exp_bits_##ELEM(selected); uint32_t cursor = 0u; for (uint32_t i = 0u; i < LANES##u; ++i) if ((bits & (UINT64_C(1) << i)) != 0u) out = ks_exp_insert_##ELEM(out, (double)(i + 1u), ks_exp_extract_##ELEM(value, (double)(cursor++ + 1u))); return out; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_prefix_sum_ordered_##ELEM(ks_exp_##ELEM value) { for (uint32_t i = 1u; i < LANES##u; ++i) value = ks_exp_insert_##ELEM(value, (double)(i + 1u), ks_exp_extract_##ELEM(value, (double)i) + ks_exp_extract_##ELEM(value, (double)(i + 1u))); return value; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_add_##ELEM(ks_exp_##ELEM left, ks_exp_##ELEM right) { for (uint32_t c = 0u; c < CHUNKS##u; ++c) left.chunk[c] = left.chunk[c] + right.chunk[c]; return left; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_sub_##ELEM(ks_exp_##ELEM left, ks_exp_##ELEM right) { for (uint32_t c = 0u; c < CHUNKS##u; ++c) left.chunk[c] = left.chunk[c] - right.chunk[c]; return left; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_mul_##ELEM(ks_exp_##ELEM left, ks_exp_##ELEM right) { for (uint32_t c = 0u; c < CHUNKS##u; ++c) left.chunk[c] = left.chunk[c] * right.chunk[c]; return left; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_div_##ELEM(ks_exp_##ELEM left, ks_exp_##ELEM right) { for (uint32_t c = 0u; c < CHUNKS##u; ++c) left.chunk[c] = left.chunk[c] / right.chunk[c]; return left; } \
static inline __attribute__((unused)) ks_exp_mask_##ELEM ks_exp_lt_##ELEM(ks_exp_##ELEM left, ks_exp_##ELEM right) { ks_exp_mask_##ELEM out; for (uint32_t c = 0u; c < CHUNKS##u; ++c) out.chunk[c] = left.chunk[c] < right.chunk[c]; return out; } \
static inline __attribute__((unused)) ks_exp_mask_##ELEM ks_exp_le_##ELEM(ks_exp_##ELEM left, ks_exp_##ELEM right) { ks_exp_mask_##ELEM out; for (uint32_t c = 0u; c < CHUNKS##u; ++c) out.chunk[c] = left.chunk[c] <= right.chunk[c]; return out; } \
static inline __attribute__((unused)) ks_exp_mask_##ELEM ks_exp_gt_##ELEM(ks_exp_##ELEM left, ks_exp_##ELEM right) { ks_exp_mask_##ELEM out; for (uint32_t c = 0u; c < CHUNKS##u; ++c) out.chunk[c] = left.chunk[c] > right.chunk[c]; return out; } \
static inline __attribute__((unused)) ks_exp_mask_##ELEM ks_exp_ge_##ELEM(ks_exp_##ELEM left, ks_exp_##ELEM right) { ks_exp_mask_##ELEM out; for (uint32_t c = 0u; c < CHUNKS##u; ++c) out.chunk[c] = left.chunk[c] >= right.chunk[c]; return out; } \
static inline __attribute__((unused)) ks_exp_mask_##ELEM ks_exp_eq_##ELEM(ks_exp_##ELEM left, ks_exp_##ELEM right) { ks_exp_mask_##ELEM out; for (uint32_t c = 0u; c < CHUNKS##u; ++c) out.chunk[c] = left.chunk[c] == right.chunk[c]; return out; } \
static inline __attribute__((unused)) ks_exp_mask_##ELEM ks_exp_ne_##ELEM(ks_exp_##ELEM left, ks_exp_##ELEM right) { ks_exp_mask_##ELEM out; for (uint32_t c = 0u; c < CHUNKS##u; ++c) out.chunk[c] = left.chunk[c] != right.chunk[c]; return out; } \
static inline __attribute__((unused)) ks_exp_mask_##ELEM ks_exp_mask_and_##ELEM(ks_exp_mask_##ELEM left, ks_exp_mask_##ELEM right) { for (uint32_t c = 0u; c < CHUNKS##u; ++c) left.chunk[c] = left.chunk[c] & right.chunk[c]; return left; } \
static inline __attribute__((unused)) ks_exp_mask_##ELEM ks_exp_mask_or_##ELEM(ks_exp_mask_##ELEM left, ks_exp_mask_##ELEM right) { for (uint32_t c = 0u; c < CHUNKS##u; ++c) left.chunk[c] = left.chunk[c] | right.chunk[c]; return left; } \
static inline __attribute__((unused)) ks_exp_mask_##ELEM ks_exp_mask_xor_##ELEM(ks_exp_mask_##ELEM left, ks_exp_mask_##ELEM right) { for (uint32_t c = 0u; c < CHUNKS##u; ++c) left.chunk[c] = left.chunk[c] ^ right.chunk[c]; return left; } \
static inline __attribute__((unused)) ks_exp_mask_##ELEM ks_exp_mask_eq_##ELEM(ks_exp_mask_##ELEM left, ks_exp_mask_##ELEM right) { for (uint32_t c = 0u; c < CHUNKS##u; ++c) left.chunk[c] = left.chunk[c] == right.chunk[c]; return left; } \
static inline __attribute__((unused)) ks_exp_mask_##ELEM ks_exp_mask_ne_##ELEM(ks_exp_mask_##ELEM left, ks_exp_mask_##ELEM right) { for (uint32_t c = 0u; c < CHUNKS##u; ++c) left.chunk[c] = left.chunk[c] != right.chunk[c]; return left; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_neg_##ELEM(ks_exp_##ELEM value) { for (uint32_t c = 0u; c < CHUNKS##u; ++c) value.chunk[c] = -value.chunk[c]; return value; } \
static inline __attribute__((unused)) ks_exp_mask_##ELEM ks_exp_mask_not_##ELEM(ks_exp_mask_##ELEM value) { for (uint32_t c = 0u; c < CHUNKS##u; ++c) value.chunk[c] = ~value.chunk[c]; return value; } \
static inline __attribute__((unused)) ks_exp_mask_##ELEM ks_exp_mask_splat_##ELEM(bool value) { ks_exp_mask_##ELEM out; for (uint32_t c = 0u; c < CHUNKS##u; ++c) out.chunk[c] = ks_exp_mask_splat_##NATIVE(value); return out; } \
static inline __attribute__((unused)) ks_exp_mask_##ELEM ks_exp_mask_from_bits_##ELEM(uint64_t bits) { ks_exp_mask_##ELEM out; bits &= UINT64_MAX >> (64u - LANES##u); for (uint32_t c = 0u; c < CHUNKS##u; ++c) out.chunk[c] = ks_exp_mask_from_bits_##NATIVE(bits >> (c * NLANES##u)); return out; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_field_load_##ELEM(const void *base, size_t count, size_t first, size_t stride, size_t offset, ks_exp_mask_##ELEM active) { ks_exp_##ELEM out = ks_exp_splat_##ELEM((CTYPE)0); if (first >= count) return out; uint64_t bits = ks_exp_bits_##ELEM(active); for (uint32_t i = 0u; i < LANES##u; ++i) if (((bits >> i) & UINT64_C(1)) && i < count - first) { CTYPE lane; memcpy(&lane, (const char *)base + (first + i) * stride + offset, sizeof lane); out = ks_exp_insert_##ELEM(out, (double)(i + 1u), lane); } return out; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_field_load_at_##ELEM(const void *base, size_t stride, size_t offset) { ks_exp_##ELEM out = ks_exp_splat_##ELEM((CTYPE)0); for (uint32_t i = 0u; i < LANES##u; ++i) { CTYPE lane; memcpy(&lane, (const char *)base + i * stride + offset, sizeof lane); out = ks_exp_insert_##ELEM(out, (double)(i + 1u), lane); } return out; } \
static inline __attribute__((unused)) void ks_exp_field_store_##ELEM(void *base, size_t count, size_t first, size_t stride, size_t offset, ks_exp_##ELEM value, ks_exp_mask_##ELEM active) { if (first >= count) return; uint64_t bits = ks_exp_bits_##ELEM(active); for (uint32_t i = 0u; i < LANES##u; ++i) if (((bits >> i) & UINT64_C(1)) && i < count - first) { CTYPE lane = ks_exp_extract_##ELEM(value, (double)(i + 1u)); memcpy((char *)base + (first + i) * stride + offset, &lane, sizeof lane); } } \
static inline __attribute__((unused)) void ks_exp_field_store_at_##ELEM(void *base, size_t stride, size_t offset, ks_exp_##ELEM value) { for (uint32_t i = 0u; i < LANES##u; ++i) { CTYPE lane = ks_exp_extract_##ELEM(value, (double)(i + 1u)); memcpy((char *)base + i * stride + offset, &lane, sizeof lane); } }

#define KS_UNSIGNED_int8_t uint8_t
#define KS_SIGNED_int8_t int8_t
#define KS_UNSIGNED_uint8_t uint8_t
#define KS_SIGNED_uint8_t int8_t
#define KS_UNSIGNED_int16_t uint16_t
#define KS_SIGNED_int16_t int16_t
#define KS_UNSIGNED_uint16_t uint16_t
#define KS_SIGNED_uint16_t int16_t
#define KS_UNSIGNED_int32_t uint32_t
#define KS_SIGNED_int32_t int32_t
#define KS_UNSIGNED_uint32_t uint32_t
#define KS_SIGNED_uint32_t int32_t
#define KS_UNSIGNED_int64_t uint64_t
#define KS_SIGNED_int64_t int64_t
#define KS_UNSIGNED_uint64_t uint64_t
#define KS_SIGNED_uint64_t int64_t

/* What an integer fixed species has that a float one does not. */
#define KS_EXP_FIXED_INT(ELEM, CTYPE, LANES, CHUNKS) \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_prefix_xor_##ELEM(ks_exp_##ELEM value) { for (uint32_t i = 1u; i < LANES##u; ++i) value = ks_exp_insert_##ELEM(value, (double)(i + 1u), ks_exp_extract_##ELEM(value, (double)i) ^ ks_exp_extract_##ELEM(value, (double)(i + 1u))); return value; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_and_##ELEM(ks_exp_##ELEM left, ks_exp_##ELEM right) { for (uint32_t c = 0u; c < CHUNKS##u; ++c) left.chunk[c] = left.chunk[c] & right.chunk[c]; return left; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_or_##ELEM(ks_exp_##ELEM left, ks_exp_##ELEM right) { for (uint32_t c = 0u; c < CHUNKS##u; ++c) left.chunk[c] = left.chunk[c] | right.chunk[c]; return left; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_xor_##ELEM(ks_exp_##ELEM left, ks_exp_##ELEM right) { for (uint32_t c = 0u; c < CHUNKS##u; ++c) left.chunk[c] = left.chunk[c] ^ right.chunk[c]; return left; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_shl_##ELEM(ks_exp_##ELEM left, ks_exp_##ELEM right) { typedef KS_UNSIGNED_##CTYPE shifted_chunk __attribute__((vector_size(sizeof(left.chunk[0])))); typedef KS_UNSIGNED_##CTYPE count_chunk __attribute__((vector_size(sizeof(left.chunk[0])))); for (uint32_t c = 0u; c < CHUNKS##u; ++c) left.chunk[c] = (__typeof__(left.chunk[c]))(((shifted_chunk)left.chunk[c]) << (((count_chunk)right.chunk[c]) & (sizeof(CTYPE) * 8u - 1u))); return left; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_shr_##ELEM(ks_exp_##ELEM left, ks_exp_##ELEM right) { typedef KS_UNSIGNED_##CTYPE shifted_chunk __attribute__((vector_size(sizeof(left.chunk[0])))); typedef KS_UNSIGNED_##CTYPE count_chunk __attribute__((vector_size(sizeof(left.chunk[0])))); for (uint32_t c = 0u; c < CHUNKS##u; ++c) left.chunk[c] = (__typeof__(left.chunk[c]))(((shifted_chunk)left.chunk[c]) >> (((count_chunk)right.chunk[c]) & (sizeof(CTYPE) * 8u - 1u))); return left; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_sar_##ELEM(ks_exp_##ELEM left, ks_exp_##ELEM right) { typedef KS_SIGNED_##CTYPE shifted_chunk __attribute__((vector_size(sizeof(left.chunk[0])))); typedef KS_UNSIGNED_##CTYPE count_chunk __attribute__((vector_size(sizeof(left.chunk[0])))); for (uint32_t c = 0u; c < CHUNKS##u; ++c) left.chunk[c] = (__typeof__(left.chunk[c]))(((shifted_chunk)left.chunk[c]) >> (((count_chunk)right.chunk[c]) & (sizeof(CTYPE) * 8u - 1u))); return left; } \
static inline __attribute__((unused)) ks_exp_##ELEM ks_exp_not_##ELEM(ks_exp_##ELEM value) { for (uint32_t c = 0u; c < CHUNKS##u; ++c) value.chunk[c] = ~value.chunk[c]; return value; }
#define KS_EXP_FIXED_FLOAT(ELEM, CTYPE, LANES, CHUNKS)

/* One fixed species, KIND being FLOAT or INT: the composite vector, the
 * oracle it shares with a native species, and both sets of horizontals. */
#define KS_EXP_FIXED(ELEM, CTYPE, MASK, LANES, NATIVE, NLANES, CHUNKS, KIND) \
KS_EXP_FIXED_VECTOR(ELEM, CTYPE, MASK, LANES, NATIVE, NLANES, CHUNKS) \
KS_EXP_FIXED_##KIND(ELEM, CTYPE, LANES, CHUNKS) \
KS_EXP_SCALAR(ELEM, CTYPE, MASK, LANES) \
KS_EXP_##KIND##_SCALAR(ELEM, CTYPE, LANES) \
KS_EXP_HORIZONTAL(exp, ELEM, CTYPE, LANES, CHUNKED) \
KS_EXP_EXTREMES_##KIND(exp, ELEM, CTYPE, LANES, CHUNKED) \
KS_EXP_HORIZONTAL(scalar_exp, ELEM, CTYPE, LANES, LANE) \
KS_EXP_EXTREMES_##KIND(scalar_exp, ELEM, CTYPE, LANES, LANE)

#endif /* KS_SIMD_H */

/* ---- This width --------------------------------------------------- */

#if KS_SIMD_WIDTH == 16
KS_EXP_ELEMENT(16, f64x2, double, int64_t, 2, 8, FLOAT)
KS_EXP_ELEMENT(16, f32x4, float, int32_t, 4, 4, FLOAT)
KS_EXP_ELEMENT(16, i8x16, int8_t, int8_t, 16, 1, INT)
KS_EXP_ELEMENT(16, u8x16, uint8_t, int8_t, 16, 1, INT)
KS_EXP_ELEMENT(16, i16x8, int16_t, int16_t, 8, 2, INT)
KS_EXP_ELEMENT(16, u16x8, uint16_t, int16_t, 8, 2, INT)
KS_EXP_ELEMENT(16, i32x4, int32_t, int32_t, 4, 4, INT)
KS_EXP_ELEMENT(16, u32x4, uint32_t, int32_t, 4, 4, INT)
KS_EXP_ELEMENT(16, i64x2, int64_t, int64_t, 2, 8, INT)
KS_EXP_ELEMENT(16, u64x2, uint64_t, int64_t, 2, 8, INT)
#elif KS_SIMD_WIDTH == 32
KS_EXP_ELEMENT(32, f64x4, double, int64_t, 4, 8, FLOAT)
KS_EXP_ELEMENT(32, f32x8, float, int32_t, 8, 4, FLOAT)
KS_EXP_ELEMENT(32, i8x32, int8_t, int8_t, 32, 1, INT)
KS_EXP_ELEMENT(32, u8x32, uint8_t, int8_t, 32, 1, INT)
KS_EXP_ELEMENT(32, i16x16, int16_t, int16_t, 16, 2, INT)
KS_EXP_ELEMENT(32, u16x16, uint16_t, int16_t, 16, 2, INT)
KS_EXP_ELEMENT(32, i32x8, int32_t, int32_t, 8, 4, INT)
KS_EXP_ELEMENT(32, u32x8, uint32_t, int32_t, 8, 4, INT)
KS_EXP_ELEMENT(32, i64x4, int64_t, int64_t, 4, 8, INT)
KS_EXP_ELEMENT(32, u64x4, uint64_t, int64_t, 4, 8, INT)
#elif KS_SIMD_WIDTH == 64
/* The 64-byte width is only ever selected for the AVX-512F tier and the
 * copy is compiled with that tier's flags, so a `zmm` register class is
 * always there for these. */
KS_EXP_ELEMENT(64, f64x8, double, int64_t, 8, 8, FLOAT)
KS_EXP_ELEMENT(64, f32x16, float, int32_t, 16, 4, FLOAT)
KS_EXP_ELEMENT(64, i8x64, int8_t, int8_t, 64, 1, INT)
KS_EXP_ELEMENT(64, u8x64, uint8_t, int8_t, 64, 1, INT)
KS_EXP_ELEMENT(64, i16x32, int16_t, int16_t, 32, 2, INT)
KS_EXP_ELEMENT(64, u16x32, uint16_t, int16_t, 32, 2, INT)
KS_EXP_ELEMENT(64, i32x16, int32_t, int32_t, 16, 4, INT)
KS_EXP_ELEMENT(64, u32x16, uint32_t, int32_t, 16, 4, INT)
KS_EXP_ELEMENT(64, i64x8, int64_t, int64_t, 8, 8, INT)
KS_EXP_ELEMENT(64, u64x8, uint64_t, int64_t, 8, 8, INT)
#else
#error "KS_SIMD_WIDTH must be 16, 32 or 64"
#endif
