/* The benchmark control's base64 encoder, declared for the files that name it.
 *
 * Nothing in Nupp builds this. It exists so that `src/base64bench.nupp` has a
 * ceiling to be measured against: the same encoding written scalar, and written
 * the way the vectorized codecs in the literature write it.
 */

#ifndef NUPP_BASE64_H
#define NUPP_BASE64_H

#include <stddef.h>
#include <stdint.h>

/* Encodes `length` bytes as standard padded base64 into `output`, which must
 * have room for `4 * ((length + 2) / 3)` bytes. Returns bytes written. */
size_t nuppBase64EncodeScalar(const uint8_t *bytes, size_t length, char *output);

/* The same encoding, vectorized where the build has a register file for it,
 * and the scalar encoder verbatim where it does not. */
size_t nuppBase64EncodeVector(const uint8_t *bytes, size_t length, char *output);

/* Whether `nuppBase64EncodeVector` is actually vectorized in this build, so a
 * benchmark reports a measured ceiling rather than the scalar one twice. */
int nuppBase64Vectorized(void);

/* The yardstick the literature uses: a plain copy of the same input. Not an
 * encoder, and deliberately so -- it is the floor any codec is measured
 * against. Returns bytes copied. */
size_t nuppBase64Memcpy(const uint8_t *bytes, size_t length, char *output);

#endif
