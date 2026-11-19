/**
 * @file
 * @brief Exercises importing inline functions and macros through a C bridge.
 *
 * Test fixture for nupp import-c's bridges: the two kinds of header function
 * a foreign call cannot reach directly, beside one it can. A static inline has
 * no symbol in any library, and a function-like macro is not a function at
 * all, so import-c skips both unless it is asked for a bridge, a small C
 * file that wraps each in an exported function (importctest).
 */

#ifndef NUPP_BRIDGE_H
#define NUPP_BRIDGE_H

#include <stdint.h>

static inline int32_t nupp_bridge_scale (int32_t value) {
  return value * 3;
}

static inline void nupp_bridge_store (int32_t *slot, int32_t value) {
  *slot = value;
}

/* An ordinary declaration after the inline bodies, which the import must
 * still see: a body is not allowed to swallow the declaration after it. */
int32_t nupp_bridge_exported (int32_t value);

/* Macro bridges, one with a result and one without. */
#define NUPP_BRIDGE_CLAMP(value, low, high)                                    \
  ((value) < (low) ? (low) : ((value) > (high) ? (high) : (value)))
#define NUPP_BRIDGE_IGNORE(value) ((void)(value))

#endif
