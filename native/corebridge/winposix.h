/**
 * @file
 * @brief The POSIX calls the core's host modules make, for Windows.
 *
 * The runtime's host modules (src/nupp/runtime/core/host*.nupp) declare the
 * C library calls they make by their POSIX names, with fixed-width types and
 * the layouts of macOS's and glibc's `struct tm` and `struct timespec`. On
 * Windows the bridge resolves those names to these functions
 * (hostwin64.h, find_symbol), which keep the declared signatures and
 * layouts over the UCRT and Win32. Paths cross as UTF-8 and come back with
 * forward slashes. Each call that fails sets errno to its POSIX number.
 */

#ifndef NUPP_CORE_WINPOSIX_H
#define NUPP_CORE_WINPOSIX_H

#include <stdint.h>

/** A broken-down time as hostclock.nupp declares it (macOS and glibc). */
struct nupptm {
  int32_t sec, min, hour, mday, mon, year, wday, yday, isdst;
  int64_t gmtoff;
  const char *zone;
};

/** A time as hostclock.nupp declares it. */
struct nupptimespec {
  int64_t seconds, nanos;
};

/** Metadata as hostfilesystem.nupp declares it (hostposix.h). */
struct nuppfilestatus {
  uint64_t mode;
  int64_t size;
  int64_t modifiedseconds;
  int64_t modifiednanos;
};

/* Clocks and calendar (hostclock.nupp). */
int64_t nuppwintime (int64_t *out);
uint64_t nuppwinclock (void);
int32_t nuppwinclockgettime (int64_t id, struct nupptimespec *out);
int32_t nuppwinnanosleep (const struct nupptimespec *wanted,
                          struct nupptimespec *left);
int32_t nuppwingetpid (void);
struct nupptm *nuppwingmtime (const int64_t *t, struct nupptm *out);
struct nupptm *nuppwinlocaltime (const int64_t *t, struct nupptm *out);
int64_t nuppwinmktime (struct nupptm *tm);
uint64_t nuppwinstrftime (char *out, uint64_t room, const char *format,
                          const struct nupptm *tm);

/* Files and directories (hostfiles.nupp). */
const void *nuppwinopenmodes (void);
int32_t nuppwinopenfile (const char *path, int64_t flags, int64_t mode);
int32_t nuppwinopendirectory (int64_t parent, const char *path);
int32_t nuppwinunlinkentry (int64_t parent, const char *path,
                            uint64_t directory);
int64_t nuppwinlseek (int64_t fd, int64_t offset, int64_t whence);
int32_t nuppwindup (int64_t fd);
int32_t nuppwinremove (const char *path);
int32_t nuppwinrename (const char *from, const char *to);
int32_t nuppwinmkstemp (char *pattern);
void *nuppwinfdopendir (int64_t fd);
void nuppwinrewinddir (void *directory);
const char *nuppwinnextname (void *directory);
int32_t nuppwinclosedir (void *directory);

/** Whether a descriptor is one nuppwinopendirectory issued, and closing it. */
int nuppwindirectorykey (int64_t fd);
int32_t nuppwinclosedirectorykey (int64_t fd);

/* Metadata, links and paths (hostfilesystem.nupp). */
int32_t nuppwinstatfile (const char *path, uint64_t follow,
                         struct nuppfilestatus *out);
int32_t nuppwinstatdescriptor (int64_t fd, struct nuppfilestatus *out);
int64_t nuppwinreadlink (const char *path, char *out, uint64_t room);
int32_t nuppwinmkdir (const char *path, int64_t mode);
int32_t nuppwinsymlink (const char *target, const char *link);
int32_t nuppwinchmod (const char *path, int64_t mode);
int32_t nuppwinsyncfile (int64_t fd);
char *nuppwingetcwd (char *out, uint64_t room);
char *nuppwinrealpath (const char *path, char *out);
int64_t nuppwinexecutablepath (char *out, uint64_t room);

/** os.tmpname's mkstemp template in the user's temporary directory. */
const char *nupptemporarytemplate (void);

/** getentropy over the system's preferred generator. */
int32_t nuppwingetentropy (void *buffer, uint64_t size);

/* The loader's and C library's remaining POSIX names. */
uint64_t nuppwinthreadself (void);
char *nuppwinstrdup (const char *text);

#endif
