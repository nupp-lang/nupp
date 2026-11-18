/* Native transport tests complement, rather than replace, actual Nupp guests.
 */
#define main bootstrap_main
#include "../../native/core-bridge/main.c"
#undef main
#include <assert.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/wait.h>
#include <time.h>
extern void nupp_core_test_abi(Entry, const uint64_t *, uint64_t *, uint64_t *);
extern uint64_t nupp_core_test_abi_clobber(const uint64_t *, uint64_t *);

static void put(unsigned char *bytes, unsigned field, uint64_t value)
{
  for (unsigned i = 0; i < 8; ++i)
    bytes[8 + field * 8 + i] = (unsigned char)(value >> (i * 8));
}

static void malformed(void)
{
  unsigned char bytes[80] = {0};
  memcpy(bytes, "NUPPCORE", 8);
  put(bytes, 0, 1);
  put(bytes, 1, 1);
  put(bytes, 3, 8);
  const unsigned fields[] = {0, 1, 2, 3, 3, 4, 5, 6, 7};
  const uint64_t values[] = {2,          2,          1,          0, UINT64_MAX,
                             UINT64_MAX, UINT64_MAX, UINT64_MAX, 1};
  char path[] = "/tmp/nupp-core-contract-XXXXXX";
  int descriptor = mkstemp(path);
  assert(descriptor >= 0);
  close(descriptor);
  for (unsigned i = 0; i < sizeof(fields) / sizeof(*fields); ++i) {
    unsigned char sample[80];
    memcpy(sample, bytes, sizeof(sample));
    put(sample, fields[i], values[i]);
    FILE *file = fopen(path, "wb");
    assert(file);
    assert(fwrite(sample, 1, sizeof(sample), file) == sizeof(sample));
    assert(!fclose(file));
    uint64_t *answer = NULL, status = 0;
    size_t length = 0;
    assert(execute(path, NULL, 0, &answer, &length, &status) != 0 && !answer);
  }
  for (size_t size = 0; size < HEADER; ++size) {
    FILE *file = fopen(path, "wb");
    assert(file);
    assert(fwrite(bytes, 1, size, file) == size);
    assert(!fclose(file));
    uint64_t *answer = NULL, status = 0;
    size_t length = 0;
    assert(execute(path, NULL, 0, &answer, &length, &status) != 0 && !answer);
  }
  unlink(path);
}

static uint64_t take(void)
{
  for (unsigned i = 0; i < 10000; ++i) {
    uint64_t ticket = nupp_io_take();
    if (ticket)
      return ticket;
    struct timespec pause = {0, 1000000};
    nanosleep(&pause, NULL);
  }
  assert(!"I/O completion timed out");
  return 0;
}

static void blocking(void)
{
  assert((int64_t)nupp_io_submit(1, 0, 0, 1) == -EFAULT);
  int wake = (int)nupp_io_start(1);
  assert(wake >= 0);
  assert(nupp_io_start(8) == (uint64_t)wake);
  assert(fcntl(wake, F_GETFL) & O_NONBLOCK);
  assert(fcntl(wake, F_GETFD) & FD_CLOEXEC);
  int descriptors[2];
  assert(!pipe(descriptors));
  uint64_t blocked = 0;
  for (unsigned i = 0; i < 10000; ++i) {
    blocked = nupp_io_submit(2, (uint64_t)descriptors[0], 0, 1);
    assert((int64_t)blocked > 0);
    struct timespec pause = {0, 1000000};
    nanosleep(&pause, NULL);
    if (!nupp_io_cancel(blocked))
      break;
    blocked = 0;
  }
  assert(blocked);
  const char path[] = "/dev/null";
  uint64_t queued = nupp_io_submit(1, 0, (uintptr_t)path, strlen(path));
  assert((int64_t)queued > 0 && nupp_io_cancel(queued) == 1);
  assert((int64_t)nupp_io_settle(queued) == -EINVAL);
  assert(write(descriptors[1], "x", 1) == 1);
  assert(nupp_io_settle(blocked) == 1);
  assert((int64_t)nupp_io_settle(blocked) == -EINVAL);
  assert(nupp_io_take() == 0);
  close(descriptors[0]);
  close(descriptors[1]);
  uint64_t first = nupp_io_submit(1, 0, (uintptr_t)path, strlen(path));
  uint64_t second = nupp_io_submit(1, 0, (uintptr_t)path, strlen(path));
  int first_fd = (int)nupp_io_settle(first);
  assert(first_fd >= 0);
  assert(take() == second);
  int second_fd = (int)nupp_io_finish(second, 0, 0);
  assert(second_fd >= 0);
  assert((int64_t)nupp_io_finish(second, 0, 0) == -EINVAL);
  close(first_fd);
  close(second_fd);
}

static void wx(void)
{
  size_t page = (size_t)sysconf(_SC_PAGESIZE);
  unsigned char *code = mapping(page);
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

int main(void)
{
  uint64_t report[2] = {0, 0};
  nupp_core_test_abi(nupp_core_test_abi_clobber, NULL, NULL, report);
  assert(report[0] == 7 && report[1] == (1 | (1 << 11)));
  malformed();
  wx();
  blocking();
  puts("native transport contracts passed");
  return 0;
}
