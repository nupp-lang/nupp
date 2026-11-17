/* Check against the exact headers used to build the sidecar.
 * These bounds/offsets are the native storage contract in foreignabi.nupp.
 * A passing upstream probe is not evidence of Nupp core execution. */
#include <assert.h>
#include <ffi.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

_Static_assert(sizeof(void *) == 8, "core libffi storage requires 64-bit pointers");
_Static_assert(sizeof(ffi_arg) == 8, "core libffi result storage requires 64-bit ffi_arg");
_Static_assert(sizeof(ffi_cif) <= 40 && _Alignof(ffi_cif) <= 8, "ffi_cif storage drift");
_Static_assert(sizeof(ffi_type) == 24 && _Alignof(ffi_type) <= 8, "ffi_type storage drift");
_Static_assert(offsetof(ffi_type, size) == 0, "ffi_type size drift");
_Static_assert(offsetof(ffi_type, alignment) == 8, "ffi_type alignment drift");
_Static_assert(offsetof(ffi_type, type) == 10, "ffi_type code drift");
_Static_assert(offsetof(ffi_type, elements) == 16, "ffi_type elements drift");
_Static_assert(FFI_TYPE_STRUCT == 13 && FFI_TYPE_POINTER == 14, "ffi type code drift");
_Static_assert(FFI_TYPE_FLOAT == 2 && FFI_TYPE_DOUBLE == 3, "ffi float code drift");
_Static_assert(FFI_TYPE_UINT8 == 5 && FFI_TYPE_SINT8 == 6 && FFI_TYPE_UINT16 == 7 && FFI_TYPE_SINT16 == 8,
               "ffi narrow integer code drift");
_Static_assert(FFI_TYPE_UINT32 == 9 && FFI_TYPE_SINT32 == 10 && FFI_TYPE_UINT64 == 11 && FFI_TYPE_SINT64 == 12,
               "ffi integer code drift");

static int32_t add(int32_t a, int32_t b) { return a + b; }
static void callback(ffi_cif *cif, void *result, void **args, void *data) {
    (void)cif;
    *(ffi_arg *)result = (ffi_arg)(*(int32_t *)args[0] + *(int32_t *)data);
}

int main(void) {
    const uint32_t endian = 1;
    assert(*(const unsigned char *)&endian == 1);
    assert(ffi_get_version_number() == FFI_VERSION_NUMBER);
    assert(ffi_get_default_abi() == FFI_DEFAULT_ABI);
    assert(ffi_get_closure_size() == sizeof(ffi_closure));
    ffi_cif cif;
    ffi_type *types[] = {&ffi_type_sint32, &ffi_type_sint32};
    assert(ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 2, &ffi_type_sint32, types) == FFI_OK);
    int32_t a = -3, b = 11;
    void *args[] = {&a, &b};
    ffi_arg answer = 0;
    ffi_call(&cif, FFI_FN(add), &answer, args);
    assert((int32_t)answer == 8);
    assert(ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 1, &ffi_type_sint32, types) == FFI_OK);
    void *code;
    ffi_closure *closure = ffi_closure_alloc(sizeof(*closure), &code);
    assert(closure);
    assert(ffi_prep_closure_loc(closure, &cif, callback, &b, code) == FFI_OK);
    int32_t (*fn)(int32_t) = (int32_t (*)(int32_t))code;
    assert(fn(a) == 8);
    ffi_closure_free(closure);
    printf("{\"libffi\":\"%s\",\"cifBytes\":%zu,\"typeBytes\":%zu,\"closureBytes\":%zu}\n",
           ffi_get_version(), sizeof(ffi_cif), sizeof(ffi_type), sizeof(ffi_closure));
    return 0;
}
