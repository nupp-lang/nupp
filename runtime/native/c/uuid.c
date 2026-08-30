/* The two UUID versions, which are the same sixteen bytes assembled from
 * different sources: the random bytes a version 4 identifier is, and the wall
 * clock a version 7 one begins with.
 *
 * SHA-256 used to live here too. It is `nupp.data.digest` now, in Nupp, and
 * nothing computes it in C any more: the check a stamped binary runs before the
 * payload can be trusted is XXH64, in `xxh64.c`. The only SHA-256 in C left in
 * the tree is `bench/sha256/sha256_control.c`, which is the frozen control that
 * benchmark measures the port against and which nothing else builds.
 */

#include "nupp_native.h"

#include <uv.h>

static const char HEX[] = "0123456789abcdef";

/* --- UUIDs -------------------------------------------------------------- */

/* Both versions are sixteen bytes with four bits saying which version this is
 * and two saying which variant. What differs is where the other bytes come
 * from. */
static bool write_uuid(const uint8_t value[16], char *output) {
    static const unsigned GROUPS[5] = {4, 2, 2, 2, 6};
    size_t at = 0;
    size_t byte = 0;
    unsigned group;
    if (output == NULL) {
        return false;
    }
    for (group = 0; group < 5; group++) {
        unsigned step;
        if (group != 0) {
            output[at++] = '-';
        }
        for (step = 0; step < GROUPS[group]; step++) {
            output[at++] = HEX[value[byte] >> 4];
            output[at++] = HEX[value[byte] & 15];
            byte++;
        }
    }
    output[at] = '\0';
    return true;
}

static void stamp_version(uint8_t value[16], uint8_t version) {
    value[6] = (uint8_t)((value[6] & 0x0Fu) | (version << 4));
    value[8] = (uint8_t)((value[8] & 0x3Fu) | 0x80u);
}

/* Version 4: random everywhere the version and variant are not. */
NUPP_EXPORT bool nuppUuid4(char *output) {
    uint8_t value[16];
    if (uv_random(NULL, NULL, value, sizeof value, 0, NULL) != 0) {
        nupp_fail("the system has no randomness to draw on");
        return false;
    }
    stamp_version(value, 4);
    return write_uuid(value, output);
}

/* Version 7: the Unix millisecond in the first six bytes, big-endian, so that
 * sorting the text sorts by when it was made, and random after it. */
NUPP_EXPORT bool nuppUuid7(char *output) {
    uint8_t value[16];
    uint64_t milliseconds = nupp_unix_ms();
    unsigned at;
    if (uv_random(NULL, NULL, value + 6, sizeof value - 6, 0, NULL) != 0) {
        nupp_fail("the system has no randomness to draw on");
        return false;
    }
    for (at = 0; at < 6; at++) {
        value[at] = (uint8_t)(milliseconds >> (8 * (5 - at)));
    }
    stamp_version(value, 7);
    return write_uuid(value, output);
}
