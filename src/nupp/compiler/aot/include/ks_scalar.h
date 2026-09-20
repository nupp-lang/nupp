/* The scalar helpers generated bodies call, and the reducer states.
 *
 * Appended verbatim after ks_prelude.h. The binary32 corrections are here rather
 * than left to the C library, because `nupp.math.f32` defines a canonical quiet
 * NaN and defines `min` and `max` to propagate NaN, where `fminf` and `fmaxf`
 * return the operand that is not NaN. It also orders the two zeros, where the C
 * library leaves which one a `+0` and `-0` pair answers unspecified -- and GCC
 * and Clang answer differently. An AOT build must not change bits that `toBits`
 * can read back. */
static inline __attribute__((unused)) uint32_t nupp_u32(double value) { return (uint32_t)value; }
static inline __attribute__((unused)) uint32_t nupp_u32_div(uint32_t left, uint32_t right) { return right == 0u ? 0u : left / right; }
static inline __attribute__((unused)) uint32_t nupp_u32_mod(uint32_t left, uint32_t right) { return right == 0u ? 0u : left % right; }
/* Lua's `%` is floored: the remainder takes the divisor's sign, so -1 % 3 is 2
 * where fmod, which truncates toward zero, says -1. */
static inline __attribute__((unused)) double nupp_mod(double a, double b) { double r = fmod(a, b); if ((r < 0) != (b < 0) && r != 0) { r += b; } return r; }
static inline __attribute__((unused)) uint32_t nupp_u32_ctz(uint32_t value) { return value == 0u ? 32u : (uint32_t)__builtin_ctz(value); }
static inline __attribute__((unused)) uint32_t nupp_u32_clz(uint32_t value) { return value == 0u ? 32u : (uint32_t)__builtin_clz(value); }
static inline __attribute__((unused)) uint32_t nupp_u64_ctz(uint64_t value) { return value == UINT64_C(0) ? 64u : (uint32_t)__builtin_ctzll(value); }
static inline __attribute__((unused)) uint32_t nupp_u64_clz(uint64_t value) { return value == UINT64_C(0) ? 64u : (uint32_t)__builtin_clzll(value); }
static inline __attribute__((unused)) uint32_t nupp_u32_i32(int32_t value) { return (uint32_t)value; }
static inline __attribute__((unused)) uint32_t nupp_u32_u32(uint32_t value) { return value; }
#define nupp_u32(value) _Generic((value), int32_t: nupp_u32_i32, uint32_t: nupp_u32_u32, default: nupp_u32)(value)

/* `wrap` is modular by definition and a C cast is not: converting a double
 * outside the destination's range is undefined, and on arm64 it saturates,
 * so a compiled body would disagree with the same source on the interpreter
 * for every value at or above 2^31. This is LuaJIT's own reduction rather
 * than an equivalent of it -- adding 2^52 + 2^51 puts the answer's low
 * thirty-two bits where an integer read of the mantissa finds them, rounding
 * to nearest-even and reducing modulo 2^32 in one step -- so the two agree at
 * the edges as well as in the middle. */
static inline __attribute__((unused)) uint32_t nupp_wrap_u32(double value) {
    union { double number; uint64_t bits; } convert;
    convert.number = value + 6755399441055744.0;
    return (uint32_t)convert.bits;
}
static inline __attribute__((unused)) int32_t nupp_wrap_i32(double value) { return (int32_t)nupp_wrap_u32(value); }

/* A one-based span offset as the zero-based index a vector load starts at.
 * Anything a span cannot hold -- zero, a negative, a fraction, a value past
 * what size_t counts -- answers SIZE_MAX, which every load and store reads as
 * out of range, so the vector helpers make one comparison against the count
 * rather than sixteen. */
static inline __attribute__((unused)) size_t nupp_first_u64(uint64_t offset) {
#if SIZE_MAX < UINT64_MAX
    if (offset - UINT64_C(1) > (uint64_t)SIZE_MAX) { return SIZE_MAX; }
#endif
    return offset >= UINT64_C(1) ? (size_t)(offset - UINT64_C(1)) : SIZE_MAX;
}
static inline __attribute__((unused)) size_t nupp_first_i64(int64_t offset) {
    return offset >= INT64_C(1) ? nupp_first_u64((uint64_t)offset) : SIZE_MAX;
}
static inline __attribute__((unused)) size_t nupp_first_f64(double offset) {
    if (!(offset >= 1.0) || offset != floor(offset) || !(offset - 1.0 < (double)SIZE_MAX)) { return SIZE_MAX; }
    return (size_t)(offset - 1.0);
}

static inline __attribute__((unused)) int32_t nupp_arshift(uint32_t value, uint32_t shift) {
    if (shift == 0u) { return (int32_t)value; }
    uint32_t shifted = value >> shift;
    if ((value & UINT32_C(0x80000000)) != 0u) { shifted |= ~(UINT32_MAX >> shift); }
    return (int32_t)shifted;
}

static inline __attribute__((unused)) float nupp_f32_nan(void) {
    uint32_t bits = UINT32_C(0x7fc00000);
    float out;
    memcpy(&out, &bits, 4);
    return out;
}
static inline __attribute__((unused)) uint32_t nupp_f32_bits(float value) {
    uint32_t bits;
    memcpy(&bits, &value, 4);
    return bits;
}
static inline __attribute__((unused)) float nupp_f16_to_f32(uint32_t input) {
    uint32_t bits = input & UINT32_C(0xffff);
    uint32_t sign = (bits & UINT32_C(0x8000)) << 16u;
    uint32_t exponent = (bits >> 10u) & UINT32_C(0x1f);
    uint32_t mantissa = bits & UINT32_C(0x03ff);
    uint32_t outBits;
    if (exponent == UINT32_C(0x1f)) {
        outBits = mantissa == 0u ? sign | UINT32_C(0x7f800000) : UINT32_C(0x7fc00000);
    } else if (exponent == 0u) {
        if (mantissa == 0u) { outBits = sign; }
        else {
            int32_t unbiased = -14;
            while (mantissa < UINT32_C(0x0400)) { mantissa <<= 1u; unbiased -= 1; }
            mantissa &= UINT32_C(0x03ff);
            outBits = sign | ((uint32_t)(unbiased + 127) << 23u) | (mantissa << 13u);
        }
    } else {
        outBits = sign | ((exponent + 112u) << 23u) | (mantissa << 13u);
    }
    float out; memcpy(&out, &outBits, 4); return out;
}
static inline __attribute__((unused)) uint32_t nupp_f32_to_f16(float value) {
    uint32_t bits = nupp_f32_bits(value);
    uint32_t sign = (bits >> 16u) & UINT32_C(0x8000);
    uint32_t magnitude = bits & UINT32_C(0x7fffffff);
    if (magnitude >= UINT32_C(0x7f800000)) {
        return magnitude == UINT32_C(0x7f800000) ? sign | UINT32_C(0x7c00) : UINT32_C(0x7e00);
    }
    if (magnitude >= UINT32_C(0x477ff000)) { return sign | UINT32_C(0x7c00); }
    if (magnitude < UINT32_C(0x33000000)) { return sign; }
    uint32_t exponent = magnitude >> 23u;
    uint32_t mantissa = magnitude & UINT32_C(0x7fffff);
    if (exponent >= 113u) {
        uint32_t out = sign | ((exponent - 112u) << 10u) | (mantissa >> 13u);
        uint32_t remainder = mantissa & UINT32_C(0x1fff);
        return out + (remainder > UINT32_C(0x1000) || (remainder == UINT32_C(0x1000) && (out & 1u)) ? 1u : 0u);
    }
    uint32_t significant = mantissa | UINT32_C(0x800000);
    uint32_t shift = 126u - exponent;
    uint32_t out = significant >> shift;
    uint32_t mask = (UINT32_C(1) << shift) - 1u;
    uint32_t remainder = significant & mask;
    uint32_t halfway = UINT32_C(1) << (shift - 1u);
    return sign | (out + (remainder > halfway || (remainder == halfway && (out & 1u)) ? 1u : 0u));
}
static inline __attribute__((unused)) float nupp_bf16_to_f32(uint32_t input) {
    uint32_t bits = (input & UINT32_C(0xffff)) << 16u;
    if ((bits & UINT32_C(0x7fffffff)) > UINT32_C(0x7f800000)) bits = UINT32_C(0x7fc00000);
    float out; memcpy(&out, &bits, sizeof(out)); return out;
}
static inline __attribute__((unused)) uint32_t nupp_f32_to_bf16(float value) {
    uint32_t bits = nupp_f32_bits(value);
    if ((bits & UINT32_C(0x7fffffff)) > UINT32_C(0x7f800000)) return UINT32_C(0x7fc0);
    uint32_t upper = bits >> 16u;
    return (bits + UINT32_C(0x7fff) + (upper & 1u)) >> 16u;
}
/* `-0.0f == 0.0f`, so an equal pair is where the two zeros have to be
 * told apart by their sign bit. Returning one of the operands rather
 * than a literal keeps this independent of how the compiler folds a
 * signed zero. */
static inline __attribute__((unused)) float nupp_f32_min(float left, float right) {
    if (left != left || right != right) { return nupp_f32_nan(); }
    if (left == right) {
        /* -0 is the smaller zero, so answer it when either side is one. */
        if (left != 0.0f) { return left; }
        return (nupp_f32_bits(left) & UINT32_C(0x80000000)) != 0u ? left : right;
    }
    return left < right ? left : right;
}
static inline __attribute__((unused)) float nupp_f32_max(float left, float right) {
    if (left != left || right != right) { return nupp_f32_nan(); }
    if (left == right) {
        /* And +0 the larger, so a pair answers -0 only when both are. */
        if (left != 0.0f) { return left; }
        return (nupp_f32_bits(left) & UINT32_C(0x80000000)) == 0u ? left : right;
    }
    return left > right ? left : right;
}
static inline __attribute__((unused)) float nupp_f32_fma(float a, float b, float c) {
    float out = fmaf(a, b, c);
    return out == out ? out : nupp_f32_nan();
}
static inline __attribute__((unused)) float nupp_f32_exp(float value) {
    float x = nupp_f32_max(-104.0f, nupp_f32_min(value, 88.0f));
    float y = x * 0.0078125f;
    float out = 0.0000000020876757f;
    out = nupp_f32_fma(out, y, 0.000000025052108f);
    out = nupp_f32_fma(out, y, 0.00000027557319f);
    out = nupp_f32_fma(out, y, 0.0000027557319f);
    out = nupp_f32_fma(out, y, 0.000024801587f);
    out = nupp_f32_fma(out, y, 0.0001984127f);
    out = nupp_f32_fma(out, y, 0.0013888889f);
    out = nupp_f32_fma(out, y, 0.0083333333f);
    out = nupp_f32_fma(out, y, 0.041666667f);
    out = nupp_f32_fma(out, y, 0.16666667f);
    out = nupp_f32_fma(out, y, 0.5f);
    out = nupp_f32_fma(out, y, 1.0f);
    out = nupp_f32_fma(out, y, 1.0f);
    out *= out; out *= out; out *= out; out *= out;
    out *= out; out *= out; out *= out;
    return out;
}

typedef struct { double partial[64]; uint64_t count; } KsPairwiseF64;
static inline __attribute__((unused)) void ks_pairwise_f64_add(KsPairwiseF64 *state, double value) {
    uint64_t occupied = state->count; uint32_t level = 0u;
    while ((occupied & UINT64_C(1)) != 0u) { value = state->partial[level] + value; occupied >>= 1u; ++level; }
    state->partial[level] = value; ++state->count;
}
static inline __attribute__((unused)) KsPairwiseF64 ks_pairwise_f64_init(double initial) {
    KsPairwiseF64 out = {{0}, 0u}; ks_pairwise_f64_add(&out, initial); return out;
}
static inline __attribute__((unused)) double ks_pairwise_f64_value(KsPairwiseF64 state) {
    double result = 0.0; bool have = false;
    for (uint32_t level = 0u; level < 64u; ++level) if (((state.count >> level) & UINT64_C(1)) != 0u) {
        result = have ? state.partial[level] + result : state.partial[level]; have = true;
    }
    return result;
}
static inline __attribute__((unused)) void ks_pairwise_f64_product_add(KsPairwiseF64 *state, double value) {
    uint64_t occupied = state->count; uint32_t level = 0u;
    while ((occupied & UINT64_C(1)) != 0u) { value = state->partial[level] * value; occupied >>= 1u; ++level; }
    state->partial[level] = value; ++state->count;
}
static inline __attribute__((unused)) KsPairwiseF64 ks_pairwise_f64_product_init(double initial) {
    KsPairwiseF64 out = {{0}, 0u}; ks_pairwise_f64_product_add(&out, initial); return out;
}
static inline __attribute__((unused)) double ks_pairwise_f64_product_value(KsPairwiseF64 state) {
    double result = 1.0; bool have = false;
    for (uint32_t level = 0u; level < 64u; ++level) if (((state.count >> level) & UINT64_C(1)) != 0u) {
        result = have ? state.partial[level] * result : state.partial[level]; have = true;
    }
    return result;
}

/* Neumaier's compensated sum: `compensation` carries the part of every
 * addition that did not fit in `total`, and compensating the larger
 * operand as well as the smaller is what makes a large value added to a
 * small running total keep its correction. Compensated is not exact --
 * the answer still depends on the order the lanes arrived in, which is
 * why the contract keeps its contribution edges serial. */
typedef struct { double total; double compensation; } KsCompensatedF64;
static inline __attribute__((unused)) void ks_compensated_f64_add(KsCompensatedF64 *state, double value) {
    double sum = state->total + value;
    double total = state->total;
    if ((total < 0.0 ? -total : total) >= (value < 0.0 ? -value : value)) {
        state->compensation += (total - sum) + value;
    } else {
        state->compensation += (value - sum) + total;
    }
    state->total = sum;
}
static inline __attribute__((unused)) KsCompensatedF64 ks_compensated_f64_init(double initial) {
    KsCompensatedF64 out = {initial, 0.0}; return out;
}
static inline __attribute__((unused)) double ks_compensated_f64_value(KsCompensatedF64 state) {
    return state.total + state.compensation;
}

/* GCC can combine sin/cos into Darwin cexp, whose imaginary -0 is +0.
 * Preserve the authored odd-function zero before that library rewrite. */
static inline __attribute__((unused)) double nupp_sin(double value) {
    return value == 0.0 ? value : sin(value);
}
/* Stock Lua 5.1 retains the first operand on ties and unordered comparisons.
 * LuaJIT's min/max instructions select the second; keep both target contracts. */
static inline __attribute__((unused)) double nupp_min2_lua51(double left, double right) {
    return right < left ? right : left;
}
static inline __attribute__((unused)) double nupp_max2_lua51(double left, double right) {
    return right > left ? right : left;
}

static inline __attribute__((unused)) double nupp_min2(double left, double right) {
    return left < right ? left : right;
}
static inline __attribute__((unused)) double nupp_max2(double left, double right) {
    return left > right ? left : right;
}

static inline __attribute__((unused)) int32_t ks_reduce_i32_bits(uint32_t bits) { int32_t out; memcpy(&out, &bits, sizeof out); return out; }
static inline __attribute__((unused)) int64_t ks_reduce_i64_bits(uint64_t bits) { int64_t out; memcpy(&out, &bits, sizeof out); return out; }
typedef struct { int32_t total; uint64_t count; uint64_t position; } KsReduce_i32;
typedef struct { uint32_t total; uint64_t count; uint64_t position; } KsReduce_u32;
typedef struct { int64_t total; uint64_t count; uint64_t position; } KsReduce_i64;
typedef struct { uint64_t total; uint64_t count; uint64_t position; } KsReduce_u64;
typedef struct { bool total; uint64_t count; uint64_t position; } KsReduce_bool;
typedef struct { double total; uint64_t count; uint64_t position; } KsReduce_f64;
static inline __attribute__((unused)) double ks_reduce_nan(void) { uint64_t bits = UINT64_C(0x7ff8000000000000); double result; memcpy(&result, &bits, sizeof result); return result; }
static inline __attribute__((unused)) KsReduce_i32 ks_reduce_exact_sum_i32_init(int32_t initial) { KsReduce_i32 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_sum_i32_add(KsReduce_i32 *state, int32_t value) {
    uint32_t bits = (uint32_t)state->total + (uint32_t)value; memcpy(&state->total, &bits, sizeof bits);
}
static inline __attribute__((unused)) int32_t ks_reduce_exact_sum_i32_value(KsReduce_i32 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_i32 ks_reduce_exact_product_i32_init(int32_t initial) { KsReduce_i32 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_product_i32_add(KsReduce_i32 *state, int32_t value) {
    uint32_t bits = (uint32_t)state->total * (uint32_t)value; memcpy(&state->total, &bits, sizeof bits);
}
static inline __attribute__((unused)) int32_t ks_reduce_exact_product_i32_value(KsReduce_i32 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_i32 ks_reduce_exact_and_i32_init(int32_t initial) { KsReduce_i32 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_and_i32_add(KsReduce_i32 *state, int32_t value) {
    uint32_t bits = (uint32_t)state->total & (uint32_t)value; memcpy(&state->total, &bits, sizeof bits);
}
static inline __attribute__((unused)) int32_t ks_reduce_exact_and_i32_value(KsReduce_i32 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_i32 ks_reduce_exact_or_i32_init(int32_t initial) { KsReduce_i32 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_or_i32_add(KsReduce_i32 *state, int32_t value) {
    uint32_t bits = (uint32_t)state->total | (uint32_t)value; memcpy(&state->total, &bits, sizeof bits);
}
static inline __attribute__((unused)) int32_t ks_reduce_exact_or_i32_value(KsReduce_i32 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_i32 ks_reduce_exact_xor_i32_init(int32_t initial) { KsReduce_i32 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_xor_i32_add(KsReduce_i32 *state, int32_t value) {
    uint32_t bits = (uint32_t)state->total ^ (uint32_t)value; memcpy(&state->total, &bits, sizeof bits);
}
static inline __attribute__((unused)) int32_t ks_reduce_exact_xor_i32_value(KsReduce_i32 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_i32 ks_reduce_integer_min_i32_init(int32_t initial) { KsReduce_i32 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_integer_min_i32_add(KsReduce_i32 *state, int32_t value) {
    if (value < state->total) { state->total = value; }
}
static inline __attribute__((unused)) int32_t ks_reduce_integer_min_i32_value(KsReduce_i32 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_i32 ks_reduce_integer_max_i32_init(int32_t initial) { KsReduce_i32 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_integer_max_i32_add(KsReduce_i32 *state, int32_t value) {
    if (value > state->total) { state->total = value; }
}
static inline __attribute__((unused)) int32_t ks_reduce_integer_max_i32_value(KsReduce_i32 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_i32 ks_reduce_integer_argmin_i32_init(int32_t initial) { KsReduce_i32 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_integer_argmin_i32_add(KsReduce_i32 *state, int32_t value) {
    ++state->count;
    if (state->position == 0 || value < state->total) { state->total = value; state->position = state->count; }
}
static inline __attribute__((unused)) double ks_reduce_integer_argmin_i32_value(KsReduce_i32 state) { return (double)state.position; }
static inline __attribute__((unused)) KsReduce_i32 ks_reduce_integer_argmax_i32_init(int32_t initial) { KsReduce_i32 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_integer_argmax_i32_add(KsReduce_i32 *state, int32_t value) {
    ++state->count;
    if (state->position == 0 || value > state->total) { state->total = value; state->position = state->count; }
}
static inline __attribute__((unused)) double ks_reduce_integer_argmax_i32_value(KsReduce_i32 state) { return (double)state.position; }
static inline __attribute__((unused)) KsReduce_u32 ks_reduce_exact_sum_u32_init(uint32_t initial) { KsReduce_u32 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_sum_u32_add(KsReduce_u32 *state, uint32_t value) {
    uint32_t bits = (uint32_t)state->total + (uint32_t)value; memcpy(&state->total, &bits, sizeof bits);
}
static inline __attribute__((unused)) uint32_t ks_reduce_exact_sum_u32_value(KsReduce_u32 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_u32 ks_reduce_exact_product_u32_init(uint32_t initial) { KsReduce_u32 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_product_u32_add(KsReduce_u32 *state, uint32_t value) {
    uint32_t bits = (uint32_t)state->total * (uint32_t)value; memcpy(&state->total, &bits, sizeof bits);
}
static inline __attribute__((unused)) uint32_t ks_reduce_exact_product_u32_value(KsReduce_u32 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_u32 ks_reduce_exact_and_u32_init(uint32_t initial) { KsReduce_u32 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_and_u32_add(KsReduce_u32 *state, uint32_t value) {
    uint32_t bits = (uint32_t)state->total & (uint32_t)value; memcpy(&state->total, &bits, sizeof bits);
}
static inline __attribute__((unused)) uint32_t ks_reduce_exact_and_u32_value(KsReduce_u32 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_u32 ks_reduce_exact_or_u32_init(uint32_t initial) { KsReduce_u32 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_or_u32_add(KsReduce_u32 *state, uint32_t value) {
    uint32_t bits = (uint32_t)state->total | (uint32_t)value; memcpy(&state->total, &bits, sizeof bits);
}
static inline __attribute__((unused)) uint32_t ks_reduce_exact_or_u32_value(KsReduce_u32 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_u32 ks_reduce_exact_xor_u32_init(uint32_t initial) { KsReduce_u32 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_xor_u32_add(KsReduce_u32 *state, uint32_t value) {
    uint32_t bits = (uint32_t)state->total ^ (uint32_t)value; memcpy(&state->total, &bits, sizeof bits);
}
static inline __attribute__((unused)) uint32_t ks_reduce_exact_xor_u32_value(KsReduce_u32 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_u32 ks_reduce_integer_min_u32_init(uint32_t initial) { KsReduce_u32 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_integer_min_u32_add(KsReduce_u32 *state, uint32_t value) {
    if (value < state->total) { state->total = value; }
}
static inline __attribute__((unused)) uint32_t ks_reduce_integer_min_u32_value(KsReduce_u32 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_u32 ks_reduce_integer_max_u32_init(uint32_t initial) { KsReduce_u32 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_integer_max_u32_add(KsReduce_u32 *state, uint32_t value) {
    if (value > state->total) { state->total = value; }
}
static inline __attribute__((unused)) uint32_t ks_reduce_integer_max_u32_value(KsReduce_u32 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_u32 ks_reduce_integer_argmin_u32_init(uint32_t initial) { KsReduce_u32 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_integer_argmin_u32_add(KsReduce_u32 *state, uint32_t value) {
    ++state->count;
    if (state->position == 0 || value < state->total) { state->total = value; state->position = state->count; }
}
static inline __attribute__((unused)) double ks_reduce_integer_argmin_u32_value(KsReduce_u32 state) { return (double)state.position; }
static inline __attribute__((unused)) KsReduce_u32 ks_reduce_integer_argmax_u32_init(uint32_t initial) { KsReduce_u32 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_integer_argmax_u32_add(KsReduce_u32 *state, uint32_t value) {
    ++state->count;
    if (state->position == 0 || value > state->total) { state->total = value; state->position = state->count; }
}
static inline __attribute__((unused)) double ks_reduce_integer_argmax_u32_value(KsReduce_u32 state) { return (double)state.position; }
static inline __attribute__((unused)) KsReduce_i64 ks_reduce_exact_sum_i64_init(int64_t initial) { KsReduce_i64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_sum_i64_add(KsReduce_i64 *state, int64_t value) {
    uint64_t bits = (uint64_t)state->total + (uint64_t)value; memcpy(&state->total, &bits, sizeof bits);
}
static inline __attribute__((unused)) int64_t ks_reduce_exact_sum_i64_value(KsReduce_i64 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_i64 ks_reduce_exact_product_i64_init(int64_t initial) { KsReduce_i64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_product_i64_add(KsReduce_i64 *state, int64_t value) {
    uint64_t bits = (uint64_t)state->total * (uint64_t)value; memcpy(&state->total, &bits, sizeof bits);
}
static inline __attribute__((unused)) int64_t ks_reduce_exact_product_i64_value(KsReduce_i64 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_i64 ks_reduce_exact_and_i64_init(int64_t initial) { KsReduce_i64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_and_i64_add(KsReduce_i64 *state, int64_t value) {
    uint64_t bits = (uint64_t)state->total & (uint64_t)value; memcpy(&state->total, &bits, sizeof bits);
}
static inline __attribute__((unused)) int64_t ks_reduce_exact_and_i64_value(KsReduce_i64 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_i64 ks_reduce_exact_or_i64_init(int64_t initial) { KsReduce_i64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_or_i64_add(KsReduce_i64 *state, int64_t value) {
    uint64_t bits = (uint64_t)state->total | (uint64_t)value; memcpy(&state->total, &bits, sizeof bits);
}
static inline __attribute__((unused)) int64_t ks_reduce_exact_or_i64_value(KsReduce_i64 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_i64 ks_reduce_exact_xor_i64_init(int64_t initial) { KsReduce_i64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_xor_i64_add(KsReduce_i64 *state, int64_t value) {
    uint64_t bits = (uint64_t)state->total ^ (uint64_t)value; memcpy(&state->total, &bits, sizeof bits);
}
static inline __attribute__((unused)) int64_t ks_reduce_exact_xor_i64_value(KsReduce_i64 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_i64 ks_reduce_integer_min_i64_init(int64_t initial) { KsReduce_i64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_integer_min_i64_add(KsReduce_i64 *state, int64_t value) {
    if (value < state->total) { state->total = value; }
}
static inline __attribute__((unused)) int64_t ks_reduce_integer_min_i64_value(KsReduce_i64 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_i64 ks_reduce_integer_max_i64_init(int64_t initial) { KsReduce_i64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_integer_max_i64_add(KsReduce_i64 *state, int64_t value) {
    if (value > state->total) { state->total = value; }
}
static inline __attribute__((unused)) int64_t ks_reduce_integer_max_i64_value(KsReduce_i64 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_i64 ks_reduce_integer_argmin_i64_init(int64_t initial) { KsReduce_i64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_integer_argmin_i64_add(KsReduce_i64 *state, int64_t value) {
    ++state->count;
    if (state->position == 0 || value < state->total) { state->total = value; state->position = state->count; }
}
static inline __attribute__((unused)) double ks_reduce_integer_argmin_i64_value(KsReduce_i64 state) { return (double)state.position; }
static inline __attribute__((unused)) KsReduce_i64 ks_reduce_integer_argmax_i64_init(int64_t initial) { KsReduce_i64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_integer_argmax_i64_add(KsReduce_i64 *state, int64_t value) {
    ++state->count;
    if (state->position == 0 || value > state->total) { state->total = value; state->position = state->count; }
}
static inline __attribute__((unused)) double ks_reduce_integer_argmax_i64_value(KsReduce_i64 state) { return (double)state.position; }
static inline __attribute__((unused)) KsReduce_u64 ks_reduce_exact_sum_u64_init(uint64_t initial) { KsReduce_u64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_sum_u64_add(KsReduce_u64 *state, uint64_t value) {
    uint64_t bits = (uint64_t)state->total + (uint64_t)value; memcpy(&state->total, &bits, sizeof bits);
}
static inline __attribute__((unused)) uint64_t ks_reduce_exact_sum_u64_value(KsReduce_u64 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_u64 ks_reduce_exact_product_u64_init(uint64_t initial) { KsReduce_u64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_product_u64_add(KsReduce_u64 *state, uint64_t value) {
    uint64_t bits = (uint64_t)state->total * (uint64_t)value; memcpy(&state->total, &bits, sizeof bits);
}
static inline __attribute__((unused)) uint64_t ks_reduce_exact_product_u64_value(KsReduce_u64 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_u64 ks_reduce_exact_and_u64_init(uint64_t initial) { KsReduce_u64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_and_u64_add(KsReduce_u64 *state, uint64_t value) {
    uint64_t bits = (uint64_t)state->total & (uint64_t)value; memcpy(&state->total, &bits, sizeof bits);
}
static inline __attribute__((unused)) uint64_t ks_reduce_exact_and_u64_value(KsReduce_u64 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_u64 ks_reduce_exact_or_u64_init(uint64_t initial) { KsReduce_u64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_or_u64_add(KsReduce_u64 *state, uint64_t value) {
    uint64_t bits = (uint64_t)state->total | (uint64_t)value; memcpy(&state->total, &bits, sizeof bits);
}
static inline __attribute__((unused)) uint64_t ks_reduce_exact_or_u64_value(KsReduce_u64 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_u64 ks_reduce_exact_xor_u64_init(uint64_t initial) { KsReduce_u64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_xor_u64_add(KsReduce_u64 *state, uint64_t value) {
    uint64_t bits = (uint64_t)state->total ^ (uint64_t)value; memcpy(&state->total, &bits, sizeof bits);
}
static inline __attribute__((unused)) uint64_t ks_reduce_exact_xor_u64_value(KsReduce_u64 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_u64 ks_reduce_integer_min_u64_init(uint64_t initial) { KsReduce_u64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_integer_min_u64_add(KsReduce_u64 *state, uint64_t value) {
    if (value < state->total) { state->total = value; }
}
static inline __attribute__((unused)) uint64_t ks_reduce_integer_min_u64_value(KsReduce_u64 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_u64 ks_reduce_integer_max_u64_init(uint64_t initial) { KsReduce_u64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_integer_max_u64_add(KsReduce_u64 *state, uint64_t value) {
    if (value > state->total) { state->total = value; }
}
static inline __attribute__((unused)) uint64_t ks_reduce_integer_max_u64_value(KsReduce_u64 state) { return state.total; }
static inline __attribute__((unused)) KsReduce_u64 ks_reduce_integer_argmin_u64_init(uint64_t initial) { KsReduce_u64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_integer_argmin_u64_add(KsReduce_u64 *state, uint64_t value) {
    ++state->count;
    if (state->position == 0 || value < state->total) { state->total = value; state->position = state->count; }
}
static inline __attribute__((unused)) double ks_reduce_integer_argmin_u64_value(KsReduce_u64 state) { return (double)state.position; }
static inline __attribute__((unused)) KsReduce_u64 ks_reduce_integer_argmax_u64_init(uint64_t initial) { KsReduce_u64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_integer_argmax_u64_add(KsReduce_u64 *state, uint64_t value) {
    ++state->count;
    if (state->position == 0 || value > state->total) { state->total = value; state->position = state->count; }
}
static inline __attribute__((unused)) double ks_reduce_integer_argmax_u64_value(KsReduce_u64 state) { return (double)state.position; }
static inline __attribute__((unused)) KsReduce_bool ks_reduce_exact_any_bool_init(bool initial) { KsReduce_bool out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_any_bool_add(KsReduce_bool *state, bool value) {
    state->total = state->total || value;
}
static inline __attribute__((unused)) bool ks_reduce_exact_any_bool_value(KsReduce_bool state) { return state.total; }
static inline __attribute__((unused)) KsReduce_bool ks_reduce_exact_all_bool_init(bool initial) { KsReduce_bool out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_all_bool_add(KsReduce_bool *state, bool value) {
    state->total = state->total && value;
}
static inline __attribute__((unused)) bool ks_reduce_exact_all_bool_value(KsReduce_bool state) { return state.total; }
static inline __attribute__((unused)) KsReduce_bool ks_reduce_exact_count_bool_init(bool initial) { KsReduce_bool out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_exact_count_bool_add(KsReduce_bool *state, bool value) {
    state->count += value ? UINT64_C(1) : UINT64_C(0);
}
static inline __attribute__((unused)) uint64_t ks_reduce_exact_count_bool_value(KsReduce_bool state) { return state.count; }
static inline __attribute__((unused)) KsReduce_f64 ks_reduce_propagating_min_f64_init(double initial) { KsReduce_f64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_propagating_min_f64_add(KsReduce_f64 *state, double value) {
    if ((!isnan(state->total) && (isnan(value) || (value < state->total || (value == 0.0 && state->total == 0.0 && (signbit(value) && !signbit(state->total))))))) { state->total = value; }
}
static inline __attribute__((unused)) double ks_reduce_propagating_min_f64_value(KsReduce_f64 state) { return (isnan(state.total) ? ks_reduce_nan() : state.total); }
static inline __attribute__((unused)) KsReduce_f64 ks_reduce_propagating_max_f64_init(double initial) { KsReduce_f64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_propagating_max_f64_add(KsReduce_f64 *state, double value) {
    if ((!isnan(state->total) && (isnan(value) || (value > state->total || (value == 0.0 && state->total == 0.0 && (!signbit(value) && signbit(state->total))))))) { state->total = value; }
}
static inline __attribute__((unused)) double ks_reduce_propagating_max_f64_value(KsReduce_f64 state) { return (isnan(state.total) ? ks_reduce_nan() : state.total); }
static inline __attribute__((unused)) KsReduce_f64 ks_reduce_propagating_argmin_f64_init(double initial) { KsReduce_f64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_propagating_argmin_f64_add(KsReduce_f64 *state, double value) {
    ++state->count;
    if (state->position == 0 || (!isnan(state->total) && (isnan(value) || (value < state->total || (value == 0.0 && state->total == 0.0 && (signbit(value) && !signbit(state->total))))))) { state->total = value; state->position = state->count; }
}
static inline __attribute__((unused)) double ks_reduce_propagating_argmin_f64_value(KsReduce_f64 state) { return (double)state.position; }
static inline __attribute__((unused)) KsReduce_f64 ks_reduce_propagating_argmax_f64_init(double initial) { KsReduce_f64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_propagating_argmax_f64_add(KsReduce_f64 *state, double value) {
    ++state->count;
    if (state->position == 0 || (!isnan(state->total) && (isnan(value) || (value > state->total || (value == 0.0 && state->total == 0.0 && (!signbit(value) && signbit(state->total))))))) { state->total = value; state->position = state->count; }
}
static inline __attribute__((unused)) double ks_reduce_propagating_argmax_f64_value(KsReduce_f64 state) { return (double)state.position; }
static inline __attribute__((unused)) KsReduce_f64 ks_reduce_number_min_f64_init(double initial) { KsReduce_f64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_number_min_f64_add(KsReduce_f64 *state, double value) {
    if ((!isnan(value) && (isnan(state->total) || (value < state->total || (value == 0.0 && state->total == 0.0 && (signbit(value) && !signbit(state->total))))))) { state->total = value; }
}
static inline __attribute__((unused)) double ks_reduce_number_min_f64_value(KsReduce_f64 state) { return (isnan(state.total) ? ks_reduce_nan() : state.total); }
static inline __attribute__((unused)) KsReduce_f64 ks_reduce_number_max_f64_init(double initial) { KsReduce_f64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_number_max_f64_add(KsReduce_f64 *state, double value) {
    if ((!isnan(value) && (isnan(state->total) || (value > state->total || (value == 0.0 && state->total == 0.0 && (!signbit(value) && signbit(state->total))))))) { state->total = value; }
}
static inline __attribute__((unused)) double ks_reduce_number_max_f64_value(KsReduce_f64 state) { return (isnan(state.total) ? ks_reduce_nan() : state.total); }
static inline __attribute__((unused)) KsReduce_f64 ks_reduce_number_argmin_f64_init(double initial) { KsReduce_f64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_number_argmin_f64_add(KsReduce_f64 *state, double value) {
    ++state->count;
    if (state->position == 0 || (!isnan(value) && (isnan(state->total) || (value < state->total || (value == 0.0 && state->total == 0.0 && (signbit(value) && !signbit(state->total))))))) { state->total = value; state->position = state->count; }
}
static inline __attribute__((unused)) double ks_reduce_number_argmin_f64_value(KsReduce_f64 state) { return (double)state.position; }
static inline __attribute__((unused)) KsReduce_f64 ks_reduce_number_argmax_f64_init(double initial) { KsReduce_f64 out = {initial, 0, 0}; return out; }
static inline __attribute__((unused)) void ks_reduce_number_argmax_f64_add(KsReduce_f64 *state, double value) {
    ++state->count;
    if (state->position == 0 || (!isnan(value) && (isnan(state->total) || (value > state->total || (value == 0.0 && state->total == 0.0 && (!signbit(value) && signbit(state->total))))))) { state->total = value; state->position = state->count; }
}
static inline __attribute__((unused)) double ks_reduce_number_argmax_f64_value(KsReduce_f64 state) { return (double)state.position; }
