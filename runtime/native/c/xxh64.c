/* XXH64, for the trailer a stamped binary checks itself against.
 *
 * Yann Collet's algorithm, written out rather than vendored: it is sixty lines,
 * the reference implementation is a much larger file of dispatch and streaming
 * this has no use for, and the one property that matters here -- that the
 * compiler and the stub agree on the number -- is easier to hold with both
 * spellings visible than with one of them behind a dependency.
 *
 * The input is read little-endian explicitly. XXH64 is defined that way, and
 * this number is written into a file that another machine reads, so it must not
 * depend on the byte order of whichever machine produced it.
 *
 * `src/nupp/compiler/build/hash.nupp` is the other half. Anything changed here
 * has to change there, and `tests/hostbinarytest.lua` is what says so.
 */

#include "nupp_xxh64.h"

#define P1 UINT64_C(0x9E3779B185EBCA87)
#define P2 UINT64_C(0xC2B2AE3D27D4EB4F)
#define P3 UINT64_C(0x165667B19E3779F9)
#define P4 UINT64_C(0x85EBCA77C2B2AE63)
#define P5 UINT64_C(0x27D4EB2F165667C5)

static uint64_t rotate_left(uint64_t value, unsigned count) {
    return (value << count) | (value >> (64 - count));
}

static uint64_t read64(const uint8_t *at) {
    return (uint64_t)at[0] | ((uint64_t)at[1] << 8) | ((uint64_t)at[2] << 16)
        | ((uint64_t)at[3] << 24) | ((uint64_t)at[4] << 32) | ((uint64_t)at[5] << 40)
        | ((uint64_t)at[6] << 48) | ((uint64_t)at[7] << 56);
}

static uint32_t read32(const uint8_t *at) {
    return (uint32_t)at[0] | ((uint32_t)at[1] << 8) | ((uint32_t)at[2] << 16) | ((uint32_t)at[3] << 24);
}

static uint64_t round_lane(uint64_t lane, uint64_t input) {
    lane += input * P2;
    lane = rotate_left(lane, 31);

    return lane * P1;
}

static uint64_t merge_lane(uint64_t accumulator, uint64_t lane) {
    accumulator ^= round_lane(0, lane);

    return accumulator * P1 + P4;
}

uint64_t nuppXxh64(const uint8_t *bytes, size_t length) {
    const uint8_t *at = bytes;
    const uint8_t *end = bytes + length;
    uint64_t hash;

    if (length >= 32) {
        const uint8_t *limit = end - 32;
        uint64_t v1 = P1 + P2;
        uint64_t v2 = P2;
        uint64_t v3 = 0;
        uint64_t v4 = (uint64_t)0 - P1;
        do {
            v1 = round_lane(v1, read64(at)); at += 8;
            v2 = round_lane(v2, read64(at)); at += 8;
            v3 = round_lane(v3, read64(at)); at += 8;
            v4 = round_lane(v4, read64(at)); at += 8;
        } while (at <= limit);
        hash = rotate_left(v1, 1) + rotate_left(v2, 7) + rotate_left(v3, 12) + rotate_left(v4, 18);
        hash = merge_lane(hash, v1);
        hash = merge_lane(hash, v2);
        hash = merge_lane(hash, v3);
        hash = merge_lane(hash, v4);
    } else {
        hash = P5;
    }

    hash += (uint64_t)length;

    while (end - at >= 8) {
        hash ^= round_lane(0, read64(at));
        hash = rotate_left(hash, 27) * P1 + P4;
        at += 8;
    }
    if (end - at >= 4) {
        hash ^= (uint64_t)read32(at) * P1;
        hash = rotate_left(hash, 23) * P2 + P3;
        at += 4;
    }
    while (at < end) {
        hash ^= (uint64_t)(*at) * P5;
        hash = rotate_left(hash, 11) * P1;
        at += 1;
    }

    hash ^= hash >> 33;
    hash *= P2;
    hash ^= hash >> 29;
    hash *= P3;
    hash ^= hash >> 32;

    return hash;
}
