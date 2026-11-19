/**
 * @file
 * @brief C interface for resumable CRC calculations using ISA-L.
 *
 * The C interface of Nupp's CRC adapter (crc.c) over the pinned ISA-L CRC
 * routines, built into the nupp_crc library that crccodec.nupp calls. It
 * keeps a stream's raw register between calls, so a checksum can be resumed
 * where ISA-L's own interface takes and answers only finished checksums.
 */

#ifndef NUPP_CRC_H
#define NUPP_CRC_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** IDs: 1 IEEE, 2 Castagnoli, 3 ECMA-182 (normal), 4 NVME (reflected).
 * words[0] is the raw register; words[1] is a non-consuming final XOR.
 * reset=1 starts a stream; reset=0 resumes words[0]. No pointers are kept.
 * words covers two writable uint64_t, disjoint from data's length bytes.
 * NULL data is allowed only for an empty update. Invalid calls change nothing.
 * Answers zero, or nonzero for an invalid call.
 */
int32_t nuppCrcUpdate (uint32_t id, int32_t reset, uint64_t words[2],
                       const uint8_t *data, size_t length);

/** The message for an invalid call, which is the only failure. */
const char *nuppCrcLastError (void);

#ifdef __cplusplus
}
#endif

#endif
