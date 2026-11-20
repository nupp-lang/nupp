/**
 * @file
 * @brief Win64 path, memory, and loader adapters for the core bridge.
 */

#ifndef NUPP_CORE_HOST_WIN64_H
#define NUPP_CORE_HOST_WIN64_H

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <io.h>
#include <process.h>
#include <wchar.h>

#ifdef NUPP_WIN64_PROCESS
#include "process.h"
#include "winpipe.h"
#endif
#include "netbridge.h"
#include "winposix.h"

/** The packet still carries UTF-8 paths, even when the CRT needs UTF-16. */
static wchar_t *wide_path (const char *utf8) {
  int length =
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, -1, NULL, 0);
  wchar_t *wide = length ? malloc((size_t)length * sizeof(*wide)) : NULL;

  if (wide && !MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, -1,
                                   wide, length)) {
    free(wide);

    return NULL;
  }

  return wide;
}

static char *utf8_path (const wchar_t *wide) {
  int length = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, -1,
                                   NULL, 0, NULL, NULL);
  char *utf8 = length ? malloc((size_t)length) : NULL;

  if (utf8 && !WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, -1,
                                   utf8, length, NULL, NULL)) {
    free(utf8);

    return NULL;
  }

  return utf8;
}

/** Resolve the bundle itself, including reparse points, before publishing its
 * directory to the guest. Do not change process working directory. */
static char *canonical_path (const char *path) {
  wchar_t *wide = wide_path(path);

  if (!wide) {
    return NULL;
  }

  HANDLE file =
      CreateFileW(wide, FILE_READ_ATTRIBUTES,
                  FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
                  OPEN_EXISTING, 0, NULL);
  free(wide);

  if (file == INVALID_HANDLE_VALUE) {
    return NULL;
  }

  DWORD length = GetFinalPathNameByHandleW(file, NULL, 0, FILE_NAME_NORMALIZED);
  wchar_t *name = length ? malloc((size_t)length * sizeof(*name)) : NULL;
  DWORD written =
      name ? GetFinalPathNameByHandleW(file, name, length, FILE_NAME_NORMALIZED)
           : 0;
  CloseHandle(file);
  char *result = written && written < length ? utf8_path(name) : NULL;
  free(name);

  if (result) {
    for (char *c = result; *c; ++c) {
      if (*c == '\\') {
        *c = '/';
      }
    }
  }

  return result;
}

static int path_separator (wchar_t c) {
  return c == L'\\' || c == L'/';
}

/* Windows releases a whole reservation by its allocation base. */
static size_t win64_page_size (void) {
  SYSTEM_INFO info;
  GetSystemInfo(&info);

  return info.dwPageSize;
}

static void *win64_map_pages (size_t bytes) {
  return VirtualAlloc(NULL, bytes, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
}

static uint64_t win64_release_pages (void *base) {
  return VirtualFree(base, 0, MEM_RELEASE) ? 0 : GetLastError();
}

/** A broker subscription with no process wait descriptor. */
static int64_t win64_open_poller (void) {
  return nupp_uv_open(-1);
}

/** Reads a CRT file descriptor, or returns zero for the completion key. */
static int64_t win64_file_read (int64_t descriptor, void *bytes,
                                uint64_t count) {
#ifdef NUPP_WIN64_PROCESS

  if (nuppwinpipekey(descriptor)) {
    return nuppwinpiperead(descriptor, bytes, count);
  }

#endif

  /* Completions are taken directly from the queue on Windows. The guest's
   * drain of the readiness key has no kernel wake bytes to consume. */
  if (descriptor == NUPP_UV_FILE_COMPLETION) {
    return 0;
  }

  if (!nupp_uv_valid_file(descriptor) || count > INT_MAX) {
    errno = count > INT_MAX ? EINVAL : EBADF;

    return -1;
  }

  return _read((int)descriptor, bytes, (unsigned)count);
}

/** Closes a live CRT file descriptor, or reports EBADF for an invalid one. */
static int win64_file_close (int64_t descriptor) {
  if (nuppwindirectorykey(descriptor)) {
    return nuppwinclosedirectorykey(descriptor);
  }

#ifdef NUPP_WIN64_PROCESS

  if (nuppwinpipekey(descriptor)) {
    return nuppwinpipeclose(descriptor);
  }

#endif

  if (!nupp_uv_valid_file(descriptor)) {
    errno = EBADF;

    return -1;
  }

  return _close((int)descriptor);
}

#ifdef NUPP_WIN64_PROCESS

/** Writes through the owned pipe adapter or to a valid CRT descriptor. */
static int64_t win64_file_write (int64_t descriptor, const void *bytes,
                                 uint64_t count) {
  if (nuppwinpipekey(descriptor)) {
    return nuppwinpipewrite(descriptor, bytes, count);
  }

  if (!nupp_uv_valid_file(descriptor) || count > INT_MAX) {
    errno = count > INT_MAX ? EINVAL : EBADF;

    return -1;
  }

  return _write((int)descriptor, bytes, (unsigned)count);
}
#endif

/** The last unread loader failure on this thread. */
static _Thread_local const char *loader_error;

/** Takes the thread's loader error through the guest's dlerror symbol. */
static const char *take_loader_error (void) {
  const char *message = loader_error;
  loader_error = NULL;

  return message;
}

/** Match the three loader packet signatures, including a borrowed self handle.
 * Resolve transitive DLL imports beside an absolute library or in the default
 * safe search directories. */
static void *open_library (const char *path, int mode) {
  (void)mode;

  if (!path) {
    HMODULE self = GetModuleHandleW(NULL);

    if (!self) {
      loader_error = "Windows loader cannot open its process";
    }

    return self;
  }

  wchar_t *wide = wide_path(path);

  if (!wide) {
    loader_error = "Windows loader cannot convert the library path";

    return NULL;
  }

  for (wchar_t *c = wide; *c; ++c) {
    if (*c == L'/') {
      *c = L'\\';
    }
  }

  DWORD flags = LOAD_LIBRARY_SEARCH_DEFAULT_DIRS;

  if (wide[0] && ((path_separator(wide[0]) && path_separator(wide[1])) ||
                  (wide[1] == L':' && path_separator(wide[2])))) {
    flags |= LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR;
  }

  HMODULE library = LoadLibraryExW(wide, NULL, flags);
  free(wide);

  if (!library) {
    loader_error = "Windows loader cannot load the library";
  }

  return library;
}

void nupp_core_retain_guest_backing (void);
int32_t nuppsnprintf1 (char *out, uint64_t room, const char *format,
                       double value);
int32_t nuppsnprintf2 (char *out, uint64_t room, const char *format,
                       int64_t count, double value);
#ifndef NUPP_CORE_HTTP
int nupp_http_scope_detach (void *scope);
#endif

static void *find_linked_crt (const char *name) {

  /* A constant table can contain PE import thunks. Resolve each expression
   * at runtime to retain the address the bridge's linked CRT actually uses. */
#define LINKED_CRT(function)                                                   \
  if (!strcmp(name, #function)) {                                              \
    return (void *)(uintptr_t)function;                                        \
  }
  LINKED_CRT(calloc)
  LINKED_CRT(exit)
  LINKED_CRT(getenv)
  LINKED_CRT(free)
  LINKED_CRT(getenv)
  LINKED_CRT(malloc)
  LINKED_CRT(memchr)
  LINKED_CRT(memcpy)
  LINKED_CRT(strerror)
  LINKED_CRT(strlen)
#undef LINKED_CRT

  return NULL;
}

static int close_library (void *library);

static void *find_symbol (void *library, const char *name) {
  if (library && library == GetModuleHandleW(NULL)) {

    /* Bind guest self imports to this executable's linked CRT. Named
     * libraries resolve only their own exports. */
    void *crt = find_linked_crt(name);

    if (crt) {
      return crt;
    }

    const struct {
      const char *name;
      void (*address)(void);
    } self_symbols[] = {
        {"__error", (void (*)(void))_errno},
        {"chmod", (void (*)(void))nuppwinchmod},
        {"clock", (void (*)(void))nuppwinclock},
        {"clock_gettime", (void (*)(void))nuppwinclockgettime},
        {"close", (void (*)(void))win64_file_close},
        {"closedir", (void (*)(void))nuppwinclosedir},
        {"dlclose", (void (*)(void))close_library},
        {"dlerror", (void (*)(void))take_loader_error},
        {"dlopen", (void (*)(void))open_library},
        {"dlsym", (void (*)(void))find_symbol},
        {"dup", (void (*)(void))nuppwindup},
        {"fdopendir", (void (*)(void))nuppwinfdopendir},
        {"getcwd", (void (*)(void))nuppwingetcwd},
        {"getentropy", (void (*)(void))nuppwingetentropy},
        {"getpid", (void (*)(void))nuppwingetpid},
        {"gmtime_r", (void (*)(void))nuppwingmtime},
        {"localtime_r", (void (*)(void))nuppwinlocaltime},
        {"lseek", (void (*)(void))nuppwinlseek},
        {"mkdir", (void (*)(void))nuppwinmkdir},
        {"mkstemp", (void (*)(void))nuppwinmkstemp},
        {"mktime", (void (*)(void))nuppwinmktime},
        {"nanosleep", (void (*)(void))nuppwinnanosleep},
        {"nupp_core_executable_path", (void (*)(void))nuppwinexecutablepath},
        {"nupp_core_next_name", (void (*)(void))nuppwinnextname},
        {"nupp_core_open_directory", (void (*)(void))nuppwinopendirectory},
        {"nupp_core_open_file", (void (*)(void))nuppwinopenfile},
        {"nupp_core_open_modes", (void (*)(void))nuppwinopenmodes},
        {"nupp_core_stat_descriptor", (void (*)(void))nuppwinstatdescriptor},
        {"nupp_core_stat_file", (void (*)(void))nuppwinstatfile},
        {"nupp_core_sync_file", (void (*)(void))nuppwinsyncfile},
        {"nupp_core_unlink_entry", (void (*)(void))nuppwinunlinkentry},
        {"pthread_self", (void (*)(void))nuppwinthreadself},
        {"readlink", (void (*)(void))nuppwinreadlink},
        {"realpath", (void (*)(void))nuppwinrealpath},
        {"remove", (void (*)(void))nuppwinremove},
        {"rename", (void (*)(void))nuppwinrename},
        {"rewinddir", (void (*)(void))nuppwinrewinddir},
        {"strdup", (void (*)(void))nuppwinstrdup},
        {"strftime", (void (*)(void))nuppwinstrftime},
        {"symlink", (void (*)(void))nuppwinsymlink},
        {"time", (void (*)(void))nuppwintime},
        {"nupp_core_map_pages", (void (*)(void))win64_map_pages},
        {"nupp_core_monotonic_nanos", (void (*)(void))uv_hrtime},
        {"nupp_core_open_poller", (void (*)(void))win64_open_poller},
        {"nupp_core_page_size", (void (*)(void))win64_page_size},
        {"nupp_core_release_pages", (void (*)(void))win64_release_pages},
        {"nupp_core_retain_guest_backing",
         (void (*)(void))nupp_core_retain_guest_backing},
#ifndef NUPP_CORE_HTTP
        {"nupp_http_scope_detach", (void (*)(void))nupp_http_scope_detach},
#endif
        {"nupp_uv_arm", (void (*)(void))nupp_uv_arm},
        {"nupp_uv_close", (void (*)(void))nupp_uv_close},
        {"nupp_uv_open", (void (*)(void))nupp_uv_open},
        {"nupp_uv_owner_active", (void (*)(void))nupp_uv_owner_active},
        {"nupp_uv_preserve_file", (void (*)(void))nupp_uv_preserve_file},
        {"nupp_uv_wait", (void (*)(void))nupp_uv_wait},
        {"nupp_uv_wait_owner", (void (*)(void))nupp_uv_wait_owner},
        {"read", (void (*)(void))win64_file_read},
        {"nuppnetcall", (void (*)(void))nuppnetcall},
        {"nuppsnprintf1", (void (*)(void))nuppsnprintf1},
        {"nupptemporarytemplate", (void (*)(void))nupptemporarytemplate},
        {"nuppsnprintf2", (void (*)(void))nuppsnprintf2},
        {"nuppnetdetach", (void (*)(void))nuppnetdetach},
#ifdef NUPP_WIN64_PROCESS
        {"write", (void (*)(void))win64_file_write},
        {"nupp_process_pipe", (void (*)(void))nupp_process_pipe},
        {"nupp_process_spawn", (void (*)(void))nupp_process_spawn},
        {"nupp_process_watch", (void (*)(void))nupp_process_watch},
        {"nupp_process_unwatch", (void (*)(void))nupp_process_unwatch},
        {"nupp_process_reap", (void (*)(void))nupp_process_reap},
        {"nupp_process_kill", (void (*)(void))nupp_process_kill},
        {"nupp_process_environ", (void (*)(void))nupp_process_environ},
        {"nupp_process_envsame", (void (*)(void))nupp_process_envsame},
        {"nupp_process_signal", (void (*)(void))nupp_process_signal},
        {"nupp_process_cpus", (void (*)(void))nupp_process_cpus},
        {"nupp_process_systemname", (void (*)(void))nupp_process_systemname},
        {"nupp_uv_nowait", (void (*)(void))nupp_uv_nowait},
        {"nupp_uv_shutdown", (void (*)(void))nupp_uv_shutdown},
#endif
    };

    for (size_t i = 0; i < sizeof(self_symbols) / sizeof(self_symbols[0]);
         ++i) {
      if (!strcmp(name, self_symbols[i].name)) {
        return (void *)(uintptr_t)self_symbols[i].address;
      }
    }
  }

  FARPROC address = library ? GetProcAddress((HMODULE)library, name) : NULL;

  /* The process's own C library names (sin, strtod and the rest) resolve
   * in the UCRT the bridge links, which shares its errno and descriptors. */
  if (!address && library && library == GetModuleHandleW(NULL)) {
    HMODULE crt = GetModuleHandleW(L"ucrtbase.dll");
    address = crt ? GetProcAddress(crt, name) : NULL;
  }

  if (!address) {
    loader_error = "Windows loader cannot find the symbol";

    /* A port names what the guest asked for and the host lacks. */
    if (getenv("NUPP_CORE_TRACE_SYMBOLS")) {
      fprintf(stderr, "nupp-core: no symbol %s\n", name);
    }
  }

  return (void *)(uintptr_t)address;
}

static int close_library (void *library) {
  if (library &&
      (library == GetModuleHandleW(NULL) || FreeLibrary((HMODULE)library))) {
    return 0;
  }

  loader_error = "Windows loader cannot close the library";

  return -1;
}

#endif
