/* Times the fused JSON decoder's structural scan, as `jsonscan.nupp` lifts
 * it out of the decoder, against the same scan written with NEON
 * intrinsics. Both classify sixteen bytes at a time, validate a block with a
 * non-ASCII byte by the lookup4 tables against the bytes before it, drain
 * events lowest lane first into the same state machine, and finish the tail
 * a byte at a time; tapes, statuses and error positions must agree before
 * either is timed. The hand version carries the previous block in a register
 * where the Nupp source reads it again, and reads masks out four bits a lane
 * through `shrn`, which is how NEON code usually does both.
 * bench/simd11/README.md records the results.
 *
 * The generated side came from the CPU AOT backend, which left the tree in
 * 68f4d7f08, so build it in a checkout of that commit's parent:
 *
 *   ./bin/nupp aot --emit c --features neon \
 *       bench/simd11/handwritten/jsonscan.nupp > /tmp/scan.c
 *   clang -std=c11 -O3 -ffp-contract=off -fno-fast-math -fPIC -dynamiclib \
 *       /tmp/scan.c -o /tmp/scan.dylib
 *   clang -std=c11 -O3 -D_POSIX_C_SOURCE=200809L \
 *       bench/simd11/handwritten/jsonscan.c -o /tmp/jsonscan
 *   /tmp/jsonscan /tmp/scan.dylib
 *
 * Each figure is the fastest of SAMPLES interleaved samples of about a
 * millisecond. */

#include <arm_neon.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* Bytes classified at a time: one NEON vector of uint8. */
#define BLOCK 16

/* Narrowing a byte mask by four leaves four bits a lane, so lane i owns bits
 * 4i to 4i + 3 of the event word: a set bit's index shifted right by
 * NIBBLE_SHIFT is its lane, and clearing LANE_BITS there retires the lane. */
#define NIBBLE_SHIFT 2
#define LANE_BITS UINT64_C(0xF)

/* The most continuation bytes one scalar has. */
#define MAX_CONTINUATIONS 3

/* Set on the tape word of a closing quote whose string held a backslash, so
 * the decoder knows to unescape it. */
#define ESCAPED_STRING UINT32_C(0x80000000)

/* Interleaved samples of each implementation; the fastest is reported. */
#define SAMPLES 101

/* Each sample makes enough calls to cover about this many bytes. */
#define BYTES_PER_SAMPLE 20000000

/* A best time slower than any sample. */
#define UNSAMPLED 1e30

/* Tape words, and so the most events, an error case can write. */
#define ERROR_TAPE 64

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
#define CONTINUATION_LAST 0xBF
#define LEAD_FIRST 0xC0
#define LEAD2_FIRST 0xC2
#define LEAD2_LAST 0xDF
#define LEAD3_FIRST 0xE0
#define LEAD3_LAST 0xEF
#define LEAD4_FIRST 0xF0
#define LEAD4_LAST 0xF4
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

/* The status a scan answers with, the decoder's own, beside the one-based
 * position of the byte that raised it. */
enum {
  SCAN_OK,
  SCAN_TAPE_FULL,
  SCAN_BAD_UTF8,
  SCAN_CONTROL_BYTE,
  SCAN_STRAY_BACKSLASH
};

/* What the byte after the leads E0, ED, F0 and F4 must also satisfy: each
 * narrows the range of its first continuation. */
enum { ANY_CONTINUATION, AFTER_E0, AFTER_ED, AFTER_F0, AFTER_F4 };

/* The words written to the tape, a status and the position that raised it,
 * as the generated entry returns them. */
typedef struct {
  uint32_t written, status, position;
} ScanResult;

typedef ScanResult (*gen_fn)(const uint8_t *, uint32_t *, size_t, size_t);

/* Leaves hand_scan with what it has written so far. */
#define RESULT(status, position)                                               \
  return (ScanResult) {                                                        \
    written, (status), (position)                                              \
  }

/* A byte mask as an event word of four bits a lane. */
static inline uint64_t nibbles (uint8x16_t mask) {
  return vget_lane_u64(
      vreinterpret_u64_u8(vshrn_n_u16(vreinterpretq_u16_u8(mask), 4)), 0);
}

/* Scans `count` bytes of `source` into `tape`, which has room for `capacity`
 * words: the zero-based position of every quote that opens or closes a
 * string, ESCAPED_STRING marking a closing quote whose string held a
 * backslash, and of every structural byte outside a string.
 *
 * Whole blocks are classified in lanes. An all-ASCII block after another
 * needs no validation; a block with a non-ASCII byte, or one after it, is
 * validated against the block before by the lookup4 tables, and only its
 * ASCII events reach the state machine. The first block that fails, or the
 * end of the whole blocks, ends the vector loop: the scan then seeds its
 * UTF-8 state from a scalar the last good block may have left unfinished
 * and goes on a byte at a time, so that the state machine reports the error
 * at the byte that raised it. It is never inlined, so the timed loop calls
 * it as it calls the generated entry. */
__attribute__((noinline)) ScanResult hand_scan (const uint8_t *source,
                                                size_t count, uint32_t *tape,
                                                size_t capacity) {
  /* By the previous byte's high nibble: 0-7 ASCII, 8-B a continuation, C-F
   * a lead. */
  static const uint8_t byte1HighTable[BLOCK] = {
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
  static const uint8_t byte1LowTable[BLOCK] = {
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
  static const uint8_t byte2HighTable[BLOCK] = {
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
  const uint8x16_t byte1High = vld1q_u8(byte1HighTable),
                   byte1Low = vld1q_u8(byte1LowTable);
  const uint8x16_t byte2High = vld1q_u8(byte2HighTable);
  uint32_t at = 0, written = 0;
  bool inString = false, stringEscaped = false, slashOdd = false,
       haveSlash = false;
  uint32_t lastSlash = 0, owed = 0, constraint = 0, lastNonAscii = 0;
  bool haveNonAscii = false, seeded = false, previousNonAscii = false,
       vectorsOff = false;
  uint8x16_t previous = vdupq_n_u8(0);

  while (at < count || !seeded) {
    uint64_t events = 0;
    uint32_t width = 0, shift = 0;

    if (!vectorsOff && (size_t)at + BLOCK <= count) {
      /* The lanes that hold a structural byte, a quote, a backslash or a
       * control byte. */
      uint8x16_t block = vld1q_u8(source + at);
      uint8x16_t m = vorrq_u8(vorrq_u8(vceqq_u8(block, vdupq_n_u8('{')),
                                       vceqq_u8(block, vdupq_n_u8('}'))),
                              vorrq_u8(vceqq_u8(block, vdupq_n_u8('[')),
                                       vceqq_u8(block, vdupq_n_u8(']'))));
      m = vorrq_u8(m, vorrq_u8(vceqq_u8(block, vdupq_n_u8(':')),
                               vceqq_u8(block, vdupq_n_u8(','))));
      m = vorrq_u8(m, vorrq_u8(vceqq_u8(block, vdupq_n_u8('"')),
                               vceqq_u8(block, vdupq_n_u8('\\'))));
      m = vorrq_u8(m, vcltq_u8(block, vdupq_n_u8(' ')));
      bool validate = false;

      if (previousNonAscii) {
        events = nibbles(m);
        validate = true;
      }
      else {
        uint8x16_t high = vcgeq_u8(block, vdupq_n_u8(ASCII_LIMIT));
        events = nibbles(vorrq_u8(m, high));

        if (events != 0) {
          validate = vmaxvq_u8(high) != 0;

          if (validate) {
            events = nibbles(m);
          }
        }
      }

      if (validate) {
        uint8x16_t previous1 = vextq_u8(previous, block, BLOCK - 1);
        uint8x16_t previous2 = vextq_u8(previous, block, BLOCK - 2);
        uint8x16_t previous3 = vextq_u8(previous, block, BLOCK - 3);
        uint8x16_t special =
            vandq_u8(vandq_u8(vqtbl1q_u8(byte1High, vshrq_n_u8(previous1, 4)),
                              vqtbl1q_u8(byte1Low, vandq_u8(previous1,
                                                            vdupq_n_u8(0x0F)))),
                     vqtbl1q_u8(byte2High, vshrq_n_u8(block, 4)));

        /* The tables flag every continuation after a continuation; that is
         * an error only where no three- or four-byte lead calls for it. */
        uint8x16_t required =
            vandq_u8(vorrq_u8(vcgeq_u8(previous2, vdupq_n_u8(LEAD3_FIRST)),
                              vcgeq_u8(previous3, vdupq_n_u8(LEAD4_FIRST))),
                     vdupq_n_u8(TWO_CONTS));

        if (vmaxvq_u8(veorq_u8(special, required)) != 0) {
          vectorsOff = true;
        }
        else {
          previousNonAscii = vgetq_lane_u8(block, BLOCK - 1) >= ASCII_LIMIT;
        }
      }
      else {
        previousNonAscii = false;
      }

      previous = block;

      if (!vectorsOff) {
        width = BLOCK;
        shift = NIBBLE_SHIFT;
      }
      else {
        events = 0;
      }
    }

    /* Leaving the vectors: look back over the last good block's final
     * bytes for a lead whose scalar it left unfinished, and owe the
     * continuations that scalar still needs. */
    if (width == 0 && !seeded) {
      seeded = true;
      uint32_t back = 1;
      bool walking = true;

      while (walking && back <= MAX_CONTINUATIONS && back <= at) {
        uint32_t earlierAt = at - back;
        uint32_t earlier = earlierAt < count ? source[earlierAt] : 0;

        if (earlier < ASCII_LIMIT) {
          walking = false;
        }
        else if (earlier >= LEAD_FIRST) {
          if (earlier < LEAD2_FIRST || earlier > LEAD4_LAST) {
            RESULT(SCAN_BAD_UTF8, earlierAt + 1);
          }

          uint32_t need = earlier <= LEAD2_LAST   ? 1
                          : earlier <= LEAD3_LAST ? 2
                                                  : 3;

          if (need >= back) {
            owed = need - back + 1;
            haveNonAscii = true;
            lastNonAscii = at - 1;

            if (back == 1) {
              if (earlier == LEAD_E0) {
                constraint = AFTER_E0;
              }
              else if (earlier == LEAD_ED) {
                constraint = AFTER_ED;
              }
              else if (earlier == LEAD_F0) {
                constraint = AFTER_F0;
              }
              else if (earlier == LEAD_F4) {
                constraint = AFTER_F4;
              }
            }
          }

          walking = false;
        }
        else {
          back += 1;
        }
      }
    }
    else if (width == 0) {
      /* The same classification for one byte, outside ASCII included. */
      if (at < count) {
        uint32_t byte = source[at];

        if (byte == '"' || byte == '\\' || byte < ' ' || byte == '{' ||
            byte == '}' || byte == '[' || byte == ']' || byte == ':' ||
            byte == ',' || byte >= ASCII_LIMIT) {
          events = 1;
        }
      }

      width = 1;
    }

    while (events != 0) {
      uint32_t bit = (uint32_t)__builtin_ctzll(events);
      events &= ~(LANE_BITS << bit);
      uint32_t position = at + (bit >> shift);

      if (position >= count) {
        continue;
      }

      uint32_t byte = source[position];

      /* Every byte a scalar still owes is non-ASCII, so it is an event, and
       * the next event must be the byte right after the last one. */
      if (owed != 0 && (!haveNonAscii || position != lastNonAscii + 1)) {
        RESULT(SCAN_BAD_UTF8, lastNonAscii + 2);
      }

      if (byte >= ASCII_LIMIT) {
        bool isContinuation = byte <= CONTINUATION_LAST;

        if (owed != 0) {
          if (!isContinuation) {
            RESULT(SCAN_BAD_UTF8, position + 1);
          }

          if ((constraint == AFTER_E0 && byte < AFTER_E0_FIRST) ||
              (constraint == AFTER_ED && byte > AFTER_ED_LAST) ||
              (constraint == AFTER_F0 && byte < AFTER_F0_FIRST) ||
              (constraint == AFTER_F4 && byte > AFTER_F4_LAST)) {
            RESULT(SCAN_BAD_UTF8, position + 1);
          }

          owed -= 1;
          constraint = ANY_CONTINUATION;
        }
        else if (isContinuation || byte < LEAD2_FIRST || byte > LEAD4_LAST) {
          RESULT(SCAN_BAD_UTF8, position + 1);
        }
        else if (byte <= LEAD2_LAST) {
          owed = 1;
        }
        else if (byte <= LEAD3_LAST) {
          owed = 2;

          if (byte == LEAD_E0) {
            constraint = AFTER_E0;
          }
          else if (byte == LEAD_ED) {
            constraint = AFTER_ED;
          }
        }
        else {
          owed = 3;

          if (byte == LEAD_F0) {
            constraint = AFTER_F0;
          }
          else if (byte == LEAD_F4) {
            constraint = AFTER_F4;
          }
        }

        haveNonAscii = true;
        lastNonAscii = position;
        haveSlash = false;
        slashOdd = false;
      }
      else if (owed != 0) {
        RESULT(SCAN_BAD_UTF8, position + 1);
      }
      else if (byte == '\\') {
        if (!inString) {
          RESULT(SCAN_STRAY_BACKSLASH, position + 1);
        }

        /* A run of backslashes escapes what follows when its length is
         * odd. */
        slashOdd = haveSlash && position == lastSlash + 1 ? !slashOdd : true;
        haveSlash = true;
        lastSlash = position;
        stringEscaped = true;
      }
      else {
        bool escaped = haveSlash && position == lastSlash + 1 && slashOdd;

        if (byte == '"' && !escaped) {
          if (written >= capacity) {
            RESULT(SCAN_TAPE_FULL, position + 1);
          }

          tape[written++] = inString && stringEscaped
                                ? (position | ESCAPED_STRING)
                                : position;
          stringEscaped = stringEscaped && inString;
          inString = !inString;
        }
        else if (byte < ' ') {
          bool whitespace = byte == '\t' || byte == '\n' || byte == '\r';

          if (inString || !whitespace) {
            RESULT(SCAN_CONTROL_BYTE, position + 1);
          }
        }
        else if (!inString) {
          if (written >= capacity) {
            RESULT(SCAN_TAPE_FULL, position + 1);
          }

          tape[written++] = position;
        }

        haveSlash = false;
        slashOdd = false;
      }
    }

    at += width;
  }

  if (owed != 0) {
    RESULT(SCAN_BAD_UTF8, lastNonAscii + 2);
  }

  RESULT(SCAN_OK, 0);
}

static double now (void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);

  return t.tv_sec + t.tv_nsec * 1e-9;
}

/* Three document classes, each repeated to the size asked for: dense
 * records, long ASCII text and text in several scripts with escapes. Writes
 * a JSON array of them into `out` and answers its length, which stays under
 * `size`. */
static size_t build (char *out, size_t size, int kind) {
  static const char *pieces[3] = {
      "{\"id\":12345,\"name\":\"widget\",\"tags\":[\"a\",\"b\"],\"price\":3.25,"
      "\"ok\":true,\"note\":null},",
      "{\"text\":\"The quick brown fox jumps over the lazy dog while the band "
      "plays on and on into the night.\"},",
      "{\"text\":\"caf\xc3\xa9 na\xc3\xafve \xe6\xbc\xa2\xe5\xad\x97 "
      "\xd0\xbf\xd1\x80\xd0\xb8\xd0\xb2\xd0\xb5\xd1\x82 \xf0\x9f\x98\x80 "
      "\\\"quoted\\\" end\"},",
  };
  size_t n = 0, len = strlen(pieces[kind]);
  out[n++] = '[';

  while (n + len + 1 < size) {
    memcpy(out + n, pieces[kind], len);
    n += len;
  }

  if (out[n - 1] == ',') {
    n--;
  }

  out[n++] = ']';

  return n;
}

/* Requires both implementations to reject the same malformed documents at
 * the same byte, then, for each document class and size, to write the same
 * tape before timing both. */
int main (int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "usage: jsonscan LIBRARY\n");

    return 2;
  }

  void *library = dlopen(argv[1], RTLD_NOW);

  if (!library) {
    fprintf(stderr, "%s\n", dlerror());

    return 1;
  }

  gen_fn generated = (gen_fn)dlsym(library, "ks_scan");

  if (!generated) {
    fprintf(stderr, "the library lacks ks_scan\n");

    return 1;
  }

  /* Errors first: both must stop at the same byte for the same reason. A
   * truncated scalar, an overlong one, a stray backslash, a raw control
   * byte, a scalar past U+10FFFF, a bad byte at the end of a long vector,
   * and a surrogate. */
  static const char *bad[] = {
      "[\"\xc3\"]",
      "[\"\xe0\x80\x80\"]",
      "[1,\\2]",
      "[\"a\x01\"]",
      "[\"\xf4\x90\x80\x80 and more text past it\"]",
      "{\"key\":\"value with a bad byte at the end of a long vector \xff\"}",
      "[\"\xed\xa0\x80\"]"};

  for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
    size_t n = strlen(bad[i]);
    uint32_t genTape[ERROR_TAPE], handTape[ERROR_TAPE];
    ScanResult g = generated((const uint8_t *)bad[i], genTape, n, ERROR_TAPE),
               h = hand_scan((const uint8_t *)bad[i], n, handTape, ERROR_TAPE);

    if (g.written != h.written || g.status != h.status ||
        g.position != h.position || g.status == SCAN_OK) {
      printf("ERROR MISMATCH %zu: %u/%u/%u vs %u/%u/%u\n", i, g.written,
             g.status, g.position, h.written, h.status, h.position);

      return 1;
    }
  }

  static const char *names[3] = {"records", "ascii", "unicode"};
  size_t sizes[] = {256, 4096, 65536};

  for (int kind = 0; kind < 3; kind++) {
    for (int s = 0; s < 3; s++) {
      size_t size = sizes[s];
      char *doc = malloc(size + 64);
      size_t n = build(doc, size, kind);
      uint32_t *genTape = malloc(sizeof(uint32_t) * (n + 1)),
               *handTape = malloc(sizeof(uint32_t) * (n + 1));
      ScanResult g = generated((const uint8_t *)doc, genTape, n, n),
                 h = hand_scan((const uint8_t *)doc, n, handTape, n);

      if (g.written != h.written || g.status != h.status ||
          g.position != h.position ||
          memcmp(genTape, handTape, sizeof(uint32_t) * g.written)) {
        printf("MISMATCH %s %zu: %u/%u/%u vs %u/%u/%u\n", names[kind], n,
               g.written, g.status, g.position, h.written, h.status,
               h.position);

        return 1;
      }

      if (g.status != SCAN_OK) {
        printf("%s %zu did not scan: status %u at %u\n", names[kind], n,
               g.status, g.position);

        return 1;
      }

      size_t calls = BYTES_PER_SAMPLE / n + 1;
      double best[2] = {UNSAMPLED, UNSAMPLED};

      /* Alternate which implementation goes first, so neither always runs
       * on a cache the other warmed. */
      for (int sample = 0; sample < SAMPLES; sample++) {
        for (int step = 0; step < 2; step++) {
          int which = (sample & 1) ? 1 - step : step;
          double start = now();

          for (size_t c = 0; c < calls; c++) {
            if (which == 0) {
              generated((const uint8_t *)doc, genTape, n, n);
            }
            else {
              hand_scan((const uint8_t *)doc, n, handTape, n);
            }

            __asm__ volatile("" ::: "memory");
          }

          double each = (now() - start) / calls * 1e9;

          if (each < best[which]) {
            best[which] = each;
          }
        }
      }

      printf("%-8s %6zu B  %6u words  generated %9.1fns  hand NEON %9.1fns  "
             "gen/hand %.3fx\n",
             names[kind], n, g.written, best[0], best[1], best[0] / best[1]);
      free(doc);
      free(genTape);
      free(handTape);
    }
  }

  return 0;
}
