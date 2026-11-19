/* The C side of the core's foreign-call tests: a library the guest and unit
 * runners build as libnuppbridgefixture.dylib, so a cdef can reach a real
 * native function. It is a test fixture, not a provider wrapper.
 *
 * The two functions are the same function under two names, because the
 * loader units declare each with a different spelling of the library path,
 * "@lib/..." and "@/lib/...", and both must resolve to this file. */

#include <stdint.h>

/* An answer no argument can produce by accident, so a call that passes the
 * wrong words or drops one shows in the result. */
uint64_t nuppbridgefixture (uint64_t left, uint64_t right) {
  return left ^ right;
}

/* The same answer, for the declaration that names the library "@/lib/...". */
uint64_t nuppbridgeslash (uint64_t left, uint64_t right) {
  return left ^ right;
}
