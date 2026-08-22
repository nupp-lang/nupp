/* The file provider, on libuv.
 *
 * Everything here used to have a POSIX half and a Windows half written beside
 * each other. libuv is those two halves, written by people who run them: stat
 * and lstat, reading and making a symbolic link, the read-only bit, directory
 * scanning that reports an entry's own kind, temporary names created rather
 * than proposed, and file handles. What is left in this file is what the ABI
 * asks for that a filesystem does not: argument checking, the packed shapes the
 * binding reads, and the walks that libuv has no opinion about.
 */

#include "nupp_native.h"

#include <uv.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* MinGW provides the mode bits libuv returns for an lstat but omits the POSIX
 * convenience macro for testing the link bit. */
#ifndef S_ISLNK
#define S_ISLNK(mode) (((mode) & S_IFMT) == S_IFLNK)
#endif

/* How many names a temporary is willing to propose before deciding the
 * directory, rather than luck, is the problem. */
#define NUPP_TEMPORARY_ATTEMPTS 64

/* --- talking to libuv --------------------------------------------------- */

/* Every call here is the synchronous form: a NULL callback runs the operation
 * on this thread and leaves its answer in the request. The asynchronous form is
 * the transfer lane's, and it is the same functions. */
static bool settled(uv_fs_t *request, const char *what) {
    if (request->result < 0) {
        nupp_fail_format("%s: %s", what, uv_strerror((int)request->result));
        return false;
    }
    return true;
}

static bool refused(uv_fs_t *request, const char *what) {
    bool ok = settled(request, what);
    uv_fs_req_cleanup(request);
    return ok;
}

/* --- metadata ----------------------------------------------------------- */

static void fill(const uv_stat_t *status, NuppFileInfo *out) {
    if (S_ISLNK(status->st_mode)) {
        out->kind = NUPP_KIND_SYMLINK;
    } else if (S_ISDIR(status->st_mode)) {
        out->kind = NUPP_KIND_DIRECTORY;
    } else if (S_ISREG(status->st_mode)) {
        out->kind = NUPP_KIND_FILE;
    } else {
        out->kind = NUPP_KIND_OTHER;
    }
    /* Read-only means no write bit anywhere, which is the question a caller
     * with one file and no user model is asking. */
    out->readOnly = (status->st_mode & 0222) == 0;
    out->size = (uint64_t)status->st_size;
    out->modified = (double)status->st_mtim.tv_sec
        + (double)status->st_mtim.tv_nsec / 1.0e9;
}

/* Describes one path. `follow` resolves a symbolic link to its target, which is
 * the difference between asking what a name refers to and asking what the name
 * itself is. */
NUPP_EXPORT bool nuppFilesInfo(
    const uint8_t *data, size_t length, bool follow, NuppFileInfo *out
) {
    NuppText path;
    uv_fs_t request;
    bool ok;
    if (out == NULL) {
        nupp_fail("file info output is null");
        return false;
    }
    if (!nupp_text(&path, data, length, "path")) {
        return false;
    }
    if (follow) {
        uv_fs_stat(NULL, &request, path.value, NULL);
    } else {
        uv_fs_lstat(NULL, &request, path.value, NULL);
    }
    ok = settled(&request, path.value);
    if (ok) {
        fill(&request.statbuf, out);
    }
    uv_fs_req_cleanup(&request);
    nupp_text_free(&path);
    return ok;
}

/* Reads a symbolic link's target without resolving it. */
NUPP_EXPORT NuppBytes *nuppFilesReadLink(const uint8_t *data, size_t length) {
    NuppText path;
    uv_fs_t request;
    NuppBytes *answer = NULL;
    if (!nupp_text(&path, data, length, "path")) {
        return NULL;
    }
    uv_fs_readlink(NULL, &request, path.value, NULL);
    if (settled(&request, path.value)) {
        answer = nupp_bytes_copy((const uint8_t *)request.ptr, strlen(request.ptr));
    }
    uv_fs_req_cleanup(&request);
    nupp_text_free(&path);
    return answer;
}

/* Creates a symbolic link. `directory` selects Windows's directory link, which
 * is the one platform that distinguishes the two. */
NUPP_EXPORT bool nuppFilesCreateSymlink(
    const uint8_t *target, size_t targetLength,
    const uint8_t *link, size_t linkLength, bool directory
) {
    NuppText to, at;
    uv_fs_t request;
    bool ok;
    if (!nupp_text(&to, target, targetLength, "link target")) {
        return false;
    }
    if (!nupp_text(&at, link, linkLength, "link path")) {
        nupp_text_free(&to);
        return false;
    }
    uv_fs_symlink(NULL, &request, to.value, at.value,
        directory ? UV_FS_SYMLINK_DIR : 0, NULL);
    ok = refused(&request, at.value);
    nupp_text_free(&to);
    nupp_text_free(&at);
    return ok;
}

/* Sets or clears the read-only bit. */
NUPP_EXPORT bool nuppFilesSetReadOnly(const uint8_t *data, size_t length, bool readOnly) {
    NuppText path;
    uv_fs_t request;
    int mode;
    bool ok;
    if (!nupp_text(&path, data, length, "path")) {
        return false;
    }
    uv_fs_stat(NULL, &request, path.value, NULL);
    if (!settled(&request, path.value)) {
        uv_fs_req_cleanup(&request);
        nupp_text_free(&path);
        return false;
    }
    mode = (int)(request.statbuf.st_mode & 07777);
    uv_fs_req_cleanup(&request);
    mode = readOnly ? (mode & ~0222) : (mode | 0222);
    uv_fs_chmod(NULL, &request, path.value, mode, NULL);
    ok = refused(&request, path.value);
    nupp_text_free(&path);
    return ok;
}

/* --- directories -------------------------------------------------------- */

/* Creates a directory and every missing parent. An existing directory is
 * success, which is what a caller building a tree wants. */
static bool make_directories(char *path) {
    size_t length = strlen(path);
    size_t at;
    for (at = 1; at <= length; at++) {
        uv_fs_t request;
        char saved;
        int result;
        if (at != length && path[at] != '/' && path[at] != '\\') {
            continue;
        }
        saved = path[at];
        path[at] = '\0';
        uv_fs_mkdir(NULL, &request, path, 0777, NULL);
        result = (int)request.result;
        uv_fs_req_cleanup(&request);
        path[at] = saved;
        /* A component that is already there is not a failure; one that is there
         * and is not a directory shows up when the next component is made. */
        if (result < 0 && result != UV_EEXIST) {
            nupp_fail_format("%s: %s", path, uv_strerror(result));
            return false;
        }
    }
    return true;
}

NUPP_EXPORT bool nuppFilesCreateDirectory(const uint8_t *data, size_t length) {
    NuppText path;
    bool ok;
    if (!nupp_text(&path, data, length, "path")) {
        return false;
    }
    if (path.length == 0) {
        nupp_text_free(&path);
        nupp_fail("the directory name is empty");
        return false;
    }
    ok = make_directories(path.value);
    nupp_text_free(&path);
    return ok;
}

/* An entry's own kind, as the binding spells it. A symbolic link reads as `l`
 * rather than as whatever it points at. */
static char kind_of(uv_dirent_type_t type) {
    switch (type) {
        case UV_DIRENT_LINK: return 'l';
        case UV_DIRENT_DIR: return 'd';
        case UV_DIRENT_FILE: return 'f';
        default: return 'o';
    }
}

/* Lists a directory's immediate children as `kind` byte, name, NUL. */
NUPP_EXPORT NuppBytes *nuppFilesList(const uint8_t *data, size_t length) {
    NuppText path;
    uv_fs_t request;
    uv_dirent_t entry;
    NuppBuffer out;
    if (!nupp_text(&path, data, length, "path")) {
        return NULL;
    }
    uv_fs_scandir(NULL, &request, path.value, 0, NULL);
    if (!settled(&request, path.value)) {
        uv_fs_req_cleanup(&request);
        nupp_text_free(&path);
        return NULL;
    }
    nupp_buffer_init(&out);
    while (uv_fs_scandir_next(&request, &entry) != UV_EOF) {
        size_t nameLength = strlen(entry.name);
        /* A name is not UTF-8 on every filesystem, and the binding turns each of
         * these into a Lua string it will compare and join. */
        if (!nupp_is_utf8((const uint8_t *)entry.name, nameLength)) {
            uv_fs_req_cleanup(&request);
            nupp_buffer_free(&out);
            nupp_text_free(&path);
            nupp_fail("directory entry name is not valid UTF-8");
            return NULL;
        }
        nupp_buffer_push(&out, (uint8_t)kind_of(entry.type));
        nupp_buffer_append(&out, entry.name, nameLength);
        nupp_buffer_push(&out, 0);
    }
    uv_fs_req_cleanup(&request);
    nupp_text_free(&path);
    if (out.failed) {
        nupp_buffer_free(&out);
        nupp_fail("out of memory");
        return NULL;
    }
    return nupp_buffer_finish(&out);
}

/* Removes a file, a symbolic link, or an empty directory. `recursive` removes a
 * directory's contents with it. */
static bool remove_tree(const char *path);

static bool remove_one(const char *path, bool directory) {
    uv_fs_t request;
    if (directory) {
        uv_fs_rmdir(NULL, &request, path, NULL);
    } else {
        uv_fs_unlink(NULL, &request, path, NULL);
    }
    return refused(&request, path);
}

static bool remove_tree(const char *path) {
    uv_fs_t request;
    uv_dirent_t entry;
    size_t pathLength = strlen(path);
    bool ok = true;

    uv_fs_scandir(NULL, &request, path, 0, NULL);
    if (!settled(&request, path)) {
        uv_fs_req_cleanup(&request);
        return false;
    }
    while (ok && uv_fs_scandir_next(&request, &entry) != UV_EOF) {
        size_t nameLength = strlen(entry.name);
        char *child = malloc(pathLength + 1 + nameLength + 1);
        if (child == NULL) {
            nupp_fail("out of memory");
            ok = false;
            break;
        }
        memcpy(child, path, pathLength);
        child[pathLength] = '/';
        memcpy(child + pathLength + 1, entry.name, nameLength + 1);
        /* A directory is descended into; a link to one is unlinked, because
         * following it would delete somewhere the caller did not name. */
        ok = entry.type == UV_DIRENT_DIR ? remove_tree(child) : remove_one(child, false);
        free(child);
    }
    uv_fs_req_cleanup(&request);
    return ok && remove_one(path, true);
}

NUPP_EXPORT bool nuppFilesRemove(const uint8_t *data, size_t length, bool recursive) {
    NuppText path;
    uv_fs_t request;
    bool directory;
    bool ok;
    if (!nupp_text(&path, data, length, "path")) {
        return false;
    }
    uv_fs_lstat(NULL, &request, path.value, NULL);
    if (!settled(&request, path.value)) {
        uv_fs_req_cleanup(&request);
        nupp_text_free(&path);
        return false;
    }
    directory = S_ISDIR(request.statbuf.st_mode);
    uv_fs_req_cleanup(&request);
    ok = directory
        ? (recursive ? remove_tree(path.value) : remove_one(path.value, true))
        : remove_one(path.value, false);
    nupp_text_free(&path);
    return ok;
}

/* Renames a path, replacing an existing destination. */
NUPP_EXPORT bool nuppFilesRename(
    const uint8_t *from, size_t fromLength, const uint8_t *to, size_t toLength
) {
    NuppText source, destination;
    uv_fs_t request;
    bool ok;
    if (!nupp_text(&source, from, fromLength, "path")) {
        return false;
    }
    if (!nupp_text(&destination, to, toLength, "destination path")) {
        nupp_text_free(&source);
        return false;
    }
    uv_fs_rename(NULL, &request, source.value, destination.value, NULL);
    ok = refused(&request, source.value);
    nupp_text_free(&source);
    nupp_text_free(&destination);
    return ok;
}

/* --- temporaries -------------------------------------------------------- */

/* Creates a uniquely named file or directory and answers its path. The name is
 * created rather than merely proposed, so no second caller can win the same name
 * between the two steps. */
NUPP_EXPORT NuppBytes *nuppFilesCreateTemporary(
    const uint8_t *directory, size_t directoryLength,
    const uint8_t *prefix, size_t prefixLength,
    const uint8_t *suffix, size_t suffixLength,
    bool asDirectory
) {
    NuppText root, before, after;
    NuppBuffer rootBuffer;
    NuppBytes *answer = NULL;
    unsigned attempt;
    bool haveRoot = false;

    nupp_buffer_init(&rootBuffer);
    if (directoryLength == 0) {
        size_t capacity = 512;
        char scratch[512];
        if (uv_os_tmpdir(scratch, &capacity) != 0) {
            snprintf(scratch, sizeof scratch, "/tmp");
        }
        nupp_buffer_append(&rootBuffer, scratch, strlen(scratch));
        nupp_buffer_push(&rootBuffer, 0);
        haveRoot = true;
    } else if (!nupp_text(&root, directory, directoryLength, "temporary directory")) {
        nupp_buffer_free(&rootBuffer);
        return NULL;
    }
    if (!nupp_text(&before, prefix, prefixLength, "temporary prefix")) {
        goto done;
    }
    if (!nupp_text(&after, suffix, suffixLength, "temporary suffix")) {
        nupp_text_free(&before);
        goto done;
    }

    for (attempt = 0; attempt < NUPP_TEMPORARY_ATTEMPTS; attempt++) {
        NuppBuffer candidate;
        uv_fs_t request;
        uint64_t stamp = 0;
        char stampText[17];
        const char *base = haveRoot ? (const char *)rootBuffer.data : root.value;
        int result;

        uv_random(NULL, NULL, &stamp, sizeof stamp, 0, NULL);
        snprintf(stampText, sizeof stampText, "%016llx", (unsigned long long)stamp);
        nupp_buffer_init(&candidate);
        nupp_buffer_append(&candidate, base, strlen(base));
        if (candidate.length == 0 || candidate.data[candidate.length - 1] != '/') {
            nupp_buffer_push(&candidate, '/');
        }
        nupp_buffer_append(&candidate, before.value, before.length);
        nupp_buffer_append(&candidate, stampText, 16);
        nupp_buffer_append(&candidate, after.value, after.length);
        nupp_buffer_push(&candidate, 0);
        if (candidate.failed) {
            nupp_buffer_free(&candidate);
            nupp_fail("out of memory");
            break;
        }
        candidate.length -= 1;

        if (asDirectory) {
            uv_fs_mkdir(NULL, &request, (const char *)candidate.data, 0700, NULL);
        } else {
            uv_fs_open(NULL, &request, (const char *)candidate.data,
                UV_FS_O_WRONLY | UV_FS_O_CREAT | UV_FS_O_EXCL, 0600, NULL);
        }
        result = (int)request.result;
        if (result >= 0 && !asDirectory) {
            uv_fs_t closing;
            uv_fs_close(NULL, &closing, (uv_file)result, NULL);
            uv_fs_req_cleanup(&closing);
        }
        uv_fs_req_cleanup(&request);
        if (result >= 0) {
            answer = nupp_bytes_copy(candidate.data, candidate.length);
            nupp_buffer_free(&candidate);
            break;
        }
        nupp_buffer_free(&candidate);
        if (result != UV_EEXIST) {
            /* The directory refused the name for a reason of its own, and
             * proposing sixty-three more will hear the same reason. */
            nupp_fail_format("%s", uv_strerror(result));
            break;
        }
        if (attempt + 1 == NUPP_TEMPORARY_ATTEMPTS) {
            nupp_fail("no unused temporary name was found");
        }
    }
    nupp_text_free(&before);
    nupp_text_free(&after);

done:
    if (haveRoot) {
        nupp_buffer_free(&rootBuffer);
    } else if (directoryLength != 0) {
        nupp_text_free(&root);
    }
    return answer;
}

/* --- the environment ---------------------------------------------------- */

NUPP_EXPORT NuppBytes *nuppFilesCurrentDirectory(void) {
    char scratch[4096];
    size_t capacity = sizeof scratch;
    int result = uv_cwd(scratch, &capacity);
    if (result != 0) {
        nupp_fail_format("cannot read the working directory: %s", uv_strerror(result));
        return NULL;
    }
    return nupp_bytes_copy((const uint8_t *)scratch, capacity);
}

/* Answers a well-known user folder. Resolved from the environment -- the XDG
 * variables where they are set, and the platform's conventional names under the
 * home directory otherwise. A desktop that records its folders somewhere else is
 * not consulted, and a folder that does not exist is a failure. */
NUPP_EXPORT NuppBytes *nuppFilesUserFolder(uint32_t which) {
    static const struct {
        const char *variable;
        const char *macos;
        const char *other;
    } FOLDERS[] = {
        {"XDG_DOCUMENTS_DIR", "Documents", "Documents"},
        {"XDG_DOWNLOAD_DIR", "Downloads", "Downloads"},
        {"XDG_DESKTOP_DIR", "Desktop", "Desktop"},
        {"XDG_PICTURES_DIR", "Pictures", "Pictures"},
        {"XDG_MUSIC_DIR", "Music", "Music"},
        {"XDG_VIDEOS_DIR", "Movies", "Videos"},
    };
    char home[4096];
    size_t capacity = sizeof home;
    NuppBuffer out;
    NuppFileInfo info;
    char configured[4096];
    size_t configuredLength = sizeof configured;
    bool named = false;

    if (uv_os_homedir(home, &capacity) != 0 || capacity == 0) {
        nupp_fail("the home directory is not set in the environment");
        return NULL;
    }
    nupp_buffer_init(&out);
    if (which == 0) {
        nupp_buffer_append(&out, home, capacity);
        nupp_buffer_push(&out, 0);
        out.length -= 1;
        return nupp_buffer_finish(&out);
    }
    if (which > sizeof FOLDERS / sizeof FOLDERS[0]) {
        nupp_buffer_free(&out);
        nupp_fail("unknown user folder");
        return NULL;
    }

    /* The XDG variables describe a desktop that has them, which Windows and
     * macOS do not; there the conventional name under the home directory is the
     * answer and a stray variable is not consulted. */
#if !NUPP_WINDOWS && !defined(__APPLE__)
    named = uv_os_getenv(FOLDERS[which - 1].variable, configured, &configuredLength) == 0
        && configuredLength != 0;
#else
    (void)configured;
    (void)configuredLength;
#endif
    if (named) {
        nupp_buffer_append(&out, configured, configuredLength);
    } else {
        const char *leaf =
#if defined(__APPLE__)
            FOLDERS[which - 1].macos;
#else
            FOLDERS[which - 1].other;
#endif
        nupp_buffer_append(&out, home, capacity);
        nupp_buffer_push(&out, '/');
        nupp_buffer_append(&out, leaf, strlen(leaf));
    }
    nupp_buffer_push(&out, 0);
    if (out.failed) {
        nupp_buffer_free(&out);
        nupp_fail("out of memory");
        return NULL;
    }
    out.length -= 1;
    if (!nuppFilesInfo(out.data, out.length, true, &info)
        || info.kind != NUPP_KIND_DIRECTORY) {
        nupp_buffer_free(&out);
        nupp_fail("the platform has no such folder");
        return NULL;
    }
    return nupp_buffer_finish(&out);
}

/* --- open files --------------------------------------------------------- */

/* A file handle is the descriptor libuv gave back and the position the caller
 * has moved to. libuv's file operations take an offset rather than keeping a
 * cursor, so the cursor is kept here. */
struct NuppFile {
    uv_file handle;
    int64_t position;
    bool appending;
};

typedef struct NuppFile NuppFile;

NUPP_EXPORT int64_t nuppFileSize(NuppFile *file);

/* Opens a file. `mode` selects read, truncating write, append, and the three
 * update modes, in that order. */
NUPP_EXPORT NuppFile *nuppFileOpen(const uint8_t *data, size_t length, uint32_t mode) {
    static const int FLAGS[6] = {
        UV_FS_O_RDONLY,
        UV_FS_O_WRONLY | UV_FS_O_CREAT | UV_FS_O_TRUNC,
        UV_FS_O_WRONLY | UV_FS_O_CREAT | UV_FS_O_APPEND,
        UV_FS_O_RDWR,
        UV_FS_O_RDWR | UV_FS_O_CREAT | UV_FS_O_TRUNC,
        UV_FS_O_RDWR | UV_FS_O_CREAT | UV_FS_O_APPEND,
    };
    NuppText path;
    uv_fs_t request;
    NuppFile *file = NULL;
    if (mode > 5) {
        nupp_fail("unknown file mode");
        return NULL;
    }
    if (!nupp_text(&path, data, length, "path")) {
        return NULL;
    }
    uv_fs_open(NULL, &request, path.value, FLAGS[mode], 0666, NULL);
    if (settled(&request, path.value)) {
        file = calloc(1, sizeof *file);
        if (file == NULL) {
            uv_fs_t closing;
            uv_fs_close(NULL, &closing, (uv_file)request.result, NULL);
            uv_fs_req_cleanup(&closing);
            nupp_fail("out of memory");
        } else {
            file->handle = (uv_file)request.result;
            file->appending = mode == 2 || mode == 5;
        }
    }
    uv_fs_req_cleanup(&request);
    nupp_text_free(&path);
    return file;
}

/* Reads at most `length` bytes. Answers zero at the end of the file and -1 on
 * failure, so a short read is progress rather than an error. */
NUPP_EXPORT int64_t nuppFileRead(NuppFile *file, uint8_t *into, size_t length) {
    uv_fs_t request;
    uv_buf_t buffer;
    int64_t got;
    if (file == NULL || (into == NULL && length != 0)) {
        nupp_fail("file read has no destination");
        return -1;
    }
    if (length == 0) {
        return 0;
    }
    buffer = uv_buf_init((char *)into, (unsigned)length);
    uv_fs_read(NULL, &request, file->handle, &buffer, 1, file->position, NULL);
    got = request.result;
    uv_fs_req_cleanup(&request);
    if (got < 0) {
        nupp_fail_format("cannot read: %s", uv_strerror((int)got));
        return -1;
    }
    file->position += got;
    return got;
}

/* Writes every byte or fails, which is what a caller counting bytes wants. */
NUPP_EXPORT int64_t nuppFileWrite(NuppFile *file, const uint8_t *from, size_t length) {
    size_t written = 0;
    if (file == NULL || (from == NULL && length != 0)) {
        nupp_fail("file write has no source");
        return -1;
    }
    while (written < length) {
        uv_fs_t request;
        uv_buf_t buffer = uv_buf_init((char *)(uintptr_t)(from + written),
            (unsigned)(length - written));
        int64_t step;
        /* An appending handle writes at the end whatever the cursor says, which
         * is what -1 asks libuv for. */
        uv_fs_write(NULL, &request, file->handle, &buffer, 1,
            file->appending ? -1 : file->position, NULL);
        step = request.result;
        uv_fs_req_cleanup(&request);
        if (step < 0) {
            nupp_fail_format("cannot write: %s", uv_strerror((int)step));
            return -1;
        }
        written += (size_t)step;
        file->position += step;
    }
    return (int64_t)length;
}

/* Moves the cursor. `whence` is the start, the current position, or the end, in
 * that order. */
NUPP_EXPORT int64_t nuppFileSeek(NuppFile *file, int64_t offset, uint32_t whence) {
    if (file == NULL) {
        nupp_fail("file seek has no file");
        return -1;
    }
    switch (whence) {
        case 0:
            /* A negative absolute position is not a position. */
            file->position = offset < 0 ? 0 : offset;
            break;
        case 1:
            file->position += offset;
            if (file->position < 0) {
                file->position = 0;
            }
            break;
        case 2: {
            int64_t size = nuppFileSize(file);
            if (size < 0) {
                return -1;
            }
            file->position = size + offset;
            if (file->position < 0) {
                file->position = 0;
            }
            break;
        }
        default:
            nupp_fail("unknown seek origin");
            return -1;
    }
    return file->position;
}

NUPP_EXPORT int64_t nuppFileSize(NuppFile *file) {
    uv_fs_t request;
    int64_t size;
    if (file == NULL) {
        nupp_fail("file size has no file");
        return -1;
    }
    uv_fs_fstat(NULL, &request, file->handle, NULL);
    if (request.result < 0) {
        nupp_fail_format("cannot size: %s", uv_strerror((int)request.result));
        uv_fs_req_cleanup(&request);
        return -1;
    }
    size = (int64_t)request.statbuf.st_size;
    uv_fs_req_cleanup(&request);
    return size;
}

NUPP_EXPORT bool nuppFileFlush(NuppFile *file) {
    if (file == NULL) {
        nupp_fail("file flush has no file");
        return false;
    }
    /* Nothing is buffered on this side of the descriptor, so there is nothing
     * to push. The call stays because the binding promises it. */
    return true;
}

NUPP_EXPORT bool nuppFileClose(NuppFile *file) {
    uv_fs_t request;
    if (file == NULL) {
        return true;
    }
    uv_fs_close(NULL, &request, file->handle, NULL);
    uv_fs_req_cleanup(&request);
    free(file);
    return true;
}
