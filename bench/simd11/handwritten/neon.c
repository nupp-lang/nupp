/* Hand-written NEON versions of the explicit kernels in ../kernels.nupp,
 * linked into compare.c, which times them beside the generated kernels.
 *
 * They are the bar the generated explicit SIMD is held to: what a C
 * programmer writes with intrinsics for the same algorithm, lane width and
 * numerical contract. Build with the harness's flags (-O3 -ffp-contract=off
 * -fno-fast-math), so neither side gets a contraction the other does not. */

#include <arm_neon.h>
#include <stddef.h>
#include <stdint.h>

/* refine halves a value at most this many times. */
#define REFINE_ROUNDS 32.0

/* The pairwise tree has a level for each bit of a size_t count of leaves,
 * and one more for the seed leaf. */
#define PAIRWISE_LEVELS 65

/* Bytes in one NEON vector of uint8. */
#define BLOCK 16

/* The bounds of well-formed UTF-8 (Unicode Table 3-7):
 *
 *   00..7F
 *   C2..DF  80..BF
 *   E0      A0..BF  80..BF
 *   E1..EC  80..BF  80..BF
 *   ED      80..9F  80..BF
 *   EE..EF  80..BF  80..BF
 *   F0      90..BF  80..BF  80..BF
 *   F1..F3  80..BF  80..BF  80..BF
 *   F4      80..8F  80..BF  80..BF */
#define ASCII_LIMIT 0x80
#define CONTINUATION_FIRST 0x80
#define CONTINUATION_LAST 0xBF
#define LEAD2_FIRST 0xC2
#define LEAD3_FIRST 0xE0
#define LEAD4_FIRST 0xF0
#define LEAD4_LIMIT 0xF5
#define LEAD_E0 0xE0
#define LEAD_ED 0xED
#define LEAD_F0 0xF0
#define LEAD_F4 0xF4
#define AFTER_E0_FIRST 0xA0
#define AFTER_ED_LAST 0x9F
#define AFTER_F0_FIRST 0x90
#define AFTER_F4_LAST 0x8F

/* The lookup4 validator's error bits. Three nibble tables, indexed by the
 * high and low nibble of the previous byte and the high nibble of this one,
 * each give the errors that nibble permits; a pair of bytes is in error
 * where all three agree. */
enum {
  /* A lead byte, then a byte that is not a continuation. */
  TOO_SHORT = 1 << 0,
  /* An ASCII byte, then a continuation. */
  TOO_LONG = 1 << 1,
  /* E0 80..9F. */
  OVERLONG_3 = 1 << 2,
  /* F4 90..BF, or F5..FF. */
  TOO_LARGE = 1 << 3,
  /* ED A0..BF. */
  SURROGATE = 1 << 4,
  /* C0 or C1. */
  OVERLONG_2 = 1 << 5,
  /* F5..FF 80..8F. */
  TOO_LARGE_1000 = 1 << 6,
  /* F0 80..8F, sharing a bit with TOO_LARGE_1000. */
  OVERLONG_4 = 1 << 6,
  /* A continuation, then another. */
  TWO_CONTS = 1 << 7,
  /* What any lead byte's low nibble permits. */
  CARRY = TOO_SHORT | TOO_LONG | TWO_CONTS
};

/* output[i] = input[i] * scale + bias, eight doubles an iteration, then one
 * register, then one element. */
void handmap (double *restrict output, const double *input, double scale,
              double bias, size_t count) {
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

/* Halve each value while it exceeds one, at most REFINE_ROUNDS times, and
 * add the number of halvings: four lanes at a time under a live mask, then
 * the leftover elements one at a time. */
void handrefine (double *restrict output, const double *input, size_t count) {
  const float64x2_t one = vdupq_n_f64(1.0), half = vdupq_n_f64(0.5),
                    cap = vdupq_n_f64(REFINE_ROUNDS);
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

    while (value > 1.0 && rounds < REFINE_ROUNDS) {
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
void handrefinetuned (double *restrict output, const double *input,
                      size_t count) {
  const float64x2_t one = vdupq_n_f64(1.0), half = vdupq_n_f64(0.5),
                    cap = vdupq_n_f64(REFINE_ROUNDS);
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

    while (value > 1.0 && rounds < REFINE_ROUNDS) {
      value = value * 0.5;
      rounds = rounds + 1.0;
    }

    output[i] = value + rounds;
  }
}

/* The dot products. Each keeps the numerical contract its reducer names. */

/* Products in source order, added one at a time: only the multiplies can run
 * in lanes. */
double handordered (const double *left, const double *right, size_t count) {
  double total = 0.0;
  size_t i = 0;

  for (; i + 4 <= count; i += 4) {
    float64x2_t p0 = vmulq_f64(vld1q_f64(left + i), vld1q_f64(right + i));
    float64x2_t p1 =
        vmulq_f64(vld1q_f64(left + i + 2), vld1q_f64(right + i + 2));
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
 * smallest up. Products are formed in lanes. While full[k] is set, sum[k]
 * holds the sum of 2^k leaves. */
typedef struct {
  double sum[PAIRWISE_LEVELS];
  unsigned char full[PAIRWISE_LEVELS];
} pairwisestate;

/* Adds one leaf the way a carry adds a bit: it merges with every full level
 * below the first empty one, which then holds the merged sum. */
static inline void pairwisepush (pairwisestate *state, double leaf) {
  unsigned level = 0;

  while (state->full[level]) {
    leaf = state->sum[level] + leaf;
    state->full[level] = 0;
    level++;
  }

  state->sum[level] = leaf;
  state->full[level] = 1;
}

double handpairwise (const double *left, const double *right, size_t count) {
  pairwisestate state;

  for (unsigned level = 0; level < PAIRWISE_LEVELS; level++) {
    state.full[level] = 0;
  }

  pairwisepush(&state, 0.0);
  size_t i = 0;

  for (; i + 4 <= count; i += 4) {
    float64x2_t p0 = vmulq_f64(vld1q_f64(left + i), vld1q_f64(right + i));
    float64x2_t p1 =
        vmulq_f64(vld1q_f64(left + i + 2), vld1q_f64(right + i + 2));
    pairwisepush(&state, vgetq_lane_f64(p0, 0));
    pairwisepush(&state, vgetq_lane_f64(p0, 1));
    pairwisepush(&state, vgetq_lane_f64(p1, 0));
    pairwisepush(&state, vgetq_lane_f64(p1, 1));
  }

  for (; i < count; i++) {
    pairwisepush(&state, left[i] * right[i]);
  }

  double total = 0.0;
  int started = 0;

  for (unsigned level = 0; level < PAIRWISE_LEVELS; level++) {
    if (!state.full[level]) {
      continue;
    }

    total = started ? state.sum[level] + total : state.sum[level];
    started = 1;
  }

  return total;
}

/* Reassociation allowed: the kernel's shape, one four-lane accumulator and a
 * horizontal sum at the end. */
double handalgebraic (const double *left, const double *right, size_t count) {
  float64x2_t a0 = vdupq_n_f64(0.0), a1 = vdupq_n_f64(0.0);
  size_t i = 0;

  for (; i + 4 <= count; i += 4) {
    a0 = vaddq_f64(a0, vmulq_f64(vld1q_f64(left + i), vld1q_f64(right + i)));
    a1 = vaddq_f64(
        a1, vmulq_f64(vld1q_f64(left + i + 2), vld1q_f64(right + i + 2)));
  }

  double total = vaddvq_f64(vaddq_f64(a0, a1));

  for (; i < count; i++) {
    total = total + left[i] * right[i];
  }

  return total;
}

/* The prefix of `source` that spells whole, well-formed UTF-8 scalars, by the
 * same lookup validator as bench/utf8simd's: sixteen bytes at a time until a
 * vector holds an error, then the scalar ladder of the table above from the
 * last scalar start at or before it. A block of ASCII after a non-ASCII one
 * only has to show that the earlier block did not end inside a scalar. */
uint32_t handutf8prefix (const uint8_t *source, size_t count) {
  /* By the previous byte's high nibble: 0-7 ASCII, 8-B a continuation, C-F
   * a lead. */
  static const uint8_t high1[BLOCK] = {
      TOO_LONG,
      TOO_LONG,
      TOO_LONG,
      TOO_LONG,
      TOO_LONG,
      TOO_LONG,
      TOO_LONG,
      TOO_LONG,
      TWO_CONTS,
      TWO_CONTS,
      TWO_CONTS,
      TWO_CONTS,
      TOO_SHORT | OVERLONG_2,
      TOO_SHORT,
      TOO_SHORT | OVERLONG_3 | SURROGATE,
      TOO_SHORT | TOO_LARGE | TOO_LARGE_1000 | OVERLONG_4,
  };

  /* By the previous byte's low nibble, which tells the leads C0, C1, E0, ED,
   * F0 and F4 apart from their neighbors. */
  static const uint8_t low1[BLOCK] = {
      CARRY | OVERLONG_3 | OVERLONG_2 | OVERLONG_4,
      CARRY | OVERLONG_2,
      CARRY,
      CARRY,
      CARRY | TOO_LARGE,
      CARRY | TOO_LARGE | TOO_LARGE_1000,
      CARRY | TOO_LARGE | TOO_LARGE_1000,
      CARRY | TOO_LARGE | TOO_LARGE_1000,
      CARRY | TOO_LARGE | TOO_LARGE_1000,
      CARRY | TOO_LARGE | TOO_LARGE_1000,
      CARRY | TOO_LARGE | TOO_LARGE_1000,
      CARRY | TOO_LARGE | TOO_LARGE_1000,
      CARRY | TOO_LARGE | TOO_LARGE_1000,
      CARRY | TOO_LARGE | TOO_LARGE_1000 | SURROGATE,
      CARRY | TOO_LARGE | TOO_LARGE_1000,
      CARRY | TOO_LARGE | TOO_LARGE_1000,
  };

  /* By this byte's high nibble, which narrows a continuation to 80-8F, 90-9F
   * or A0-BF. */
  static const uint8_t high2[BLOCK] = {
      TOO_SHORT,
      TOO_SHORT,
      TOO_SHORT,
      TOO_SHORT,
      TOO_SHORT,
      TOO_SHORT,
      TOO_SHORT,
      TOO_SHORT,
      TOO_LONG | OVERLONG_2 | TWO_CONTS | OVERLONG_3 | TOO_LARGE_1000 |
          OVERLONG_4,
      TOO_LONG | OVERLONG_2 | TWO_CONTS | OVERLONG_3 | TOO_LARGE,
      TOO_LONG | OVERLONG_2 | TWO_CONTS | SURROGATE | TOO_LARGE,
      TOO_LONG | OVERLONG_2 | TWO_CONTS | SURROGATE | TOO_LARGE,
      TOO_SHORT,
      TOO_SHORT,
      TOO_SHORT,
      TOO_SHORT,
  };

  /* A block ends inside a scalar when its last byte is any lead, its second
   * to last leads three or four bytes, or its third to last leads four. */
  static const uint8_t limits[BLOCK] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
                                        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
                                        0xFF, 0xEF, 0xDF, 0xBF};
  const uint8x16_t byte1high = vld1q_u8(high1), byte1low = vld1q_u8(low1),
                   byte2high = vld1q_u8(high2);
  const uint8x16_t incompletelimit = vld1q_u8(limits);
  const uint8x16_t lownibble = vdupq_n_u8(0x0F);
  uint8x16_t previous = vdupq_n_u8(0);
  int previousascii = 1;
  size_t at = 0;

  while (at + BLOCK <= count) {
    uint8x16_t input = vld1q_u8(source + at);

    if (vmaxvq_u8(input) >= ASCII_LIMIT) {
      uint8x16_t prev1 = vextq_u8(previous, input, BLOCK - 1);
      uint8x16_t special =
          vandq_u8(vandq_u8(vqtbl1q_u8(byte1high, vshrq_n_u8(prev1, 4)),
                            vqtbl1q_u8(byte1low, vandq_u8(prev1, lownibble))),
                   vqtbl1q_u8(byte2high, vshrq_n_u8(input, 4)));

      /* The tables flag every continuation after a continuation; that is
       * an error only where no three- or four-byte lead calls for it. */
      uint8x16_t prev2 = vextq_u8(previous, input, BLOCK - 2);
      uint8x16_t prev3 = vextq_u8(previous, input, BLOCK - 3);
      uint8x16_t must =
          vandq_u8(vorrq_u8(vcgeq_u8(prev2, vdupq_n_u8(LEAD3_FIRST)),
                            vcgeq_u8(prev3, vdupq_n_u8(LEAD4_FIRST))),
                   vdupq_n_u8(TWO_CONTS));

      if (vmaxvq_u8(veorq_u8(special, must)) != 0) {
        break;
      }

      previousascii = 0;
    }
    else if (!previousascii) {
      if (vmaxvq_u8(vcgtq_u8(previous, incompletelimit)) != 0) {
        break;
      }

      previousascii = 1;
    }

    previous = input;
    at += BLOCK;
  }

  /* Back up over the continuations of a scalar the last block may have
   * split, to the byte that starts it. */
  size_t stop = at;
  at = at >= 3 ? at - 3 : 0;

  while (at < stop && at < count && source[at] >= CONTINUATION_FIRST &&
         source[at] <= CONTINUATION_LAST) {
    at++;
  }

  while (at < count) {
    uint32_t lead = source[at];

    if (lead < ASCII_LIMIT) {
      at++;
      continue;
    }

    uint32_t low = CONTINUATION_FIRST, high = CONTINUATION_LAST, need;

    if (lead < LEAD2_FIRST) {
      return (uint32_t)at;
    }
    else if (lead < LEAD3_FIRST) {
      need = 1;
    }
    else if (lead < LEAD4_FIRST) {
      need = 2;

      if (lead == LEAD_E0) {
        low = AFTER_E0_FIRST;
      }
      else if (lead == LEAD_ED) {
        high = AFTER_ED_LAST;
      }
    }
    else if (lead < LEAD4_LIMIT) {
      need = 3;

      if (lead == LEAD_F0) {
        low = AFTER_F0_FIRST;
      }
      else if (lead == LEAD_F4) {
        high = AFTER_F4_LAST;
      }
    }
    else {
      return (uint32_t)at;
    }

    if (at + 1 >= count || source[at + 1] < low || source[at + 1] > high) {
      return (uint32_t)at;
    }

    if (need > 1 && (at + 2 >= count || source[at + 2] < CONTINUATION_FIRST ||
                     source[at + 2] > CONTINUATION_LAST)) {
      return (uint32_t)at;
    }

    if (need > 2 && (at + 3 >= count || source[at + 3] < CONTINUATION_FIRST ||
                     source[at + 3] > CONTINUATION_LAST)) {
      return (uint32_t)at;
    }

    at += need + 1;
  }

  return (uint32_t)count;
}
