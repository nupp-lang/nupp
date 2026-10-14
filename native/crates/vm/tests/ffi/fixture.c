/* Native ABI oracle for the FFI parity manifest. No VM implementation lives here. */
#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#ifndef _MSC_VER
#include <complex.h>
#endif

#ifdef _WIN32
#define API __declspec(dllexport)
#else
#define API __attribute__((visibility("default")))
#endif

struct FfiPair { double x, y; };
struct FfiIntegers { int32_t low; uint64_t high; };
struct FfiNuppScalars { _Bool flag; int32_t count; };
struct FfiLarge { uint64_t a, b, c, d; };
union FfiUnion { uint32_t bits; float real; };
union FfiByteUnion { uint32_t word; uint8_t bytes[4]; };
struct FfiBits { unsigned low:3; signed middle:5; unsigned high:24; };
struct FfiNested { uint8_t tag; struct FfiPair pair; uint16_t lanes[3]; };
struct FfiFlex { uint32_t count; double values[]; };
#pragma pack(push, 1)
struct FfiPacked { uint8_t tag; uint32_t value; };
#pragma pack(pop)
#ifdef _MSC_VER
struct __declspec(align(16)) FfiAligned { uint8_t value; };
#else
struct __attribute__((aligned(16))) FfiAligned { uint8_t value; };
#endif

API int32_t ffi_test_global = 7;
API const uint32_t ffi_test_constant = 0x12345678;
API const char ffi_test_text[] = "nupp\0ffi";
API uint64_t ffi_test_wide_global = UINT64_C(0xfedcba9876543210);

#define IDENTITY(NAME, TYPE) API TYPE ffi_test_##NAME(TYPE value) { return value; }
IDENTITY(bool, _Bool)
IDENTITY(char, char)
IDENTITY(i8, int8_t)
IDENTITY(u8, uint8_t)
IDENTITY(i16, int16_t)
IDENTITY(u16, uint16_t)
IDENTITY(i32, int32_t)
IDENTITY(u32, uint32_t)
IDENTITY(i64, int64_t)
IDENTITY(u64, uint64_t)
IDENTITY(float, float)
IDENTITY(double, double)
IDENTITY(size, size_t)
IDENTITY(ptrdiff, ptrdiff_t)
IDENTITY(pointer, void *)

API struct FfiPair ffi_test_pair(struct FfiPair p, double delta) {
    p.x += delta;
    p.y -= delta;
    return p;
}
API struct FfiIntegers ffi_test_integers(struct FfiIntegers value) { return value; }
API struct FfiNuppScalars ffi_test_nupp_scalars(struct FfiNuppScalars value) {
    value.flag = !value.flag;
    value.count += 1;
    return value;
}
API struct FfiLarge ffi_test_large(struct FfiLarge value) { return value; }
API union FfiUnion ffi_test_union(union FfiUnion value) { return value; }
API void ffi_test_byte_union(union FfiByteUnion *value, uint32_t word) { value->word = word; }
API void ffi_test_nested(struct FfiNested *value) {
    value->tag = 17;
    value->pair.x = 1.5;
    value->pair.y = -2.25;
    value->lanes[0] = 3;
    value->lanes[1] = 65535;
    value->lanes[2] = 9;
}
API uint32_t ffi_test_bits(struct FfiBits *value, unsigned low, int middle, unsigned high) {
    value->low = low;
    value->middle = middle;
    value->high = high;
    return value->low + (uint32_t)(value->middle + 16) * 8 + value->high * 256;
}
API uint64_t ffi_test_varargs_int(int count, ...) {
    va_list args;
    va_start(args, count);
    uint64_t result = 0;
    for (int i = 0; i < count; ++i) result += va_arg(args, int);
    va_end(args);
    return result;
}
API double ffi_test_varargs_double(int count, ...) {
    va_list args;
    va_start(args, count);
    double result = 0;
    for (int i = 0; i < count; ++i) result += va_arg(args, double);
    va_end(args);
    return result;
}
API int ffi_test_errno(int value) { errno = value; return -1; }
API int ffi_test_read_errno(void) { return errno; }
API int ffi_test_callback(int (*callback)(int, int), int a, int b) { return callback(a, b); }
API double ffi_test_callback_double(double (*callback)(double), double value) { return callback(value); }
static int (*saved_callback)(int, int);
API void ffi_test_save_callback(int (*callback)(int, int)) { saved_callback = callback; }
API int ffi_test_call_saved(int a, int b) { return saved_callback ? saved_callback(a, b) : -1; }
API void ffi_test_clear_saved(void) { saved_callback = NULL; }
static unsigned frees;
API void *ffi_test_alloc(size_t count) { return calloc(1, count); }
API void ffi_test_free(void *value) { ++frees; free(value); }
API unsigned ffi_test_frees(void) { return frees; }
API void *ffi_test_offset(void *value, size_t bytes) { return (uint8_t *)value + bytes; }
API void ffi_test_copy(void *target, const void *source, uint64_t bytes) { memcpy(target, source, (size_t)bytes); }
API uint64_t ffi_test_strlen(const char *value) { return (uint64_t)strlen(value); }
API void *ffi_test_function_address(void) { return (void *)(uintptr_t)&ffi_test_i32; }
API size_t ffi_test_layout(unsigned query) {
    switch (query) {
    case 0: return sizeof(struct FfiPair);
    case 1: return offsetof(struct FfiPair, y);
    case 2: return sizeof(struct FfiNested);
    case 3: return offsetof(struct FfiNested, pair);
    case 4: return offsetof(struct FfiNested, lanes);
    case 5: return sizeof(struct FfiBits);
    case 6: return sizeof(struct FfiPacked);
    case 7: return offsetof(struct FfiPacked, value);
    case 8: return sizeof(struct FfiAligned);
    case 9: return sizeof(struct FfiFlex);
    case 10: return offsetof(struct FfiFlex, values);
    case 11: return (char)-1 < 0;
    case 12: return sizeof(long);
    case 13: return sizeof(void *);
    case 14: return sizeof(union FfiByteUnion);
    case 15: return _Alignof(union FfiByteUnion);
    case 16: return offsetof(union FfiByteUnion, word);
    case 17: return offsetof(union FfiByteUnion, bytes);
    default: return (size_t)-1;
    }
}
#ifndef _MSC_VER
API double _Complex ffi_test_complex(double _Complex value) { return value; }
API float _Complex ffi_test_complex_float(float _Complex value) { return value; }
#endif
API uint64_t ffi_test_callback_u64(uint64_t (*callback)(uint64_t), uint64_t value) { return callback(value); }
API _Bool ffi_test_callback_bool(_Bool (*callback)(_Bool), _Bool value) { return callback(value); }
API uint32_t ffi_test_callback_pointer(const uint8_t *value, int (*callback)(int, int)) {
    callback(0, 0);
    return value[0];
}
API struct FfiPair ffi_test_callback_pair(int (*callback)(int, int)) {
    callback(0, 0);
    struct FfiPair result = {19.0, 23.0};
    return result;
}
