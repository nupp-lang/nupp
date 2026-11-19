/**
 * @file
 * @brief Sizing and budget arithmetic for Markdown's tracked allocations.
 */

#ifndef NUPP_MARKDOWN_ALLOCATION_BUDGET_H
#define NUPP_MARKDOWN_ALLOCATION_BUDGET_H

#include <stddef.h>
#include <stdint.h>

/** Computes the charge for a known payload and header within the budget.
 * Returns 0 with total untouched when the budget cannot cover the charge.
 */
static inline int allocationdebit (size_t bytes, size_t overhead,
                                   size_t remaining, size_t *total) {
  if (bytes > remaining || overhead > remaining - bytes) {
    return 0;
  }

  *total = bytes + overhead;

  return 1;
}

/** Checks the payload multiplication before computing the charge. */
static inline int allocationcharge (size_t count, size_t width, size_t overhead,
                                    size_t remaining, size_t *total) {
  size_t bytes;

#if defined(__GNUC__) || defined(__clang__)

  if (__builtin_mul_overflow(count, width, &bytes)) {
    return 0;
  }

#else

  if (width && count > SIZE_MAX / width) {
    return 0;
  }

  bytes = count * width;

#endif

  return allocationdebit(bytes, overhead, remaining, total);
}

#endif
