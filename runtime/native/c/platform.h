/* What the filesystem looks like once the platform differences are behind it.
 *
 * These are the operations `files.c` is written against. Two implementations
 * answer them, `platform_posix.c` and `platform_windows.c`, and neither pretends
 * standard C covers this ground: directory iteration, link creation, permission
 * bits and atomic replacement are four different interfaces on the two systems,
 * so the seam is here rather than inside every function that needs one.
 *
 * Every call reports failure the same way: `false` or a negative count, with the
 * reason already in the error slot. A caller that has an operation to name first
 * -- the path it was working on, the argument that was wrong -- writes its own
 * message instead and passes `NULL` for `what`.
 */

#ifndef NUPP_PLATFORM_H
#define NUPP_PLATFORM_H

#include "nupp_native.h"

#define NUPP_KIND_FILE 1u
#define NUPP_KIND_DIRECTORY 2u
#define NUPP_KIND_OTHER 3u
#define NUPP_KIND_SYMLINK 4u

/* What one resolved path is. Mirrors `NuppFileInfo` in the Lua binding, so the
 * field order and widths are part of the ABI rather than a private choice. */
typedef struct {
    uint32_t kind;
    bool readOnly;
    uint64_t size;
    double modified;
} NuppFileInfo;

/* `follow` resolves a symbolic link to its target, which is the difference
 * between asking what a name refers to and asking what the name itself is. */
bool nupp_fs_stat(const char *path, bool follow, NuppFileInfo *out);

/* The link's target, unresolved, appended to `into`. */
bool nupp_fs_read_link(const char *path, NuppBuffer *into);

/* `directory` selects Windows's directory link and is ignored elsewhere, because
 * only Windows distinguishes the two. */
bool nupp_fs_create_symlink(const char *target, const char *link, bool directory);

bool nupp_fs_set_read_only(const char *path, bool readOnly);

/* Creates a directory and every missing parent. An existing directory is
 * success, which is what a caller building a tree wants. */
bool nupp_fs_create_directory_all(const char *path);

/* Removes a file, a symbolic link, or an empty directory. `recursive` removes a
 * directory's contents with it. */
bool nupp_fs_remove(const char *path, bool recursive);

bool nupp_fs_rename(const char *from, const char *to);

/* Replaces `to` with `from` atomically where the platform can. */
bool nupp_fs_replace(const char *from, const char *to);

/* Copies contents and permission bits, creating or truncating the destination. */
bool nupp_fs_copy(const char *from, const char *to);

/* The path with every symbolic link resolved and every `..` applied, which needs
 * the filesystem because a name can lead somewhere a lexical answer would not. */
bool nupp_fs_canonicalize(const char *path, NuppBuffer *into);

/* --- directory iteration ------------------------------------------------ */

typedef struct NuppDirectory NuppDirectory;

NuppDirectory *nupp_fs_open_directory(const char *path);

/* Answers 1 with the entry filled in, 0 at the end, and -1 on failure. `kind` is
 * `f`, `d`, `l` or `o` and describes the entry itself, so a symbolic link reads
 * as `l` rather than as whatever it points at. `.` and `..` never appear. */
int nupp_fs_next_entry(NuppDirectory *directory, const char **name, char *kind);

void nupp_fs_close_directory(NuppDirectory *directory);

/* --- open files --------------------------------------------------------- */

typedef struct NuppFile NuppFile;

/* `mode` selects read, truncating write, append, and the three update modes, in
 * that order. */
NuppFile *nupp_fs_open(const char *path, uint32_t mode);

/* At most `length` bytes. Zero at the end of the file and -1 on failure, so a
 * short read is progress rather than an error. */
int64_t nupp_fs_read(NuppFile *file, uint8_t *into, size_t length);

/* Every byte or nothing, which is what a caller counting bytes wants. */
int64_t nupp_fs_write(NuppFile *file, const uint8_t *from, size_t length);

/* `whence` is the start, the current position, or the end, in that order. */
int64_t nupp_fs_seek(NuppFile *file, int64_t offset, uint32_t whence);

int64_t nupp_fs_size(NuppFile *file);
bool nupp_fs_flush(NuppFile *file);

/* Pushes the bytes and the directory entry at the disk, for the temporary half
 * of an atomic write. */
bool nupp_fs_sync(NuppFile *file);
bool nupp_fs_close(NuppFile *file);

/* Creates the file and fails if the name is taken, which is how a temporary name
 * is claimed rather than merely proposed. `taken` says the name was the reason,
 * so a caller can try another rather than give up. */
NuppFile *nupp_fs_create_new(const char *path, bool *taken);
bool nupp_fs_create_directory_new(const char *path, bool *taken);

/* --- whole files -------------------------------------------------------- */

bool nupp_fs_read_whole(const char *path, NuppBuffer *into);
bool nupp_fs_write_whole(const char *path, const uint8_t *data, size_t length, bool append);

/* --- the environment ---------------------------------------------------- */

/* The process's working directory, appended to `into` with `/` separators. */
bool nupp_fs_current_directory(NuppBuffer *into);

/* Where temporary files go when the caller named no directory. */
bool nupp_fs_temporary_directory(NuppBuffer *into);

/* A named environment variable, or NULL when it is unset or empty. */
const char *nupp_environment(const char *name);

/* Bytes with no pattern to them, for a temporary name. */
void nupp_fs_random(void *into, size_t length);

/* --- threads ------------------------------------------------------------ */

/* Enough of a threading interface for the work that has to leave the calling
 * thread. Handles rather than values, because the two platforms disagree about
 * how large a mutex is and about whether one can be moved after it is created.
 *
 * A spawned thread is detached and never joined: the lanes here outlive every
 * caller and are torn down by the process exiting. */

typedef struct NuppMutex NuppMutex;
typedef struct NuppCondition NuppCondition;

NuppMutex *nupp_mutex_new(void);
void nupp_mutex_free(NuppMutex *mutex);
void nupp_mutex_lock(NuppMutex *mutex);
void nupp_mutex_unlock(NuppMutex *mutex);

NuppCondition *nupp_condition_new(void);
void nupp_condition_free(NuppCondition *condition);
void nupp_condition_wait(NuppCondition *condition, NuppMutex *mutex);

/* Waits up to `milliseconds`, answering false when that elapsed first. A
 * spurious wake answers true, so a caller re-checks what it was waiting for. */
bool nupp_condition_wait_for(
    NuppCondition *condition, NuppMutex *mutex, uint64_t milliseconds);
void nupp_condition_signal(NuppCondition *condition);
void nupp_condition_broadcast(NuppCondition *condition);

bool nupp_thread_spawn(void (*entry)(void *), void *argument);

#endif /* NUPP_PLATFORM_H */
