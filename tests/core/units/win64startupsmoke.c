/**
 * @file
 * @brief Links the Win64 startup entry against the transport and guard.
 */
#define NUPP_CORE_GUARD 1
#define wmain bootstrap_wmain
#include "../../../native/corebridge/main.c"
#undef wmain

#include <assert.h>

extern uint64_t nupp_core_win64_entry (const uint64_t *packet, uint64_t *out);

int main (void) {
  unsigned char *code = (unsigned char *)(uintptr_t)nupp_core_win64_entry;
  DWORD64 base;
  PRUNTIME_FUNCTION range =
      RtlLookupFunctionEntry((uintptr_t)code + 4, &base, NULL);
  assert(range && base + range->BeginAddress == (uintptr_t)code);
  size_t instructions = range->EndAddress - range->BeginAddress;
  assert(!strcmp((const char *)(code + instructions), "nupp_core_page_size"));

  struct bundle program = {
      .codebytes = instructions + sizeof("nupp_core_page_size"),
      .outputwords = 1,
  };
  struct regions regions = {.code = code};
  uint64_t input = 0, output = 0, status;
  assert(!enter(&program, &regions, &input, 1, &output, &status));
  assert(!status && output == win64_page_size());

  input = 17;
  assert(!enter(&program, &regions, &input, 1, &output, &status));
  assert(!status && output == 17);

  output = 0;
  uint64_t bad_packet[PACKET_FIELDS] = {
      [PACKET_INPUT_WORDS] = 1,
      [PACKET_IMPORT_COUNT] = IMPORT_COUNT - 1,
  };
  assert(!callentry(nupp_core_win64_entry, bad_packet, &output, &status));
  assert(status == 4 && !output);

  return 0;
}
