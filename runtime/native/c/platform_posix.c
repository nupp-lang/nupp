/* The filesystem on POSIX.
 *
 * Nothing here is clever. What it is, is complete: every operation the binding
 * offers, spelled in the calls the platform actually has, so `files.c` never
 * reaches for one directly and the Windows file beside this one can differ
 * wherever it has to.
 */

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
#include <sys/types.h>
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

#endif /* !NUPP_WINDOWS */
