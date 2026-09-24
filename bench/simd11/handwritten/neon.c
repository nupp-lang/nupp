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
