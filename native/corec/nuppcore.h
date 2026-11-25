/* nuppcore.h: what the C the native core is emitted as is written against.
   The Nupp intrinsics (nupp.runtime.vm.intrinsics) as inline functions, the
   frame-slot and bytecode contracts, and the handler conventions. */
#ifndef NUPPCORE_H
#define NUPPCORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#if defined(__clang__) || (defined(__GNUC__) && __GNUC__ >= 15)
#define NUPP_MUSTTAIL __attribute__((musttail))
#else
#define NUPP_MUSTTAIL
#endif

/* A handler saves no register for the calls only its slow paths make. */
#if defined(__clang__) && __has_attribute(preserve_none)
#define NUPP_HANDLER __attribute__((preserve_none))
#else
#define NUPP_HANDLER
#endif

typedef uint64_t(NUPP_HANDLER *nupp_handler)(void *pc, void *regs, void *ints,
                                             void *floats, void *ctx,
                                             void *frame);

/* Memory: unaligned and type-blind, as the machine's loads and stores are. */
#define NUPP_AT(base, offset) ((uint8_t *)(base) + (offset))

static inline int64_t native_load8 (const void *base, int64_t offset) {
  uint8_t v;
  __builtin_memcpy(&v, NUPP_AT(base, offset), 1);

  return v;
}

static inline int64_t native_load16 (const void *base, int64_t offset) {
  uint16_t v;
  __builtin_memcpy(&v, NUPP_AT(base, offset), 2);

  return v;
}

static inline int64_t native_load32 (const void *base, int64_t offset) {
  int32_t v;
  __builtin_memcpy(&v, NUPP_AT(base, offset), 4);

  return v;
}

static inline uint64_t native_load64 (const void *base, int64_t offset) {
  uint64_t v;
  __builtin_memcpy(&v, NUPP_AT(base, offset), 8);

  return v;
}

static inline int64_t native_loadIndex (const void *base, int64_t offset) {
  return (int64_t)native_load64(base, offset);
}

static inline void *native_loadPointer (const void *base, int64_t offset) {
  return (void *)(uintptr_t)native_load64(base, offset);
}

static inline double native_loadFloat (const void *base, int64_t offset) {
  double v;
  __builtin_memcpy(&v, NUPP_AT(base, offset), 8);

  return v;
}

static inline void native_store8 (void *base, int64_t offset, uint64_t value) {
  uint8_t v = (uint8_t)value;
  __builtin_memcpy(NUPP_AT(base, offset), &v, 1);
}

static inline void native_store16 (void *base, int64_t offset, uint64_t value) {
  uint16_t v = (uint16_t)value;
  __builtin_memcpy(NUPP_AT(base, offset), &v, 2);
}

static inline void native_store32 (void *base, int64_t offset, int64_t value) {
  int32_t v = (int32_t)value;
  __builtin_memcpy(NUPP_AT(base, offset), &v, 4);
}

static inline void native_store64 (void *base, int64_t offset, uint64_t value) {
  __builtin_memcpy(NUPP_AT(base, offset), &value, 8);
}

static inline void native_storeIndex (void *base, int64_t offset,
                                      int64_t value) {
  native_store64(base, offset, (uint64_t)value);
}

static inline void native_storePointer (void *base, int64_t offset,
                                        void *value) {
  native_store64(base, offset, (uint64_t)(uintptr_t)value);
}

static inline void native_storeFloat (void *base, int64_t offset,
                                      double value) {
  __builtin_memcpy(NUPP_AT(base, offset), &value, 8);
}

/* Floats and their bits. */
static inline uint64_t native_bits (double value) {
  uint64_t v;
  __builtin_memcpy(&v, &value, 8);

  return v;
}

static inline double native_fromBits (uint64_t value) {
  double v;
  __builtin_memcpy(&v, &value, 8);

  return v;
}

#define native_floatBits native_bits
#define native_floatFromBits native_fromBits
#define native_floor __builtin_floor
#define native_ceil __builtin_ceil
#define native_sqrt __builtin_sqrt
#define native_sqrtFloat __builtin_sqrt
#define native_roundFloat __builtin_nearbyint
#define native_fma __builtin_fma
#define native_fmaFloat __builtin_fma

/* Conversions saturate, as the machine's do: NaN is zero. */
static inline int64_t native_toInt (double value) {
  if (value != value) {
    return 0;
  }

  if (value >= 9223372036854775807.0) {
    return INT64_MAX;
  }

  if (value <= -9223372036854775808.0) {
    return INT64_MIN;
  }

  return (int64_t)value;
}

static inline uint64_t native_unsignedInt (double value) {
  if (value != value || value <= 0.0) {
    return 0;
  }

  if (value >= 18446744073709551615.0) {
    return UINT64_MAX;
  }

  return (uint64_t)value;
}

/* Integers. */
static inline uint64_t native_unsignedMulHigh (uint64_t a, uint64_t b) {
  return (uint64_t)(((unsigned __int128)a * b) >> 64);
}

static inline uint64_t native_signedMulHigh (int64_t a, int64_t b) {
  return (uint64_t)(((__int128)a * b) >> 64);
}

static inline int64_t native_signedQuotient (int64_t a, int64_t b) {
  if (b == -1) {
    return (int64_t)(0 - (uint64_t)a);
  }

  return a / b;
}

static inline uint64_t native_popcount (uint64_t value) {
  return (uint64_t)__builtin_popcountll(value);
}

/* Lua's floor division and modulo of signed integers; a zero divisor is the
   caller's to exclude. */
static inline int64_t nupp_floordiv (int64_t a, int64_t b) {
  int64_t q = native_signedQuotient(a, b);
  int64_t r = (int64_t)((uint64_t)a - (uint64_t)q * (uint64_t)b);

  if (r != 0 && (r ^ b) < 0) {
    q -= 1;
  }

  return q;
}

static inline int64_t nupp_floormod (int64_t a, int64_t b) {
  int64_t r = b == -1 ? 0 : a % b;

  if (r != 0 && (r ^ b) < 0) {
    r += b;
  }

  return r;
}

/* A symbol of a library the runtime opens itself: `@/...` beside the
   runtime's artifact, any other name as the dynamic loader finds it. */
void *nupp_resolve (const char *library, const char *symbol);

/* What a struct the compiler lays out must be in C. */
#define NUPP_SIZE(type, bytes)                                                 \
  _Static_assert(sizeof(type) == (bytes), #type " size")
#define NUPP_OFFSET(type, field, at)                                           \
  _Static_assert(offsetof(type, field) == (at), #type "." #field)

/* The bytecode a handler reads, from its instruction pointer. */
static inline int64_t program_readByte (const void *code, int64_t offset) {
  return native_load8(code, offset);
}

static inline int64_t program_readSigned32 (const void *code, int64_t offset) {
  return native_load32(code, offset);
}

static inline uint64_t program_readWord (const void *code, int64_t offset) {
  return native_load64(code, offset);
}

/* A frame's register windows, by slot. */
static inline uint64_t slots_readValue (void *frame, void *window,
                                        int64_t slot) {
  (void)frame;

  return native_load64(window, slot * 8);
}

static inline void slots_writeValue (void *frame, void *window, int64_t slot,
                                     uint64_t value) {
  (void)frame;
  native_store64(window, slot * 8, value);
}

/* The next instruction's handler, through the context's dispatch table. */
#define NUPP_DISPATCH_TABLE 40
#define NUPP_DISPATCH(pc, regs, ints, floats, ctx, frame)                      \
  (((nupp_handler *)native_loadPointer(                                        \
      (ctx), NUPP_DISPATCH_TABLE))[*(const uint8_t *)(pc)](                    \
      (pc), (regs), (ints), (floats), (ctx), (frame)))

#endif
