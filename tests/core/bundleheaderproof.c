/**
 * @file
 * @brief CBMC proof of the core bridge's ARM64 bundle header contract.
 *
 * Run with `nupp task prove-bundle-header`. The stream model supplies arbitrary
 * header bytes and read lengths. The validator and decoder are production C.
 */

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static size_t proofread (void *out, size_t size, size_t count, FILE *stream);
static int proofprint (FILE *stream, const char *format, ...);

#define fread proofread
#define fprintf proofprint
#define main bridgemain
#include "../../native/core-bridge/main.c" /* NOLINT(bugprone-suspicious-include) */
#undef main
#undef fprintf
#undef fread

/* CBMC models calls to these functions as independent arbitrary values. */
extern unsigned char nondet_byte (void);
extern size_t nondet_size (void);
extern int64_t nondet_filesize (void);

/* CBMC recognizes these intrinsics. Declare them for ordinary C linting. */
/* NOLINTNEXTLINE(bugprone-reserved-identifier,cert-dcl37-c) */
extern void __CPROVER_assume (_Bool condition);
/* NOLINTNEXTLINE(bugprone-reserved-identifier,cert-dcl37-c) */
extern void __CPROVER_assert (_Bool condition, const char *description);

static unsigned char input[HEADER_BYTES];
static size_t readable;

/** Supplies the bytes contiguous from the beginning of the modeled file. */
static size_t proofread (void *out, size_t size, size_t count, FILE *stream) {
  (void)stream;
  __CPROVER_assert(size == 1 && count == HEADER_BYTES,
                   "validator asks for one fixed-size header");
  __CPROVER_assert(readable <= count && readable <= sizeof(input),
                   "stream supplies at most the requested bytes");
  memcpy(out, input, readable);

  return readable;
}

/** Ignores diagnostics so the proof depends only on the validation result. */
static int proofprint (FILE *stream, const char *format, ...) {
  (void)stream;
  (void)format;

  return 0;
}

/** Checks the postconditions for every header and modeled read outcome. */
static void provesymbolicheaders (void) {
  for (size_t i = 0; i < sizeof(input); ++i) {
    input[i] = nondet_byte();
  }

  readable = nondet_size();
  __CPROVER_assume(readable <= sizeof(input));
  int64_t filebytes = nondet_filesize();
  struct bundle decoded = {0};
  int status = readheader(NULL, filebytes, &decoded);

  if (filebytes < HEADER_BYTES || readable < HEADER_BYTES) {
    __CPROVER_assert(status != 0, "short file or short read cannot succeed");
  }

  if (status == 0) {
    __CPROVER_assert(decoded.codebytes != 0 &&
                         decoded.entry < decoded.codebytes,
                     "accepted entry lies within nonempty code");
    __CPROVER_assert(decoded.codebytes % INSTRUCTION_BYTES == 0 &&
                         decoded.entry % INSTRUCTION_BYTES == 0,
                     "accepted code size and entry are instruction-aligned");
    __CPROVER_assert(decoded.codebytes <= REGION &&
                         decoded.databytes <= REGION &&
                         decoded.scratchbytes <= REGION,
                     "accepted individual region sizes fit the region limit");
    __CPROVER_assert(decoded.outputwords <= MAX_WORDS,
                     "accepted output fits the word limit");
    __CPROVER_assert((__uint128_t)decoded.codebytes + decoded.databytes +
                             decoded.scratchbytes <=
                         (__uint128_t)REGION * 2,
                     "accepted regions fit the total mapped limit");
    __CPROVER_assert((__uint128_t)HEADER_BYTES + decoded.codebytes +
                             decoded.databytes ==
                         (uint64_t)filebytes,
                     "accepted stored extent matches file size without wrap");
  }
}

/** Establishes that a valid header is accepted with a nonzero entry. */
static void proveknownvalid (void) {
  memset(input, 0, sizeof(input));
  memcpy(input, BUNDLE_MAGIC, MAGIC_BYTES);
  storele64(input + headeroffset(BUNDLE_VERSION), BUNDLE_FORMAT);
  storele64(input + headeroffset(BUNDLE_ARCHITECTURE), HOST_ARCH);
  storele64(input + headeroffset(BUNDLE_ENTRY), INSTRUCTION_BYTES);
  storele64(input + headeroffset(BUNDLE_CODE_BYTES),
            UINT64_C(2) * INSTRUCTION_BYTES);
  readable = sizeof(input);
  struct bundle decoded = {0};
  int status = readheader(NULL, HEADER_BYTES + 2 * INSTRUCTION_BYTES, &decoded);
  __CPROVER_assert(status == 0 && decoded.entry == INSTRUCTION_BYTES,
                   "known valid header succeeds and preserves its entry");
}

int main (void) {
  __CPROVER_assert(HOST_SUPPORTED && HOST_ARCH == BUNDLE_ARM64 &&
                       INSTRUCTION_BYTES == 4,
                   "proof uses the production ARM64 configuration");
  provesymbolicheaders();
  proveknownvalid();

  return 0;
}
