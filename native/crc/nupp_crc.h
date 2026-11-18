#ifndef NUPP_CRC_H
#define NUPP_CRC_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* IDs: 1 IEEE, 2 Castagnoli, 3 ECMA-182 (normal), 4 NVME (reflected).
 * words[0] is the raw register; words[1] is a non-consuming final XOR.
 * reset=1 starts a stream; reset=0 resumes words[0]. No pointers are kept.
 * words covers two writable uint64_t, disjoint from data's length bytes.
 * NULL data is allowed only for an empty update. Invalid calls change nothing.
 */
int32_t nuppCrcUpdate(uint32_t id, int32_t reset, uint64_t words[2],
                      const uint8_t *data, size_t length);
const char *nuppCrcLastError(void);
#ifdef __cplusplus
}
#endif
#endif
