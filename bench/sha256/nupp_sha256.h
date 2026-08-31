/* The benchmark control's digest, declared for the two files that name it.
 *
 * Nothing in Nupp builds this. `nupp.data.sha256` is `nupp.data.digest` now, in
 * Nupp, and the check a stamped binary runs before trusting its payload is
 * XXH64, in the Rust base provider. What is left here is the frozen control
 * `sha256_control.c` defines and `implementations.lua` calls through the FFI.
 */

#ifndef NUPP_SHA256_H
#define NUPP_SHA256_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Writes the digest of `length` bytes as 64 lowercase hexadecimal digits and a
 * terminator. `output` must have room for 65 bytes. */
bool nuppSha256(const uint8_t *bytes, size_t length, char *output);

#endif
