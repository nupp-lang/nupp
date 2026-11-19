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
#include <fcntl.h>
#include <signal.h>
#include <sys/wait.h>
#include <time.h>

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

/* How often, and how long between, polls for the I/O pool's progress. */
enum { POLL_ATTEMPTS = 10000, POLL_NANOSECONDS = 1000000 };

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

static void pausebriefly (void) {
  struct timespec pause = {0, POLL_NANOSECONDS};
  nanosleep(&pause, NULL);
}

/* Waits for a job to finish and answers its ticket. */
static uint64_t take (void) {
  for (unsigned i = 0; i < POLL_ATTEMPTS; ++i) {
    uint64_t ticket = nuppiotake();

    if (ticket) {
      return ticket;
    }

    pausebriefly();
  }

  assert(!"I/O completion timed out");

  return 0;
}

static uint64_t submitopen (const char *path) {
  return nuppiosubmit(NUPP_IO_OPEN, 0, (uintptr_t)path, strlen(path));
}

/* Submits a read of an empty pipe until a worker has started it, so it can
 * no longer be cancelled, and answers its ticket. */
static uint64_t startblockedread (int descriptor) {
  for (unsigned i = 0; i < POLL_ATTEMPTS; ++i) {
    uint64_t ticket = nuppiosubmit(NUPP_IO_READ, (uint64_t)descriptor, 0, 1);
    assert((int64_t)ticket > 0);
    pausebriefly();

    if (!nuppiocancel(ticket)) {
      return ticket;
    }
  }

  assert(!"no worker started the read");

  return 0;
}

static void startsonce (void) {
  assert((int64_t)nuppiosubmit(NUPP_IO_OPEN, 0, 0, 1) == -EFAULT);
  int wake = (int)nuppiostart(1);
  assert(wake >= 0);
  assert(nuppiostart(8) == (uint64_t)wake);
  assert(fcntl(wake, F_GETFL) & O_NONBLOCK);
  assert(fcntl(wake, F_GETFD) & FD_CLOEXEC);
}

/* With the one worker blocked, a queued job can be cancelled and is then
 * forgotten; the blocked one settles once its read can complete. */
static void cancelsqueued (void) {
  int ends[2];
  assert(!pipe(ends));
  uint64_t blocked = startblockedread(ends[0]);
  uint64_t queued = submitopen("/dev/null");
  assert((int64_t)queued > 0 && nuppiocancel(queued) == 1);
  assert((int64_t)nuppiosettle(queued) == -EINVAL);
  assert(write(ends[1], "x", 1) == 1);
  assert(nuppiosettle(blocked) == 1);
  assert((int64_t)nuppiosettle(blocked) == -EINVAL);
  assert(nuppiotake() == 0);
  close(ends[0]);
  close(ends[1]);
}

/* Settling one job leaves the other for take, and a finished ticket is
 * forgotten. */
static void completesapart (void) {
  uint64_t first = submitopen("/dev/null");
  uint64_t second = submitopen("/dev/null");
  int firstfd = (int)nuppiosettle(first);
  assert(firstfd >= 0);
  assert(take() == second);
  int secondfd = (int)nuppiofinish(second, 0, 0);
  assert(secondfd >= 0);
  assert((int64_t)nuppiofinish(second, 0, 0) == -EINVAL);
  close(firstfd);
  close(secondfd);
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

int main (void) {
  abiprobe();
  malformed();
  codereadonly();
  startsonce();
  cancelsqueued();
  completesapart();
  puts("native transport contracts passed");

  return 0;
}
