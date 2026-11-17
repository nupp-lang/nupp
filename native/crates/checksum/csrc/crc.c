/* State conversion only. All CRC arithmetic and CPU dispatch belong to ISA-L. */
#include "nupp_crc.h"
#include "crc.h"
#include "crc64.h"
#include <limits.h>

int32_t nuppCrcUpdate(uint32_t id, int32_t reset, uint64_t words[2],
                      const uint8_t *data, size_t length)
{
    if (id < 1 || id > 4 || (reset != 0 && reset != 1) || !words ||
        length > PTRDIFF_MAX || (length && !data))
        return 1;
    const uint64_t mask = id <= 2 ? UINT32_MAX : UINT64_MAX;
    const uint64_t xorout = id == 3 ? 0 : mask;
    uint64_t state = reset ? xorout : words[0];
    /* ISCsi takes a signed int length. Bound every call before narrowing.
     * Empty updates bypass upstream: NULL is valid at this boundary only.
     */
    while (length) {
        const int count = length > INT_MAX ? INT_MAX : (int)length;
        switch (id) {
        case 1: state = crc32_gzip_refl((uint32_t)state ^ UINT32_MAX, data, count) ^ UINT32_MAX; break;
        case 2: state = crc32_iscsi((unsigned char *)data, count, (uint32_t)state); break;
        /* ISA-L normal ECMA complements both its seed and its result. */
        case 3: state = ~crc64_ecma_norm(~state, data, count); break;
        case 4: state = ~crc64_rocksoft_refl(~state, data, count); break;
        }
        data += count;
        length -= count;
    }
    words[0] = state;
    words[1] = state ^ xorout;
    return 0;
}

const char *nuppCrcLastError(void)
{
    return "invalid CRC algorithm, input, or state";
}
