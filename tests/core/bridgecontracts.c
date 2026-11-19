/* Native contract tests for the startup transport, built and run by
 * `scripts/core-bridge --test`. They check what a Nupp guest cannot easily
 * reach: that malformed bundles are refused, that loaded code is not
 * writable, that the ABI probe the guard relies on detects clobbering, and
 * the I/O pool's cancellation, settling and completion order. They
 * complement, rather than replace, running actual Nupp guests. */

/* The transport itself, with its main renamed so this file can have one.
 * It is included rather than linked so the contracts reach its static
 * functions. */
#define main bootstrapmain
#include "../../native/core-bridge/main.c" /* NOLINT(bugprone-suspicious-include) */
#undef main

#include <assert.h>
#include <signal.h>
#include <sys/wait.h>

/* tests/core/bridgeabi.S. The probe calls an entry and reports its
 * status and a mask of the callee-saved registers it clobbered: x19 to x29
 * in bits 0 to 10, d8 to d15 in bits 11 to 18. The clobber function is its
 * calibration: it answers 7 and clobbers exactly x19 and d8. */
extern void nuppabiprobe (Entry entry, const uint64_t *packet, uint64_t *output,
                          uint64_t *report);
extern uint64_t nuppabiclobber (const uint64_t *packet, uint64_t *output);

enum {
  CLOBBER_STATUS = 7,
  CLOBBERED_X19 = 1 << 0,
  CLOBBERED_D8 = 1 << 11,
};

/* A well-formed bundle of two instructions' code and nothing else. */
enum { SAMPLE_CODE_BYTES = INSTRUCTION_BYTES * 2 };

enum { SAMPLE_BYTES = HEADER_BYTES + SAMPLE_CODE_BYTES };

static void putfield (unsigned char *bundle, enum bundlefield field,
                      uint64_t value) {
  storele64(bundle + headeroffset(field), value);
}

static void writefile (const char *path, const unsigned char *bytes,
                       size_t size) {
  FILE *file = fopen(path, "wb");
  assert(file);
  assert(fwrite(bytes, 1, size, file) == size);
  assert(!fclose(file));
}

static void assertrefused (const char *path) {
  uint64_t *answer = NULL, status = 0;
  size_t length = 0;
  assert(execute(path, NULL, 0, &answer, &length, &status) != 0 && !answer);
}

/* Every header field out of range, and every truncated header, is refused
 * before anything is mapped or entered. */
static void malformed (void) {
  unsigned char sample[SAMPLE_BYTES] = {0};
  memcpy(sample, BUNDLE_MAGIC, MAGIC_BYTES);
  putfield(sample, BUNDLE_VERSION, BUNDLE_FORMAT);
  putfield(sample, BUNDLE_ARCHITECTURE, BUNDLE_ARM64);
  putfield(sample, BUNDLE_CODE_BYTES, SAMPLE_CODE_BYTES);

  const struct {
    enum bundlefield field;
    uint64_t value;
  } faults[] = {
      {BUNDLE_VERSION, BUNDLE_FORMAT + 1},
      {BUNDLE_ARCHITECTURE, BUNDLE_ARM64 + 1},
      {BUNDLE_ENTRY, 1},
      {BUNDLE_CODE_BYTES, 0},
      {BUNDLE_CODE_BYTES, UINT64_MAX},
      {BUNDLE_DATA_BYTES, UINT64_MAX},
      {BUNDLE_SCRATCH_BYTES, UINT64_MAX},
      {BUNDLE_OUTPUT_WORDS, UINT64_MAX},
      {BUNDLE_RESERVED, 1},
  };

  char path[] = "/tmp/nupp-core-contract-XXXXXX";
  int descriptor = mkstemp(path);
  assert(descriptor >= 0);
  close(descriptor);

  for (size_t i = 0; i < ARRAY_LENGTH(faults); ++i) {
    unsigned char faulty[SAMPLE_BYTES];
    memcpy(faulty, sample, sizeof(faulty));
    putfield(faulty, faults[i].field, faults[i].value);
    writefile(path, faulty, sizeof(faulty));
    assertrefused(path);
  }

  for (size_t size = 0; size < HEADER_BYTES; ++size) {
    writefile(path, sample, size);
    assertrefused(path);
  }

  unlink(path);
}

/* Sealed code faults when written. */
static void codereadonly (void) {
  size_t page = (size_t)sysconf(_SC_PAGESIZE);
  unsigned char *code = mapregion(page);
  assert(code);
  assert(!mprotect(code, page, PROT_READ | PROT_EXEC));
  pid_t child = fork();
  assert(child >= 0);

  if (!child) {
    code[0] = 1;
    _exit(0);
  }

  int status;
  assert(waitpid(child, &status, 0) == child);
  assert(WIFSIGNALED(status) &&
         (WTERMSIG(status) == SIGSEGV || WTERMSIG(status) == SIGBUS));
  assert(!munmap(code, page));
}

static void abiprobe (void) {
  uint64_t report[2] = {0, 0};
  nuppabiprobe(nuppabiclobber, NULL, NULL, report);
  assert(report[0] == CLOBBER_STATUS &&
         report[1] == (CLOBBERED_X19 | CLOBBERED_D8));
}

void nupp_test_uv (void);

int main (void) {
  abiprobe();
  malformed();
  codereadonly();
  nupp_test_uv();
  puts("native transport contracts passed");

  return 0;
}
