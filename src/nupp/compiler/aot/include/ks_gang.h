/* The gang vector types, and the mask, splat and select helpers a vectorised
 * loop body is written against.
 *
 * Appended verbatim after ks_prelude.h when any function in the file chose a
 * gang. A gang is a 32-bit or 64-bit element at two, four or eight lanes, and
 * every combination the lane lowering can choose is defined here whichever one a
 * file picked: a typedef costs nothing and a static inline helper nobody calls is
 * never compiled, so a vector wider than this target's register class raises no
 * -Wpsabi -- that warning is about a call, and no body calls into a gang it did
 * not choose. That holds the helpers to one rule: none of them may call another,
 * because GCC weighs a call for inlining before it drops the caller as unused,
 * and weighing it computes the callee's vector ABI. Defining them all once is
 * also what keeps two gangs that share a vector, as the eight-lane pair does,
 * from each defining it.
 *
 * A mask is one all-ones or all-zeros integer per lane, as wide as the values it
 * selects between, so a gang carrying elements at two widths has a mask at each
 * and a comparison yields the one as wide as what it compared. */
#define KS_GANG_CAT_(a, b) a##b
#define KS_GANG_CAT(a, b) KS_GANG_CAT_(a, b)
#define KS_GANG_REP2(v) v, v
#define KS_GANG_REP4(v) v, v, v, v
#define KS_GANG_REP8(v) v, v, v, v, v, v, v, v
#define KS_GANG_REP(lanes, v) KS_GANG_CAT(KS_GANG_REP, lanes)(v)

/* Whether any lane of a mask is set. AArch64 has no move-mask instruction, so a
 * mask is read back as 16-byte chunks and each is reduced by its maximum. */
#if defined(__aarch64__)
#define KS_GANG_MAX16 vmaxvq_u32(chunks[0])
#define KS_GANG_MAX32 vmaxvq_u32(chunks[0]) | vmaxvq_u32(chunks[1])
#define KS_GANG_MAX64 vmaxvq_u32(chunks[0]) | vmaxvq_u32(chunks[1]) | vmaxvq_u32(chunks[2]) | vmaxvq_u32(chunks[3])
#define KS_GANG_ANY(mask, bytes, lanes) \
    static inline __attribute__((unused)) bool ks_any_##mask(ks_##mask m) { \
        uint32x4_t chunks[sizeof(m) / sizeof(uint32x4_t)]; \
        memcpy(chunks, &m, sizeof(m)); \
        return (KS_GANG_CAT(KS_GANG_MAX, bytes)) != 0; \
    }
#else
#define KS_GANG_OR2 m[0] | m[1]
#define KS_GANG_OR4 m[0] | m[1] | m[2] | m[3]
#define KS_GANG_OR8 m[0] | m[1] | m[2] | m[3] | m[4] | m[5] | m[6] | m[7]
#define KS_GANG_ANY(mask, bytes, lanes) \
    static inline __attribute__((unused)) bool ks_any_##mask(ks_##mask m) { \
        return (KS_GANG_CAT(KS_GANG_OR, lanes)) != 0; \
    }
#endif

/* The mask helpers: every lane set, a scalar condition widened to the gang, and
 * whether any lane is set. */
#define KS_GANG_MASK(bits, bytes, lanes) \
    static inline __attribute__((unused)) ks_m##bits##x##lanes ks_mask_all_m##bits##x##lanes(void) { return (ks_m##bits##x##lanes){KS_GANG_REP(lanes, -1)}; } \
    static inline __attribute__((unused)) ks_m##bits##x##lanes ks_bool_mask_m##bits##x##lanes(bool v) { return v ? (ks_m##bits##x##lanes){KS_GANG_REP(lanes, -1)} : (ks_m##bits##x##lanes){KS_GANG_REP(lanes, 0)}; } \
    KS_GANG_ANY(m##bits##x##lanes, bytes, lanes)

/* A splat and a select for one value-carrying vector.
 *
 * A select blends through the mask's own integer lanes, so the mask has to be
 * as wide as what it selects between. A branchless select is what makes an
 * inactive lane keep its old value instead of computing a new one, so it must
 * not be an arithmetic idiom: multiplying by zero turns an escaped lane's
 * infinity into a NaN and destroys it. */
#define KS_GANG_VALUE(elem, ctype, bits, lanes) \
    static inline __attribute__((unused)) ks_##elem##x##lanes ks_splat_##elem##x##lanes(ctype v) { return (ks_##elem##x##lanes){KS_GANG_REP(lanes, v)}; } \
    static inline __attribute__((unused)) ks_##elem##x##lanes ks_sel_##elem##x##lanes(ks_m##bits##x##lanes m, ks_##elem##x##lanes a, ks_##elem##x##lanes b) { return (ks_##elem##x##lanes)((m & (ks_m##bits##x##lanes)a) | (~m & (ks_m##bits##x##lanes)b)); }

/* One gang width: the masks and vectors at `lanes` lanes, 32-bit elements in
 * `bytes32` bytes and 64-bit ones in twice that. */
#define KS_GANG(lanes, bytes32, bytes64) \
    typedef int ks_m32x##lanes __attribute__((vector_size(bytes32))); \
    typedef long long ks_m64x##lanes __attribute__((vector_size(bytes64))); \
    typedef float ks_f32x##lanes __attribute__((vector_size(bytes32))); \
    typedef int32_t ks_i32x##lanes __attribute__((vector_size(bytes32))); \
    typedef uint32_t ks_u32x##lanes __attribute__((vector_size(bytes32))); \
    typedef double ks_f64x##lanes __attribute__((vector_size(bytes64))); \
    typedef int64_t ks_i64x##lanes __attribute__((vector_size(bytes64))); \
    typedef uint64_t ks_u64x##lanes __attribute__((vector_size(bytes64))); \
    KS_GANG_MASK(64, bytes64, lanes) \
    KS_GANG_VALUE(f32, float, 32, lanes) \
    KS_GANG_VALUE(i32, int32_t, 32, lanes) \
    KS_GANG_VALUE(u32, uint32_t, 32, lanes) \
    KS_GANG_VALUE(f64, double, 64, lanes) \
    KS_GANG_VALUE(i64, int64_t, 64, lanes) \
    KS_GANG_VALUE(u64, uint64_t, 64, lanes)

KS_GANG(2, 8, 16)
KS_GANG(4, 16, 32)
KS_GANG(8, 32, 64)

/* The 32-bit masks a gang runs its algebra at. The two-lane one is 8 bytes,
 * which is under any register class here, so no gang runs at it and it has
 * only the typedef above for the two-lane binary32 select. */
KS_GANG_MASK(32, 16, 4)
KS_GANG_MASK(32, 32, 8)
