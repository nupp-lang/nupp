/* Native contract tests for the startup transport, built and run by
 * `scripts/core-bridge --test`. They check what a Nupp guest cannot easily
 * reach: that malformed bundles are refused, that loaded code is not
 * writable, that the ABI probe the guard relies on detects clobbering, and
 * the I/O pool's cancellation, settling and completion order. They
 * complement, rather than replace, running actual Nupp guests. */
#define main bootstrap_main
#include "../../native/core-bridge/main.c"
#undef main
#include <assert.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/wait.h>
#include <time.h>

/* tests/core/bridge-abi-aarch64.S. The probe calls an entry and reports its
 * status and a mask of the callee-saved registers it clobbered: x19 to x29
 * in bits 0 to 10, d8 to d15 in bits 11 to 18. The clobber function is its
 * calibration: it answers 7 and clobbers exactly x19 and d8. */
extern void nupp_core_test_abi (Entry entry, const uint64_t *packet,
                                uint64_t *output, uint64_t *report);
extern uint64_t nupp_core_test_abi_clobber (const uint64_t *packet,
                                            uint64_t *output);

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

static void put_field (unsigned char *bundle, enum bundle_field field,
                       uint64_t value) {
  store_le64(bundle + header_offset(field), value);
}

static void write_file (const char *path, const unsigned char *bytes,
                        size_t size) {
  FILE *file = fopen(path, "wb");
  assert(file);
  assert(fwrite(bytes, 1, size, file) == size);
  assert(!fclose(file));
}

static void assert_refused (const char *path) {
  uint64_t *answer = NULL, status = 0;
  size_t length = 0;
  assert(execute(path, NULL, 0, &answer, &length, &status) != 0 && !answer);
}

/* Every header field out of range, and every truncated header, is refused
 * before anything is mapped or entered. */
static void malformed (void) {
  unsigned char sample[SAMPLE_BYTES] = {0};
  memcpy(sample, BUNDLE_MAGIC, MAGIC_BYTES);
  put_field(sample, BUNDLE_VERSION, BUNDLE_FORMAT);
  put_field(sample, BUNDLE_ARCHITECTURE, BUNDLE_ARM64);
  put_field(sample, BUNDLE_CODE_BYTES, SAMPLE_CODE_BYTES);

  const struct {
    enum bundle_field field;
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
    put_field(faulty, faults[i].field, faults[i].value);
    write_file(path, faulty, sizeof(faulty));
    assert_refused(path);
  }

  for (size_t size = 0; size < HEADER_BYTES; ++size) {
    write_file(path, sample, size);
    assert_refused(path);
  }

  unlink(path);
}

static void pause_briefly (void) {
  struct timespec pause = {0, POLL_NANOSECONDS};
  nanosleep(&pause, NULL);
}

/* Waits for a job to finish and answers its ticket. */
static uint64_t take (void) {
  for (unsigned i = 0; i < POLL_ATTEMPTS; ++i) {
    uint64_t ticket = nupp_io_take();

    if (ticket)
      return ticket;

    pause_briefly();
  }

  assert(!"I/O completion timed out");

  return 0;
}

static uint64_t submit_open (const char *path) {
  return nupp_io_submit(NUPP_IO_OPEN, 0, (uintptr_t)path, strlen(path));
}

/* Submits a read of an empty pipe until a worker has started it, so it can
 * no longer be cancelled, and answers its ticket. */
static uint64_t start_blocked_read (int descriptor) {
  for (unsigned i = 0; i < POLL_ATTEMPTS; ++i) {
    uint64_t ticket = nupp_io_submit(NUPP_IO_READ, (uint64_t)descriptor, 0, 1);
    assert((int64_t)ticket > 0);
    pause_briefly();

    if (!nupp_io_cancel(ticket))
      return ticket;
  }

  assert(!"no worker started the read");

  return 0;
}

static void starts_once (void) {
  assert((int64_t)nupp_io_submit(NUPP_IO_OPEN, 0, 0, 1) == -EFAULT);
  int wake = (int)nupp_io_start(1);
  assert(wake >= 0);
  assert(nupp_io_start(8) == (uint64_t)wake);
  assert(fcntl(wake, F_GETFL) & O_NONBLOCK);
  assert(fcntl(wake, F_GETFD) & FD_CLOEXEC);
}

/* With the one worker blocked, a queued job can be cancelled and is then
 * forgotten; the blocked one settles once its read can complete. */
static void cancels_queued_work (void) {
  int pipe_ends[2];
  assert(!pipe(pipe_ends));
  uint64_t blocked = start_blocked_read(pipe_ends[0]);
  uint64_t queued = submit_open("/dev/null");
  assert((int64_t)queued > 0 && nupp_io_cancel(queued) == 1);
  assert((int64_t)nupp_io_settle(queued) == -EINVAL);
  assert(write(pipe_ends[1], "x", 1) == 1);
  assert(nupp_io_settle(blocked) == 1);
  assert((int64_t)nupp_io_settle(blocked) == -EINVAL);
  assert(nupp_io_take() == 0);
  close(pipe_ends[0]);
  close(pipe_ends[1]);
}

/* Settling one job leaves the other for take, and a finished ticket is
 * forgotten. */
static void completes_independently (void) {
  uint64_t first = submit_open("/dev/null");
  uint64_t second = submit_open("/dev/null");
  int first_fd = (int)nupp_io_settle(first);
  assert(first_fd >= 0);
  assert(take() == second);
  int second_fd = (int)nupp_io_finish(second, 0, 0);
  assert(second_fd >= 0);
  assert((int64_t)nupp_io_finish(second, 0, 0) == -EINVAL);
  close(first_fd);
  close(second_fd);
}

/* Sealed code faults when written. */
static void code_is_not_writable (void) {
  size_t page = (size_t)sysconf(_SC_PAGESIZE);
  unsigned char *code = map_region(page);
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

static void abi_probe_detects_clobbering (void) {
  uint64_t report[2] = {0, 0};
  nupp_core_test_abi(nupp_core_test_abi_clobber, NULL, NULL, report);
  assert(report[0] == CLOBBER_STATUS &&
         report[1] == (CLOBBERED_X19 | CLOBBERED_D8));
}

int main (void) {
  abi_probe_detects_clobbering();
  malformed();
  code_is_not_writable();
  starts_once();
  cancels_queued_work();
  completes_independently();
  puts("native transport contracts passed");

  return 0;
}
