/**
 * @file
 * @brief POSIX file constants and calls used by the native core.
 */

#ifndef NUPP_CORE_HOST_POSIX_H
#define NUPP_CORE_HOST_POSIX_H

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

/** Open flags, in the order declared by hostfiles.nupp. */
struct openmodes {
  int32_t readonly;
  int32_t writeonly;
  int32_t readwrite;
  int32_t closeonexec;
  int32_t nonblock;
  int32_t append;
  int32_t create;
  int32_t truncate;
  int32_t exclusive;
  int32_t directory;
};

/** The SDK's flags for this process. */
const struct openmodes *nupp_core_open_modes (void) {
  static const struct openmodes modes = {
      O_RDONLY, O_WRONLY, O_RDWR,  O_CLOEXEC, O_NONBLOCK,
      O_APPEND, O_CREAT,  O_TRUNC, O_EXCL,    O_DIRECTORY};

  return &modes;
}

/** Gives the guest a fixed signature for libc's variadic open. */
int32_t nupp_core_open_file (const char *path, int64_t flags, int64_t mode) {
  return open(path, (int)flags, (mode_t)mode);
}

/** Opens a directory relative to a descriptor without following a symlink. */
int32_t nupp_core_open_directory (int64_t parent, const char *path) {
  int at = parent < 0 ? AT_FDCWD : (int)parent;
  int fd = openat(at, path, O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);

  if (fd < 0 && errno == ELOOP) {
    errno = ENOTDIR;
  }

  return fd;
}

/** The next directory entry's name, valid until the next read. */
const char *nupp_core_next_name (DIR *directory) {
  struct dirent *entry = readdir(directory);

  return entry ? entry->d_name : NULL;
}

/** Removes a file or directory relative to a descriptor. */
int32_t nupp_core_unlink_entry (int64_t parent, const char *path,
                                uint64_t directory) {
  int at = parent < 0 ? AT_FDCWD : (int)parent;

  return unlinkat(at, path, directory == 1 ? AT_REMOVEDIR : 0);
}

/** The fields the guest reads from the native struct stat. */
struct filestatus {
  uint64_t mode;
  int64_t size;
  int64_t modifiedseconds;
  int64_t modifiednanos;
};

static void copyfilestatus (struct filestatus *out, const struct stat *status) {
  out->mode = (uint64_t)status->st_mode;
  out->size = (int64_t)status->st_size;
#ifdef __APPLE__
  out->modifiedseconds = (int64_t)status->st_mtimespec.tv_sec;
  out->modifiednanos = (int64_t)status->st_mtimespec.tv_nsec;
#else
  out->modifiedseconds = (int64_t)status->st_mtim.tv_sec;
  out->modifiednanos = (int64_t)status->st_mtim.tv_nsec;
#endif
}

/** Reads metadata by path, optionally following a symbolic link. */
int32_t nupp_core_stat_file (const char *path, uint64_t follow,
                             struct filestatus *out) {
  struct stat status;
  int result = follow ? stat(path, &status) : lstat(path, &status);

  if (!result) {
    copyfilestatus(out, &status);
  }

  return result;
}

/** Reads metadata from an open descriptor. */
int32_t nupp_core_stat_descriptor (int64_t fd, struct filestatus *out) {
  struct stat status;
  int result = fstat((int)fd, &status);

  if (!result) {
    copyfilestatus(out, &status);
  }

  return result;
}

/** Flushes file data and metadata to the backing store. */
int32_t nupp_core_sync_file (int64_t fd) {
#ifdef __APPLE__

  return fcntl((int)fd, F_FULLFSYNC);
#else

  return fsync((int)fd);
#endif
}

/** os.tmpname's mkstemp template, as Lua's own: LUA_TMPNAMTEMPLATE. */
const char *nupptemporarytemplate (void) {
  return "/tmp/lua_XXXXXX";
}

/** The executable path's byte length, copied out when it fits. */
int64_t nupp_core_executable_path (char *out, uint64_t room) {
  char path[PATH_MAX];
#ifdef __APPLE__
  uint32_t capacity = sizeof(path);

  if (_NSGetExecutablePath(path, &capacity)) {
    return -EINVAL;
  }

  size_t length = strlen(path);
#else
  ssize_t bytes = readlink("/proc/self/exe", path, sizeof(path));

  if (bytes < 0) {
    return -errno;
  }

  if ((size_t)bytes == sizeof(path)) {
    return -ENAMETOOLONG;
  }

  size_t length = (size_t)bytes;
#endif

  if (length && length <= room) {
    memcpy(out, path, length);
  }

  return (int64_t)length;
}

#endif
