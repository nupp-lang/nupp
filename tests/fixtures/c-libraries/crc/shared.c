/**
 * @file
 * @brief Exercises loading the relocated shared CRC adapter.
 *
 * A consumer of the relocated shared CRC library, only in tests.
 * .github/scripts/test-crc-isal.sh moves the installed bundle after linking
 * and runs this against it, so it passes only when the library loads from
 * its new place. It checks each algorithm's check value, split across a
 * resumed stream with an empty update between.
 */

#include "nuppcrc.h"

#include <assert.h>
#include <stdio.h>

/* The algorithm ids nuppcrc.h documents. */
enum { FIRST_ALGORITHM = 1, LAST_ALGORITHM = 4 };

int main (void) {
  /* Each algorithm's CRC of "123456789", indexed by its id. */
  const uint64_t vectors[] = {0, 0xcbf43926, 0xe3069283, 0x6c40df5f0b497347,
                              0xae8b14860a799888};

  for (unsigned id = FIRST_ALGORITHM; id <= LAST_ALGORITHM; ++id) {
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
