/* The immediate half of `nupp.io.files`: metadata, listing, and the directory
 * operations that answer before a request could have been submitted. Transfers
 * belong to the request lane in `fslane.c`, not here.
 */

#include "platform.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* How many names a temporary is willing to propose before deciding the
 * directory, rather than luck, is the problem. */
#define NUPP_TEMPORARY_ATTEMPTS 64

/* --- answering ---------------------------------------------------------- */

/* One path, as bytes the binding can read. Separators come back as `/` whatever
 * the platform writes them as, because the binding's paths are one shape
 * everywhere. */
static NuppBytes *named(NuppBuffer *buffer) {
    if (buffer->failed) {
        nupp_buffer_free(buffer);
        nupp_fail("out of memory");
        return NULL;
    }
    if (buffer->data != NULL) {
        buffer->data[buffer->length] = 0;
        nupp_normalize_separators((char *)buffer->data);
    }
    return nupp_buffer_finish(buffer);
}

/* --- metadata ----------------------------------------------------------- */

/* Describes one path. `follow` resolves a symbolic link to its target, which is
 * the difference between asking what a name refers to and asking what the name
 * itself is. */
NUPP_EXPORT bool nuppcFilesInfo(
    const uint8_t *data, size_t length, bool follow, NuppFileInfo *out
) {
    NuppText path;
    bool ok;
    if (out == NULL) {
        nupp_fail("file info output is null");
        return false;
    }
    if (!nupp_text(&path, data, length, "path")) {
        return false;
    }
    ok = nupp_fs_stat(path.value, follow, out);
    nupp_text_free(&path);
    return ok;
}

/* Reads a symbolic link's target without resolving it. */
NUPP_EXPORT NuppBytes *nuppcFilesReadLink(const uint8_t *data, size_t length) {
    NuppText path;
    NuppBuffer target;
    if (!nupp_text(&path, data, length, "path")) {
        return NULL;
    }
    nupp_buffer_init(&target);
    if (!nupp_fs_read_link(path.value, &target)) {
        nupp_text_free(&path);
        nupp_buffer_free(&target);
        return NULL;
    }
    nupp_text_free(&path);
    return named(&target);
}

/* Creates a symbolic link. `directory` selects Windows's directory link and is
 * ignored elsewhere, because only Windows distinguishes the two. */
NUPP_EXPORT bool nuppcFilesCreateSymlink(
    const uint8_t *target, size_t targetLength,
    const uint8_t *link, size_t linkLength,
    bool directory
) {
    NuppText to, at;
    bool ok;
    if (!nupp_text(&to, target, targetLength, "link target")) {
        return false;
    }
    if (!nupp_text(&at, link, linkLength, "link path")) {
        nupp_text_free(&to);
        return false;
    }
    ok = nupp_fs_create_symlink(to.value, at.value, directory);
    nupp_text_free(&to);
    nupp_text_free(&at);
    return ok;
}

/* Sets or clears the read-only bit. */
NUPP_EXPORT bool nuppcFilesSetReadOnly(const uint8_t *data, size_t length, bool readOnly) {
    NuppText path;
    bool ok;
    if (!nupp_text(&path, data, length, "path")) {
        return false;
    }
    ok = nupp_fs_set_read_only(path.value, readOnly);
    nupp_text_free(&path);
    return ok;
}

/* Creates a directory and every missing parent. An existing directory is
 * success, which is what a caller building a tree wants. */
NUPP_EXPORT bool nuppcFilesCreateDirectory(const uint8_t *data, size_t length) {
    NuppText path;
    bool ok;
    if (!nupp_text(&path, data, length, "path")) {
        return false;
    }
    ok = nupp_fs_create_directory_all(path.value);
    nupp_text_free(&path);
    return ok;
}

/* Removes a file, a symbolic link, or an empty directory. `recursive` removes a
 * directory's contents with it. */
NUPP_EXPORT bool nuppcFilesRemove(const uint8_t *data, size_t length, bool recursive) {
    NuppText path;
    bool ok;
    if (!nupp_text(&path, data, length, "path")) {
        return false;
    }
    ok = nupp_fs_remove(path.value, recursive);
    nupp_text_free(&path);
    return ok;
}

/* Renames a path, replacing an existing destination. */
NUPP_EXPORT bool nuppcFilesRename(
    const uint8_t *from, size_t fromLength, const uint8_t *to, size_t toLength
) {
    NuppText source, destination;
    bool ok;
    if (!nupp_text(&source, from, fromLength, "path")) {
        return false;
    }
    if (!nupp_text(&destination, to, toLength, "destination path")) {
        nupp_text_free(&source);
        return false;
    }
    ok = nupp_fs_rename(source.value, destination.value);
    nupp_text_free(&source);
    nupp_text_free(&destination);
    return ok;
}

/* Lists a directory's immediate children as `kind` byte, name, NUL. The kind
 * comes from the directory entry rather than a second call per name, and
 * describes the entry itself, so a symbolic link reads as `l`. */
NUPP_EXPORT NuppBytes *nuppcFilesList(const uint8_t *data, size_t length) {
    NuppText path;
    NuppDirectory *directory;
    NuppBuffer out;
    if (!nupp_text(&path, data, length, "path")) {
        return NULL;
    }
    directory = nupp_fs_open_directory(path.value);
    nupp_text_free(&path);
    if (directory == NULL) {
        return NULL;
    }
    nupp_buffer_init(&out);
    for (;;) {
        const char *name;
        char kind;
        size_t nameLength;
        int step = nupp_fs_next_entry(directory, &name, &kind);
        if (step < 0) {
            nupp_fs_close_directory(directory);
            nupp_buffer_free(&out);
            return NULL;
        }
        if (step == 0) {
            break;
        }
        nameLength = strlen(name);
        /* A name is not UTF-8 on every filesystem, and the binding turns each of
         * these into a Lua string it will compare and join. One that is not is
         * refused here rather than becoming a name nothing can round-trip. */
        if (!nupp_is_utf8((const uint8_t *)name, nameLength)) {
            nupp_fs_close_directory(directory);
            nupp_buffer_free(&out);
            nupp_fail("directory entry name is not valid UTF-8");
            return NULL;
        }
        nupp_buffer_push(&out, (uint8_t)kind);
        nupp_buffer_append(&out, name, nameLength);
        nupp_buffer_push(&out, 0);
    }
    nupp_fs_close_directory(directory);
    if (out.failed) {
        nupp_buffer_free(&out);
        nupp_fail("out of memory");
        return NULL;
    }
    return nupp_buffer_finish(&out);
}

/* --- temporaries -------------------------------------------------------- */

/* Creates a uniquely named file or directory and answers its path. The name is
 * created rather than merely proposed, so no second caller can win the same name
 * between the two steps. */
NUPP_EXPORT NuppBytes *nuppcFilesCreateTemporary(
    const uint8_t *directory, size_t directoryLength,
    const uint8_t *prefix, size_t prefixLength,
    const uint8_t *suffix, size_t suffixLength,
    bool asDirectory
) {
    NuppText root, before, after;
    NuppBuffer rootBuffer;
    unsigned attempt;
    bool haveRoot = false;

    nupp_buffer_init(&rootBuffer);
    if (directoryLength == 0) {
        if (!nupp_fs_temporary_directory(&rootBuffer)) {
            nupp_buffer_free(&rootBuffer);
            return NULL;
        }
        nupp_buffer_push(&rootBuffer, 0);
        if (rootBuffer.failed) {
            nupp_buffer_free(&rootBuffer);
            nupp_fail("out of memory");
            return NULL;
        }
        haveRoot = true;
    } else if (!nupp_text(&root, directory, directoryLength, "temporary directory")) {
        nupp_buffer_free(&rootBuffer);
        return NULL;
    }
    if (!nupp_text(&before, prefix, prefixLength, "temporary prefix")) {
        goto refuse_root;
    }
    if (!nupp_text(&after, suffix, suffixLength, "temporary suffix")) {
        nupp_text_free(&before);
        goto refuse_root;
    }

    for (attempt = 0; attempt < NUPP_TEMPORARY_ATTEMPTS; attempt++) {
        NuppBuffer candidate;
        uint64_t stamp;
        char stampText[17];
        const char *base = haveRoot ? (const char *)rootBuffer.data : root.value;
        bool taken = false;
        bool made;

        nupp_fs_random(&stamp, sizeof stamp);
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
        candidate.length -= 1; /* the terminator is not part of the answer */

        if (asDirectory) {
            made = nupp_fs_create_directory_new((const char *)candidate.data, &taken);
        } else {
            NuppFile *file = nupp_fs_create_new((const char *)candidate.data, &taken);
            made = file != NULL;
            if (made) {
                nupp_fs_close(file);
            }
        }
        if (made) {
            nupp_text_free(&before);
            nupp_text_free(&after);
            if (haveRoot) {
                nupp_buffer_free(&rootBuffer);
            } else {
                nupp_text_free(&root);
            }
            return named(&candidate);
        }
        nupp_buffer_free(&candidate);
        if (!taken) {
            /* The directory refused the name for a reason of its own, and
             * proposing sixty-three more will hear the same reason. */
            break;
        }
        if (attempt + 1 == NUPP_TEMPORARY_ATTEMPTS) {
            nupp_fail("no unused temporary name was found");
        }
    }

    nupp_text_free(&before);
    nupp_text_free(&after);
refuse_root:
    if (haveRoot) {
        nupp_buffer_free(&rootBuffer);
    } else if (directoryLength != 0) {
        nupp_text_free(&root);
    }
    return NULL;
}

/* --- the environment ---------------------------------------------------- */

/* Answers the process's current working directory. */
NUPP_EXPORT NuppBytes *nuppcFilesCurrentDirectory(void) {
    NuppBuffer out;
    nupp_buffer_init(&out);
    if (!nupp_fs_current_directory(&out)) {
        nupp_buffer_free(&out);
        return NULL;
    }
    return named(&out);
}

/* Answers a well-known user folder. Resolved from the environment -- the XDG
 * variables where they are set, and the platform's conventional names under the
 * home directory otherwise. A desktop that records its folders somewhere else is
 * not consulted, and a folder that does not exist is a failure. */
NUPP_EXPORT NuppBytes *nuppcFilesUserFolder(uint32_t which) {
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
    const char *home = nupp_environment(NUPP_WINDOWS ? "USERPROFILE" : "HOME");
    NuppBuffer out;
    NuppFileInfo info;
    const char *configured = NULL;

    if (home == NULL) {
        nupp_fail("the home directory is not set in the environment");
        return NULL;
    }
    nupp_buffer_init(&out);
    if (which == 0) {
        nupp_buffer_append(&out, home, strlen(home));
        return named(&out);
    }
    if (which > sizeof FOLDERS / sizeof FOLDERS[0]) {
        nupp_fail("unknown user folder");
        return NULL;
    }

    /* The XDG variables describe a desktop that has them, which Windows and
     * macOS do not; on those two the conventional name under the home directory
     * is the answer and a stray variable is not consulted. */
#if !NUPP_WINDOWS && !defined(__APPLE__)
    configured = nupp_environment(FOLDERS[which - 1].variable);
#endif
    if (configured != NULL) {
        nupp_buffer_append(&out, configured, strlen(configured));
    } else {
        const char *leaf =
#if defined(__APPLE__)
            FOLDERS[which - 1].macos;
#else
            FOLDERS[which - 1].other;
#endif
        nupp_buffer_append(&out, home, strlen(home));
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
    if (!nupp_fs_stat((const char *)out.data, true, &info)
        || info.kind != NUPP_KIND_DIRECTORY) {
        nupp_buffer_free(&out);
        nupp_fail("the platform has no such folder");
        return NULL;
    }
    return named(&out);
}

/* --- open files --------------------------------------------------------- */

/* Opens a file. `mode` selects read, truncating write, append, and the three
 * update modes, in that order. */
NUPP_EXPORT NuppFile *nuppcFileOpen(const uint8_t *data, size_t length, uint32_t mode) {
    NuppText path;
    NuppFile *file;
    if (!nupp_text(&path, data, length, "path")) {
        return NULL;
    }
    file = nupp_fs_open(path.value, mode);
    nupp_text_free(&path);
    return file;
}

/* Reads at most `length` bytes. Answers zero at the end of the file and -1 on
 * failure, so a short read is progress rather than an error. */
NUPP_EXPORT int64_t nuppcFileRead(NuppFile *file, uint8_t *into, size_t length) {
    if (file == NULL || (into == NULL && length != 0)) {
        nupp_fail("file read has no destination");
        return -1;
    }
    if (length == 0) {
        return 0;
    }
    return nupp_fs_read(file, into, length);
}

/* Writes every byte or fails, which is what a caller counting bytes wants. */
NUPP_EXPORT int64_t nuppcFileWrite(NuppFile *file, const uint8_t *from, size_t length) {
    if (file == NULL || (from == NULL && length != 0)) {
        nupp_fail("file write has no source");
        return -1;
    }
    if (length == 0) {
        return 0;
    }
    return nupp_fs_write(file, from, length);
}

/* Moves the cursor. `whence` is the start, the current position, or the end, in
 * that order. Answers the new position, or -1 on failure. */
NUPP_EXPORT int64_t nuppcFileSeek(NuppFile *file, int64_t offset, uint32_t whence) {
    if (file == NULL) {
        nupp_fail("file seek has no file");
        return -1;
    }
    return nupp_fs_seek(file, offset, whence);
}

/* Answers the file's byte length without moving the cursor. */
NUPP_EXPORT int64_t nuppcFileSize(NuppFile *file) {
    if (file == NULL) {
        nupp_fail("file size has no file");
        return -1;
    }
    return nupp_fs_size(file);
}

/* Pushes buffered writes at the operating system. */
NUPP_EXPORT bool nuppcFileFlush(NuppFile *file) {
    if (file == NULL) {
        nupp_fail("file flush has no file");
        return false;
    }
    return nupp_fs_flush(file);
}

/* Closes and releases the file. Repeated calls are the binding's problem, not
 * this one's: a released handle must not be passed again. */
NUPP_EXPORT bool nuppcFileClose(NuppFile *file) {
    if (file == NULL) {
        return true;
    }
    nupp_fs_close(file);
    return true;
}
