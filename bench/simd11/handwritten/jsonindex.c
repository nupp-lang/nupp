/* Times bench/simd-json's generated structural indexer against the same
 * algorithm written with NEON intrinsics. Both classify sixteen bytes at a
 * time into one event mask, drain it lowest lane first, and feed each event
 * byte to the same string, backslash-parity and UTF-8 state machine; the
 * tapes, statuses and error positions must agree before either is timed.
 * The hand version reads the mask out the way NEON code usually does, four
 * bits a lane through `shrn`. bench/simd11/README.md records the results.
 *
 * The generated side came from bench/simd-json and the CPU AOT backend, which
 * both left the tree in 68f4d7f08, so build it in a checkout of that commit's
 * parent:
 *
 *   (cd bench/simd-json && ../../bin/nupp aot --emit c --features neon \
 *       src/simd_json/indexer.nupp > /tmp/index.c)
 *   clang -std=c11 -O3 -ffp-contract=off -fno-fast-math -fPIC -dynamiclib \
 *       /tmp/index.c -o /tmp/index.dylib
 *   clang -std=c11 -O3 -D_POSIX_C_SOURCE=200809L \
 *       bench/simd11/handwritten/jsonindex.c -o /tmp/jsonindex
 *   /tmp/jsonindex /tmp/index.dylib
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

/* Interleaved samples of each implementation; the fastest is reported. */
#define SAMPLES 101

/* Each sample makes enough calls to cover about this many bytes. */
#define BYTES_PER_SAMPLE 20000000

/* A best time slower than any sample. */
#define UNSAMPLED 1e30

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
#define LEAD2_FIRST 0xC2
#define LEAD2_LAST 0xDF
#define LEAD3_LAST 0xEF
#define LEAD4_LAST 0xF4
#define LEAD_E0 0xE0
#define LEAD_ED 0xED
#define LEAD_F0 0xF0
#define LEAD_F4 0xF4
#define AFTER_E0_FIRST 0xA0
#define AFTER_ED_LAST 0x9F
#define AFTER_F0_FIRST 0x90
#define AFTER_F4_LAST 0x8F

/* The status an index answers with, beside the one-based position of the
 * byte that raised it. */
enum {
  INDEX_OK,
  INDEX_TAPE_FULL,
  INDEX_BAD_UTF8,
  INDEX_CONTROL_BYTE,
  INDEX_STRAY_BACKSLASH
};

/* What the byte after the leads E0, ED, F0 and F4 must also satisfy: each
 * narrows the range of its first continuation. */
enum { ANY_CONTINUATION, AFTER_E0, AFTER_ED, AFTER_F0, AFTER_F4 };

/* The words written to the tape, a status and the position that raised it,
 * as the generated entry returns them. */
typedef struct {
  uint32_t written, status, position;
} IndexResult;

typedef IndexResult (*genfn)(const uint8_t *, uint32_t *, size_t, size_t);

/* Leaves handindex with what it has written so far. */
#define RESULT(status, position)                                               \
  return (IndexResult) {                                                       \
    written, (status), (position)                                              \
  }

/* Indexes `count` bytes of `source` into `tape`, which has room for
 * `capacity` words: the zero-based position of every quote that opens or
 * closes a string, and of every structural byte outside one. Whole blocks
 * are classified in lanes and the tail a byte at a time. It is never
 * inlined, so the timed loop calls it as it calls the generated entry. */
__attribute__((noinline)) IndexResult handindex (const uint8_t *source,
                                                 size_t count, uint32_t *tape,
                                                 size_t capacity) {
  uint32_t at = 0, written = 0;
  bool instring = false, slashodd = false, haveslash = false,
       havenonascii = false;
  uint32_t lastslash = 0, expected = 0, constraint = 0, lastnonascii = 0;

  while (at < count) {
    uint64_t events = 0;
    uint32_t width, shift;

    if ((size_t)at + BLOCK <= count) {
      /* The lanes that hold a structural byte, a quote, a backslash, a
       * control byte or a byte outside ASCII: every byte the state machine
       * below sees. */
      uint8x16_t block = vld1q_u8(source + at);
      uint8x16_t m = vorrq_u8(vorrq_u8(vceqq_u8(block, vdupq_n_u8('{')),
                                       vceqq_u8(block, vdupq_n_u8('}'))),
                              vorrq_u8(vceqq_u8(block, vdupq_n_u8('[')),
                                       vceqq_u8(block, vdupq_n_u8(']'))));
      m = vorrq_u8(m, vorrq_u8(vceqq_u8(block, vdupq_n_u8(':')),
                               vceqq_u8(block, vdupq_n_u8(','))));
      m = vorrq_u8(m, vorrq_u8(vceqq_u8(block, vdupq_n_u8('"')),
                               vceqq_u8(block, vdupq_n_u8('\\'))));
      m = vorrq_u8(m, vorrq_u8(vcltq_u8(block, vdupq_n_u8(' ')),
                               vcgeq_u8(block, vdupq_n_u8(ASCII_LIMIT))));
      events = vget_lane_u64(
          vreinterpret_u64_u8(vshrn_n_u16(vreinterpretq_u16_u8(m), 4)), 0);
      width = BLOCK;
      shift = NIBBLE_SHIFT;
    }
    else {
      /* The same question for one byte of the tail. */
      uint32_t byte = source[at];

      if (byte == '"' || byte == '\\' || byte < ' ' || byte == '{' ||
          byte == '}' || byte == '[' || byte == ']' || byte == ':' ||
          byte == ',' || byte >= ASCII_LIMIT) {
        events = 1;
      }

      width = 1;
      shift = 0;
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
      if (expected != 0 && (!havenonascii || position != lastnonascii + 1)) {
        RESULT(INDEX_BAD_UTF8, lastnonascii + 2);
      }

      if (byte >= ASCII_LIMIT) {
        bool iscontinuation = byte <= CONTINUATION_LAST;

        if (expected != 0) {
          if (!iscontinuation) {
            RESULT(INDEX_BAD_UTF8, position + 1);
          }

          if ((constraint == AFTER_E0 && byte < AFTER_E0_FIRST) ||
              (constraint == AFTER_ED && byte > AFTER_ED_LAST) ||
              (constraint == AFTER_F0 && byte < AFTER_F0_FIRST) ||
              (constraint == AFTER_F4 && byte > AFTER_F4_LAST)) {
            RESULT(INDEX_BAD_UTF8, position + 1);
          }

          expected -= 1;
          constraint = ANY_CONTINUATION;
        }
        else if (iscontinuation || byte < LEAD2_FIRST || byte > LEAD4_LAST) {
          RESULT(INDEX_BAD_UTF8, position + 1);
        }
        else if (byte <= LEAD2_LAST) {
          expected = 1;
        }
        else if (byte <= LEAD3_LAST) {
          expected = 2;

          if (byte == LEAD_E0) {
            constraint = AFTER_E0;
          }
          else if (byte == LEAD_ED) {
            constraint = AFTER_ED;
          }
        }
        else {
          expected = 3;

          if (byte == LEAD_F0) {
            constraint = AFTER_F0;
          }
          else if (byte == LEAD_F4) {
            constraint = AFTER_F4;
          }
        }

        havenonascii = true;
        lastnonascii = position;
        haveslash = false;
        slashodd = false;
      }
      else if (expected != 0) {
        RESULT(INDEX_BAD_UTF8, position + 1);
      }
      else if (byte == '\\') {
        if (!instring) {
          RESULT(INDEX_STRAY_BACKSLASH, position + 1);
        }

        /* A run of backslashes escapes what follows when its length is
         * odd. */
        slashodd = haveslash && position == lastslash + 1 ? !slashodd : true;
        haveslash = true;
        lastslash = position;
      }
      else {
        bool escaped = haveslash && position == lastslash + 1 && slashodd;

        if (byte == '"' && !escaped) {
          instring = !instring;

          if (written >= capacity) {
            RESULT(INDEX_TAPE_FULL, position + 1);
          }

          tape[written++] = position;
        }
        else if (byte < ' ') {
          bool whitespace = byte == '\t' || byte == '\n' || byte == '\r';

          if (instring || !whitespace) {
            RESULT(INDEX_CONTROL_BYTE, position + 1);
          }
        }
        else if (!instring) {
          if (written >= capacity) {
            RESULT(INDEX_TAPE_FULL, position + 1);
          }

          tape[written++] = position;
        }

        haveslash = false;
        slashodd = false;
      }
    }

    at += width;
  }

  if (expected != 0) {
    RESULT(INDEX_BAD_UTF8, lastnonascii + 2);
  }

  RESULT(INDEX_OK, 0);
}

static double now (void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);

  return t.tv_sec + t.tv_nsec * 1e-9;
}

/* Three document classes, each repeated to the size asked for: dense
 * records, long ASCII text and text in several scripts. Writes a JSON array
 * of them into `out` and answers its length, which stays under `size`. */
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

/* For each document class and size: index once with each implementation,
 * require the same tape, then time both. */
int main (int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "usage: jsonindex LIBRARY\n");

    return 2;
  }

  void *library = dlopen(argv[1], RTLD_NOW);

  if (!library) {
    fprintf(stderr, "%s\n", dlerror());

    return 1;
  }

  genfn generated = (genfn)dlsym(library, "ks_index");

  if (!generated) {
    fprintf(stderr, "the library lacks ks_index\n");

    return 1;
  }

  static const char *names[3] = {"records", "ascii", "unicode"};
  size_t sizes[] = {256, 4096, 65536};

  for (int kind = 0; kind < 3; kind++) {
    for (int s = 0; s < 3; s++) {
      size_t size = sizes[s];
      char *doc = malloc(size + 64);
      size_t n = build(doc, size, kind);
      uint32_t *gentape = malloc(sizeof(uint32_t) * (n + 1)),
               *handtape = malloc(sizeof(uint32_t) * (n + 1));
      IndexResult g = generated((const uint8_t *)doc, gentape, n, n),
                  h = handindex((const uint8_t *)doc, n, handtape, n);

      if (g.written != h.written || g.status != h.status ||
          g.position != h.position ||
          memcmp(gentape, handtape, sizeof(uint32_t) * g.written) != 0) {
        printf("MISMATCH %s %zu: %u/%u/%u vs %u/%u/%u\n", names[kind], n,
               g.written, g.status, g.position, h.written, h.status,
               h.position);
        free(doc);
        free(gentape);
        free(handtape);

        return 1;
      }

      if (g.status != INDEX_OK) {
        printf("%s %zu did not index: status %u at %u\n", names[kind], n,
               g.status, g.position);
        free(doc);
        free(gentape);
        free(handtape);

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
              generated((const uint8_t *)doc, gentape, n, n);
            }
            else {
              handindex((const uint8_t *)doc, n, handtape, n);
            }

            __asm__ volatile("" ::: "memory");
          }

          double each = (now() - start) / calls * 1e9;

          if (each < best[which]) {
            best[which] = each;
          }
        }
      }

      printf("%-8s %6zu B  %6u events  generated %9.1fns  hand NEON %9.1fns  "
             "gen/hand %.3fx\n",
             names[kind], n, g.written, best[0], best[1], best[0] / best[1]);
      free(doc);
      free(gentape);
      free(handtape);
    }
  }

  return 0;
}
