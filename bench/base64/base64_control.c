/* Base64 encoding, scalar and vectorized, as the ceiling `src/base64bench.nupp`
 * is measured against. See `nupp_base64.h` for why this exists.
 *
 * The vectorized encoder is the NEON one, which is shorter than the SSE and
 * AVX-512 codecs the literature describes for a reason worth writing down:
 * `vld3q_u8` de-interleaves three-byte groups on load, so the byte shuffle
 * those codecs spend an instruction on is free here, and `vqtbl4q_u8` looks up
 * all sixty-four alphabet entries in one instruction, which on x86 needs
 * AVX-512 VBMI's `vpermb` and is otherwise built out of a nibble lookup and
 * arithmetic. Forty-eight input bytes become sixty-four output bytes per
 * iteration.
 */

#include "nupp_base64.h"

#include <string.h>

static const uint8_t NUPP_BASE64_ALPHABET[65] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

size_t nuppBase64Memcpy(const uint8_t *bytes, size_t length, char *output) {
    memcpy(output, bytes, length);
    return length;
}

size_t nuppBase64EncodeScalar(const uint8_t *bytes, size_t length, char *output) {
    const uint8_t *alphabet = NUPP_BASE64_ALPHABET;
    size_t at = 0;
    size_t out = 0;

    while (at + 3 <= length) {
        const uint32_t value = ((uint32_t)bytes[at] << 16) | ((uint32_t)bytes[at + 1] << 8) | (uint32_t)bytes[at + 2];
        output[out + 0] = (char)alphabet[(value >> 18) & 0x3f];
        output[out + 1] = (char)alphabet[(value >> 12) & 0x3f];
        output[out + 2] = (char)alphabet[(value >> 6) & 0x3f];
        output[out + 3] = (char)alphabet[value & 0x3f];
        at += 3;
        out += 4;
    }

    if (length - at == 1) {
        const uint32_t value = (uint32_t)bytes[at] << 16;
        output[out + 0] = (char)alphabet[(value >> 18) & 0x3f];
        output[out + 1] = (char)alphabet[(value >> 12) & 0x3f];
        output[out + 2] = '=';
        output[out + 3] = '=';
        out += 4;
    } else if (length - at == 2) {
        const uint32_t value = ((uint32_t)bytes[at] << 16) | ((uint32_t)bytes[at + 1] << 8);
        output[out + 0] = (char)alphabet[(value >> 18) & 0x3f];
        output[out + 1] = (char)alphabet[(value >> 12) & 0x3f];
        output[out + 2] = (char)alphabet[(value >> 6) & 0x3f];
        output[out + 3] = '=';
        out += 4;
    }

    return out;
}

#if defined(__aarch64__)

#include <arm_neon.h>

int nuppBase64Vectorized(void) { return 1; }

size_t nuppBase64EncodeVector(const uint8_t *bytes, size_t length, char *output) {
    const uint8x16x4_t table = vld1q_u8_x4(NUPP_BASE64_ALPHABET);
    const uint8x16_t twoBits = vdupq_n_u8(0x03);
    const uint8x16_t fourBits = vdupq_n_u8(0x0f);
    const uint8x16_t sixBits = vdupq_n_u8(0x3f);
    size_t at = 0;
    size_t out = 0;

    for (; at + 48 <= length; at += 48, out += 64) {
        const uint8x16x3_t in = vld3q_u8(bytes + at);
        uint8x16x4_t encoded;

        encoded.val[0] = vshrq_n_u8(in.val[0], 2);
        encoded.val[1] = vorrq_u8(vshlq_n_u8(vandq_u8(in.val[0], twoBits), 4), vshrq_n_u8(in.val[1], 4));
        encoded.val[2] = vorrq_u8(vshlq_n_u8(vandq_u8(in.val[1], fourBits), 2), vshrq_n_u8(in.val[2], 6));
        encoded.val[3] = vandq_u8(in.val[2], sixBits);

        encoded.val[0] = vqtbl4q_u8(table, encoded.val[0]);
        encoded.val[1] = vqtbl4q_u8(table, encoded.val[1]);
        encoded.val[2] = vqtbl4q_u8(table, encoded.val[2]);
        encoded.val[3] = vqtbl4q_u8(table, encoded.val[3]);

        vst4q_u8((uint8_t *)output + out, encoded);
    }

    return out + nuppBase64EncodeScalar(bytes + at, length - at, output + out);
}

#else

int nuppBase64Vectorized(void) { return 0; }

size_t nuppBase64EncodeVector(const uint8_t *bytes, size_t length, char *output) {
    return nuppBase64EncodeScalar(bytes, length, output);
}

#endif
