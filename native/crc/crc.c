/* The adapter between Nupp's resumable CRC state and ISA-L, which crccodec.nupp
 * calls through nupp_crc.h. It converts state only: all CRC arithmetic and CPU
 * dispatch belong to ISA-L. ISA-L takes and answers finalized checksums, while
 * Nupp keeps the raw register so a stream can be resumed. */
#include "nupp_crc.h"

#include "crc.h"
#include "crc64.h"

#include <limits.h>

/* The algorithm ids nupp_crc.h documents. */
enum algorithm {
  CRC32_IEEE = 1,
  CRC32_CASTAGNOLI = 2,
  CRC64_ECMA_182 = 3,
  CRC64_NVME = 4,
};

/* What each algorithm XORs into its register to finish a checksum. It is also
 * each one's initial register. */
static uint64_t final_xor (enum algorithm id) {
  switch (id) {
    case CRC32_IEEE:
    case CRC32_CASTAGNOLI:
      return UINT32_MAX;
    case CRC64_ECMA_182:
      return 0;
    case CRC64_NVME:
      break;
  }

  return UINT64_MAX;
}

static int valid (uint32_t id, int32_t reset, const uint64_t *words,
                  const uint8_t *data, size_t length) {
  /* NULL data is valid at this boundary for an empty update only. */
  return id >= CRC32_IEEE && id <= CRC64_NVME && (reset == 0 || reset == 1) &&
         words && length <= PTRDIFF_MAX && (data || !length);
}

/* Continues the raw register over count bytes. */
static uint64_t update (enum algorithm id, uint64_t state, const uint8_t *data,
                        int count) {
  switch (id) {
    case CRC32_IEEE:
      return crc32_gzip_refl((uint32_t)state ^ UINT32_MAX, data, count) ^
             UINT32_MAX;
    case CRC32_CASTAGNOLI:
      return crc32_iscsi((unsigned char *)data, count, (uint32_t)state);
    /* ISA-L's normal ECMA complements both its seed and its result. */
    case CRC64_ECMA_182:
      return ~crc64_ecma_norm(~state, data, count);
    case CRC64_NVME:
      return ~crc64_rocksoft_refl(~state, data, count);
  }

  return state;
}

int32_t nuppCrcUpdate (uint32_t id, int32_t reset, uint64_t words[2],
                       const uint8_t *data, size_t length) {
  if (!valid(id, reset, words, data, length)) {
    return 1;
  }

  const uint64_t xorout = final_xor(id);
  uint64_t state = reset ? xorout : words[0];

  /* iSCSI takes a signed int length, so feed every algorithm at most
   * INT_MAX bytes at a time. An empty update never reaches ISA-L. */
  while (length) {
    const int count = length > INT_MAX ? INT_MAX : (int)length;
    state = update(id, state, data, count);
    data += count;
    length -= count;
  }

  words[0] = state;
  words[1] = state ^ xorout;

  return 0;
}

const char *nuppCrcLastError (void) {
  return "invalid CRC algorithm, input, or state";
}
