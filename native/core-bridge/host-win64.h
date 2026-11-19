#ifndef NUPP_CORE_HOST_WIN64_H
#define NUPP_CORE_HOST_WIN64_H

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <io.h>
#include <process.h>
#include <wchar.h>

/* The packet still carries UTF-8 paths, even when the CRT needs UTF-16. */
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

/* Resolve the bundle itself, including reparse points, before publishing its
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

/* A broker subscription with no process wait descriptor. */
static int64_t win64_open_poller (void) {
  return nupp_uv_open(-1);
}

/* dlerror reports the last unread loader failure on this thread. The guest
 * finds this function through the existing symbol slot and process handle. */
static _Thread_local const char *loader_error;

static const char *take_loader_error (void) {
  const char *message = loader_error;
  loader_error = NULL;

  return message;
}

/* Match the three loader packet signatures, including a borrowed self handle.
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

static void *find_symbol (void *library, const char *name) {
  if (library && library == GetModuleHandleW(NULL)) {
    /* Bind guest self imports to this executable's linked CRT. Named
     * libraries resolve only their own exports. */
    const struct {
      const char *name;
      void (*address)(void);
    } self_symbols[] = {
        {"calloc", (void (*)(void))calloc},
        {"dlerror", (void (*)(void))take_loader_error},
        {"free", (void (*)(void))free},
        {"getenv", (void (*)(void))getenv},
        {"malloc", (void (*)(void))malloc},
        {"memchr", (void (*)(void))memchr},
        {"memcpy", (void (*)(void))memcpy},
        {"nupp_core_map_pages", (void (*)(void))win64_map_pages},
        {"nupp_core_monotonic_nanos", (void (*)(void))uv_hrtime},
        {"nupp_core_open_poller", (void (*)(void))win64_open_poller},
        {"nupp_core_page_size", (void (*)(void))win64_page_size},
        {"nupp_core_release_pages", (void (*)(void))win64_release_pages},
        {"nupp_uv_close", (void (*)(void))nupp_uv_close},
        {"nupp_uv_owner_active", (void (*)(void))nupp_uv_owner_active},
        {"nupp_uv_wait", (void (*)(void))nupp_uv_wait},
        {"nupp_uv_wait_owner", (void (*)(void))nupp_uv_wait_owner},
        {"strerror", (void (*)(void))strerror},
        {"strlen", (void (*)(void))strlen},
    };

    for (size_t i = 0; i < sizeof(self_symbols) / sizeof(self_symbols[0]);
         ++i) {
      if (!strcmp(name, self_symbols[i].name)) {
        return (void *)(uintptr_t)self_symbols[i].address;
      }
    }
  }

  FARPROC address = library ? GetProcAddress((HMODULE)library, name) : NULL;

  if (!address) {
    loader_error = "Windows loader cannot find the symbol";
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
