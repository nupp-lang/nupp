/* Win64 loader contract. Build with the same reactor inputs as the bridge. */
#define wmain bootstrap_wmain
#include "../../native/core-bridge/main.c" /* NOLINT(bugprone-suspicious-include) */
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

int main (void) {
  assert(!header_refused(BUNDLE_WIN64));
  assert(header_refused(BUNDLE_ARM64));
  executable_region();
  void *self = open_library(NULL, 0);
  assert(self && find_symbol(self, "nupp_core_artifact_directory"));
  void *kernel = open_library("kernel32.dll", 0);
  assert(kernel && find_symbol(kernel, "GetSystemInfo"));
  lookup_error(self, kernel);
  startup_pages_and_clock(self);
  startup_poller(self);
  assert(!close_library(kernel));
  assert(!close_library(self));

  return 0;
}
