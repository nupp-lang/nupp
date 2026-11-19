/**
 * @file
 * @brief Exercises owned Win64 jobs on the libuv reactor with real descendants.
 */

#define WIN32_LEAN_AND_MEAN
#include "process.h"
#include "reactor.h"
#include "winpipe.h"
#include <uv.h>
#include <assert.h>
#include <errno.h>
#include <io.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SECOND UINT64_C(1000000000)

static int descendant (int hold) {
  wchar_t path[32768];
  DWORD length = GetModuleFileNameW(NULL, path, sizeof(path) / sizeof(*path));
  assert(length && length < sizeof(path) / sizeof(*path));

  STARTUPINFOW startup = {.cb = sizeof(startup)};
  PROCESS_INFORMATION process;
  wchar_t breakaway[] = L"process --descendant";
  BOOL escaped =
      CreateProcessW(path, breakaway, NULL, NULL, FALSE,
                     CREATE_BREAKAWAY_FROM_JOB, NULL, NULL, &startup, &process);

  if (escaped) {
    TerminateProcess(process.hProcess, 1);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
  }

  assert(!escaped && GetLastError() == ERROR_ACCESS_DENIED);
  wchar_t command[] = L"process --descendant";
  assert(CreateProcessW(path, command, NULL, NULL, FALSE, 0, NULL, NULL,
                        &startup, &process));
  assert(WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), &process.dwProcessId,
                   sizeof(process.dwProcessId), &length, NULL));
  assert(length == sizeof(process.dwProcessId));

  if (hold) {
    WaitForSingleObject(process.hProcess, 60000);
  }

  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);

  return 7;
}

static uint64_t start (char *path, char *mode, int output) {
  char *args[] = {path, mode, NULL};
  int64_t child = nupp_process_spawn(path, args, NULL, NULL, -1, output, -1, 0);

  if (child < 0) {
    fprintf(stderr, "nupp_process_spawn failed: %lld\n", (long long)child);
    abort();
  }

  return (uint64_t)child >> 32;
}

static uint64_t starttree (char *path, char *mode, HANDLE *leaf) {
  int64_t pair = nupp_process_pipe(0, 0);
  assert(pair > 0);
  int reader = (int)(uint32_t)pair, writer = (int)((uint64_t)pair >> 32);
  HANDLE pipe = (HANDLE)_get_osfhandle(reader);
  assert(pipe != INVALID_HANDLE_VALUE);
  uint64_t root = start(path, mode, writer);
  assert(_close(writer) == 0);
  uint64_t limit = uv_hrtime() + 5 * SECOND;

  DWORD available, pid, received;

  do {
    assert(uv_hrtime() < limit);
    assert(PeekNamedPipe(pipe, NULL, 0, NULL, &available, NULL));

    if (available < sizeof(pid)) {
      Sleep(5);
    }
  } while (available < sizeof(pid));

  assert(ReadFile(pipe, &pid, sizeof(pid), &received, NULL));
  assert(received == sizeof(pid));
  assert(_close(reader) == 0);
  *leaf = OpenProcess(SYNCHRONIZE, FALSE, pid);
  assert(*leaf && WaitForSingleObject(*leaf, 0) == WAIT_TIMEOUT);

  return root;
}

static int64_t waitexit (uint64_t poller, uint64_t child) {
  uint64_t limit = uv_hrtime() + 5 * SECOND;

  for (;;) {
    assert(uv_hrtime() < limit);
    int64_t event = nupp_uv_wait(poller, SECOND);
    assert(event >= 0);

    if (event) {
      assert(event == (int64_t)((child << 5) | 16));

      return nupp_process_reap(child);
    }
  }
}

static int echoinput (void) {
  HANDLE input = GetStdHandle(STD_INPUT_HANDLE);
  HANDLE output = GetStdHandle(STD_OUTPUT_HANDLE);
  char bytes[4096];
  DWORD count, written;

  while (ReadFile(input, bytes, sizeof(bytes), &count, NULL) && count) {
    assert(WriteFile(output, bytes, count, &written, NULL) && count == written);
  }

  return 0;
}

static void transferpipes (char *path, uint64_t poller) {
  enum { SIZE = 40000 };

  char given[SIZE], received[SIZE];

  for (size_t i = 0; i < sizeof(given); i++) {
    given[i] = (char)(i % 197);
  }

  int64_t input = nupp_process_pipe(0, 1), output = nupp_process_pipe(1, 0);
  assert(input > 0 && output > 0);
  int inchild = (int)(uint32_t)input, inparent = (int)(input >> 32);
  int outchild = (int)(output >> 32), outparent = (int)(uint32_t)output;
  assert(nuppwinpipekey(inparent) && nuppwinpipekey(outparent));
  assert(nuppwinpiperead(outparent, received, 1) == -1 && errno == EAGAIN);
  char *args[] = {path, "--echo", NULL};
  int64_t child =
      nupp_process_spawn(path, args, NULL, NULL, inchild, outchild, -1, 0);
  assert(child > 0);
  assert(_close(inchild) == 0 && _close(outchild) == 0);

  size_t sent = 0, got = 0;
  uint64_t deadline = uv_hrtime() + 5 * SECOND;
  char extra;

  for (;;) {
    assert(uv_hrtime() < deadline);

    if (sent < sizeof(given)) {
      int64_t count =
          nuppwinpipewrite(inparent, given + sent, sizeof(given) - sent);
      assert(count > 0 || (count == -1 && errno == EAGAIN));

      if (count > 0) {
        sent += (size_t)count;
      }

      if (sent == sizeof(given)) {
        assert(nuppwinpipeclose(inparent) == 0);
        assert(nuppwinpipewrite(inparent, given, 1) == -1 && errno == EBADF);
      }
      else {
        assert(nupp_uv_arm(poller, inparent, 2) == 0);
      }
    }

    int64_t count = got == sizeof(received)
                        ? nuppwinpiperead(outparent, &extra, 1)
                        : nuppwinpiperead(outparent, received + got,
                                          sizeof(received) - got);
    assert(count >= 0 || (count == -1 && errno == EAGAIN));

    if (count == 0) {
      break;
    }

    if (count > 0) {
      assert(got < sizeof(received));
      got += (size_t)count;
    }

    assert(nupp_uv_arm(poller, outparent, 1) == 0);
    int64_t event = nupp_uv_wait_owner(poller, 1000000);
    assert(event == 0 || event == ((int64_t)inparent << 5 | 2) ||
           event == ((int64_t)outparent << 5 | 1));
  }

  assert(sent == sizeof(given) && got == sizeof(received));
  assert(memcmp(given, received, sizeof(given)) == 0);
  assert(nuppwinpipeclose(outparent) == 0);
  assert(nupp_uv_arm(poller, outparent, 1) == -EBADF);
  int64_t exit = nupp_process_reap((uint64_t)child >> 32);

  while (!exit) {
    assert(uv_hrtime() < deadline);
    assert(nupp_uv_wait(poller, 1000000) == 0);
    exit = nupp_process_reap((uint64_t)child >> 32);
  }

  assert(exit == 256);
}

int main (int argc, char **argv) {
  if (argc == 2) {
    if (!strcmp(argv[1], "--echo")) {
      return echoinput();
    }

    if (!strcmp(argv[1], "--descendant")) {
      Sleep(60000);

      return 0;
    }

    return descendant(!strcmp(argv[1], "--root-hold"));
  }

  wchar_t wide[32768];
  DWORD length = GetModuleFileNameW(NULL, wide, sizeof(wide) / sizeof(*wide));
  assert(length && length < sizeof(wide) / sizeof(*wide));
  char path[4 * (sizeof(wide) / sizeof(*wide))];
  assert(WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, -1, path,
                             sizeof(path), NULL, NULL));

  int64_t poller = nupp_uv_open(-1), discarded = nupp_uv_open(-1);
  assert(poller > 0 && discarded > 0);
  transferpipes(path, (uint64_t)poller);
  char *missing[] = {"no-such-nupp-process.exe", NULL};
  assert(nupp_process_spawn(missing[0], missing, NULL, NULL, -1, -1, -1, 0) ==
         -ENOENT);

  HANDLE leaf;
  uint64_t root = starttree(path, "--root-hold", &leaf);
  assert(nupp_process_watch((uint64_t)poller, root) == 0);
  assert(nupp_process_watch((uint64_t)discarded, root) == 0);
  assert(nupp_uv_close((uint64_t)discarded) == 0);
  assert(nupp_process_kill(root, 9) == 0);
  assert(waitexit((uint64_t)poller, root) == 521);
  assert(WaitForSingleObject(leaf, 5000) == WAIT_OBJECT_0);
  CloseHandle(leaf);
  assert(nupp_process_reap(root) == -ECHILD);
  assert(nupp_process_kill(root, 9) == -ESRCH);

  uint64_t late = starttree(path, "--root-exit", &leaf);
  assert(nupp_process_watch((uint64_t)poller, late) == 0);
  assert(waitexit((uint64_t)poller, late) == 263);
  assert(WaitForSingleObject(leaf, 0) == WAIT_TIMEOUT);
  assert(nupp_uv_shutdown() == 0);
  assert(WaitForSingleObject(leaf, 5000) == WAIT_OBJECT_0);
  CloseHandle(leaf);
  assert(nupp_uv_shutdown() == 0);
  assert(!nupp_process_pending());
  assert(!nuppwinpipepending());
  puts("Win64 owned process contracts passed");

  return 0;
}
