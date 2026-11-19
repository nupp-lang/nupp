/**
 * @file
 * @brief Calls an emitted entry through the Win64 ABI guard.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <assert.h>
#include <stdint.h>

typedef uint64_t (*Entry)(const uint64_t *, uint64_t *);

extern uint64_t nupp_core_win64_entry (const uint64_t *packet, uint64_t *out);
extern void nupp_core_test_abi (Entry entry, const uint64_t *packet,
                                uint64_t *output, uint64_t *report);

int main (void) {
  enum { INPUT = 9, INPUT_WORDS, OUTPUT_WORDS, PACKET_WORDS };

  uint64_t input = 11, output = 0;
  uint64_t packet[PACKET_WORDS] = {
      [0] = 1,
      [INPUT] = (uintptr_t)&input,
      [INPUT_WORDS] = 1,
      [OUTPUT_WORDS] = 1,
  };
  uint64_t report[2];
  nupp_core_test_abi(nupp_core_win64_entry, packet, &output, report);
  assert(report[0] == 0 && report[1] == 0 && output == UINT64_C(0x10000000e));

  packet[INPUT_WORDS] = 0;
  output = 0;
  nupp_core_test_abi(nupp_core_win64_entry, packet, &output, report);
  assert(report[0] == 3 && report[1] == 0 && output == 0);

  DWORD64 base;
  DWORD64 entry = (uintptr_t)nupp_core_win64_entry;
  PRUNTIME_FUNCTION function = RtlLookupFunctionEntry(entry + 4, &base, NULL);
  assert(function && base + function->BeginAddress == entry);

  return 0;
}
