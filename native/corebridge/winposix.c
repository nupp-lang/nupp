/**
 * @file
 * @brief The POSIX calls the core's host modules make, over the UCRT and Win32.
 *
 * See winposix.h. Directories opened by descriptor have no CRT descriptor on
 * Windows, so they are issued keys of their own above the CRT's range and
 * below the pipe adapter's (winpipe.c), each naming the directory's absolute
 * path. Files are opened with every sharing mode, so a file can be renamed
 * or removed while it is open, as on POSIX.
 */

/* rand_s, and the Windows 10 file disposition, timer and link flags. */
#define _CRT_RAND_S
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <bcrypt.h>
#include <winioctl.h>

#include "winposix.h"

#include <errno.h>
#include <fcntl.h>
#include <io.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <wchar.h>

/* POSIX's file type and permission bits, as the guest reads st_mode. */
enum {
  MODE_DIRECTORY = 0040000,
  MODE_FILE = 0100000,
  MODE_LINK = 0120000,
  MODE_WRITABLE = 0200,
  MODE_READABLE = 0444,
  MODE_DIRECTORY_PERMISSIONS = 0755,
  MODE_FILE_PERMISSIONS = 0644
};

/* The open flags the guest passes (nuppwinopenmodes): the UCRT's, and a bit
 * of the bridge's own asking for a directory. */
enum { OPEN_DIRECTORY = 0x01000000 };

/* Directory keys: FIRST_DIRECTORY_KEY plus a slot, below winpipe.c's keys. */
enum { FIRST_DIRECTORY_KEY = 0x30000000, MAX_DIRECTORIES = 1024 };

/* 100-nanosecond FILETIME ticks: a second's, and those from 1601 to 1970. */
static const int64_t TICKS_PER_SECOND = INT64_C(10000000);
static const int64_t EPOCH_TICKS = INT64_C(116444736000000000);
static const int64_t NANOS_PER_TICK = 100;
static const int64_t NANOS_PER_SECOND = INT64_C(1000000000);
static const int64_t MICROS_PER_TICK_DIVISOR = 10;
static const int64_t NANOS_PER_MILLI = 1000000;

/* The attempts mkstemp makes, and the pattern's random suffix. */
enum { TEMPORARY_ATTEMPTS = 100, TEMPLATE_SUFFIX = 6 };

/* FSCTL_GET_REPARSE_POINT's largest answer. */
enum { REPARSE_BYTES = 16 * 1024 };

/* What the bridge reads of a reparse point (ntifs.h's REPARSE_DATA_BUFFER). */
struct reparsedata {
  ULONG tag;
  USHORT length;
  USHORT reserved;
  USHORT substituteoffset, substitutelength, printoffset, printlength;

  /* A symbolic link's flags precede its path buffer; a junction's do not. */
  ULONG flags;
  WCHAR path[1];
};

enum { SYMLINK_RELATIVE = 1 };

static wchar_t *directorypaths[MAX_DIRECTORIES];
static SRWLOCK directorylock = SRWLOCK_INIT;

/** Converts a Win32 error to its POSIX errno, and sets errno to it. */
static int seterror (DWORD error) {
  int code;

  switch (error) {
    case ERROR_FILE_NOT_FOUND:
    case ERROR_PATH_NOT_FOUND:
    case ERROR_INVALID_NAME:
    case ERROR_BAD_NETPATH:
    case ERROR_BAD_PATHNAME:
    case ERROR_INVALID_DRIVE:
      code = ENOENT;
      break;
    case ERROR_ACCESS_DENIED:
    case ERROR_SHARING_VIOLATION:
    case ERROR_LOCK_VIOLATION:
      code = EACCES;
      break;
    case ERROR_ALREADY_EXISTS:
    case ERROR_FILE_EXISTS:
      code = EEXIST;
      break;
    case ERROR_DIR_NOT_EMPTY:
      code = ENOTEMPTY;
      break;
    case ERROR_DIRECTORY:
      code = ENOTDIR;
      break;
    case ERROR_NOT_SAME_DEVICE:
      code = EXDEV;
      break;
    case ERROR_INVALID_HANDLE:
      code = EBADF;
      break;
    case ERROR_NOT_ENOUGH_MEMORY:
    case ERROR_OUTOFMEMORY:
      code = ENOMEM;
      break;
    case ERROR_PRIVILEGE_NOT_HELD:
      code = EPERM;
      break;
    case ERROR_CANT_RESOLVE_FILENAME:
      code = ELOOP;
      break;
    case ERROR_FILENAME_EXCED_RANGE:
      code = ENAMETOOLONG;
      break;
    case ERROR_DISK_FULL:
    case ERROR_HANDLE_DISK_FULL:
      code = ENOSPC;
      break;
    case ERROR_NOT_A_REPARSE_POINT:
    case ERROR_INVALID_PARAMETER:
      code = EINVAL;
      break;
    default:
      code = EIO;
      break;
  }

  errno = code;

  return code;
}

/** Fails with the calling thread's last Win32 error. */
static int failwin32 (void) {
  seterror(GetLastError());

  return -1;
}

static int failerrno (int code) {
  errno = code;

  return -1;
}

/** A UTF-8 path as a new UTF-16 one with backslashes, or NULL with errno. */
static wchar_t *widen (const char *path) {
  if (!path) {
    errno = EINVAL;

    return NULL;
  }

  int length =
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
  wchar_t *wide = length ? malloc((size_t)length * sizeof(*wide)) : NULL;

  if (!wide || !MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1,
                                    wide, length)) {
    free(wide);
    errno = length ? ENOMEM : EINVAL;

    return NULL;
  }

  for (wchar_t *c = wide; *c; ++c) {
    if (*c == L'/') {
      *c = L'\\';
    }
  }

  return wide;
}

/** A UTF-16 path as a new UTF-8 one with forward slashes, without the
 * \\?\ prefix of a final path: \\?\UNC\server\share is //server/share. */
static char *narrow (const wchar_t *wide) {
  int unc = 0;

  if (!wcsncmp(wide, L"\\\\?\\UNC\\", 8)) {
    wide += 8;
    unc = 1;
  }
  else if (!wcsncmp(wide, L"\\\\?\\", 4) || !wcsncmp(wide, L"\\??\\", 4)) {
    wide += 4;
  }

  int length = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, -1,
                                   NULL, 0, NULL, NULL);
  size_t prefix = unc ? 2 : 0;
  char *utf8 = length ? malloc(prefix + (size_t)length) : NULL;

  if (!utf8 || !WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, -1,
                                    utf8 + prefix, length, NULL, NULL)) {
    free(utf8);
    errno = length ? ENOMEM : EILSEQ;

    return NULL;
  }

  if (unc) {
    utf8[0] = '/';
    utf8[1] = '/';
  }

  for (char *c = utf8; *c; ++c) {
    if (*c == '\\') {
      *c = '/';
    }
  }

  return utf8;
}

#ifdef __MINGW32__

/* The UCRT exports this, and MinGW's headers do not declare it. */
_invalid_parameter_handler __cdecl _set_thread_local_invalid_parameter_handler (
    _invalid_parameter_handler handler);
#endif

/* An invalid parameter the UCRT would end the process for fails the call. */
static void ignoreparameter (const wchar_t *expression, const wchar_t *function,
                             const wchar_t *file, unsigned int line,
                             uintptr_t reserved) {
  (void)expression;
  (void)function;
  (void)file;
  (void)line;
  (void)reserved;
}

#define GUARDED(result, call)                                                  \
  do {                                                                         \
    _invalid_parameter_handler previous =                                      \
        _set_thread_local_invalid_parameter_handler(ignoreparameter);          \
    (result) = (call);                                                         \
    _set_thread_local_invalid_parameter_handler(previous);                     \
  } while (0)

static int64_t unixticks (FILETIME time) {
  ULARGE_INTEGER ticks;
  ticks.LowPart = time.dwLowDateTime;
  ticks.HighPart = time.dwHighDateTime;

  return (int64_t)ticks.QuadPart - EPOCH_TICKS;
}

int64_t nuppwintime (int64_t *out) {
  int64_t now = (int64_t)_time64(NULL);

  if (out) {
    *out = now;
  }

  return now;
}

/** The processor time the process has used, in POSIX's microsecond ticks. */
uint64_t nuppwinclock (void) {
  FILETIME created, exited, kernel, user;

  if (!GetProcessTimes(GetCurrentProcess(), &created, &exited, &kernel,
                       &user)) {
    return (uint64_t)-1;
  }

  ULARGE_INTEGER k, u;
  k.LowPart = kernel.dwLowDateTime;
  k.HighPart = kernel.dwHighDateTime;
  u.LowPart = user.dwLowDateTime;
  u.HighPart = user.dwHighDateTime;

  return (k.QuadPart + u.QuadPart) / (uint64_t)MICROS_PER_TICK_DIVISOR;
}

/** CLOCK_REALTIME (0) reads the wall clock; any other the monotonic one. */
int32_t nuppwinclockgettime (int64_t id, struct nupptimespec *out) {
  if (!out) {
    return failerrno(EFAULT);
  }

  if (id == 0) {
    FILETIME now;
    GetSystemTimePreciseAsFileTime(&now);
    int64_t ticks = unixticks(now);
    out->seconds = ticks / TICKS_PER_SECOND;
    out->nanos = (ticks % TICKS_PER_SECOND) * NANOS_PER_TICK;

    return 0;
  }

  LARGE_INTEGER count, frequency;

  if (!QueryPerformanceCounter(&count) ||
      !QueryPerformanceFrequency(&frequency)) {
    return failwin32();
  }

  out->seconds = count.QuadPart / frequency.QuadPart;
  out->nanos = (count.QuadPart % frequency.QuadPart) * NANOS_PER_SECOND /
               frequency.QuadPart;

  return 0;
}

int32_t nuppwinnanosleep (const struct nupptimespec *wanted,
                          struct nupptimespec *left) {
  if (!wanted || wanted->seconds < 0 || wanted->nanos < 0 ||
      wanted->nanos >= NANOS_PER_SECOND) {
    return failerrno(EINVAL);
  }

  HANDLE timer = CreateWaitableTimerExW(
      NULL, NULL, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
  int64_t ticks =
      wanted->seconds * TICKS_PER_SECOND + wanted->nanos / NANOS_PER_TICK;

  if (timer) {
    LARGE_INTEGER due;
    due.QuadPart = -ticks;

    if (SetWaitableTimer(timer, &due, 0, NULL, NULL, FALSE)) {
      WaitForSingleObject(timer, INFINITE);
    }
    else {
      Sleep((DWORD)((wanted->seconds * 1000) +
                    (wanted->nanos + NANOS_PER_MILLI - 1) / NANOS_PER_MILLI));
    }

    CloseHandle(timer);
  }
  else {
    Sleep((DWORD)((wanted->seconds * 1000) +
                  (wanted->nanos + NANOS_PER_MILLI - 1) / NANOS_PER_MILLI));
  }

  if (left) {
    left->seconds = 0;
    left->nanos = 0;
  }

  return 0;
}

int32_t nuppwingetpid (void) {
  return (int32_t)GetCurrentProcessId();
}

static void totm (const struct nupptm *from, struct tm *to) {
  memset(to, 0, sizeof(*to));
  to->tm_sec = from->sec;
  to->tm_min = from->min;
  to->tm_hour = from->hour;
  to->tm_mday = from->mday;
  to->tm_mon = from->mon;
  to->tm_year = from->year;
  to->tm_wday = from->wday;
  to->tm_yday = from->yday;
  to->tm_isdst = from->isdst;
}

/* The time zone's names, as tm_zone points at them, per thread. */
static _Thread_local char zonenames[2][64];

static void fromtm (const struct tm *from, struct nupptm *to, int64_t gmtoff,
                    int utc) {
  to->sec = from->tm_sec;
  to->min = from->tm_min;
  to->hour = from->tm_hour;
  to->mday = from->tm_mday;
  to->mon = from->tm_mon;
  to->year = from->tm_year;
  to->wday = from->tm_wday;
  to->yday = from->tm_yday;
  to->isdst = from->tm_isdst;
  to->gmtoff = gmtoff;

  if (utc) {
    to->zone = "GMT";

    return;
  }

  int index = from->tm_isdst > 0 ? 1 : 0;
  size_t length = 0;

  if (_get_tzname(&length, zonenames[index], sizeof(zonenames[index]), index)) {
    zonenames[index][0] = 0;
  }

  to->zone = zonenames[index];
}

struct nupptm *nuppwingmtime (const int64_t *t, struct nupptm *out) {
  struct tm broken;
  __time64_t at = (__time64_t)*t;

  if (_gmtime64_s(&broken, &at)) {
    errno = EOVERFLOW;

    return NULL;
  }

  fromtm(&broken, out, 0, 1);

  return out;
}

/** The local offset east of UTC, in seconds, of a local broken-down time. */
static int64_t offset (const struct tm *local, __time64_t at) {
  struct tm copy = *local;

  return (int64_t)(_mkgmtime64(&copy) - at);
}

struct nupptm *nuppwinlocaltime (const int64_t *t, struct nupptm *out) {
  struct tm broken;
  __time64_t at = (__time64_t)*t;
  _tzset();

  if (_localtime64_s(&broken, &at)) {
    errno = EOVERFLOW;

    return NULL;
  }

  fromtm(&broken, out, offset(&broken, at), 0);

  return out;
}

int64_t nuppwinmktime (struct nupptm *tm) {
  struct tm broken;
  totm(tm, &broken);
  _tzset();
  __time64_t at = _mktime64(&broken);

  if (at == -1) {
    errno = EOVERFLOW;

    return -1;
  }

  fromtm(&broken, tm, offset(&broken, at), 0);

  return (int64_t)at;
}

uint64_t nuppwinstrftime (char *out, uint64_t room, const char *format,
                          const struct nupptm *tm) {
  struct tm broken;
  totm(tm, &broken);
  size_t written;
  GUARDED(written, strftime(out, room > SIZE_MAX ? SIZE_MAX : (size_t)room,
                            format, &broken));

  return (uint64_t)written;
}

const void *nuppwinopenmodes (void) {
  /* The order of hostfiles.nupp's OpenModes: read, write, both, no-inherit,
   * non-blocking (none for files), append, create, truncate, exclusive and
   * directory. */
  static const int32_t modes[] = {
      _O_RDONLY, _O_WRONLY, _O_RDWR,  _O_NOINHERIT, 0,
      _O_APPEND, _O_CREAT,  _O_TRUNC, _O_EXCL,      OPEN_DIRECTORY};

  return modes;
}

/** A directory path's slot key, claimed under the lock; -1 with EMFILE. */
static int32_t claimdirectory (wchar_t *path) {
  AcquireSRWLockExclusive(&directorylock);

  for (int slot = 0; slot < MAX_DIRECTORIES; ++slot) {
    if (!directorypaths[slot]) {
      directorypaths[slot] = path;
      ReleaseSRWLockExclusive(&directorylock);

      return FIRST_DIRECTORY_KEY + slot;
    }
  }

  ReleaseSRWLockExclusive(&directorylock);
  free(path);

  return failerrno(EMFILE);
}

int nuppwindirectorykey (int64_t fd) {
  return fd >= FIRST_DIRECTORY_KEY &&
         fd < FIRST_DIRECTORY_KEY + MAX_DIRECTORIES;
}

/** A copy of a directory key's path, or NULL with EBADF. */
static wchar_t *directorypath (int64_t fd) {
  wchar_t *copy = NULL;

  if (!nuppwindirectorykey(fd)) {
    errno = EBADF;

    return NULL;
  }

  AcquireSRWLockShared(&directorylock);
  const wchar_t *path = directorypaths[fd - FIRST_DIRECTORY_KEY];

  if (path) {
    copy = _wcsdup(path);
  }

  ReleaseSRWLockShared(&directorylock);

  if (!copy) {
    errno = path ? ENOMEM : EBADF;
  }

  return copy;
}

int32_t nuppwinclosedirectorykey (int64_t fd) {
  if (!nuppwindirectorykey(fd)) {
    return failerrno(EBADF);
  }

  AcquireSRWLockExclusive(&directorylock);
  wchar_t *path = directorypaths[fd - FIRST_DIRECTORY_KEY];
  directorypaths[fd - FIRST_DIRECTORY_KEY] = NULL;
  ReleaseSRWLockExclusive(&directorylock);

  if (!path) {
    return failerrno(EBADF);
  }

  free(path);

  return 0;
}

/** `path` relative to directory key `parent`, or to the working directory
 * when parent is negative, as a new absolute UTF-16 path. */
static wchar_t *resolve (int64_t parent, const char *path) {
  wchar_t *wide = widen(path);

  if (!wide) {
    return NULL;
  }

  wchar_t *joined = wide;

  if (parent >= 0 &&
      !(wide[0] == L'\\' || (wide[0] && wide[1] == L':' && wide[2] == L'\\'))) {
    wchar_t *base = directorypath(parent);

    if (!base) {
      free(wide);

      return NULL;
    }

    size_t baselength = wcslen(base), length = wcslen(wide);
    joined = malloc((baselength + length + 2) * sizeof(*joined));

    if (joined) {
      memcpy(joined, base, baselength * sizeof(*joined));
      joined[baselength] = L'\\';
      memcpy(joined + baselength + 1, wide, (length + 1) * sizeof(*joined));
    }

    free(base);
    free(wide);

    if (!joined) {
      errno = ENOMEM;

      return NULL;
    }
  }

  DWORD length = GetFullPathNameW(joined, 0, NULL, NULL);
  wchar_t *full = length ? malloc((size_t)length * sizeof(*full)) : NULL;
  DWORD written = full ? GetFullPathNameW(joined, length, full, NULL) : 0;
  free(joined);

  if (!written || written >= length) {
    free(full);
    seterror(full ? GetLastError() : ERROR_NOT_ENOUGH_MEMORY);

    return NULL;
  }

  return full;
}

/** Whether path's nearest existing ancestor is something other than a
 * directory, which POSIX reports as ENOTDIR rather than ENOENT. */
static int throughfile (const wchar_t *path) {
  wchar_t *copy = _wcsdup(path);
  int file = 0;

  for (wchar_t *c = copy ? copy + wcslen(copy) : NULL; c && c > copy; --c) {
    if (*c != L'\\') {
      continue;
    }

    *c = 0;
    DWORD attributes = GetFileAttributesW(copy);

    if (attributes != INVALID_FILE_ATTRIBUTES) {
      file = !(attributes & FILE_ATTRIBUTE_DIRECTORY);
      break;
    }
  }

  free(copy);

  return file;
}

/** Fails with the thread's last Win32 error for path, as POSIX would: a
 * missing path under a file is ENOTDIR, and a directory refusing to be
 * opened as a file is EISDIR. */
static int failpath (const wchar_t *path) {
  DWORD error = GetLastError();

  if ((error == ERROR_PATH_NOT_FOUND || error == ERROR_FILE_NOT_FOUND ||
       error == ERROR_DIRECTORY) &&
      throughfile(path)) {
    return failerrno(ENOTDIR);
  }

  if (error == ERROR_ACCESS_DENIED) {
    DWORD attributes = GetFileAttributesW(path);

    if (attributes != INVALID_FILE_ATTRIBUTES &&
        (attributes & FILE_ATTRIBUTE_DIRECTORY)) {
      return failerrno(EISDIR);
    }
  }

  seterror(error);

  return -1;
}

/** Opens a handle for metadata on path, following a final link or not. */
static HANDLE openmetadata (const wchar_t *path, int follow, DWORD access) {
  DWORD flags =
      FILE_FLAG_BACKUP_SEMANTICS | (follow ? 0 : FILE_FLAG_OPEN_REPARSE_POINT);

  return CreateFileW(path, access,
                     FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                     NULL, OPEN_EXISTING, flags, NULL);
}

static int32_t opendirectory (int64_t parent, const char *path, int follow) {
  wchar_t *full = resolve(parent, path);

  if (!full) {
    return -1;
  }

  DWORD attributes = GetFileAttributesW(full);

  if (attributes == INVALID_FILE_ATTRIBUTES) {
    int32_t failed = failpath(full);
    free(full);

    return failed;
  }

  if (!(attributes & FILE_ATTRIBUTE_DIRECTORY) ||
      (!follow && (attributes & FILE_ATTRIBUTE_REPARSE_POINT))) {
    free(full);

    return failerrno(ENOTDIR);
  }

  return claimdirectory(full);
}

int32_t nuppwinopendirectory (int64_t parent, const char *path) {
  return opendirectory(parent, path, 0);
}

int32_t nuppwinopenfile (const char *path, int64_t flags, int64_t mode) {
  if (flags & OPEN_DIRECTORY) {
    return opendirectory(-1, path, 1);
  }

  wchar_t *full = resolve(-1, path);

  if (!full) {
    return -1;
  }

  int access = (int)(flags & (_O_RDONLY | _O_WRONLY | _O_RDWR));
  DWORD existing = GetFileAttributesW(full);

  /* POSIX refuses to open a directory for writing, unless it asked to make
   * a new file, which the directory being there refuses first. */
  if (existing != INVALID_FILE_ATTRIBUTES &&
      (existing & FILE_ATTRIBUTE_DIRECTORY) && access != _O_RDONLY) {
    free(full);

    return failerrno((flags & _O_CREAT) && (flags & _O_EXCL) ? EEXIST : EISDIR);
  }

  DWORD desired = access == _O_WRONLY ? GENERIC_WRITE
                  : access == _O_RDWR ? GENERIC_READ | GENERIC_WRITE
                                      : GENERIC_READ;
  DWORD disposition = OPEN_EXISTING;

  if ((flags & _O_CREAT) && (flags & _O_EXCL)) {
    disposition = CREATE_NEW;
  }
  else if ((flags & _O_CREAT) && (flags & _O_TRUNC)) {
    disposition = CREATE_ALWAYS;
  }
  else if (flags & _O_CREAT) {
    disposition = OPEN_ALWAYS;
  }
  else if (flags & _O_TRUNC) {
    disposition = TRUNCATE_EXISTING;
  }

  SECURITY_ATTRIBUTES inherit = {sizeof(inherit), NULL,
                                 (flags & _O_NOINHERIT) ? FALSE : TRUE};
  DWORD attributes = (flags & _O_CREAT) && !(mode & MODE_WRITABLE)
                         ? FILE_ATTRIBUTE_READONLY
                         : FILE_ATTRIBUTE_NORMAL;
  HANDLE file = CreateFileW(
      full, desired, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
      &inherit, disposition, attributes | FILE_FLAG_BACKUP_SEMANTICS, NULL);

  if (file == INVALID_HANDLE_VALUE) {
    int32_t failed = failpath(full);
    free(full);

    return failed;
  }

  free(full);

  BY_HANDLE_FILE_INFORMATION information;

  if (GetFileInformationByHandle(file, &information) &&
      (information.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) &&
      access != _O_RDONLY) {
    CloseHandle(file);

    return failerrno(EISDIR);
  }

  int crt = (int)(flags & (_O_APPEND | _O_NOINHERIT));
  int fd = _open_osfhandle((intptr_t)file, crt | _O_BINARY);

  if (fd < 0) {
    CloseHandle(file);
  }

  return fd;
}

/** Marks path for deletion as POSIX unlinks: while open, read-only or not. */
static int32_t unlinkpath (const wchar_t *path, int directory) {
  HANDLE file = CreateFileW(
      path, DELETE | FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
      OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
      NULL);

  if (file == INVALID_HANDLE_VALUE) {
    return failpath(path);
  }

  FILE_ATTRIBUTE_TAG_INFO tag;

  if (GetFileInformationByHandleEx(file, FileAttributeTagInfo, &tag,
                                   sizeof(tag))) {
    int isdirectory = (tag.FileAttributes & FILE_ATTRIBUTE_DIRECTORY) &&
                      !(tag.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT);

    if (isdirectory != directory) {
      CloseHandle(file);

      return failerrno(isdirectory ? EISDIR : ENOTDIR);
    }
  }

  FILE_DISPOSITION_INFO_EX disposition = {
      FILE_DISPOSITION_FLAG_DELETE | FILE_DISPOSITION_FLAG_POSIX_SEMANTICS |
      FILE_DISPOSITION_FLAG_IGNORE_READONLY_ATTRIBUTE};
  BOOL removed = SetFileInformationByHandle(file, FileDispositionInfoEx,
                                            &disposition, sizeof(disposition));

  if (!removed) {
    FILE_DISPOSITION_INFO legacy = {TRUE};
    removed = SetFileInformationByHandle(file, FileDispositionInfo, &legacy,
                                         sizeof(legacy));
  }

  DWORD error = GetLastError();
  CloseHandle(file);

  if (!removed) {
    seterror(error);

    return -1;
  }

  return 0;
}

int32_t nuppwinunlinkentry (int64_t parent, const char *path,
                            uint64_t directory) {
  wchar_t *full = resolve(parent, path);

  if (!full) {
    return -1;
  }

  int32_t result = unlinkpath(full, directory == 1);
  free(full);

  return result;
}

int64_t nuppwinlseek (int64_t fd, int64_t offset, int64_t whence) {
  int64_t position;

  if (fd < 0 || fd > INT_MAX || whence < 0 || whence > SEEK_END) {
    return failerrno(fd < 0 || fd > INT_MAX ? EBADF : EINVAL);
  }

  GUARDED(position, _lseeki64((int)fd, offset, (int)whence));

  return position;
}

int32_t nuppwindup (int64_t fd) {
  if (nuppwindirectorykey(fd)) {
    wchar_t *path = directorypath(fd);

    return path ? claimdirectory(path) : -1;
  }

  if (fd < 0 || fd > INT_MAX) {
    return failerrno(EBADF);
  }

  int copy;
  GUARDED(copy, _dup((int)fd));

  return copy;
}

int32_t nuppwinremove (const char *path) {
  wchar_t *full = resolve(-1, path);

  if (!full) {
    return -1;
  }

  DWORD attributes = GetFileAttributesW(full);
  int32_t result =
      attributes == INVALID_FILE_ATTRIBUTES
          ? failpath(full)
          : unlinkpath(full, (attributes & FILE_ATTRIBUTE_DIRECTORY) &&
                                 !(attributes & FILE_ATTRIBUTE_REPARSE_POINT));
  free(full);

  return result;
}

int32_t nuppwinrename (const char *from, const char *to) {
  wchar_t *source = resolve(-1, from),
          *target = source ? resolve(-1, to) : NULL;
  int32_t result = -1;

  if (source && target) {
    if (MoveFileExW(source, target, MOVEFILE_REPLACE_EXISTING)) {
      result = 0;
    }
    else {
      /* The path to blame: the source when it is missing, else the target. */
      DWORD error = GetLastError();
      int missing = GetFileAttributesW(source) == INVALID_FILE_ATTRIBUTES;
      SetLastError(error);
      result = failpath(missing ? source : target);
    }
  }

  free(source);
  free(target);

  return result;
}

int32_t nuppwinmkstemp (char *pattern) {
  static const char letters[] =
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  size_t length = pattern ? strlen(pattern) : 0;

  if (length < TEMPLATE_SUFFIX ||
      strcmp(pattern + length - TEMPLATE_SUFFIX, "XXXXXX")) {
    return failerrno(EINVAL);
  }

  char *suffix = pattern + length - TEMPLATE_SUFFIX;

  for (int attempt = 0; attempt < TEMPORARY_ATTEMPTS; ++attempt) {
    for (int at = 0; at < TEMPLATE_SUFFIX; ++at) {
      unsigned int value = 0;

      if (rand_s(&value)) {
        return failerrno(EIO);
      }

      suffix[at] = letters[value % (sizeof(letters) - 1)];
    }

    int fd = nuppwinopenfile(pattern, _O_RDWR | _O_CREAT | _O_EXCL,
                             MODE_FILE_PERMISSIONS);

    if (fd >= 0 || errno != EEXIST) {
      return fd;
    }
  }

  return failerrno(EEXIST);
}

/* A directory stream over a key the stream owns. */
struct directorystream {
  int64_t key;
  HANDLE find;
  int started;
  WIN32_FIND_DATAW entry;
  char *name;
};

void *nuppwinfdopendir (int64_t fd) {
  if (!nuppwindirectorykey(fd)) {
    errno = ENOTDIR;

    return NULL;
  }

  struct directorystream *stream = calloc(1, sizeof(*stream));

  if (!stream) {
    errno = ENOMEM;

    return NULL;
  }

  stream->key = fd;
  stream->find = INVALID_HANDLE_VALUE;

  return stream;
}

void nuppwinrewinddir (void *directory) {
  struct directorystream *stream = directory;

  if (stream->find != INVALID_HANDLE_VALUE) {
    FindClose(stream->find);
    stream->find = INVALID_HANDLE_VALUE;
  }

  stream->started = 0;
}

const char *nuppwinnextname (void *directory) {
  struct directorystream *stream = directory;
  free(stream->name);
  stream->name = NULL;

  if (!stream->started) {
    stream->started = 1;
    wchar_t *base = directorypath(stream->key);

    if (!base) {
      return NULL;
    }

    size_t length = wcslen(base);
    wchar_t *pattern = malloc((length + 3) * sizeof(*pattern));

    if (!pattern) {
      free(base);
      errno = ENOMEM;

      return NULL;
    }

    memcpy(pattern, base, length * sizeof(*pattern));
    memcpy(pattern + length, L"\\*", 3 * sizeof(*pattern));
    free(base);
    stream->find = FindFirstFileExW(pattern, FindExInfoBasic, &stream->entry,
                                    FindExSearchNameMatch, NULL, 0);
    free(pattern);

    if (stream->find == INVALID_HANDLE_VALUE) {
      DWORD error = GetLastError();

      if (error != ERROR_FILE_NOT_FOUND) {
        seterror(error);
      }

      return NULL;
    }
  }
  else if (stream->find == INVALID_HANDLE_VALUE ||
           !FindNextFileW(stream->find, &stream->entry)) {
    return NULL;
  }

  int length = WideCharToMultiByte(CP_UTF8, 0, stream->entry.cFileName, -1,
                                   NULL, 0, NULL, NULL);
  stream->name = length ? malloc((size_t)length) : NULL;

  if (!stream->name ||
      !WideCharToMultiByte(CP_UTF8, 0, stream->entry.cFileName, -1,
                           stream->name, length, NULL, NULL)) {
    errno = ENOMEM;

    return NULL;
  }

  return stream->name;
}

int32_t nuppwinclosedir (void *directory) {
  struct directorystream *stream = directory;

  if (!stream) {
    return failerrno(EBADF);
  }

  nuppwinrewinddir(stream);
  int32_t result = nuppwinclosedirectorykey(stream->key);
  free(stream->name);
  free(stream);

  return result;
}

/** Fills out from an open handle; link says the handle is a link's own. */
static int32_t describe (HANDLE file, int link, struct nuppfilestatus *out) {
  BY_HANDLE_FILE_INFORMATION information;

  if (!GetFileInformationByHandle(file, &information)) {
    return failwin32();
  }

  DWORD attributes = information.dwFileAttributes;
  int64_t ticks = unixticks(information.ftLastWriteTime);

  if (link) {
    out->mode = MODE_LINK | 0777;
  }
  else if (attributes & FILE_ATTRIBUTE_DIRECTORY) {
    out->mode = MODE_DIRECTORY | MODE_DIRECTORY_PERMISSIONS;
  }
  else {
    out->mode = MODE_FILE | ((attributes & FILE_ATTRIBUTE_READONLY)
                                 ? MODE_READABLE
                                 : MODE_FILE_PERMISSIONS);
  }

  out->size = (attributes & FILE_ATTRIBUTE_DIRECTORY)
                  ? 0
                  : (int64_t)(((uint64_t)information.nFileSizeHigh << 32) |
                              information.nFileSizeLow);
  out->modifiedseconds = ticks / TICKS_PER_SECOND;
  out->modifiednanos = (ticks % TICKS_PER_SECOND) * NANOS_PER_TICK;

  if (out->modifiednanos < 0) {
    out->modifiedseconds -= 1;
    out->modifiednanos += NANOS_PER_SECOND;
  }

  return 0;
}

/** Whether an open handle is a symbolic link or a junction. */
static int islink (HANDLE file) {
  FILE_ATTRIBUTE_TAG_INFO tag;

  return GetFileInformationByHandleEx(file, FileAttributeTagInfo, &tag,
                                      sizeof(tag)) &&
         (tag.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) &&
         (tag.ReparseTag == IO_REPARSE_TAG_SYMLINK ||
          tag.ReparseTag == IO_REPARSE_TAG_MOUNT_POINT);
}

int32_t nuppwinstatfile (const char *path, uint64_t follow,
                         struct nuppfilestatus *out) {
  wchar_t *full = resolve(-1, path);

  if (!full) {
    return -1;
  }

  HANDLE file = openmetadata(full, follow != 0, FILE_READ_ATTRIBUTES);

  if (file == INVALID_HANDLE_VALUE) {
    int32_t failed = failpath(full);
    free(full);

    return failed;
  }

  free(full);

  int32_t result = describe(file, !follow && islink(file), out);
  CloseHandle(file);

  return result;
}

int32_t nuppwinstatdescriptor (int64_t fd, struct nuppfilestatus *out) {
  if (nuppwindirectorykey(fd)) {
    wchar_t *path = directorypath(fd);

    if (!path) {
      return -1;
    }

    HANDLE file = openmetadata(path, 1, FILE_READ_ATTRIBUTES);
    free(path);

    if (file == INVALID_HANDLE_VALUE) {
      return failwin32();
    }

    int32_t result = describe(file, 0, out);
    CloseHandle(file);

    return result;
  }

  if (fd < 0 || fd > INT_MAX) {
    return failerrno(EBADF);
  }

  intptr_t handle;
  GUARDED(handle, _get_osfhandle((int)fd));

  if (handle == -1) {
    return failerrno(EBADF);
  }

  DWORD type = GetFileType((HANDLE)handle);

  if (type != FILE_TYPE_DISK) {
    /* A console or pipe: a character device with no size or time. */
    out->mode = (type == FILE_TYPE_PIPE ? 0010000 : 0020000) | 0666;
    out->size = 0;
    out->modifiedseconds = 0;
    out->modifiednanos = 0;

    return 0;
  }

  return describe((HANDLE)handle, 0, out);
}

int64_t nuppwinreadlink (const char *path, char *out, uint64_t room) {
  wchar_t *full = resolve(-1, path);

  if (!full) {
    return -1;
  }

  HANDLE file = openmetadata(full, 0, FILE_READ_ATTRIBUTES);
  free(full);

  if (file == INVALID_HANDLE_VALUE) {
    return failwin32();
  }

  struct reparsedata *data = malloc(REPARSE_BYTES);
  DWORD bytes = 0;
  BOOL read = data && DeviceIoControl(file, FSCTL_GET_REPARSE_POINT, NULL, 0,
                                      data, REPARSE_BYTES, &bytes, NULL);
  DWORD error = GetLastError();
  CloseHandle(file);

  if (!read) {
    free(data);
    seterror(data ? error : ERROR_NOT_ENOUGH_MEMORY);

    return -1;
  }

  const WCHAR *buffer;
  USHORT offset, length;

  if (data->tag == IO_REPARSE_TAG_SYMLINK) {
    buffer = data->path;
    int relative = (data->flags & SYMLINK_RELATIVE) != 0;
    offset = relative ? data->substituteoffset : data->printoffset;
    length = relative ? data->substitutelength : data->printlength;
  }
  else if (data->tag == IO_REPARSE_TAG_MOUNT_POINT) {
    /* A junction's path buffer starts where a link's flags would, and its
     * printed name may be empty beside its \??\ substitute. */
    buffer = (const WCHAR *)&data->flags;
    int printed = data->printlength != 0;
    offset = printed ? data->printoffset : data->substituteoffset;
    length = printed ? data->printlength : data->substitutelength;
  }
  else {
    free(data);

    return failerrno(EINVAL);
  }

  size_t count = length / sizeof(WCHAR);
  wchar_t *target = malloc((count + 1) * sizeof(*target));

  if (!target) {
    free(data);

    return failerrno(ENOMEM);
  }

  memcpy(target, (const char *)buffer + offset, length);
  target[count] = 0;
  free(data);
  char *utf8 = narrow(target);
  free(target);

  if (!utf8) {
    return -1;
  }

  /* readlink copies without a NUL, as much as room holds. */
  size_t size = strlen(utf8);
  memcpy(out, utf8, size < room ? size : (size_t)room);
  free(utf8);

  return (int64_t)(size < room ? size : room);
}

int32_t nuppwinmkdir (const char *path, int64_t mode) {
  (void)mode;
  wchar_t *full = resolve(-1, path);

  if (!full) {
    return -1;
  }

  int32_t result = CreateDirectoryW(full, NULL) ? 0 : failpath(full);
  free(full);

  return result;
}

int32_t nuppwinsymlink (const char *target, const char *link) {
  wchar_t *name = resolve(-1, link), *to = name ? widen(target) : NULL;

  if (!name || !to) {
    free(name);

    return -1;
  }

  /* A link to a directory is a directory link; a relative target names a
   * path beside the link. */
  DWORD flags = SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE;
  int absolute = to[0] == L'\\' || (to[0] && to[1] == L':');
  wchar_t *resolved = NULL;

  if (absolute) {
    resolved = _wcsdup(to);
  }
  else {
    wchar_t *slash = wcsrchr(name, L'\\');
    size_t prefix = slash ? (size_t)(slash - name) + 1 : 0;
    size_t length = wcslen(to);
    resolved = malloc((prefix + length + 1) * sizeof(*resolved));

    if (resolved) {
      memcpy(resolved, name, prefix * sizeof(*resolved));
      memcpy(resolved + prefix, to, (length + 1) * sizeof(*resolved));
    }
  }

  DWORD attributes =
      resolved ? GetFileAttributesW(resolved) : INVALID_FILE_ATTRIBUTES;
  free(resolved);

  if (attributes != INVALID_FILE_ATTRIBUTES &&
      (attributes & FILE_ATTRIBUTE_DIRECTORY)) {
    flags |= SYMBOLIC_LINK_FLAG_DIRECTORY;
  }

  int32_t result = CreateSymbolicLinkW(name, to, flags) ? 0 : failwin32();
  free(name);
  free(to);

  return result;
}

int32_t nuppwinchmod (const char *path, int64_t mode) {
  wchar_t *full = resolve(-1, path);

  if (!full) {
    return -1;
  }

  DWORD attributes = GetFileAttributesW(full);
  int32_t result;

  if (attributes == INVALID_FILE_ATTRIBUTES) {
    result = failwin32();
  }
  else {
    attributes = (mode & MODE_WRITABLE) ? attributes & ~FILE_ATTRIBUTE_READONLY
                                        : attributes | FILE_ATTRIBUTE_READONLY;
    result = SetFileAttributesW(full, attributes) ? 0 : failwin32();
  }

  free(full);

  return result;
}

int32_t nuppwinsyncfile (int64_t fd) {
  /* Windows has no directory sync: a rename is durable once its file is,
   * and NTFS journals the directory itself. */
  if (nuppwindirectorykey(fd)) {
    wchar_t *path = directorypath(fd);
    free(path);

    return path ? 0 : -1;
  }

  if (fd < 0 || fd > INT_MAX) {
    return failerrno(EBADF);
  }

  intptr_t handle;
  GUARDED(handle, _get_osfhandle((int)fd));

  if (handle == -1) {
    return failerrno(EBADF);
  }

  return FlushFileBuffers((HANDLE)handle) ? 0 : failwin32();
}

/** Answers text in out when it fits, or a new copy when out is NULL. */
static char *answer (char *text, char *out, uint64_t room) {
  if (!text || !out) {
    return text;
  }

  size_t length = strlen(text);

  if (length >= room) {
    free(text);
    errno = ERANGE;

    return NULL;
  }

  memcpy(out, text, length + 1);
  free(text);

  return out;
}

char *nuppwingetcwd (char *out, uint64_t room) {
  DWORD length = GetCurrentDirectoryW(0, NULL);
  wchar_t *wide = length ? malloc((size_t)length * sizeof(*wide)) : NULL;
  DWORD written = wide ? GetCurrentDirectoryW(length, wide) : 0;

  if (!written || written >= length) {
    free(wide);
    seterror(wide ? GetLastError() : ERROR_NOT_ENOUGH_MEMORY);

    return NULL;
  }

  char *text = narrow(wide);
  free(wide);

  return answer(text, out, room);
}

char *nuppwinrealpath (const char *path, char *out) {
  wchar_t *full = resolve(-1, path);

  if (!full) {
    return NULL;
  }

  HANDLE file = openmetadata(full, 1, FILE_READ_ATTRIBUTES);
  free(full);

  if (file == INVALID_HANDLE_VALUE) {
    failwin32();

    return NULL;
  }

  DWORD length = GetFinalPathNameByHandleW(file, NULL, 0, FILE_NAME_NORMALIZED);
  wchar_t *name = length ? malloc((size_t)length * sizeof(*name)) : NULL;
  DWORD written =
      name ? GetFinalPathNameByHandleW(file, name, length, FILE_NAME_NORMALIZED)
           : 0;
  DWORD error = GetLastError();
  CloseHandle(file);

  if (!written || written >= length) {
    free(name);
    seterror(name ? error : ERROR_NOT_ENOUGH_MEMORY);

    return NULL;
  }

  char *text = narrow(name);
  free(name);

  /* POSIX's PATH_MAX, which a caller's buffer must hold. */
  return answer(text, out, PATH_MAX);
}

int64_t nuppwinexecutablepath (char *out, uint64_t room) {
  DWORD capacity = MAX_PATH;

  for (;;) {
    wchar_t *wide = malloc((size_t)capacity * sizeof(*wide));

    if (!wide) {
      return -ENOMEM;
    }

    DWORD written = GetModuleFileNameW(NULL, wide, capacity);

    if (!written) {
      free(wide);

      return -seterror(GetLastError());
    }

    if (written < capacity) {
      char *text = narrow(wide);
      free(wide);

      if (!text) {
        return -errno;
      }

      size_t length = strlen(text);

      if (length && length <= room) {
        memcpy(out, text, length);
      }

      free(text);

      return (int64_t)length;
    }

    free(wide);

    if (capacity > UINT16_MAX) {
      return -ENAMETOOLONG;
    }

    capacity *= 2;
  }
}

/* getentropy's own limit, which POSIX fixes. */
enum { ENTROPY_MOST = 256 };

/* The template's name within the temporary directory. */
static const wchar_t TEMPLATE_NAME[] = L"lua_XXXXXX";

const char *nupptemporarytemplate (void) {
  static _Thread_local char *template;
  wchar_t directory[MAX_PATH + 1];
  DWORD length = GetTempPathW(MAX_PATH + 1, directory);

  if (!length || length > MAX_PATH) {
    failwin32();

    return NULL;
  }

  size_t extra = ARRAYSIZE(TEMPLATE_NAME);
  wchar_t *wide = malloc((length + extra) * sizeof(*wide));

  if (!wide) {
    errno = ENOMEM;

    return NULL;
  }

  memcpy(wide, directory, length * sizeof(*wide));
  memcpy(wide + length, TEMPLATE_NAME, extra * sizeof(*wide));
  char *text = narrow(wide);
  free(wide);

  if (!text) {
    return NULL;
  }

  free(template);
  template = text;

  return template;
}

int32_t nuppwingetentropy (void *buffer, uint64_t size) {
  if (size > ENTROPY_MOST) {
    return failerrno(EIO);
  }

  NTSTATUS status = BCryptGenRandom(NULL, buffer, (ULONG)size,
                                    BCRYPT_USE_SYSTEM_PREFERRED_RNG);

  return BCRYPT_SUCCESS(status) ? 0 : failerrno(EIO);
}

uint64_t nuppwinthreadself (void) {
  return (uint64_t)GetCurrentThreadId();
}

char *nuppwinstrdup (const char *text) {
  return _strdup(text);
}
