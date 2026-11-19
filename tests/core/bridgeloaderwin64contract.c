/**
 * @file
 * @brief Exercises the core bridge loader on Win64.
 *
 * Build this probe with the same reactor inputs as the bridge.
 */
#define wmain bootstrap_wmain
#include "../../native/corebridge/main.c" /* NOLINT(bugprone-suspicious-include) */
#undef wmain

#include <assert.h>

static int header_refused (uint64_t architecture) {
  unsigned char header[HEADER_BYTES] = {0};
  memcpy(header, BUNDLE_MAGIC, MAGIC_BYTES);
  storele64(header + headeroffset(BUNDLE_VERSION), BUNDLE_FORMAT);
  storele64(header + headeroffset(BUNDLE_ARCHITECTURE), architecture);
  storele64(header + headeroffset(BUNDLE_CODE_BYTES), 1);
  FILE *file = tmpfile();
  assert(file);
  assert(fwrite(header, 1, sizeof(header), file) == sizeof(header));
  assert(fputc(0xc3, file) == 0xc3);
  rewind(file);
  struct bundle bundle;
  int result = readheader(file, HEADER_BYTES + 1, &bundle);
  fclose(file);

  return result;
}

static void executable_region (void) {

  /* mov eax, 7; ret (only the native machine ABI is under test). */
  const unsigned char code[] = {0xb8, 7, 0, 0, 0, 0xc3};
  unsigned char *region = mapregion(sizeof(code));
  assert(region);
  MEMORY_BASIC_INFORMATION info;
  assert(VirtualQuery(region, &info, sizeof(info)) == sizeof(info));
  assert(info.Protect == PAGE_READWRITE);
  memcpy(region, code, sizeof(code));
  assert(!sealcode(region, sizeof(code)));
  assert(VirtualQuery(region, &info, sizeof(info)) == sizeof(info));
  assert(info.Protect == PAGE_EXECUTE_READ);
  assert(((Entry)region)(NULL, NULL) == 7);
  unmap_region(region, sizeof(code));
}

typedef const char *(*LoaderError)(void);

static DWORD WINAPI missing_on_other_thread (void *library) {
  void *self = open_library(NULL, 0);
  LoaderError read_error = (LoaderError)find_symbol(self, "dlerror");
  assert(read_error && !read_error());
  assert(!find_symbol(library, "nupp_missing_win64_contract_export"));

  /* Leave this thread's error unread. */
  return 0;
}

static void linked_crt (void *self) {
  assert(find_symbol(self, "calloc") == (void *)(uintptr_t)calloc);
  assert(find_symbol(self, "free") == (void *)(uintptr_t)free);
  assert(find_symbol(self, "getenv") == (void *)(uintptr_t)getenv);
  assert(find_symbol(self, "malloc") == (void *)(uintptr_t)malloc);
  assert(find_symbol(self, "memchr") == (void *)(uintptr_t)memchr);
  assert(find_symbol(self, "memcpy") == (void *)(uintptr_t)memcpy);
  assert(find_symbol(self, "strerror") == (void *)(uintptr_t)strerror);
  assert(find_symbol(self, "strlen") == (void *)(uintptr_t)strlen);
}

static void lookup_error (void *self, void *kernel) {
  LoaderError read_error = (LoaderError)find_symbol(self, "dlerror");
  assert(read_error && !read_error());
  assert(!find_symbol(self, "nupp_missing_win64_contract_export"));
  linked_crt(self);
  assert(read_error());
  assert(!read_error());

  /* Neither named DLLs nor self fall back to the other module. */
  assert(!find_symbol(kernel, "dlerror"));
  assert(read_error());
  assert(!read_error());
  assert(!find_symbol(self, "GetSystemInfo"));
  assert(read_error());
  assert(!read_error());

  assert(!find_symbol(kernel, "nupp_missing_win64_contract_export"));
  assert(find_symbol(kernel, "GetSystemInfo"));
  assert(read_error());
  assert(!read_error());
  assert(find_symbol(kernel, "GetSystemInfo"));
  assert(!read_error());

  HANDLE thread =
      CreateThread(NULL, 0, missing_on_other_thread, kernel, 0, NULL);
  assert(thread);
  assert(WaitForSingleObject(thread, 5000) == WAIT_OBJECT_0);
  assert(CloseHandle(thread));
  assert(!read_error());
}

static void startup_pages_and_clock (void *self) {
  size_t (*size)(void) =
      (size_t (*)(void))find_symbol(self, "nupp_core_page_size");
  void *(*pages)(size_t) =
      (void *(*)(size_t))find_symbol(self, "nupp_core_map_pages");
  uint64_t (*release)(void *) =
      (uint64_t (*)(void *))find_symbol(self, "nupp_core_release_pages");
  uint64_t (*now)(void) =
      (uint64_t (*)(void))find_symbol(self, "nupp_core_monotonic_nanos");
  assert(size && pages && release && now);

  size_t page = size();
  assert(page && !(page & (page - 1)));
  unsigned char *base = pages(page * 2);
  assert(base && (uintptr_t)base % page == 0);
  MEMORY_BASIC_INFORMATION info;
  assert(VirtualQuery(base, &info, sizeof(info)) == sizeof(info));
  assert(info.State == MEM_COMMIT && info.Protect == PAGE_READWRITE);
  assert(info.RegionSize >= page * 2);
  assert(!base[0] && !base[page] && !base[page * 2 - 1]);
  base[page] = 42;
  assert(release(base + page) != 0);
  assert(base[page] == 42);
  assert(!release(base));

  uint64_t before = now();
  Sleep(1);
  assert(now() > before);
}

static void startup_poller (void *self) {
  int64_t (*open_poller)(void) =
      (int64_t (*)(void))find_symbol(self, "nupp_core_open_poller");
  int64_t (*wait)(uint64_t, uint64_t) =
      (int64_t (*)(uint64_t, uint64_t))find_symbol(self, "nupp_uv_wait");
  int64_t (*wait_owner)(uint64_t, uint64_t) =
      (int64_t (*)(uint64_t, uint64_t))find_symbol(self, "nupp_uv_wait_owner");
  int64_t (*close_poller)(uint64_t) =
      (int64_t (*)(uint64_t))find_symbol(self, "nupp_uv_close");
  int (*owner_active)(void) =
      (int (*)(void))find_symbol(self, "nupp_uv_owner_active");
  assert(open_poller && wait && wait_owner && close_poller && owner_active);

  int64_t opened = open_poller();
  assert(opened > 0);
  uint64_t token = (uint64_t)opened;
  assert(nupp_uv_processfd(token) == -1);
  assert(!owner_active());
  assert(!wait(token, 0));
  assert(!wait_owner(token, 1000000));
  assert(!close_poller(token));
  assert(wait(token, 0) == -EBADF && wait_owner(token, 0) == -EBADF);
  assert(!nupp_uv_shutdown());
}

#ifdef NUPP_WIN64_PROCESS
static void startup_pipes (void *self) {
  int64_t (*pipe)(uint64_t, uint64_t) =
      (int64_t (*)(uint64_t, uint64_t))find_symbol(self, "nupp_process_pipe");
  int64_t (*read)(int64_t, void *, uint64_t) =
      (int64_t (*)(int64_t, void *, uint64_t))find_symbol(self, "read");
  int64_t (*write)(int64_t, const void *, uint64_t) =
      (int64_t (*)(int64_t, const void *, uint64_t))find_symbol(self, "write");
  int (*close)(int64_t) = (int (*)(int64_t))find_symbol(self, "close");
  assert(pipe && read && write && close);
#ifndef NUPP_CORE_NET
  int64_t (*net)(void *, uint64_t, uint64_t, void *, uint64_t, uint64_t) =
      (int64_t (*)(void *, uint64_t, uint64_t, void *, uint64_t,
                   uint64_t))find_symbol(self, "nuppnetcall");
  void (*detach)(void *) = (void (*)(void *))find_symbol(self, "nuppnetdetach");
  assert(net && detach && net(self, 0, 0, NULL, 0, 0) == -ENOSYS);
  detach(self);
#endif

  int64_t pair = pipe(1, 1), poller = nupp_uv_open(-1);
  assert(pair > 0 && poller > 0);
  int64_t reader = (uint32_t)pair, writer = pair >> 32;
  assert(nupp_uv_arm((uint64_t)poller, reader, 1) == 0);
  char byte = 0;
  assert(read(reader, &byte, 1) == -1 && errno == EAGAIN);
  assert(write(writer, "q", 1) == 1);
  assert(close(writer) == 0);

  int64_t event = 0;

  for (int turn = 0; turn < 20 && !event; turn++) {
    event = nupp_uv_wait_owner((uint64_t)poller, 10000000);
  }

  assert(event == ((reader << 5) | 1));
  assert(read(reader, &byte, 1) == 1 && byte == 'q');
  assert(close(reader) == 0);
  assert(read(reader, &byte, 1) == -1 && errno == EBADF);
  assert(nupp_uv_shutdown() == 0);
}
#endif

static void wait_for_job (uint64_t poller, int64_t wake, uint64_t ticket) {
  assert((int64_t)ticket > 0);
  assert(!nupp_uv_arm(poller, wake, 1));

  int64_t event = 0;

  for (unsigned turn = 0; turn < 100 && !event; ++turn) {
    event = nupp_uv_wait_owner(poller, 50000000);
  }

  assert(event == ((wake << 5) | 1));
  assert(!nupp_uv_wait(poller, 0));
  assert(nuppiotake() == ticket);
  assert(!nuppiotake());
}

static void file_completions (void *self) {
  int64_t (*read_file)(int64_t, void *, uint64_t) =
      (int64_t (*)(int64_t, void *, uint64_t))find_symbol(self, "read");
  int (*close_file)(int64_t) = (int (*)(int64_t))find_symbol(self, "close");
  int *(*file_errno)(void) = (int *(*)(void))find_symbol(self, "__error");
  assert(read_file && close_file && file_errno);
  assert(find_symbol(self, "nupp_uv_open") == (void *)(uintptr_t)nupp_uv_open);
  assert(find_symbol(self, "nupp_uv_arm") == (void *)(uintptr_t)nupp_uv_arm);
  assert(find_symbol(self, "nupp_uv_preserve_file") ==
         (void *)(uintptr_t)nupp_uv_preserve_file);

  wchar_t directory[MAX_PATH], filename[MAX_PATH];
  DWORD count = GetTempPathW(MAX_PATH, directory);
  assert(count && count < MAX_PATH);
  assert(GetTempFileNameW(directory, L"n\u00fc", 0, filename));
  assert(DeleteFileW(filename));
  char *path = utf8_path(filename);
  assert(path);
  uint64_t bytes = strlen(path);

  int64_t descriptor = nupp_uv_open(-1);
  assert(descriptor > 0);
  uint64_t poller = (uint64_t)descriptor;
  assert((int64_t)nuppiostart(0) == -EINVAL);
  int64_t wake = (int64_t)nuppiostart(2);
  assert(wake == NUPP_UV_FILE_COMPLETION && wake > INT_MAX);
  assert((int64_t)nuppiostart(1) == wake);
  assert(nupp_uv_arm(poller, wake, 2) == -EINVAL);
  unsigned char output[8] = {0};
  assert(!read_file(wake, output, sizeof(output)));
  assert(close_file(wake) == -1 && *file_errno() == EBADF);

  /* The imported pool uses the Darwin bit layout on every host. */
  const uint64_t cloexec = 0x1000000, create = 0x200, directory_only = 0x100000;
  uint64_t ticket = nuppiosubmit(1, cloexec, (uintptr_t)path, bytes);
  wait_for_job(poller, wake, ticket);
  assert((int64_t)nuppiofinish(ticket, 0, 0) == -ENOENT);

  ticket = nuppiosubmit(1, cloexec | directory_only, (uintptr_t)path, bytes);
  wait_for_job(poller, wake, ticket);
  assert((int64_t)nuppiofinish(ticket, 0, 0) == -ENOTSUP);

  uint64_t mode = (UINT64_C(0600) << 32) | cloexec | create | 2;
  ticket = nuppiosubmit(1, mode, (uintptr_t)path, bytes);
  wait_for_job(poller, wake, ticket);
  int64_t file = (int64_t)nuppiofinish(ticket, 0, 0);
  assert(file >= 0 && file <= INT_MAX);

  unsigned char input[] = {'a', '\r', '\n', 0, 'z'};
  static const unsigned char expected[] = {'a', '\r', '\n', 0, 'z'};
  ticket = nuppiosubmit(3, (uint64_t)file, (uintptr_t)input, sizeof(input));
  memset(input, 0, sizeof(input));
  wait_for_job(poller, wake, ticket);
  assert(nuppiofinish(ticket, 0, 0) == sizeof(expected));

  assert(_lseeki64((int)file, 0, SEEK_SET) == 0);
  ticket = nuppiosubmit(2, (uint64_t)file, 0, sizeof(output));
  nupp_uv_preserve_file((uint64_t)file);
  assert(!close_file(file));
  wait_for_job(poller, wake, ticket);
  assert(nuppiofinish(ticket, (uintptr_t)output, sizeof(output)) ==
         sizeof(expected));
  assert(!memcmp(output, expected, sizeof(expected)));

  ticket = nuppiosubmit(2, (uint64_t)file, 0, sizeof(output));
  wait_for_job(poller, wake, ticket);
  assert((int64_t)nuppiofinish(ticket, 0, 0) == -EBADF);
  assert(!nupp_uv_close(poller));
  assert(!nupp_uv_shutdown());
  assert(DeleteFileW(filename));
  free(path);
}

int main (void) {
  assert(!header_refused(BUNDLE_WIN64));
  assert(header_refused(BUNDLE_ARM64));
  executable_region();
  void *self = open_library(NULL, 0);
  assert(self && find_symbol(self, "nupp_core_artifact_directory"));
  assert(find_symbol(self, "nupp_core_retain_guest_backing") ==
         (void *)(uintptr_t)nupp_core_retain_guest_backing);
  void *kernel = open_library("kernel32.dll", 0);
  assert(kernel && find_symbol(kernel, "GetSystemInfo"));
  lookup_error(self, kernel);
  startup_pages_and_clock(self);
  startup_poller(self);
#ifdef NUPP_WIN64_PROCESS
  startup_pipes(self);
#endif
  file_completions(self);
  assert(!close_library(kernel));
  assert(!close_library(self));

  return 0;
}
