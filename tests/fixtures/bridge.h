#ifndef NUPP_BRIDGE_H
#define NUPP_BRIDGE_H

#include <stdint.h>

static inline int32_t nupp_bridge_scale(int32_t value)
{
    return value * 3;
}

static inline void nupp_bridge_store(int32_t *slot, int32_t value)
{
    *slot = value;
}

int32_t nupp_bridge_exported(int32_t value);

#define NUPP_BRIDGE_CLAMP(value, low, high) \
    ((value) < (low) ? (low) : ((value) > (high) ? (high) : (value)))
#define NUPP_BRIDGE_IGNORE(value) ((void)(value))

#endif
