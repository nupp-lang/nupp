/* The C that was `nupp.data.sha256`, kept as this benchmark's control.
 *
 * Nothing in Nupp builds this any more. It lived in the native provider until
 * `nupp.data.digest` replaced it, and it is here for the same reason
 * `legacy.lua` is: a port is only worth what it can be measured against, and
 * the thing to measure against is the implementation that was actually there.
 *
 * Frozen, like `legacy.lua`. Do not fix it and do not make it faster. Its whole
 * value is being exactly what was replaced, and it goes when this benchmark
 * does.
 */

#include "nupp_sha256.h"

#include <string.h>

/* FIPS 180-4, written the way the standard states it: the eight starting words
 * are the fractional parts of the square roots of the first eight primes, and
 * the sixty-four constants those of the cube roots of the first sixty-four. */
static const uint32_t ROUND_CONSTANTS[64] = {
    0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u,
    0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
    0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u,
    0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
    0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu,
    0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
    0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u,
    0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
    0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u,
    0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
    0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u,
    0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
    0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u,
    0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
    0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u,
    0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u,
};

static uint32_t rotate_right(uint32_t value, unsigned count) {
    return (value >> count) | (value << (32 - count));
}

static void sha256_block(uint32_t state[8], const uint8_t block[64]) {
    uint32_t schedule[64];
    uint32_t a, b, c, d, e, f, g, h;
    unsigned round;

    for (round = 0; round < 16; round++) {
        schedule[round] = ((uint32_t)block[round * 4] << 24)
            | ((uint32_t)block[round * 4 + 1] << 16)
            | ((uint32_t)block[round * 4 + 2] << 8)
            | (uint32_t)block[round * 4 + 3];
    }
    for (round = 16; round < 64; round++) {
        uint32_t low = schedule[round - 15];
        uint32_t high = schedule[round - 2];
        uint32_t mixLow = rotate_right(low, 7) ^ rotate_right(low, 18) ^ (low >> 3);
        uint32_t mixHigh = rotate_right(high, 17) ^ rotate_right(high, 19) ^ (high >> 10);
        schedule[round] = schedule[round - 16] + mixLow + schedule[round - 7] + mixHigh;
    }

    a = state[0]; b = state[1]; c = state[2]; d = state[3];
    e = state[4]; f = state[5]; g = state[6]; h = state[7];
    for (round = 0; round < 64; round++) {
        uint32_t sigmaOne = rotate_right(e, 6) ^ rotate_right(e, 11) ^ rotate_right(e, 25);
        uint32_t choose = (e & f) ^ (~e & g);
        uint32_t first = h + sigmaOne + choose + ROUND_CONSTANTS[round] + schedule[round];
        uint32_t sigmaZero = rotate_right(a, 2) ^ rotate_right(a, 13) ^ rotate_right(a, 22);
        uint32_t majority = (a & b) ^ (a & c) ^ (b & c);
        uint32_t second = sigmaZero + majority;
        h = g; g = f; f = e;
        e = d + first;
        d = c; c = b; b = a;
        a = first + second;
    }
    state[0] += a; state[1] += b; state[2] += c; state[3] += d;
    state[4] += e; state[5] += f; state[6] += g; state[7] += h;
}

static void sha256(const uint8_t *data, size_t length, uint8_t digest[32]) {
    uint32_t state[8] = {
        0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
        0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u,
    };
    uint8_t tail[128];
    size_t whole = length / 64;
    size_t rest = length % 64;
    size_t padded;
    uint64_t bits = (uint64_t)length * 8;
    size_t at;

    for (at = 0; at < whole; at++) {
        sha256_block(state, data + at * 64);
    }
    if (rest != 0) {
        memcpy(tail, data + whole * 64, rest);
    }
    tail[rest] = 0x80;
    /* One padded block when the length and its eight-byte tally still fit, two
     * when they do not. */
    padded = rest + 1 <= 56 ? 64 : 128;
    memset(tail + rest + 1, 0, padded - rest - 1 - 8);
    for (at = 0; at < 8; at++) {
        tail[padded - 1 - at] = (uint8_t)(bits >> (8 * at));
    }
    sha256_block(state, tail);
    if (padded == 128) {
        sha256_block(state, tail + 64);
    }
    for (at = 0; at < 8; at++) {
        digest[at * 4] = (uint8_t)(state[at] >> 24);
        digest[at * 4 + 1] = (uint8_t)(state[at] >> 16);
        digest[at * 4 + 2] = (uint8_t)(state[at] >> 8);
        digest[at * 4 + 3] = (uint8_t)state[at];
    }
}

/* Writes the digest of `length` bytes as 64 lowercase hex digits and a
 * terminator, into storage the caller sized. */
bool nuppSha256(const uint8_t *bytes, size_t length, char *output) {
    static const char HEX[] = "0123456789abcdef";
    uint8_t digest[32];
    size_t at;
    if (output == NULL || (bytes == NULL && length != 0)) {
        return false;
    }
    sha256(bytes, length, digest);
    for (at = 0; at < 32; at++) {
        output[at * 2] = HEX[digest[at] >> 4];
        output[at * 2 + 1] = HEX[digest[at] & 15];
    }
    output[64] = '\0';
    return true;
}
