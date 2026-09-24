/* Times bench/simd-json's generated structural indexer against the same
 * algorithm written with NEON intrinsics. Both classify sixteen bytes at a
 * time into one event mask, drain it lowest lane first, and feed each event
 * byte to the same string, backslash-parity and UTF-8 state machine; the
 * tapes, statuses and error positions must agree before either is timed.
 * The hand version reads the mask out the way NEON code usually does, four
 * bits a lane through `shrn`.
 *
 *   (cd bench/simd-json && ../../bin/nupp aot --emit c --features neon \
 *       src/simd_json/indexer.nupp > /tmp/index.c)
 *   clang -std=c11 -O3 -ffp-contract=off -fno-fast-math -fPIC -dynamiclib /tmp/index.c -o /tmp/index.dylib
 *   clang -std=c11 -O3 -D_POSIX_C_SOURCE=200809L bench/simd11/handwritten/jsonindex.c -o /tmp/jsonindex
 *   /tmp/jsonindex /tmp/index.dylib
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

typedef struct { uint32_t written, status, position; } IndexResult;
typedef IndexResult (*gen_fn)(const uint8_t *, uint32_t *, size_t, size_t);

#define RESULT(status, position) return (IndexResult){written, (status), (position)}

__attribute__((noinline)) IndexResult hand_index(const uint8_t *source, size_t count, uint32_t *tape, size_t capacity) {
    uint32_t at = 0, written = 0;
    bool inString = false, slashOdd = false, haveSlash = false, haveNonAscii = false;
    uint32_t lastSlash = 0, expected = 0, constraint = 0, lastNonAscii = 0;
    while (at < count) {
        uint64_t events = 0;
        uint32_t width, shift;
        if ((size_t)at + 16 <= count) {
            uint8x16_t b = vld1q_u8(source + at);
            uint8x16_t m = vorrq_u8(vorrq_u8(vceqq_u8(b, vdupq_n_u8(123)), vceqq_u8(b, vdupq_n_u8(125))),
                                    vorrq_u8(vceqq_u8(b, vdupq_n_u8(91)), vceqq_u8(b, vdupq_n_u8(93))));
            m = vorrq_u8(m, vorrq_u8(vceqq_u8(b, vdupq_n_u8(58)), vceqq_u8(b, vdupq_n_u8(44))));
            m = vorrq_u8(m, vorrq_u8(vceqq_u8(b, vdupq_n_u8(34)), vceqq_u8(b, vdupq_n_u8(92))));
            m = vorrq_u8(m, vorrq_u8(vcltq_u8(b, vdupq_n_u8(32)), vcgeq_u8(b, vdupq_n_u8(128))));
            events = vget_lane_u64(vreinterpret_u64_u8(vshrn_n_u16(vreinterpretq_u16_u8(m), 4)), 0);
            width = 16;
            shift = 2;
        } else {
            uint32_t byte = source[at];
            if (byte == 34 || byte == 92 || byte < 32 || byte == 123 || byte == 125 || byte == 91 || byte == 93 ||
                byte == 58 || byte == 44 || byte >= 128) {
                events = 1;
            }
            width = 1;
            shift = 0;
        }
        while (events != 0) {
            uint32_t bit = (uint32_t)__builtin_ctzll(events);
            events &= ~(UINT64_C(0xF) << bit);
            uint32_t position = at + (bit >> shift);
            if (position >= count) continue;
            uint32_t byte = source[position];
            if (expected != 0 && (!haveNonAscii || position != lastNonAscii + 1)) RESULT(2, lastNonAscii + 2);
            if (byte >= 128) {
                bool isContinuation = byte <= 191;
                if (expected != 0) {
                    if (!isContinuation) RESULT(2, position + 1);
                    if ((constraint == 1 && byte < 160) || (constraint == 2 && byte > 159) ||
                        (constraint == 3 && byte < 144) || (constraint == 4 && byte > 143)) RESULT(2, position + 1);
                    expected -= 1;
                    constraint = 0;
                } else if (isContinuation || byte < 194 || byte > 244) {
                    RESULT(2, position + 1);
                } else if (byte <= 223) {
                    expected = 1;
                } else if (byte <= 239) {
                    expected = 2;
                    if (byte == 224) constraint = 1; else if (byte == 237) constraint = 2;
                } else {
                    expected = 3;
                    if (byte == 240) constraint = 3; else if (byte == 244) constraint = 4;
                }
                haveNonAscii = true;
                lastNonAscii = position;
                haveSlash = false;
                slashOdd = false;
            } else if (expected != 0) {
                RESULT(2, position + 1);
            } else if (byte == 92) {
                if (!inString) RESULT(4, position + 1);
                slashOdd = haveSlash && position == lastSlash + 1 ? !slashOdd : true;
                haveSlash = true;
                lastSlash = position;
            } else {
                bool escaped = haveSlash && position == lastSlash + 1 && slashOdd;
                if (byte == 34 && !escaped) {
                    inString = !inString;
                    if (written >= capacity) RESULT(1, position + 1);
                    tape[written++] = position;
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
    if (expected != 0) RESULT(2, lastNonAscii + 2);
    RESULT(0, 0);
}

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }

/* Three document classes, each repeated to the size asked for: dense
 * records, long ASCII text and text in several scripts. */
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
    if (argc != 2) { fprintf(stderr, "usage: jsonindex LIBRARY\n"); return 2; }
    void *lib = dlopen(argv[1], RTLD_NOW); if (!lib) { fprintf(stderr, "%s\n", dlerror()); return 1; }
    gen_fn gen = (gen_fn)dlsym(lib, "ks_index"); if (!gen) { fprintf(stderr, "the library lacks ks_index\n"); return 1; }
    static const char *names[3] = {"records", "ascii", "unicode"};
    size_t sizes[] = {256, 4096, 65536};
    for (int kind = 0; kind < 3; kind++) for (int s = 0; s < 3; s++) {
        size_t size = sizes[s];
        char *doc = malloc(size + 64);
        size_t n = build(doc, size, kind);
        uint32_t *a = malloc(sizeof(uint32_t) * (n + 1)), *b = malloc(sizeof(uint32_t) * (n + 1));
        IndexResult g = gen((const uint8_t *)doc, a, n, n), h = hand_index((const uint8_t *)doc, n, b, n);
        if (g.written != h.written || g.status != h.status || g.position != h.position || memcmp(a, b, sizeof(uint32_t) * g.written)) {
            printf("MISMATCH %s %zu: %u/%u/%u vs %u/%u/%u\n", names[kind], n, g.written, g.status, g.position, h.written, h.status, h.position);
            return 1;
        }
        if (g.status != 0) { printf("%s %zu did not index: status %u at %u\n", names[kind], n, g.status, g.position); return 1; }
        size_t calls = 20000000 / n + 1; double best[2] = {1e30, 1e30};
        for (int r = 0; r < 101; r++) for (int k = 0; k < 2; k++) {
            int f = (r & 1) ? 1 - k : k; double t = now();
            for (size_t c = 0; c < calls; c++) {
                if (f == 0) gen((const uint8_t *)doc, a, n, n); else hand_index((const uint8_t *)doc, n, b, n);
                __asm__ volatile("" ::: "memory");
            }
            double each = (now() - t) / calls * 1e9; if (each < best[f]) best[f] = each;
        }
        printf("%-8s %6zu B  %6u events  generated %9.1fns  hand NEON %9.1fns  gen/hand %.3fx\n",
               names[kind], n, g.written, best[0], best[1], best[0] / best[1]);
        free(doc); free(a); free(b);
    }
    return 0;
}
