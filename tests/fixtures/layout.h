/* Test fixture for nupp import-c: structs whose C layout a rendering that
 * names only their fields would get wrong, beside structs it gets right. */
#ifndef NUPP_LAYOUT_H
#define NUPP_LAYOUT_H

#include <stdbool.h>
#include <stdint.h>

/* An anonymous union member promotes its fields; dropping it loses bytes. */
struct layout_tagged {
    int32_t tag;
    union {
        int32_t i;
        double d;
    };
    int32_t after;
};

/* Unnamed bitfields are padding, and a zero-width one starts a new unit. */
struct layout_bits {
    uint32_t a : 3;
    uint32_t : 0;
    uint32_t b : 3;
    uint32_t : 5;
    uint32_t c : 4;
};

/* Attributes that move fields. */
struct __attribute__((packed)) layout_wire {
    uint8_t kind;
    uint32_t len;
};

struct layout_aligned {
    int32_t a __attribute__((aligned(16)));
    int32_t b;
};

typedef int32_t layout_wide_int __attribute__((aligned(8)));

struct layout_typedef_aligned {
    int32_t a;
    layout_wide_int b;
};

#pragma pack(push, 1)
struct layout_pragma_packed {
    uint8_t kind;
    uint32_t len;
};
#pragma pack(pop)

/* Types that are not their element arrays. */
typedef float layout_v4sf __attribute__((vector_size(16)));

struct layout_holds_vector {
    layout_v4sf v;
};

float layout_vector_first(layout_v4sf v);
double _Complex layout_complex_make(double re, double im);
double layout_complex_real(double _Complex z);

/* A bool bitfield reads back as a boolean. */
struct layout_flags {
    bool on : 1;
    int32_t level : 4;
};

/* An incomplete type is a handle, never a value. */
typedef struct layout_opaque layout_opaque;
layout_opaque *layout_opaque_new(void);

/* These import, and lay out exactly as C lays them out. */
struct layout_inner {
    int8_t a;
    double b;
};

typedef struct {
    bool flag;
    struct layout_inner inner;
    int32_t (*row)[4];
    float matrix[2][3];
    uint16_t mode : 3;
    uint16_t level : 5;
    int64_t id;
    void (*callback)(int32_t value);
    struct layout_inner pair[2];
} layout_mixed;

union layout_value {
    int32_t i;
    double d;
    uint8_t bytes[12];
};

void layout_use(layout_mixed *mixed, union layout_value *value);

#endif
