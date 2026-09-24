/* Hand-written NEON versions of the explicit kernels in ../kernels.nupp.
 *
 * These are the bar the generated explicit SIMD is held to: what a C
 * programmer writes with intrinsics for the same algorithm, lane width and
 * numerical contract. Build with the harness's flags (-O3 -ffp-contract=off
 * -fno-fast-math), so neither side gets a contraction the other does not. */
#include <arm_neon.h>
#include <stddef.h>
#include <stdint.h>

/* output[i] = input[i] * scale + bias, eight doubles an iteration, then one
 * register, then one element. */
void hand_map(double *restrict output, const double *input, double scale, double bias, size_t count) {
    float64x2_t s = vdupq_n_f64(scale), b = vdupq_n_f64(bias);
    size_t i = 0;
    for (; i + 8 <= count; i += 8) {
        float64x2_t a0 = vld1q_f64(input + i), a1 = vld1q_f64(input + i + 2);
        float64x2_t a2 = vld1q_f64(input + i + 4), a3 = vld1q_f64(input + i + 6);
        vst1q_f64(output + i, vaddq_f64(vmulq_f64(a0, s), b));
        vst1q_f64(output + i + 2, vaddq_f64(vmulq_f64(a1, s), b));
        vst1q_f64(output + i + 4, vaddq_f64(vmulq_f64(a2, s), b));
        vst1q_f64(output + i + 6, vaddq_f64(vmulq_f64(a3, s), b));
    }
    for (; i + 2 <= count; i += 2) {
        vst1q_f64(output + i, vaddq_f64(vmulq_f64(vld1q_f64(input + i), s), b));
    }
    if (i < count) {
        output[i] = input[i] * scale + bias;
    }
}

/* Halve each value while it exceeds one, at most 32 times, and add the
 * number of halvings: four lanes at a time under a live mask. */
void hand_refine(double *restrict output, const double *input, size_t count) {
    const float64x2_t one = vdupq_n_f64(1.0), half = vdupq_n_f64(0.5), cap = vdupq_n_f64(32.0);
    size_t i = 0;
    for (; i + 4 <= count; i += 4) {
        float64x2_t v0 = vld1q_f64(input + i), v1 = vld1q_f64(input + i + 2);
        float64x2_t r0 = vdupq_n_f64(0.0), r1 = vdupq_n_f64(0.0);
        uint64x2_t l0 = vcgtq_f64(v0, one), l1 = vcgtq_f64(v1, one);
        while (vmaxvq_u32(vreinterpretq_u32_u64(vorrq_u64(l0, l1))) != 0) {
            v0 = vbslq_f64(l0, vmulq_f64(v0, half), v0);
            v1 = vbslq_f64(l1, vmulq_f64(v1, half), v1);
            r0 = vbslq_f64(l0, vaddq_f64(r0, one), r0);
            r1 = vbslq_f64(l1, vaddq_f64(r1, one), r1);
            l0 = vandq_u64(vcgtq_f64(v0, one), vcltq_f64(r0, cap));
            l1 = vandq_u64(vcgtq_f64(v1, one), vcltq_f64(r1, cap));
        }
        vst1q_f64(output + i, vaddq_f64(v0, r0));
        vst1q_f64(output + i + 2, vaddq_f64(v1, r1));
    }
    for (; i < count; i++) {
        double value = input[i];
        double rounds = 0.0;
        while (value > 1.0 && rounds < 32.0) {
            value = value * 0.5;
            rounds = rounds + 1.0;
        }
        output[i] = value + rounds;
    }
}

/* The same loop with the live masks pinned in their registers. Without the
 * empty asm, clang carries the masks as one bit a lane and widens them again
 * at every select, which is what the plain version above pays. This is the
 * version an author who read the assembly would keep. */
void hand_refine_tuned(double *restrict output, const double *input, size_t count) {
    const float64x2_t one = vdupq_n_f64(1.0), half = vdupq_n_f64(0.5), cap = vdupq_n_f64(32.0);
    size_t i = 0;
    for (; i + 4 <= count; i += 4) {
        float64x2_t v0 = vld1q_f64(input + i), v1 = vld1q_f64(input + i + 2);
        float64x2_t r0 = vdupq_n_f64(0.0), r1 = vdupq_n_f64(0.0);
        uint64x2_t l0 = vcgtq_f64(v0, one), l1 = vcgtq_f64(v1, one);
        while (vmaxvq_u32(vreinterpretq_u32_u64(vorrq_u64(l0, l1))) != 0) {
            v0 = vbslq_f64(l0, vmulq_f64(v0, half), v0);
            v1 = vbslq_f64(l1, vmulq_f64(v1, half), v1);
            r0 = vbslq_f64(l0, vaddq_f64(r0, one), r0);
            r1 = vbslq_f64(l1, vaddq_f64(r1, one), r1);
            l0 = vandq_u64(vcgtq_f64(v0, one), vcltq_f64(r0, cap));
            l1 = vandq_u64(vcgtq_f64(v1, one), vcltq_f64(r1, cap));
            __asm__("" : "+w"(l0), "+w"(l1));
        }
        vst1q_f64(output + i, vaddq_f64(v0, r0));
        vst1q_f64(output + i + 2, vaddq_f64(v1, r1));
    }
    for (; i < count; i++) {
        double value = input[i];
        double rounds = 0.0;
        while (value > 1.0 && rounds < 32.0) {
            value = value * 0.5;
            rounds = rounds + 1.0;
        }
        output[i] = value + rounds;
    }
}

/* The dot products. Each keeps the numerical contract its reducer names. */

/* Products in source order, added one at a time: only the multiplies can run
 * in lanes. */
double hand_ordered(const double *left, const double *right, size_t count) {
    double total = 0.0;
    size_t i = 0;
    for (; i + 4 <= count; i += 4) {
        float64x2_t p0 = vmulq_f64(vld1q_f64(left + i), vld1q_f64(right + i));
        float64x2_t p1 = vmulq_f64(vld1q_f64(left + i + 2), vld1q_f64(right + i + 2));
        total = total + vgetq_lane_f64(p0, 0);
        total = total + vgetq_lane_f64(p0, 1);
        total = total + vgetq_lane_f64(p1, 0);
        total = total + vgetq_lane_f64(p1, 1);
    }
    for (; i < count; i++) {
        total = total + left[i] * right[i];
    }
    return total;
}

/* The adjacent-pair tree whose first leaf is the seed: a binary counter of
 * completed blocks, merged left to right, then the partial blocks from the
 * smallest up. Products are formed in lanes. */
typedef struct { double sum[65]; unsigned char full[65]; } hand_pairwise_state;

static inline void hand_pairwise_push(hand_pairwise_state *state, double leaf) {
    unsigned level = 0;
    while (state->full[level]) {
        leaf = state->sum[level] + leaf;
        state->full[level] = 0;
        level++;
    }
    state->sum[level] = leaf;
    state->full[level] = 1;
}

double hand_pairwise(const double *left, const double *right, size_t count) {
    hand_pairwise_state state;
    for (unsigned level = 0; level < 65; level++) state.full[level] = 0;
    hand_pairwise_push(&state, 0.0);
    size_t i = 0;
    for (; i + 4 <= count; i += 4) {
        float64x2_t p0 = vmulq_f64(vld1q_f64(left + i), vld1q_f64(right + i));
        float64x2_t p1 = vmulq_f64(vld1q_f64(left + i + 2), vld1q_f64(right + i + 2));
        hand_pairwise_push(&state, vgetq_lane_f64(p0, 0));
        hand_pairwise_push(&state, vgetq_lane_f64(p0, 1));
        hand_pairwise_push(&state, vgetq_lane_f64(p1, 0));
        hand_pairwise_push(&state, vgetq_lane_f64(p1, 1));
    }
    for (; i < count; i++) hand_pairwise_push(&state, left[i] * right[i]);
    double total = 0.0;
    int started = 0;
    for (unsigned level = 0; level < 65; level++) {
        if (!state.full[level]) continue;
        total = started ? state.sum[level] + total : state.sum[level];
        started = 1;
    }
    return total;
}

/* Reassociation allowed: the kernel's shape, one four-lane accumulator and a
 * horizontal sum at the end. */
double hand_algebraic(const double *left, const double *right, size_t count) {
    float64x2_t a0 = vdupq_n_f64(0.0), a1 = vdupq_n_f64(0.0);
    size_t i = 0;
    for (; i + 4 <= count; i += 4) {
        a0 = vaddq_f64(a0, vmulq_f64(vld1q_f64(left + i), vld1q_f64(right + i)));
        a1 = vaddq_f64(a1, vmulq_f64(vld1q_f64(left + i + 2), vld1q_f64(right + i + 2)));
    }
    double total = vaddvq_f64(vaddq_f64(a0, a1));
    for (; i < count; i++) total = total + left[i] * right[i];
    return total;
}

/* The prefix of `source` that spells whole, well-formed UTF-8 scalars, by the
 * same lookup validator as bench/utf8simd/src/utf8simd.nupp: sixteen bytes at
 * a time until a vector holds an error, then the same scalar ladder from the
 * last scalar start at or before it. */
uint32_t hand_utf8_valid_prefix(const uint8_t *source, size_t count) {
    static const uint8_t high1[16] = {2, 2, 2, 2, 2, 2, 2, 2, 128, 128, 128, 128, 33, 1, 21, 73};
    static const uint8_t low1[16] = {231, 163, 131, 131, 139, 203, 203, 203, 203, 203, 203, 203, 203, 219, 203, 203};
    static const uint8_t high2[16] = {1, 1, 1, 1, 1, 1, 1, 1, 230, 174, 186, 186, 1, 1, 1, 1};
    static const uint8_t limits[16] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xEF, 0xDF, 0xBF};
    const uint8x16_t byte1High = vld1q_u8(high1), byte1Low = vld1q_u8(low1), byte2High = vld1q_u8(high2);
    const uint8x16_t incompleteLimit = vld1q_u8(limits);
    const uint8x16_t nibble = vdupq_n_u8(15);
    uint8x16_t previous = vdupq_n_u8(0);
    int previousAscii = 1;
    size_t at = 0;
    while (at + 16 <= count) {
        uint8x16_t input = vld1q_u8(source + at);
        if (vmaxvq_u8(input) >= 0x80) {
            uint8x16_t prev1 = vextq_u8(previous, input, 15);
            uint8x16_t special = vandq_u8(
                vandq_u8(vqtbl1q_u8(byte1High, vshrq_n_u8(prev1, 4)), vqtbl1q_u8(byte1Low, vandq_u8(prev1, nibble))),
                vqtbl1q_u8(byte2High, vshrq_n_u8(input, 4)));
            uint8x16_t prev2 = vextq_u8(previous, input, 14);
            uint8x16_t prev3 = vextq_u8(previous, input, 13);
            uint8x16_t must = vandq_u8(vorrq_u8(vcgeq_u8(prev2, vdupq_n_u8(0xE0)), vcgeq_u8(prev3, vdupq_n_u8(0xF0))), vdupq_n_u8(0x80));
            if (vmaxvq_u8(veorq_u8(special, must)) != 0) break;
            previousAscii = 0;
        } else if (!previousAscii) {
            if (vmaxvq_u8(vcgtq_u8(previous, incompleteLimit)) != 0) break;
            previousAscii = 1;
        }
        previous = input;
        at += 16;
    }
    size_t stop = at;
    at = at >= 3 ? at - 3 : 0;
    while (at < stop && at < count && source[at] >= 128 && source[at] <= 191) at++;
    while (at < count) {
        uint32_t lead = source[at];
        if (lead < 128) { at++; continue; }
        uint32_t low = 128, high = 191, need;
        if (lead < 194) return (uint32_t)at;
        else if (lead < 224) need = 1;
        else if (lead < 240) { need = 2; if (lead == 224) low = 160; else if (lead == 237) high = 159; }
        else if (lead < 245) { need = 3; if (lead == 240) low = 144; else if (lead == 244) high = 143; }
        else return (uint32_t)at;
        if (at + 1 >= count || source[at + 1] < low || source[at + 1] > high) return (uint32_t)at;
        if (need > 1 && (at + 2 >= count || source[at + 2] < 128 || source[at + 2] > 191)) return (uint32_t)at;
        if (need > 2 && (at + 3 >= count || source[at + 3] < 128 || source[at + 3] > 191)) return (uint32_t)at;
        at += need + 1;
    }
    return (uint32_t)count;
}
