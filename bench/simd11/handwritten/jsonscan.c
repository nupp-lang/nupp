/* Times the fused JSON decoder's structural scan, as `jsonscan.nupp` lifts
 * it out of the decoder, against the same scan written with NEON
 * intrinsics. Both classify sixteen bytes at a time, validate a block with a
 * non-ASCII byte by the lookup4 tables against the bytes before it, drain
 * events lowest lane first into the same state machine, and finish the tail
 * a byte at a time; tapes, statuses and error positions must agree before
 * either is timed. The hand version carries the previous block in a register
 * where the Nupp source reads it again, and reads masks out four bits a lane
 * through `shrn`, which is how NEON code usually does both.
 *
 *   ./bin/nupp aot --emit c --features neon bench/simd11/handwritten/jsonscan.nupp > /tmp/scan.c
 *   clang -std=c11 -O3 -ffp-contract=off -fno-fast-math -fPIC -dynamiclib /tmp/scan.c -o /tmp/scan.dylib
 *   clang -std=c11 -O3 -D_POSIX_C_SOURCE=200809L bench/simd11/handwritten/jsonscan.c -o /tmp/jsonscan
 *   /tmp/jsonscan /tmp/scan.dylib
 *
 * Each figure is the fastest of 101 interleaved samples of about a
 * millisecond. */
#include <arm_neon.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct { uint32_t written, status, position; } ScanResult;
typedef ScanResult (*gen_fn)(const uint8_t *, uint32_t *, size_t, size_t);

#define RESULT(status, position) return (ScanResult){written, (status), (position)}

static inline uint64_t nibbles(uint8x16_t mask) {
    return vget_lane_u64(vreinterpret_u64_u8(vshrn_n_u16(vreinterpretq_u16_u8(mask), 4)), 0);
}

__attribute__((noinline)) ScanResult hand_scan(const uint8_t *source, size_t count, uint32_t *tape, size_t capacity) {
    static const uint8_t byte1HighTable[16] = {2, 2, 2, 2, 2, 2, 2, 2, 128, 128, 128, 128, 33, 1, 21, 73};
    static const uint8_t byte1LowTable[16] = {231, 163, 131, 131, 139, 203, 203, 203, 203, 203, 203, 203, 203, 219, 203, 203};
    static const uint8_t byte2HighTable[16] = {1, 1, 1, 1, 1, 1, 1, 1, 230, 174, 186, 186, 1, 1, 1, 1};
    const uint8x16_t byte1High = vld1q_u8(byte1HighTable), byte1Low = vld1q_u8(byte1LowTable);
    const uint8x16_t byte2High = vld1q_u8(byte2HighTable);
    uint32_t at = 0, written = 0;
    bool inString = false, stringEscaped = false, slashOdd = false, haveSlash = false;
    uint32_t lastSlash = 0, owed = 0, constraint = 0, lastNonAscii = 0;
    bool haveNonAscii = false, seeded = false, previousNonAscii = false, vectorsOff = false;
    uint8x16_t previous = vdupq_n_u8(0);
    while (at < count || !seeded) {
        uint64_t events = 0;
        uint32_t width = 0, shift = 0;
        if (!vectorsOff && (size_t)at + 16 <= count) {
            uint8x16_t block = vld1q_u8(source + at);
            uint8x16_t m = vorrq_u8(vorrq_u8(vceqq_u8(block, vdupq_n_u8(123)), vceqq_u8(block, vdupq_n_u8(125))),
                                    vorrq_u8(vceqq_u8(block, vdupq_n_u8(91)), vceqq_u8(block, vdupq_n_u8(93))));
            m = vorrq_u8(m, vorrq_u8(vceqq_u8(block, vdupq_n_u8(58)), vceqq_u8(block, vdupq_n_u8(44))));
            m = vorrq_u8(m, vorrq_u8(vceqq_u8(block, vdupq_n_u8(34)), vceqq_u8(block, vdupq_n_u8(92))));
            m = vorrq_u8(m, vcltq_u8(block, vdupq_n_u8(32)));
            bool validate = false;
            if (previousNonAscii) {
                events = nibbles(m);
                validate = true;
            } else {
                uint8x16_t high = vcgeq_u8(block, vdupq_n_u8(128));
                events = nibbles(vorrq_u8(m, high));
                if (events != 0) {
                    validate = vmaxvq_u8(high) != 0;
                    if (validate) events = nibbles(m);
                }
            }
            if (validate) {
                uint8x16_t previous1 = vextq_u8(previous, block, 15);
                uint8x16_t previous2 = vextq_u8(previous, block, 14);
                uint8x16_t previous3 = vextq_u8(previous, block, 13);
                uint8x16_t special = vandq_u8(vandq_u8(vqtbl1q_u8(byte1High, vshrq_n_u8(previous1, 4)),
                                                       vqtbl1q_u8(byte1Low, vandq_u8(previous1, vdupq_n_u8(15)))),
                                              vqtbl1q_u8(byte2High, vshrq_n_u8(block, 4)));
                uint8x16_t required = vandq_u8(vorrq_u8(vcgeq_u8(previous2, vdupq_n_u8(224)), vcgeq_u8(previous3, vdupq_n_u8(240))),
                                               vdupq_n_u8(128));
                if (vmaxvq_u8(veorq_u8(special, required)) != 0) {
                    vectorsOff = true;
                } else {
                    previousNonAscii = vgetq_lane_u8(block, 15) >= 128;
                }
            } else {
                previousNonAscii = false;
            }
            previous = block;
            if (!vectorsOff) {
                width = 16;
                shift = 2;
            } else {
                events = 0;
            }
        }
        if (width == 0 && !seeded) {
            seeded = true;
            uint32_t back = 1;
            bool walking = true;
            while (walking && back <= 3 && back <= at) {
                uint32_t earlierAt = at - back;
                uint32_t earlier = earlierAt < count ? source[earlierAt] : 0;
                if (earlier < 128) {
                    walking = false;
                } else if (earlier >= 192) {
                    if (earlier < 194 || earlier > 244) RESULT(2, earlierAt + 1);
                    uint32_t need = earlier <= 223 ? 1 : earlier <= 239 ? 2 : 3;
                    if (need >= back) {
                        owed = need - back + 1;
                        haveNonAscii = true;
                        lastNonAscii = at - 1;
                        if (back == 1) {
                            if (earlier == 224) constraint = 1;
                            else if (earlier == 237) constraint = 2;
                            else if (earlier == 240) constraint = 3;
                            else if (earlier == 244) constraint = 4;
                        }
                    }
                    walking = false;
                } else {
                    back += 1;
                }
            }
        } else if (width == 0) {
            if (at < count) {
                uint32_t byte = source[at];
                if (byte == 34 || byte == 92 || byte < 32 || byte == 123 || byte == 125 || byte == 91 || byte == 93 ||
                    byte == 58 || byte == 44 || byte >= 128) {
                    events = 1;
                }
            }
            width = 1;
        }
        while (events != 0) {
            uint32_t bit = (uint32_t)__builtin_ctzll(events);
            events &= ~(UINT64_C(0xF) << bit);
            uint32_t position = at + (bit >> shift);
            if (position >= count) continue;
            uint32_t byte = source[position];
            if (owed != 0 && (!haveNonAscii || position != lastNonAscii + 1)) RESULT(2, lastNonAscii + 2);
            if (byte >= 128) {
                bool isContinuation = byte <= 191;
                if (owed != 0) {
                    if (!isContinuation) RESULT(2, position + 1);
                    if ((constraint == 1 && byte < 160) || (constraint == 2 && byte > 159) ||
                        (constraint == 3 && byte < 144) || (constraint == 4 && byte > 143)) RESULT(2, position + 1);
                    owed -= 1;
                    constraint = 0;
                } else if (isContinuation || byte < 194 || byte > 244) {
                    RESULT(2, position + 1);
                } else if (byte <= 223) {
                    owed = 1;
                } else if (byte <= 239) {
                    owed = 2;
                    if (byte == 224) constraint = 1; else if (byte == 237) constraint = 2;
                } else {
                    owed = 3;
                    if (byte == 240) constraint = 3; else if (byte == 244) constraint = 4;
                }
                haveNonAscii = true;
                lastNonAscii = position;
                haveSlash = false;
                slashOdd = false;
            } else if (owed != 0) {
                RESULT(2, position + 1);
            } else if (byte == 92) {
                if (!inString) RESULT(4, position + 1);
                slashOdd = haveSlash && position == lastSlash + 1 ? !slashOdd : true;
                haveSlash = true;
                lastSlash = position;
                stringEscaped = true;
            } else {
                bool escaped = haveSlash && position == lastSlash + 1 && slashOdd;
                if (byte == 34 && !escaped) {
                    if (written >= capacity) RESULT(1, position + 1);
                    tape[written++] = inString && stringEscaped ? (position | UINT32_C(0x80000000)) : position;
                    stringEscaped = stringEscaped && inString;
                    inString = !inString;
                } else if (byte < 32) {
                    bool whitespace = byte == 9 || byte == 10 || byte == 13;
                    if (inString || !whitespace) RESULT(3, position + 1);
                } else if (!inString) {
                    if (written >= capacity) RESULT(1, position + 1);
                    tape[written++] = position;
                }
                haveSlash = false;
                slashOdd = false;
            }
        }
        at += width;
    }
    if (owed != 0) RESULT(2, lastNonAscii + 2);
    RESULT(0, 0);
}

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }

/* Three document classes, each repeated to the size asked for: dense
 * records, long ASCII text and text in several scripts with escapes. */
static size_t build(char *out, size_t size, int kind) {
    static const char *pieces[3] = {
        "{\"id\":12345,\"name\":\"widget\",\"tags\":[\"a\",\"b\"],\"price\":3.25,\"ok\":true,\"note\":null},",
        "{\"text\":\"The quick brown fox jumps over the lazy dog while the band plays on and on into the night.\"},",
        "{\"text\":\"caf\xc3\xa9 na\xc3\xafve \xe6\xbc\xa2\xe5\xad\x97 \xd0\xbf\xd1\x80\xd0\xb8\xd0\xb2\xd0\xb5\xd1\x82 \xf0\x9f\x98\x80 \\\"quoted\\\" end\"},",
    };
    size_t n = 0, len = strlen(pieces[kind]);
    out[n++] = '[';
    while (n + len + 1 < size) { memcpy(out + n, pieces[kind], len); n += len; }
    if (out[n - 1] == ',') n--;
    out[n++] = ']';
    return n;
}

int main(int argc, char **argv) {
    if (argc != 2) { fprintf(stderr, "usage: jsonscan LIBRARY\n"); return 2; }
    void *lib = dlopen(argv[1], RTLD_NOW); if (!lib) { fprintf(stderr, "%s\n", dlerror()); return 1; }
    gen_fn gen = (gen_fn)dlsym(lib, "ks_scan"); if (!gen) { fprintf(stderr, "the library lacks ks_scan\n"); return 1; }
    /* Errors first: both must stop at the same byte for the same reason. */
    static const char *bad[] = {"[\"\xc3\"]", "[\"\xe0\x80\x80\"]", "[1,\\2]", "[\"a\x01\"]", "[\"\xf4\x90\x80\x80 and more text past it\"]",
                                "{\"key\":\"value with a bad byte at the end of a long vector \xff\"}", "[\"\xed\xa0\x80\"]"};
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        size_t n = strlen(bad[i]); uint32_t a[64], b[64];
        ScanResult g = gen((const uint8_t *)bad[i], a, n, 64), h = hand_scan((const uint8_t *)bad[i], n, b, 64);
        if (g.written != h.written || g.status != h.status || g.position != h.position || g.status == 0) {
            printf("ERROR MISMATCH %zu: %u/%u/%u vs %u/%u/%u\n", i, g.written, g.status, g.position, h.written, h.status, h.position);
            return 1;
        }
    }
    static const char *names[3] = {"records", "ascii", "unicode"};
    size_t sizes[] = {256, 4096, 65536};
    for (int kind = 0; kind < 3; kind++) for (int s = 0; s < 3; s++) {
        size_t size = sizes[s];
        char *doc = malloc(size + 64);
        size_t n = build(doc, size, kind);
        uint32_t *a = malloc(sizeof(uint32_t) * (n + 1)), *b = malloc(sizeof(uint32_t) * (n + 1));
        ScanResult g = gen((const uint8_t *)doc, a, n, n), h = hand_scan((const uint8_t *)doc, n, b, n);
        if (g.written != h.written || g.status != h.status || g.position != h.position || memcmp(a, b, sizeof(uint32_t) * g.written)) {
            printf("MISMATCH %s %zu: %u/%u/%u vs %u/%u/%u\n", names[kind], n, g.written, g.status, g.position, h.written, h.status, h.position);
            return 1;
        }
        if (g.status != 0) { printf("%s %zu did not scan: status %u at %u\n", names[kind], n, g.status, g.position); return 1; }
        size_t calls = 20000000 / n + 1; double best[2] = {1e30, 1e30};
        for (int r = 0; r < 101; r++) for (int k = 0; k < 2; k++) {
            int f = (r & 1) ? 1 - k : k; double t = now();
            for (size_t c = 0; c < calls; c++) {
                if (f == 0) gen((const uint8_t *)doc, a, n, n); else hand_scan((const uint8_t *)doc, n, b, n);
                __asm__ volatile("" ::: "memory");
            }
            double each = (now() - t) / calls * 1e9; if (each < best[f]) best[f] = each;
        }
        printf("%-8s %6zu B  %6u words  generated %9.1fns  hand NEON %9.1fns  gen/hand %.3fx\n",
               names[kind], n, g.written, best[0], best[1], best[0] / best[1]);
        free(doc); free(a); free(b);
    }
    return 0;
}
