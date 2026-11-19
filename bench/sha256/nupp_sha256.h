/**
 * @file
 * @brief Entry point for the SHA-256 benchmark control.
 *
 * The benchmark calls the frozen control in `sha256_control.c` from
 * `implementations.lua` through the FFI.
 */

#ifndef NUPP_SHA256_H
#define NUPP_SHA256_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/**
 * @brief Writes a SHA-256 digest as 64 lowercase hexadecimal digits.
 * @param[in] bytes Input bytes, or null when length is zero.
 * @param[in] length Input size in bytes.
 * @param[out] output Buffer of at least 65 bytes, including the terminator.
 * @return True on success. A null output or a null input with nonzero
 *         length returns false.
 */
bool nuppSha256(const uint8_t *bytes, size_t length, char *output);

#endif
