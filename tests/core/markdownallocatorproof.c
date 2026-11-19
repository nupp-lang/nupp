/**
 * @file
 * @brief CBMC proof of Markdown allocation sizing and budget arithmetic.
 */

#include "proofintrinsics.h"
#include "../../native/markdown/allocationbudget.h"

/** Checks exact fit and accounting independently of the checked multiply. */
static void provedebit (void) {
  size_t payload = nondet_size();
  size_t overhead = nondet_size();
  size_t budget = nondet_size();
  size_t before = nondet_size();
  size_t total = before;
  int ok = allocationdebit(payload, overhead, budget, &total);
  __CPROVER_assert(ok == (overhead <= budget && payload <= budget - overhead),
                   "allocation succeeds exactly when the full charge fits");

  if (ok) {
    __CPROVER_assert(total >= overhead && total - overhead == payload,
                     "charge contains the exact payload and header");
    __CPROVER_assert(total <= budget, "charging cannot underflow the budget");
  }
  else {
    __CPROVER_assert(total == before, "failure leaves the charge untouched");
  }
}

/** Checks the production entry for arbitrary dimensions and oversized input. */
static void provecharge (void) {
  size_t count = nondet_size();
  size_t width = nondet_size();
  size_t overhead = nondet_size();
  size_t budget = nondet_size();
  size_t before = nondet_size();
  size_t total = before;
  int ok = allocationcharge(count, width, overhead, budget, &total);

  if (ok) {
    __CPROVER_assert(total >= overhead && total <= budget,
                     "an accepted allocation can be charged safely");
  }
  else {
    __CPROVER_assert(total == before,
                     "rejected dimensions leave charge intact");
  }

  total = before;
  __CPROVER_assume(width > 1);
  __CPROVER_assert(!allocationcharge(SIZE_MAX, width, 0, SIZE_MAX, &total) &&
                       total == before,
                   "even unlimited budget cannot admit an overflowing product");
}

int main (void) {
  provedebit();
  provecharge();

  return 0;
}
