/**
 * @file
 * @brief Records whether checked interop calls reach the C callee.
 *
 * The C side of cdeftest's countedBy cases: functions whose pointer
 * parameters are bounded by count parameters, as a cdef's
 * `countedBy(count)` declares them. The test builds this file into a shared
 * library and checks two things through it: that a call passes the length
 * of the span it borrows, and, through the call counter, that a call it
 * should refuse never reaches C at all.
 */

#include <stddef.h>
#include <stdint.h>

/* What countedtransform adds to each element, so an output element can be
 * told apart from the input it came from. */
#define TRANSFORM_OFFSET 10

/* The number of calls into either transform since the last reset. */
static uint64_t calls = 0;

void countedreset (void) {
  calls = 0;
}

uint64_t countedcalls (void) {
  return calls;
}

/* One count bounds both spans: output and input each hold count elements. */
void countedtransform (int32_t *output, const int32_t *input, size_t count) {
  calls += 1;

  for (size_t i = 0; i < count; ++i) {
    output[i] = input[i] + TRANSFORM_OFFSET;
  }
}

/* Each span has its own count. The output reports what arrived, as far as it
 * has room: its own count, the input's count, and the input's first element. */
void countedindependent (int32_t *output, size_t outcount, const int32_t *input,
                         size_t incount) {
  calls += 1;

  if (outcount > 0) {
    output[0] = (int32_t)outcount;
  }

  if (outcount > 1) {
    output[1] = (int32_t)incount;
  }

  if (outcount > 2 && incount > 0) {
    output[2] = input[0];
  }
}
