/**
 * @file
 * @brief Checks libffi layouts against the headers used to build the sidecar.
 *
 * The libffi layout probe. scripts/c-libraries/libffi.sh builds it against
 * the exact headers and library it has just built for the core's sidecar,
 * and scripts/test-libffi runs it again in CI; both read the one line of
 * JSON it prints.
 *
 * The core does not call libffi through these headers. It lays out ffi_cif,
 * ffi_type and the result word itself, from the bounds and offsets
 * foreignabi.nupp declares, so this file states that contract once more in
 * C and fails to compile when the library drifts from it. The calls in main
 * show the library works; a passing probe is not evidence that Nupp's core
 * executes calls correctly.
 */

#include <ffi.h>

#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

/* The storage contract in foreignabi.nupp: word sizes, the largest ffi_cif
 * the core reserves room for, and where ffi_type keeps each field. */
_Static_assert(sizeof(void *) == 8,
               "core libffi storage requires 64-bit pointers");
_Static_assert(sizeof(ffi_arg) == 8,
               "core libffi result storage requires 64-bit ffi_arg");
_Static_assert(sizeof(ffi_cif) <= 40 && _Alignof(ffi_cif) <= 8,
               "ffi_cif storage drift");
_Static_assert(sizeof(ffi_type) == 24 && _Alignof(ffi_type) <= 8,
               "ffi_type storage drift");
_Static_assert(offsetof(ffi_type, size) == 0, "ffi_type size drift");
_Static_assert(offsetof(ffi_type, alignment) == 8, "ffi_type alignment drift");
_Static_assert(offsetof(ffi_type, type) == 10, "ffi_type code drift");
_Static_assert(offsetof(ffi_type, elements) == 16, "ffi_type elements drift");

/* The type codes the core writes into ffi_type.type for itself. */
_Static_assert(FFI_TYPE_STRUCT == 13 && FFI_TYPE_POINTER == 14,
               "ffi type code drift");
_Static_assert(FFI_TYPE_FLOAT == 2 && FFI_TYPE_DOUBLE == 3,
               "ffi float code drift");
_Static_assert(FFI_TYPE_UINT8 == 5 && FFI_TYPE_SINT8 == 6 &&
                   FFI_TYPE_UINT16 == 7 && FFI_TYPE_SINT16 == 8,
               "ffi narrow integer code drift");
_Static_assert(FFI_TYPE_UINT32 == 9 && FFI_TYPE_SINT32 == 10 &&
                   FFI_TYPE_UINT64 == 11 && FFI_TYPE_SINT64 == 12,
               "ffi integer code drift");

/* The two operands main passes, and the answer both the call and the
 * closure must give: their sum. */
#define LEFT_OPERAND (-3)
#define RIGHT_OPERAND 11
#define SUM 8

/* The function main calls through ffi_call. */
static int32_t add (int32_t a, int32_t b) {
  return a + b;
}

/* The closure's body: adds its one argument to the integer bound as its
 * data, and answers through the full-width result word, as libffi requires
 * of a narrower integer result. */
static void callback (ffi_cif *cif, void *result, void **args, void *data) {
  (void)cif;
  int32_t sum = *(int32_t *)args[0] + *(int32_t *)data;
  *(ffi_sarg *)result = sum;
}

/* The line the build scripts read: the version and the sizes of the
 * structures whose storage the core reserves. */
static void report (void) {
  printf("{\"libffi\":\"%s\",\"cifBytes\":%zu,\"typeBytes\":%zu,"
         "\"closureBytes\":%zu}\n",
         ffi_get_version(), sizeof(ffi_cif), sizeof(ffi_type),
         sizeof(ffi_closure));
}

int main (void) {
  /* The core assumes a little-endian host, and headers that match the
   * library they were installed with. */
  const uint32_t endian = 1;
  assert(*(const unsigned char *)&endian == 1);
  assert(ffi_get_version_number() == FFI_VERSION_NUMBER);
  assert(ffi_get_default_abi() == FFI_DEFAULT_ABI);
  assert(ffi_get_closure_size() == sizeof(ffi_closure));

  /* A call into C through a prepared interface. */
  ffi_cif cif;
  ffi_type *types[] = {&ffi_type_sint32, &ffi_type_sint32};
  assert(ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 2, &ffi_type_sint32, types) ==
         FFI_OK);
  int32_t a = LEFT_OPERAND, b = RIGHT_OPERAND;
  void *args[] = {&a, &b};
  ffi_arg answer = 0;
  ffi_call(&cif, FFI_FN(add), &answer, args);
  assert((int32_t)answer == SUM);

  /* A call from C into a closure, which executable memory must allow. */
  assert(ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 1, &ffi_type_sint32, types) ==
         FFI_OK);
  void *code;
  ffi_closure *closure = ffi_closure_alloc(sizeof(*closure), &code);
  assert(closure);
  assert(ffi_prep_closure_loc(closure, &cif, callback, &b, code) == FFI_OK);
  int32_t (*fn)(int32_t) = (int32_t (*)(int32_t))code;
  assert(fn(a) == SUM);
  ffi_closure_free(closure);
  report();

  return 0;
}
