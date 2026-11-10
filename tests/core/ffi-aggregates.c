// The C side of catalog-ffi-aggregates: functions taking and answering
// structs by value in each of the ways AAPCS64 and Apple pass them. The
// guest runner builds it with cc into a directory DYLD_LIBRARY_PATH names.
#include <stdint.h>

typedef struct { float x, y; } F2;
typedef struct { float x, y, z; } F3;
typedef struct { double a, b, c, d; } D4;
typedef struct { F2 low, high; } F2x2;
typedef struct { double v[3]; } D3;
typedef struct { int32_t a, b; } I2;
typedef struct { int8_t a; int16_t b; int32_t c; } Mixed;
typedef struct { int64_t a; int32_t b; } L12;
typedef struct { int64_t a, b, c; } L3;

// Homogeneous aggregates of floats, in s and d registers both ways.
F2 f2_scale(F2 p, float k) { return (F2){p.x * k, p.y * k}; }
F3 f3_add(F3 a, F3 b) { return (F3){a.x + b.x, a.y + b.y, a.z + b.z}; }
D4 d4_scale(D4 r, double k) { return (D4){r.a * k, r.b * k, r.c * k, r.d * k}; }
F2x2 f2x2_swap(F2x2 q) { return (F2x2){q.high, q.low}; }
double d3_sum(D3 d) { return d.v[0] + d.v[1] + d.v[2]; }

// Aggregates of floats past the float registers: on the stack at their
// members' alignment, the float registers then spent.
double d4_spill(double a, double b, double c, double d, double e, double f, D4 r, double tail) {
    return a + b + c + d + e + f + r.a * 10 + r.b * 100 + r.c * 1000 + r.d * 10000 + tail * 100000;
}
float f3_spill(double a, double b, double c, double d, double e, double f, double g, F3 s, float tail) {
    return (float)(a + b + c + d + e + f + g) + s.x * 10 + s.y * 100 + s.z * 1000 + tail * 10000;
}

// Composites of up to 16 bytes, in x registers both ways.
I2 i2_swap(I2 v) { return (I2){v.b, v.a}; }
Mixed mixed_bump(Mixed m) { return (Mixed){(int8_t)(m.a + 1), (int16_t)(m.b + 1), m.c + 1}; }
L12 l12_make(int64_t a, int32_t b) { return (L12){a, b}; }
int64_t l12_sum(L12 v) { return v.a + v.b; }

// A composite past the integer registers: on the stack in whole words, the
// integer registers then spent.
int64_t l12_spill(int64_t a, int64_t b, int64_t c, int64_t d, int64_t e, int64_t f, int64_t g, L12 v, int64_t tail) {
    return a + b + c + d + e + f + g + v.a * 100 + v.b * 1000 + tail * 10000;
}

// Larger composites: by reference to the caller's copy, and answered
// through the memory x8 names.
L3 l3_add(L3 x, L3 y) {
    L3 r = {x.a + y.a, x.b + y.b, x.c + y.c};
    x.a = -1; // the caller's copy, not the caller's struct
    return r;
}
int64_t l3_spill(int64_t a, int64_t b, int64_t c, int64_t d, int64_t e, int64_t f, int64_t g, int64_t h, L3 v, int32_t t) {
    return a + b + c + d + e + f + g + h + v.a * 100 + v.b * 1000 + v.c * 10000 + t * 100000;
}
L3 l3_make(int64_t a, int64_t b, int64_t c) { return (L3){a, b, c}; }

// A walk that hands each struct it visits to a C visitor by value, which
// AAPCS64 passes by reference, as libclang's clang_visitChildren does: it
// stops when the visitor answers 0.
typedef unsigned (*Visitor)(L3 item, L3 parent, void *data);
unsigned walk_l3(Visitor visit, void *data, int64_t count) {
    L3 parent = {-1, -1, -1};
    for (int64_t i = 0; i < count; i++) {
        L3 item = {i + 1, (i + 1) * 10, (i + 1) * 100};
        if (visit(item, parent, data) == 0) {
            return 0;
        }
    }
    return 1;
}
