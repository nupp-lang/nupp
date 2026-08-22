/* The filesystem on POSIX.
 *
 * Nothing here is clever. What it is, is complete: every operation the binding
 * offers, spelled in the calls the platform actually has, so `files.c` never
 * reaches for one directly and the Windows file beside this one can differ
 * wherever it has to.
 */

/* `pipe2` is a Linux extension. Ask glibc for its declaration before any
 * system header is included, without changing the feature-test choices of the
 * other native translation units. */
#if defined(__linux__) && !defined(_GNU_SOURCE)
#   define _GNU_SOURCE
#endif

#include "platform.h"

#if !NUPP_WINDOWS

#include <dirent.h>
#include <pthread.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <poll.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

/* --- metadata ----------------------------------------------------------- */

static double nupp_modified_seconds(const struct stat *status) {
#if defined(__APPLE__)
    return (double)status->st_mtimespec.tv_sec
        + (double)status->st_mtimespec.tv_nsec / 1.0e9;
#elif defined(st_mtime) || defined(__USE_XOPEN2K8) || defined(_POSIX_C_SOURCE)
    return (double)status->st_mtim.tv_sec + (double)status->st_mtim.tv_nsec / 1.0e9;
#else
    return (double)status->st_mtime;
#endif
}

static void nupp_fill_info(const struct stat *status, NuppFileInfo *out) {
    if (S_ISLNK(status->st_mode)) {
        out->kind = NUPP_KIND_SYMLINK;
    } else if (S_ISDIR(status->st_mode)) {
        out->kind = NUPP_KIND_DIRECTORY;
    } else if (S_ISREG(status->st_mode)) {
        out->kind = NUPP_KIND_FILE;
    } else {
        out->kind = NUPP_KIND_OTHER;
    }
    /* Read-only means no write bit anywhere, which is the question a caller with
     * one file and no user model is asking. A file writable by its group and not
     * by this process still reads as writable, the same way it does everywhere
     * else that offers this bit. */
    out->readOnly = (status->st_mode & (S_IWUSR | S_IWGRP | S_IWOTH)) == 0;
    out->size = (uint64_t)status->st_size;
    out->modified = nupp_modified_seconds(status);
}

bool nupp_fs_stat(const char *path, bool follow, NuppFileInfo *out) {
    struct stat status;
    int answered = follow ? stat(path, &status) : lstat(path, &status);
    if (answered != 0) {
        nupp_fail_errno(path, errno);
        return false;
    }
    nupp_fill_info(&status, out);
    return true;
}

bool nupp_fs_read_link(const char *path, NuppBuffer *into) {
    /* A link's recorded length is a hint rather than a promise -- some
     * filesystems answer zero for it -- so the buffer grows until the call stops
     * filling it. */
    size_t capacity = 256;
    for (;;) {
        char *scratch = malloc(capacity);
        ssize_t written;
        if (scratch == NULL) {
            nupp_fail("out of memory");
            return false;
        }
        written = readlink(path, scratch, capacity);
        if (written < 0) {
            free(scratch);
            nupp_fail_errno(path, errno);
            return false;
        }
        if ((size_t)written < capacity) {
            nupp_buffer_append(into, scratch, (size_t)written);
            free(scratch);
            return true;
        }
        free(scratch);
        if (capacity > (size_t)1 << 20) {
            nupp_fail_format("%s: the link target is unreasonably long", path);
            return false;
        }
        capacity *= 2;
    }
}

bool nupp_fs_create_symlink(const char *target, const char *link, bool directory) {
    (void)directory;
    if (symlink(target, link) != 0) {
        nupp_fail_errno(link, errno);
        return false;
    }
    return true;
}

bool nupp_fs_set_read_only(const char *path, bool readOnly) {
    struct stat status;
    mode_t mode;
    if (stat(path, &status) != 0) {
        nupp_fail_errno(path, errno);
        return false;
    }
    mode = status.st_mode & 07777;
    if (readOnly) {
        mode &= (mode_t)~(S_IWUSR | S_IWGRP | S_IWOTH);
    } else {
        mode |= (S_IWUSR | S_IWGRP | S_IWOTH);
    }
    if (chmod(path, mode) != 0) {
        nupp_fail_errno(path, errno);
        return false;
    }
    return true;
}

/* --- directories -------------------------------------------------------- */

bool nupp_fs_create_directory_all(const char *path) {
    char *copy;
    size_t at;
    size_t length = strlen(path);
    if (length == 0) {
        nupp_fail("the directory name is empty");
        return false;
    }
    copy = malloc(length + 1);
    if (copy == NULL) {
        nupp_fail("out of memory");
        return false;
    }
    memcpy(copy, path, length + 1);
    /* Each prefix in turn, so a missing parent is created rather than reported.
     * An existing one is success: the caller asked for the tree to be there, not
     * for it to be new. */
    for (at = 1; at <= length; at++) {
        char saved;
        if (at != length && copy[at] != '/') {
            continue;
        }
        saved = copy[at];
        copy[at] = '\0';
        if (copy[0] != '\0' && mkdir(copy, 0777) != 0 && errno != EEXIST) {
            int number = errno;
            /* A component that is there but is not a directory only shows up
             * here, and EEXIST would have hidden it. */
            nupp_fail_errno(copy, number);
            copy[at] = saved;
            free(copy);
            return false;
        }
        copy[at] = saved;
    }
    free(copy);
    return true;
}

struct NuppDirectory {
    DIR *handle;
    char *path;
    size_t pathLength;
    char kind;
};

NuppDirectory *nupp_fs_open_directory(const char *path) {
    NuppDirectory *directory;
    DIR *handle = opendir(path);
    if (handle == NULL) {
        nupp_fail_errno(path, errno);
        return NULL;
    }
    directory = malloc(sizeof *directory);
    if (directory == NULL) {
        closedir(handle);
        nupp_fail("out of memory");
        return NULL;
    }
    directory->handle = handle;
    directory->pathLength = strlen(path);
    directory->path = malloc(directory->pathLength + 1);
    if (directory->path == NULL) {
        closedir(handle);
        free(directory);
        nupp_fail("out of memory");
        return NULL;
    }
    memcpy(directory->path, path, directory->pathLength + 1);
    directory->kind = 'o';
    return directory;
}

/* The entry's own kind. `d_type` answers it without a second system call where
 * the filesystem records it; where it does not, one `lstat` per entry is the
 * price of the answer being right. */
static char nupp_entry_kind(NuppDirectory *directory, struct dirent *entry) {
#ifdef DT_UNKNOWN
    switch (entry->d_type) {
        case DT_LNK: return 'l';
        case DT_DIR: return 'd';
        case DT_REG: return 'f';
        case DT_UNKNOWN: break;
        default: return 'o';
    }
#endif
    {
        struct stat status;
        size_t nameLength = strlen(entry->d_name);
        size_t total = directory->pathLength + 1 + nameLength;
        char *full = malloc(total + 1);
        char kind = 'o';
        if (full == NULL) {
            return 'o';
        }
        memcpy(full, directory->path, directory->pathLength);
        full[directory->pathLength] = '/';
        memcpy(full + directory->pathLength + 1, entry->d_name, nameLength + 1);
        if (lstat(full, &status) == 0) {
            if (S_ISLNK(status.st_mode)) {
                kind = 'l';
            } else if (S_ISDIR(status.st_mode)) {
                kind = 'd';
            } else if (S_ISREG(status.st_mode)) {
                kind = 'f';
            }
        }
        free(full);
        return kind;
    }
}

int nupp_fs_next_entry(NuppDirectory *directory, const char **name, char *kind) {
    for (;;) {
        struct dirent *entry;
        errno = 0;
        entry = readdir(directory->handle);
        if (entry == NULL) {
            if (errno != 0) {
                nupp_fail_errno(directory->path, errno);
                return -1;
            }
            return 0;
        }
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        *name = entry->d_name;
        *kind = nupp_entry_kind(directory, entry);
        return 1;
    }
}

void nupp_fs_close_directory(NuppDirectory *directory) {
    if (directory != NULL) {
        closedir(directory->handle);
        free(directory->path);
        free(directory);
    }
}

/* --- removal ------------------------------------------------------------ */

static bool nupp_remove_tree(const char *path) {
    NuppDirectory *directory = nupp_fs_open_directory(path);
    size_t pathLength = strlen(path);
    bool ok = true;
    if (directory == NULL) {
        return false;
    }
    for (;;) {
        const char *name;
        char kind;
        char *child;
        size_t nameLength;
        int step = nupp_fs_next_entry(directory, &name, &kind);
        if (step < 0) {
            ok = false;
            break;
        }
        if (step == 0) {
            break;
        }
        nameLength = strlen(name);
        child = malloc(pathLength + 1 + nameLength + 1);
        if (child == NULL) {
            nupp_fail("out of memory");
            ok = false;
            break;
        }
        memcpy(child, path, pathLength);
        child[pathLength] = '/';
        memcpy(child + pathLength + 1, name, nameLength + 1);
        /* A directory is descended into; a symbolic link to one is unlinked,
         * because following it would delete somewhere the caller did not name. */
        if (kind == 'd') {
            ok = nupp_remove_tree(child);
        } else if (unlink(child) != 0) {
            nupp_fail_errno(child, errno);
            ok = false;
        }
        free(child);
        if (!ok) {
            break;
        }
    }
    nupp_fs_close_directory(directory);
    if (!ok) {
        return false;
    }
    if (rmdir(path) != 0) {
        nupp_fail_errno(path, errno);
        return false;
    }
    return true;
}

bool nupp_fs_remove(const char *path, bool recursive) {
    struct stat status;
    if (lstat(path, &status) != 0) {
        nupp_fail_errno(path, errno);
        return false;
    }
    if (S_ISDIR(status.st_mode)) {
        if (recursive) {
            return nupp_remove_tree(path);
        }
        if (rmdir(path) != 0) {
            nupp_fail_errno(path, errno);
            return false;
        }
        return true;
    }
    if (unlink(path) != 0) {
        nupp_fail_errno(path, errno);
        return false;
    }
    return true;
}

bool nupp_fs_canonicalize(const char *path, NuppBuffer *into) {
    /* A null destination asks realpath to allocate, which is the only spelling
     * that cannot answer a path longer than the buffer somebody guessed at. */
    char *resolved = realpath(path, NULL);
    if (resolved == NULL) {
        nupp_fail_errno(path, errno);
        return false;
    }
    nupp_buffer_append(into, resolved, strlen(resolved));
    free(resolved);
    if (into->failed) {
        nupp_fail("out of memory");
        return false;
    }
    return true;
}

bool nupp_fs_rename(const char *from, const char *to) {
    if (rename(from, to) != 0) {
        nupp_fail_errno(from, errno);
        return false;
    }
    return true;
}

bool nupp_fs_replace(const char *from, const char *to) {
    return nupp_fs_rename(from, to);
}

/* --- open files --------------------------------------------------------- */

struct NuppFile {
    int descriptor;
    bool appending;
};

static NuppFile *nupp_wrap(int descriptor, bool appending) {
    NuppFile *file = malloc(sizeof *file);
    if (file == NULL) {
        close(descriptor);
        nupp_fail("out of memory");
        return NULL;
    }
    file->descriptor = descriptor;
    file->appending = appending;
    return file;
}

NuppFile *nupp_fs_open(const char *path, uint32_t mode) {
    int flags;
    int descriptor;
    switch (mode) {
        case 0: flags = O_RDONLY; break;
        case 1: flags = O_WRONLY | O_CREAT | O_TRUNC; break;
        case 2: flags = O_WRONLY | O_CREAT | O_APPEND; break;
        case 3: flags = O_RDWR; break;
        case 4: flags = O_RDWR | O_CREAT | O_TRUNC; break;
        case 5: flags = O_RDWR | O_CREAT | O_APPEND; break;
        default:
            nupp_fail("unknown file mode");
            return NULL;
    }
    descriptor = open(path, flags, 0666);
    if (descriptor < 0) {
        nupp_fail_errno(path, errno);
        return NULL;
    }
    return nupp_wrap(descriptor, (flags & O_APPEND) != 0);
}

NuppFile *nupp_fs_create_new(const char *path, bool *taken) {
    int descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, 0600);
    *taken = false;
    if (descriptor < 0) {
        if (errno == EEXIST) {
            *taken = true;
        } else {
            nupp_fail_errno(path, errno);
        }
        return NULL;
    }
    return nupp_wrap(descriptor, false);
}

bool nupp_fs_create_directory_new(const char *path, bool *taken) {
    *taken = false;
    if (mkdir(path, 0700) != 0) {
        if (errno == EEXIST) {
            *taken = true;
        } else {
            nupp_fail_errno(path, errno);
        }
        return false;
    }
    return true;
}

int64_t nupp_fs_read(NuppFile *file, uint8_t *into, size_t length) {
    for (;;) {
        ssize_t got = read(file->descriptor, into, length);
        if (got >= 0) {
            return (int64_t)got;
        }
        if (errno == EINTR) {
            continue;
        }
        nupp_fail_errno("cannot read", errno);
        return -1;
    }
}

int64_t nupp_fs_write(NuppFile *file, const uint8_t *from, size_t length) {
    size_t written = 0;
    while (written < length) {
        ssize_t step = write(file->descriptor, from + written, length - written);
        if (step < 0) {
            if (errno == EINTR) {
                continue;
            }
            nupp_fail_errno("cannot write", errno);
            return -1;
        }
        written += (size_t)step;
    }
    return (int64_t)length;
}

int64_t nupp_fs_seek(NuppFile *file, int64_t offset, uint32_t whence) {
    off_t moved;
    int origin;
    switch (whence) {
        case 0:
            origin = SEEK_SET;
            /* A negative absolute position is not a position. Clamping matches
             * what the binding above already promises. */
            if (offset < 0) {
                offset = 0;
            }
            break;
        case 1: origin = SEEK_CUR; break;
        case 2: origin = SEEK_END; break;
        default:
            nupp_fail("unknown seek origin");
            return -1;
    }
    moved = lseek(file->descriptor, (off_t)offset, origin);
    if (moved < 0) {
        nupp_fail_errno("cannot seek", errno);
        return -1;
    }
    return (int64_t)moved;
}

int64_t nupp_fs_size(NuppFile *file) {
    struct stat status;
    if (fstat(file->descriptor, &status) != 0) {
        nupp_fail_errno("cannot size", errno);
        return -1;
    }
    return (int64_t)status.st_size;
}

bool nupp_fs_flush(NuppFile *file) {
    /* Nothing is buffered on this side of the descriptor, so there is nothing to
     * push. The call stays because the binding promises it and because a
     * buffered implementation would need it. */
    (void)file;
    return true;
}

bool nupp_fs_sync(NuppFile *file) {
    if (fsync(file->descriptor) != 0) {
        nupp_fail_errno("cannot sync", errno);
        return false;
    }
    return true;
}

bool nupp_fs_close(NuppFile *file) {
    bool ok = true;
    if (file == NULL) {
        return true;
    }
    if (close(file->descriptor) != 0 && errno != EINTR) {
        nupp_fail_errno("cannot close", errno);
        ok = false;
    }
    free(file);
    return ok;
}

/* --- whole files -------------------------------------------------------- */

bool nupp_fs_read_whole(const char *path, NuppBuffer *into) {
    NuppFile *file = nupp_fs_open(path, 0);
    if (file == NULL) {
        return false;
    }
    for (;;) {
        uint8_t scratch[65536];
        int64_t got = nupp_fs_read(file, scratch, sizeof scratch);
        if (got < 0) {
            nupp_fs_close(file);
            return false;
        }
        if (got == 0) {
            break;
        }
        nupp_buffer_append(into, scratch, (size_t)got);
        if (into->failed) {
            nupp_fs_close(file);
            nupp_fail("out of memory");
            return false;
        }
    }
    nupp_fs_close(file);
    return true;
}

bool nupp_fs_write_whole(const char *path, const uint8_t *data, size_t length, bool append) {
    NuppFile *file = nupp_fs_open(path, append ? 2 : 1);
    bool ok;
    if (file == NULL) {
        return false;
    }
    ok = nupp_fs_write(file, data, length) >= 0;
    if (!nupp_fs_close(file)) {
        ok = false;
    }
    return ok;
}

bool nupp_fs_copy(const char *from, const char *to) {
    struct stat status;
    NuppFile *source = nupp_fs_open(from, 0);
    NuppFile *destination;
    bool ok = true;
    if (source == NULL) {
        return false;
    }
    if (fstat(source->descriptor, &status) != 0) {
        nupp_fail_errno(from, errno);
        nupp_fs_close(source);
        return false;
    }
    destination = nupp_fs_open(to, 1);
    if (destination == NULL) {
        nupp_fs_close(source);
        return false;
    }
    for (;;) {
        uint8_t scratch[65536];
        int64_t got = nupp_fs_read(source, scratch, sizeof scratch);
        if (got < 0) {
            ok = false;
            break;
        }
        if (got == 0) {
            break;
        }
        if (nupp_fs_write(destination, scratch, (size_t)got) < 0) {
            ok = false;
            break;
        }
    }
    /* The permission bits travel with the contents, which is what makes a copied
     * executable still one. */
    if (ok && fchmod(destination->descriptor, status.st_mode & 07777) != 0) {
        nupp_fail_errno(to, errno);
        ok = false;
    }
    nupp_fs_close(source);
    if (!nupp_fs_close(destination)) {
        ok = false;
    }
    return ok;
}

/* --- the environment ---------------------------------------------------- */

bool nupp_fs_current_directory(NuppBuffer *into) {
    size_t capacity = 512;
    for (;;) {
        char *scratch = malloc(capacity);
        if (scratch == NULL) {
            nupp_fail("out of memory");
            return false;
        }
        if (getcwd(scratch, capacity) != NULL) {
            nupp_buffer_append(into, scratch, strlen(scratch));
            free(scratch);
            return true;
        }
        free(scratch);
        if (errno != ERANGE) {
            nupp_fail_errno("cannot read the working directory", errno);
            return false;
        }
        if (capacity > (size_t)1 << 20) {
            nupp_fail("the working directory path is unreasonably long");
            return false;
        }
        capacity *= 2;
    }
}

bool nupp_fs_temporary_directory(NuppBuffer *into) {
    const char *named = nupp_environment("TMPDIR");
    if (named == NULL) {
        named = "/tmp";
    }
    {
        /* One trailing separator or none, so joining a name onto it is one rule
         * rather than two. */
        size_t length = strlen(named);
        while (length > 1 && named[length - 1] == '/') {
            length--;
        }
        nupp_buffer_append(into, named, length);
    }
    return true;
}

const char *nupp_environment(const char *name) {
    const char *value = getenv(name);
    return (value != NULL && value[0] != '\0') ? value : NULL;
}

void nupp_fs_random(void *into, size_t length) {
    /* `/dev/urandom` rather than `rand`, because two processes started in the
     * same millisecond must not propose the same temporary name. A machine that
     * cannot open it falls back to the clock and the process id, which collide
     * far less often than a name generator that has already claimed the file. */
    int descriptor = open("/dev/urandom", O_RDONLY);
    if (descriptor >= 0) {
        size_t filled = 0;
        while (filled < length) {
            ssize_t got = read(descriptor, (uint8_t *)into + filled, length - filled);
            if (got <= 0) {
                break;
            }
            filled += (size_t)got;
        }
        close(descriptor);
        if (filled == length) {
            return;
        }
    }
    {
        uint64_t mixed = (uint64_t)getpid();
        size_t at;
        mixed ^= (uint64_t)(nupp_monotonic_ms() * 1000.0);
        for (at = 0; at < length; at++) {
            mixed = mixed * 6364136223846793005ull + 1442695040888963407ull;
            ((uint8_t *)into)[at] = (uint8_t)(mixed >> 33);
        }
    }
}

/* --- threads ------------------------------------------------------------ */

struct NuppMutex {
    pthread_mutex_t handle;
};

struct NuppCondition {
    pthread_cond_t handle;
};

NuppMutex *nupp_mutex_new(void) {
    NuppMutex *mutex = malloc(sizeof *mutex);
    if (mutex == NULL) {
        return NULL;
    }
    if (pthread_mutex_init(&mutex->handle, NULL) != 0) {
        free(mutex);
        return NULL;
    }
    return mutex;
}

void nupp_mutex_free(NuppMutex *mutex) {
    if (mutex != NULL) {
        pthread_mutex_destroy(&mutex->handle);
        free(mutex);
    }
}

void nupp_mutex_lock(NuppMutex *mutex) {
    pthread_mutex_lock(&mutex->handle);
}

void nupp_mutex_unlock(NuppMutex *mutex) {
    pthread_mutex_unlock(&mutex->handle);
}

NuppCondition *nupp_condition_new(void) {
    NuppCondition *condition = malloc(sizeof *condition);
    if (condition == NULL) {
        return NULL;
    }
    if (pthread_cond_init(&condition->handle, NULL) != 0) {
        free(condition);
        return NULL;
    }
    return condition;
}

void nupp_condition_free(NuppCondition *condition) {
    if (condition != NULL) {
        pthread_cond_destroy(&condition->handle);
        free(condition);
    }
}

void nupp_condition_wait(NuppCondition *condition, NuppMutex *mutex) {
    pthread_cond_wait(&condition->handle, &mutex->handle);
}

bool nupp_condition_wait_for(
    NuppCondition *condition, NuppMutex *mutex, uint64_t milliseconds
) {
    /* A deadline on the real-time clock, because that is the only one
     * `pthread_cond_timedwait` is defined against without a per-platform
     * attribute. A clock step moves the deadline; what that costs is one wait
     * that is early or late, and every caller re-checks its condition anyway. */
    struct timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline);
    deadline.tv_sec += (time_t)(milliseconds / 1000);
    deadline.tv_nsec += (long)((milliseconds % 1000) * 1000000);
    if (deadline.tv_nsec >= 1000000000L) {
        deadline.tv_sec += 1;
        deadline.tv_nsec -= 1000000000L;
    }
    return pthread_cond_timedwait(&condition->handle, &mutex->handle, &deadline)
        != ETIMEDOUT;
}

void nupp_condition_signal(NuppCondition *condition) {
    pthread_cond_signal(&condition->handle);
}

void nupp_condition_broadcast(NuppCondition *condition) {
    pthread_cond_broadcast(&condition->handle);
}

typedef struct {
    void (*entry)(void *);
    void *argument;
} Spawned;

static void *nupp_thread_trampoline(void *raw) {
    Spawned *spawned = raw;
    void (*entry)(void *) = spawned->entry;
    void *argument = spawned->argument;
    free(spawned);
    entry(argument);
    return NULL;
}

bool nupp_thread_spawn(void (*entry)(void *), void *argument) {
    pthread_attr_t attributes;
    pthread_t thread;
    Spawned *spawned = malloc(sizeof *spawned);
    int started;
    if (spawned == NULL) {
        nupp_fail("out of memory");
        return false;
    }
    spawned->entry = entry;
    spawned->argument = argument;
    pthread_attr_init(&attributes);
    pthread_attr_setdetachstate(&attributes, PTHREAD_CREATE_DETACHED);
    started = pthread_create(&thread, &attributes, nupp_thread_trampoline, spawned);
    pthread_attr_destroy(&attributes);
    if (started != 0) {
        free(spawned);
        nupp_fail_errno("cannot start a worker thread", started);
        return false;
    }
    return true;
}

/* --- child processes ---------------------------------------------------- */

/* `F_SETNOSIGPIPE`, where the platform has it.
 *
 * Per target, because the number is per target and nothing about it is
 * guessable: Darwin says 73 and NetBSD says 14, and issuing one platform's
 * number on the other does not fail harmlessly -- it performs whatever that
 * number means there. */
#if defined(__APPLE__)
#   define NUPP_F_SETNOSIGPIPE 73
#   define NUPP_QUIETS_PER_DESCRIPTOR 1
#elif defined(__NetBSD__)
#   define NUPP_F_SETNOSIGPIPE 14
#   define NUPP_QUIETS_PER_DESCRIPTOR 1
#else
#   define NUPP_QUIETS_PER_DESCRIPTOR 0
#endif

struct NuppPipeEnd {
    int descriptor;
    bool closed;
};

/* Makes a descriptor nonblocking, and on the platforms that can, quiet about
 * `SIGPIPE`.
 *
 * Only ever applied to an end this process keeps. `O_NONBLOCK` lives on the open
 * file description, so a descriptor shared with the child would make the child's
 * own stdin or stdout nonblocking -- and a child that gets `EAGAIN` from what it
 * believes is a plain write usually fails. */
static bool prepare_end(int descriptor) {
    int flags = fcntl(descriptor, F_GETFL, 0);
    if (flags < 0) {
        nupp_fail_errno("cannot read the pipe's flags", errno);
        return false;
    }
    if (fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) < 0) {
        nupp_fail_errno("cannot make the pipe nonblocking", errno);
        return false;
    }
#if NUPP_QUIETS_PER_DESCRIPTOR
    /* A descriptor that will not raise `SIGPIPE` is strictly better than a
     * signal mask held across every write: set once, scoped to a descriptor this
     * process owns, and it leaves the host's disposition alone. Its failure is
     * reported rather than shrugged at, because this is the whole of the
     * protection on these platforms. */
    if (fcntl(descriptor, NUPP_F_SETNOSIGPIPE, 1) < 0) {
        nupp_fail_errno("cannot quiet the pipe", errno);
        return false;
    }
#endif
    return true;
}

static NuppPipeEnd *wrap_descriptor(int descriptor) {
    NuppPipeEnd *end = malloc(sizeof *end);
    if (end == NULL) {
        close(descriptor);
        nupp_fail("out of memory");
        return NULL;
    }
    end->descriptor = descriptor;
    end->closed = false;
    return end;
}

bool nupp_pipe_is_closed(const NuppPipeEnd *end) {
    return end == NULL || end->closed;
}

void nupp_pipe_close(NuppPipeEnd *end) {
    if (end != NULL && !end->closed) {
        close(end->descriptor);
        end->closed = true;
        end->descriptor = -1;
    }
}

void nupp_pipe_destroy(NuppPipeEnd *end) {
    if (end != NULL) {
        nupp_pipe_close(end);
        free(end);
    }
}

intptr_t nupp_pipe_read(NuppPipeEnd *end, uint8_t *into, size_t length) {
    for (;;) {
        ssize_t got = read(end->descriptor, into, length);
        if (got > 0) {
            return (intptr_t)got;
        }
        if (got == 0) {
            return NUPP_GONE;
        }
        if (errno == EINTR) {
            return NUPP_WOULD_BLOCK;
        }
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return NUPP_WOULD_BLOCK;
        }
        nupp_fail_errno("cannot read from the child", errno);
        return NUPP_FAILED;
    }
}

/* Writes without letting a broken pipe reach the host.
 *
 * On a platform with `F_SETNOSIGPIPE` the descriptor was quieted when it was
 * prepared and this is an ordinary write. Everywhere else the signal is blocked
 * for the duration, and this is the sequence that has to be got exactly right:
 *
 * 1. Block `SIGPIPE` on this thread, keeping the old mask.
 * 2. Read `sigpending` -- after the block, because an unblocked signal is
 *    delivered rather than left pending, so a check taken first answers "not
 *    pending" for one about to arrive.
 * 3. Write.
 * 4. If the write reported `EPIPE` and `SIGPIPE` was not already pending at step
 *    2, consume the one it raised.
 * 5. Restore the mask, on every path out.
 *
 * Step 4's condition is the careful part. Standard signals are not queued, so a
 * `SIGPIPE` already pending when the write began is indistinguishable from the
 * one the write raised, and consuming it steals a signal the host was going to
 * handle. When it was already there, it is left alone: `EPIPE` still comes back,
 * which is all this needs.
 *
 * What this never does is install a disposition. Ignoring `SIGPIPE`
 * process-wide would be permanent, global, and the host's choice rather than a
 * library's. */
intptr_t nupp_pipe_write(NuppPipeEnd *end, const uint8_t *from, size_t length) {
    ssize_t written;
    int failure = 0;
#if !NUPP_QUIETS_PER_DESCRIPTOR
    sigset_t blocked, previous, pending;
    bool already;
    int blocking;

    sigemptyset(&blocked);
    sigaddset(&blocked, SIGPIPE);
    /* `pthread_sigmask` reports through its return value, not `errno`. */
    blocking = pthread_sigmask(SIG_BLOCK, &blocked, &previous);
    if (blocking != 0) {
        nupp_fail_errno("cannot block SIGPIPE for the write", blocking);
        return NUPP_FAILED;
    }
    sigemptyset(&pending);
    if (sigpending(&pending) != 0) {
        /* Without knowing whether a `SIGPIPE` was already waiting there is no
         * safe way to finish: consume afterwards and this may steal the host's,
         * decline to and a signal this write raised is delivered the moment the
         * mask comes off. So the write does not happen. */
        int inspection = errno;
        int restoring = pthread_sigmask(SIG_SETMASK, &previous, NULL);
        nupp_fail_errno(
            restoring != 0 ? "cannot restore the signal mask" : "cannot inspect pending signals",
            restoring != 0 ? restoring : inspection);
        return NUPP_FAILED;
    }
    already = sigismember(&pending, SIGPIPE) == 1;
#endif

    written = write(end->descriptor, from, length);
    if (written < 0) {
        failure = errno;
    }

#if !NUPP_QUIETS_PER_DESCRIPTOR
    if (!already && written < 0 && failure == EPIPE) {
        struct timespec immediately = {0, 0};
        for (;;) {
            if (sigtimedwait(&blocked, NULL, &immediately) >= 0) {
                break;
            }
            if (errno == EINTR) {
                continue;
            }
            if (errno == EAGAIN) {
                /* Nothing was pending after all, which is the ordinary answer
                 * when the write failed for a reason other than a broken pipe
                 * reaching this thread. */
                break;
            }
            /* A `SIGPIPE` this write raised, still pending, and no way to take
             * it. Restoring the mask now delivers it, and under the default
             * disposition that ends the process -- so the mask stays as it is
             * and the caller is told. A thread with `SIGPIPE` blocked is a
             * changed host, which is bad; a dead host is worse. */
            nupp_fail_errno("cannot consume the SIGPIPE this write raised", errno);
            return NUPP_FAILED;
        }
    }
    {
        /* A failed restore outranks a successful write. The bytes did go, and
         * saying so while leaving the host's mask changed would trade a fact the
         * caller can recover from for one it cannot even see. */
        int restoring = pthread_sigmask(SIG_SETMASK, &previous, NULL);
        if (restoring != 0) {
            nupp_fail_errno("cannot restore the signal mask", restoring);
            return NUPP_FAILED;
        }
    }
#endif

    if (written >= 0) {
        return (intptr_t)written;
    }
    if (failure == EINTR || failure == EAGAIN || failure == EWOULDBLOCK) {
        return NUPP_WOULD_BLOCK;
    }
    if (failure == EPIPE) {
        return NUPP_GONE;
    }
    nupp_fail_errno("cannot write to the child", failure);
    return NUPP_FAILED;
}

/* One pipe, close-on-exec on both ends.
 *
 * Close-on-exec matters on both: it does not stop the child receiving the ends
 * it is given -- `dup2` clears the flag on what it creates -- but it does stop
 * anything else in the host spawning concurrently from inheriting copies and
 * holding the pipe open against a reader waiting for end of stream.
 *
 * Where `pipe2` exists the descriptors are close-on-exec from the instant they
 * do. macOS has none, so there the flag is set just afterwards and a window
 * really is open between the two calls: a concurrent spawn in that instant
 * inherits them. That is a constraint on the host rather than something this can
 * close, and it is written down instead of papered over. */
static bool make_pipe(int ends[2]) {
#if defined(__linux__) || defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__)
    if (pipe2(ends, O_CLOEXEC) != 0) {
        nupp_fail_errno("cannot create a pipe", errno);
        return false;
    }
#else
    int which;
    if (pipe(ends) != 0) {
        nupp_fail_errno("cannot create a pipe", errno);
        return false;
    }
    for (which = 0; which < 2; which++) {
        if (fcntl(ends[which], F_SETFD, FD_CLOEXEC) < 0) {
            nupp_fail_errno("cannot mark a pipe close-on-exec", errno);
            close(ends[0]);
            close(ends[1]);
            return false;
        }
    }
#endif
    return true;
}

/* A close-on-exec copy of one of this process's own descriptors, for a child
 * that should write where this one does rather than to the slot of the same
 * number. */
static int duplicate_cloexec(int descriptor) {
    int copy = fcntl(descriptor, F_DUPFD_CLOEXEC, 0);
    if (copy < 0) {
        nupp_fail_errno("cannot duplicate a descriptor for the child", errno);
    }
    return copy;
}

extern char **environ;

/* The environment the child receives.
 *
 * Entries modify rather than replace unless the request cleared first, which is
 * what makes "run this with one variable set" a one-line request rather than a
 * copy of everything the host happens to hold. */
static char **build_environment(const NuppSpawnRequest *request) {
    size_t inherited = 0;
    size_t added = 0;
    size_t capacity;
    char **out;
    size_t count = 0;
    size_t at;

    if (!request->clearEnv && environ != NULL) {
        while (environ[inherited] != NULL) {
            inherited++;
        }
    }
    if (request->envp != NULL) {
        while (request->envp[added] != NULL) {
            added++;
        }
    }
    capacity = inherited + added + 1;
    out = malloc(capacity * sizeof *out);
    if (out == NULL) {
        nupp_fail("out of memory");
        return NULL;
    }
    for (at = 0; at < inherited; at++) {
        out[count++] = environ[at];
    }
    for (at = 0; at < added; at++) {
        char *entry = request->envp[at];
        const char *equals = strchr(entry, '=');
        size_t nameLength = equals != NULL ? (size_t)(equals - entry) : strlen(entry);
        size_t scan;
        bool replaced = false;
        for (scan = 0; scan < count; scan++) {
            if (strncmp(out[scan], entry, nameLength) == 0 && out[scan][nameLength] == '=') {
                out[scan] = entry;
                replaced = true;
                break;
            }
        }
        if (!replaced) {
            out[count++] = entry;
        }
    }
    out[count] = NULL;
    return out;
}

/* Where `pipe2` is missing, one spawn at a time.
 *
 * `make_pipe` there is `pipe` and then `fcntl`, and between those two calls the
 * descriptors are inheritable. A fork in that instant hands them to a child that
 * did not ask for them -- and a long-lived child holding the write end of
 * another child's pipe means the reader of that pipe never sees end of stream.
 * That is not a theoretical window: a test suite spawning shards and a server
 * concurrently walks into it, and what it looks like is a command that finished
 * and never returned.
 *
 * So the window is closed by making it unreachable: no fork in this process
 * happens while another spawn is between its two calls. It costs the spawns
 * their concurrency, which is microseconds against starting a process, and it
 * is only paid where the platform has no better answer. */
#if defined(__linux__) || defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__)
#   define NUPP_SPAWN_NEEDS_LOCK 0
#else
#   define NUPP_SPAWN_NEEDS_LOCK 1
static pthread_mutex_t spawn_lock = PTHREAD_MUTEX_INITIALIZER;
#endif

static void spawn_lock_take(void) {
#if NUPP_SPAWN_NEEDS_LOCK
    pthread_mutex_lock(&spawn_lock);
#endif
}

static void spawn_lock_drop(void) {
#if NUPP_SPAWN_NEEDS_LOCK
    pthread_mutex_unlock(&spawn_lock);
#endif
}

bool nupp_spawn(const NuppSpawnRequest *request, NuppSpawnResult *result) {
    /* Parent end, child end, per stream. -1 is "not a pipe". */
    int parentEnds[3] = {-1, -1, -1};
    int childEnds[3] = {-1, -1, -1};
    int report[2] = {-1, -1};
    int devNull = -1;
    int inheritedStdout = -1;
    char **childEnvironment = NULL;
    pid_t child;
    size_t which;
    bool merged = false;

    memset(result, 0, sizeof *result);
    spawn_lock_take();

    /* Joining stderr to stdout has to be arranged before the spawn: the child's
     * two descriptors must already be the same pipe when it starts, and there is
     * no merging a pipe that was made separately. So one pipe is made here, its
     * write end is handed to the child twice, and the single read end is what
     * this process keeps. */
    for (which = 0; which < 3; which++) {
        uint8_t mode = request->modes[which];
        if (which == 2 && mode == NUPP_MODE_STDOUT) {
            continue;
        }
        if (mode == NUPP_MODE_PIPE) {
            int ends[2];
            if (!make_pipe(ends)) {
                goto fail;
            }
            if (which == 0) {
                childEnds[0] = ends[0];
                parentEnds[0] = ends[1];
            } else {
                parentEnds[which] = ends[0];
                childEnds[which] = ends[1];
            }
            if (!prepare_end(parentEnds[which])) {
                goto fail;
            }
        } else if (mode == NUPP_MODE_NULL) {
            if (devNull < 0) {
                devNull = open("/dev/null", O_RDWR);
                if (devNull < 0) {
                    nupp_fail_errno("cannot open /dev/null", errno);
                    goto fail;
                }
            }
            childEnds[which] = devNull;
        }
        /* Inherit leaves the child end at -1, which the fork reads as "keep the
         * one you were given". */
    }

    if (request->modes[2] == NUPP_MODE_STDOUT) {
        switch (request->modes[1]) {
            case NUPP_MODE_PIPE:
                /* The same write end twice, so both of the child's streams land
                 * in one pipe with one reader. */
                childEnds[2] = childEnds[1];
                merged = true;
                break;
            case NUPP_MODE_NULL:
                /* Both discarded, which really is the same destination. */
                childEnds[2] = childEnds[1];
                break;
            default:
                /* Inheriting is per descriptor, and handing the child this
                 * process's descriptor 2 is only stdout's destination when the
                 * two happen to point at the same place. A parent whose own
                 * stdout is redirected and whose stderr is not would have its
                 * child's streams land in two places, having asked for one. So
                 * stderr becomes a duplicate of descriptor 1 -- the
                 * destination, not the slot. */
                inheritedStdout = duplicate_cloexec(STDOUT_FILENO);
                if (inheritedStdout < 0) {
                    goto fail;
                }
                childEnds[2] = inheritedStdout;
                break;
        }
    }

    childEnvironment = build_environment(request);
    if (childEnvironment == NULL) {
        goto fail;
    }
    /* How the child says it could not start. Close-on-exec, so a successful exec
     * closes it and the parent reads end of file rather than a reason. */
    if (!make_pipe(report)) {
        goto fail;
    }

    child = fork();
    if (child < 0) {
        nupp_fail_errno("cannot fork", errno);
        goto fail;
    }
    if (child == 0) {
        /* Between here and the exec, only async-signal-safe calls. The lock
         * above is not unlocked here: this side of the fork is about to become
         * another program, and touching a mutex whose owner is in another
         * process is how a child hangs before it ever starts. */
        int failure = 0;
        for (which = 0; which < 3; which++) {
            if (childEnds[which] >= 0 && dup2(childEnds[which], (int)which) < 0) {
                failure = errno;
                break;
            }
        }
        if (failure == 0 && request->cwd != NULL && chdir(request->cwd) != 0) {
            failure = errno;
        }
        if (failure == 0) {
            environ = childEnvironment;
            execvp(request->argv[0], request->argv);
            failure = errno;
        }
        {
            ssize_t ignored = write(report[1], &failure, sizeof failure);
            (void)ignored;
        }
        _exit(127);
    }

    spawn_lock_drop();

    /* The parent keeps its ends and nothing else. */
    close(report[1]);
    report[1] = -1;
    for (which = 0; which < 3; which++) {
        /* Each of these is closed once. `devNull` and the duplicate of stdout
         * are shared with their own cleanup below, and the joined stderr is the
         * same descriptor as stdout. */
        if (childEnds[which] >= 0 && childEnds[which] != devNull
            && childEnds[which] != inheritedStdout && !(which == 2 && merged)) {
            close(childEnds[which]);
        }
        childEnds[which] = -1;
    }
    if (devNull >= 0) {
        close(devNull);
        devNull = -1;
    }
    if (inheritedStdout >= 0) {
        close(inheritedStdout);
        inheritedStdout = -1;
    }

    {
        int failure = 0;
        ssize_t got;
        do {
            got = read(report[0], &failure, sizeof failure);
        } while (got < 0 && errno == EINTR);
        close(report[0]);
        report[0] = -1;
        if (got == (ssize_t)sizeof failure) {
            int status;
            while (waitpid(child, &status, 0) < 0 && errno == EINTR) {
                /* The child exists and is about to be collected. */
            }
            nupp_fail_errno(request->argv[0], failure);
            goto fail;
        }
    }

    free(childEnvironment);
    result->child = (uintptr_t)child;
    result->id = (unsigned long)child;
    result->merged = merged;
    for (which = 0; which < 3; which++) {
        if (parentEnds[which] >= 0) {
            result->ends[which] = wrap_descriptor(parentEnds[which]);
            if (result->ends[which] == NULL) {
                return false;
            }
        }
    }
    return true;

fail:
    spawn_lock_drop();
    for (which = 0; which < 3; which++) {
        if (parentEnds[which] >= 0) {
            close(parentEnds[which]);
        }
        if (childEnds[which] >= 0 && childEnds[which] != devNull
            && childEnds[which] != inheritedStdout && !(which == 2 && merged)) {
            close(childEnds[which]);
        }
    }
    if (devNull >= 0) {
        close(devNull);
    }
    if (inheritedStdout >= 0) {
        close(inheritedStdout);
    }
    if (report[0] >= 0) {
        close(report[0]);
    }
    if (report[1] >= 0) {
        close(report[1]);
    }
    free(childEnvironment);
    return false;
}

bool nupp_child_kill(const NuppSpawnResult *child, bool force) {
    /* `kill` reads zero as "every process in my own group" and a negative as a
     * group id. Neither is ever what a child handle means, and either one would
     * take the host down with whatever else it was running. */
    if ((pid_t)child->child <= 0) {
        nupp_fail("the child has no process to signal");
        return false;
    }
    if (kill((pid_t)child->child, force ? SIGKILL : SIGTERM) == 0) {
        return true;
    }
    /* The child ended between the poll and this signal, which is a race nothing
     * can close and not a failure: what was asked for has happened. */
    if (errno == ESRCH) {
        return true;
    }
    nupp_fail_errno("cannot signal the child", errno);
    return false;
}

int nupp_child_poll(NuppSpawnResult *child, int32_t *code, bool *killed) {
    int status = 0;
    pid_t answered;
    do {
        answered = waitpid((pid_t)child->child, &status, WNOHANG);
    } while (answered < 0 && errno == EINTR);
    if (answered == 0) {
        return 0;
    }
    if (answered < 0) {
        /* A host that reaps its own children -- `SIGCHLD` set to `SIG_IGN`, or
         * its own handler -- leaves nothing here to wait for, and reading that
         * as "still running" would report a leak that did not happen. */
        if (errno == ECHILD) {
            *code = 0;
            *killed = false;
            return 1;
        }
        nupp_fail_errno("cannot ask after the child", errno);
        return -1;
    }
    if (WIFSIGNALED(status)) {
        /* A signal leaves no exit code of its own. 128 plus the signal is what a
         * shell reports, and what this ABI's callers already read. */
        *code = 128 + WTERMSIG(status);
        *killed = true;
    } else {
        *code = WIFEXITED(status) ? WEXITSTATUS(status) : 0;
        *killed = false;
    }
    return 1;
}

void nupp_child_release(NuppSpawnResult *child) {
    /* `waitpid` already collected the status, so the id is gone and there is
     * nothing left for the platform to hold. */
    (void)child;
}

int nupp_pipe_wait(
    NuppPipeEnd *const *readable, size_t readableCount,
    NuppPipeEnd *const *writable, size_t writableCount,
    int32_t timeoutMs
) {
    struct pollfd *slots;
    size_t count = 0;
    size_t at;
    int ready;

    slots = malloc((readableCount + writableCount + 1) * sizeof *slots);
    if (slots == NULL) {
        nupp_fail("out of memory");
        return -1;
    }
    for (at = 0; at < readableCount; at++) {
        if (readable[at] == NULL || readable[at]->closed) {
            continue;
        }
        slots[count].fd = readable[at]->descriptor;
        slots[count].events = POLLIN;
        slots[count].revents = 0;
        count++;
    }
    for (at = 0; at < writableCount; at++) {
        if (writable[at] == NULL || writable[at]->closed) {
            continue;
        }
        slots[count].fd = writable[at]->descriptor;
        slots[count].events = POLLOUT;
        slots[count].revents = 0;
        count++;
    }
    /* A negative timeout means "forever" to `poll`, which is the one thing this
     * must never do: every caller above is bounded, and the usual way to arrive
     * here negative is a deadline that has already passed -- which asks for no
     * wait at all rather than an endless one. */
    ready = poll(slots, (nfds_t)count, timeoutMs < 0 ? 0 : timeoutMs);
    free(slots);
    if (ready >= 0) {
        return ready;
    }
    /* Interrupted before anything was ready, which is a wait that ended early
     * rather than one that failed: the caller re-checks and waits again. */
    if (errno == EINTR) {
        return 0;
    }
    nupp_fail_errno("cannot wait for the child's streams", errno);
    return -1;
}

#endif /* !NUPP_WINDOWS */
