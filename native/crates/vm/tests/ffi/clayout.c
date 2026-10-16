/* Native oracle for C layouts and call mappings on the VM: bitfields, pointer,
 * union, fixed-array and function-pointer fields, counted pointers and out
 * parameters. The C compiler lays these structs out; the VM test lays out the
 * same declarations and both sides read what the other wrote. No VM code lives
 * here. */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#define API __declspec(dllexport)
#else
#define API __attribute__((visibility("default")))
#endif

struct clayout_flags {
    uint32_t offset;
    bool missing : 1;
    bool type_colon : 1;
    bool break_op : 1;
    uint16_t mode : 3;
    uint16_t level : 5;
    int32_t delta : 4;
    uint64_t wide : 40;
    int64_t span : 20;
    uint8_t tail;
};

/* Every member of a struct of this shape, by its declaration position. */
API int64_t clayout_flags_get(const struct clayout_flags *f, int32_t which) {
    switch (which) {
    case 1: return f->offset;
    case 2: return f->missing;
    case 3: return f->type_colon;
    case 4: return f->break_op;
    case 5: return f->mode;
    case 6: return f->level;
    case 7: return f->delta;
    case 8: return (int64_t)f->wide;
    case 9: return f->span;
    case 10: return f->tail;
    default: return -9999;
    }
}

API void clayout_flags_set(struct clayout_flags *f, int32_t which, int64_t value) {
    switch (which) {
    case 1: f->offset = (uint32_t)value; break;
    case 2: f->missing = value != 0; break;
    case 3: f->type_colon = value != 0; break;
    case 4: f->break_op = value != 0; break;
    case 5: f->mode = (uint16_t)value; break;
    case 6: f->level = (uint16_t)value; break;
    case 7: f->delta = (int32_t)value; break;
    case 8: f->wide = (uint64_t)value; break;
    case 9: f->span = value; break;
    case 10: f->tail = (uint8_t)value; break;
    default: break;
    }
}

API uint64_t clayout_flags_size(void) { return sizeof(struct clayout_flags); }
API uint64_t clayout_flags_align(void) { return _Alignof(struct clayout_flags); }
API uint64_t clayout_flags_tail_offset(void) { return offsetof(struct clayout_flags, tail); }

/* Twenty-three one-bit flags beside a word: four bytes of flags, not 23. */
struct clayout_marks {
    uint32_t offset;
    bool f1 : 1; bool f2 : 1; bool f3 : 1; bool f4 : 1; bool f5 : 1; bool f6 : 1;
    bool f7 : 1; bool f8 : 1; bool f9 : 1; bool f10 : 1; bool f11 : 1; bool f12 : 1;
    bool f13 : 1; bool f14 : 1; bool f15 : 1; bool f16 : 1; bool f17 : 1; bool f18 : 1;
    bool f19 : 1; bool f20 : 1; bool f21 : 1; bool f22 : 1; bool f23 : 1;
};
API uint64_t clayout_marks_size(void) { return sizeof(struct clayout_marks); }
API int32_t clayout_marks_count(const struct clayout_marks *m) {
    return m->f1 + m->f2 + m->f3 + m->f4 + m->f5 + m->f6 + m->f7 + m->f8 + m->f9 + m->f10 + m->f11 +
           m->f12 + m->f13 + m->f14 + m->f15 + m->f16 + m->f17 + m->f18 + m->f19 + m->f20 +
           m->f21 + m->f22 + (m->f23 ? 100 : 0);
}

union clayout_value {
    int32_t i;
    double d;
    uint8_t bytes[12];
};

struct clayout_inner {
    int8_t a;
    double b;
};

struct clayout_node {
    struct clayout_node *next;
    int32_t value;
};

/* Pointer, nested union, fixed-array, array-of-struct and callback fields. */
struct clayout_mixed {
    bool flag;
    struct clayout_inner inner;
    union clayout_value value;
    float matrix[6];
    struct clayout_inner pair[2];
    struct clayout_node *head;
    int32_t (*callback)(int32_t);
    uint16_t mode : 3;
    uint16_t level : 5;
    int64_t id;
};

API uint64_t clayout_mixed_size(void) { return sizeof(struct clayout_mixed); }
API uint64_t clayout_mixed_align(void) { return _Alignof(struct clayout_mixed); }
API uint64_t clayout_mixed_offset(int32_t which) {
    switch (which) {
    case 1: return offsetof(struct clayout_mixed, flag);
    case 2: return offsetof(struct clayout_mixed, inner);
    case 3: return offsetof(struct clayout_mixed, value);
    case 4: return offsetof(struct clayout_mixed, matrix);
    case 5: return offsetof(struct clayout_mixed, pair);
    case 6: return offsetof(struct clayout_mixed, head);
    case 7: return offsetof(struct clayout_mixed, callback);
    case 8: return offsetof(struct clayout_mixed, id);
    default: return 9999;
    }
}

/* What C reads of a mixed struct the VM filled: the walk of its list, its
 * callback's answer, its union's int, and every scalar weighed by position. */
API int64_t clayout_mixed_read(const struct clayout_mixed *m) {
    int64_t total = 0;
    for (const struct clayout_node *node = m->head; node; node = node->next) {
        total += node->value;
    }
    total += m->callback ? m->callback(5) : 0;
    total += m->value.i;
    total += m->flag ? 1000 : 0;
    total += (int64_t)(m->matrix[5] * 10);
    total += m->pair[1].a;
    total += m->mode * 10000 + m->level * 100000;
    total += m->id;
    return total;
}

static struct clayout_node clayout_static_node = {NULL, 77};
/* C writes a pointer the VM did not store. */
API void clayout_mixed_link_static(struct clayout_mixed *m) { m->head = &clayout_static_node; }
API int32_t clayout_node_value(const struct clayout_node *node) { return node ? node->value : -1; }

/* Counted pointers. */
API int64_t clayout_sum(const int32_t *values, size_t count) {
    int64_t total = 0;
    for (size_t i = 0; i < count; ++i) {
        total += values[i];
    }
    return total;
}
API void clayout_scale(int32_t *output, const int32_t *input, uint32_t count, int32_t factor) {
    for (uint32_t i = 0; i < count; ++i) {
        output[i] = input[i] * factor;
    }
}
API int32_t clayout_inner_total(const struct clayout_inner *items, int32_t count) {
    int32_t total = 0;
    for (int32_t i = 0; i < count; ++i) {
        total += items[i].a + (int32_t)items[i].b;
    }
    return total;
}

/* A caller's buffer filled up to its capacity, with the length reported through
 * an out parameter: the shape of a description call. */
API int32_t clayout_describe(uint8_t *output, uint64_t capacity, uint64_t *length) {
    static const char text[] = "nupp layout";
    *length = sizeof(text) - 1;
    if (capacity < sizeof(text) - 1) {
        return 2;
    }
    memcpy(output, text, sizeof(text) - 1);
    return 0;
}

/* Out parameters: a handle, a struct and an owned pointer, under a status. */
API int32_t clayout_create(uint64_t seed, uint64_t *handle) {
    if (seed == 0) {
        return 7;
    }
    *handle = seed * 3;
    return 0;
}
API void clayout_fill(int32_t seed, struct clayout_inner *inner) {
    inner->a = (int8_t)seed;
    inner->b = seed * 1.5;
}
API int32_t clayout_allocate(uint64_t size, void **result) {
    *result = malloc(size);
    return *result ? 0 : 1;
}
API void clayout_release(void *pointer) { free(pointer); }

/* Unions by value, alone and nested in a struct: libffi has no union, so the
 * VM passes each as the struct the target classifies alike. */
union clayout_hfa {
    float a[2];
    float b[2];
};
struct clayout_tagged {
    int32_t tag;
    union clayout_value value;
};
API int32_t clayout_value_int(union clayout_value v) { return v.i; }
API float clayout_hfa_sum(union clayout_hfa v) { return v.a[0] + v.b[1]; }
API union clayout_hfa clayout_hfa_make(float a, float b) {
    union clayout_hfa v;
    v.a[0] = a;
    v.a[1] = b;
    return v;
}
API double clayout_tagged_read(struct clayout_tagged t) { return t.tag == 1 ? t.value.d : t.value.i; }
API struct clayout_tagged clayout_tagged_make(int32_t tag, double value) {
    struct clayout_tagged t;
    memset(&t, 0, sizeof t);
    t.tag = tag;
    if (tag == 1) {
        t.value.d = value;
    } else {
        t.value.i = (int32_t)value;
    }
    return t;
}
/* A struct holding bitfields by value passes as its storage units. */
API int64_t clayout_flags_by_value(struct clayout_flags f) { return f.mode + f.level * 100 + f.delta * 10000; }

#include <stdarg.h>
#include <stdio.h>
/* A variadic C function: its extra arguments are typed by the default promotions. */
API int32_t clayout_format(char *output, uint64_t capacity, const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    int written = vsnprintf(output, (size_t)capacity, format, arguments);
    va_end(arguments);
    return written;
}
