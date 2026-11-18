#include "nupp_crc.h"
#include <assert.h>
#include <stdio.h>

int main(void)
{
  const uint64_t vectors[] = {0, 0xcbf43926, 0xe3069283, 0x6c40df5f0b497347,
                              0xae8b14860a799888};
  for (unsigned id = 1; id <= 4; ++id) {
    uint64_t words[2];
    assert(!nuppCrcUpdate(id, 1, words, (const uint8_t *)"1234", 4));
    uint64_t copy[] = {words[0], words[1]};
    assert(!nuppCrcUpdate(id, 0, words, NULL, 0));
    assert(words[0] == copy[0] && words[1] == copy[1]);
    assert(!nuppCrcUpdate(id, 0, copy, (const uint8_t *)"56789", 5));
    assert(copy[1] == vectors[id]);
  }
  puts("relocated shared CRC bundle: pass");
  return 0;
}
