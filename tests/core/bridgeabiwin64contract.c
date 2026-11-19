/**
 * @file
 * @brief Calibrates the Win64 bridge ABI guard.
 */
#include <assert.h>
#include <stdint.h>

typedef uint64_t (*Entry)(const uint64_t *, uint64_t *);

extern void nupp_core_test_abi (Entry entry, const uint64_t *packet,
                                uint64_t *output, uint64_t *report);
extern uint64_t nupp_core_test_abi_clobber (const uint64_t *packet,
                                            uint64_t *output);

static uint64_t copy (const uint64_t *packet, uint64_t *output) {
  *output = *packet;

  return 42;
}

int main (void) {
  uint64_t packet = 37, output = 0;
  uint64_t report[2] = {0, 0};
  nupp_core_test_abi(copy, &packet, &output, report);
  assert(report[0] == 42 && report[1] == 0 && output == packet);
  nupp_core_test_abi(nupp_core_test_abi_clobber, &packet, &output, report);
  assert(report[0] == 7 && report[1] == ((1U << 0) | (1U << 8)));

  return 0;
}
