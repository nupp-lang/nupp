/* The trailer digest, declared for the one C caller that computes it.
 *
 * A stamped binary checks the payload appended to it before handing a byte to
 * Lua, on every run. That check is an integrity check and nothing more: the
 * file is unsigned, only eight bytes of the digest are recorded, and anyone who
 * can rewrite the payload can rewrite the trailer beside it. What it catches is
 * a truncated download or a damaged file, and it says so.
 *
 * So it is XXH64 rather than a cryptographic hash, which for a ten megabyte
 * payload is the difference between a millisecond and a twentieth of a second
 * on every invocation. `nupp.data.sha256` is elsewhere and is Nupp; the
 * playground's bundle check, which is authenticity rather than integrity, is
 * `crypto.subtle` in `editors/playground/src/wasm-runtime.js`, where the bytes
 * already are.
 */

#ifndef NUPP_XXH64_H
#define NUPP_XXH64_H

#include <stddef.h>
#include <stdint.h>

/* XXH64 of `length` bytes under seed zero, reading the input little-endian on
 * every host so a binary stamped on one machine verifies on another. */
uint64_t nuppXxh64(const uint8_t *bytes, size_t length);

#endif
