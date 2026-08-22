/* The filesystem on Windows.
 *
 * The same operations as `platform_posix.c`, in the calls this platform has.
 * Almost none of it lines up: paths are UTF-16, metadata comes from attributes
 * rather than a mode, a symbolic link is read by asking the driver for its
 * reparse point, and directory iteration is a search rather than a stream. That
 * is why the two files exist instead of one file with the differences threaded
 * through it.
 *
 * Paths cross this seam as UTF-8, because that is what the binding above speaks
 * and what every other platform stores. Each entry point widens on the way in
 * and narrows on the way out, so nothing outside this file has to know.
 */

#include "platform.h"

#if NUPP_WINDOWS

/* Windows 7, which is what `CancelIoEx`, the process attribute list and
 * `PIPE_REJECT_REMOTE_CLIENTS` are all new enough to need. Declared before the
 * header rather than on the command line, so the file says what it stands on. */
#ifndef _WIN32_WINNT
#   define _WIN32_WINNT 0x0601
#endif

#include <windows.h>
#include <wchar.h>
#include <bcrypt.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* --- failure ------------------------------------------------------------ */

static bool fail_last(const char *what) {
    DWORD code = GetLastError();
    char text[256];
    DWORD written = FormatMessageA(
        FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
        NULL, code, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        text, (DWORD)sizeof text, NULL);
    while (written > 0 && (text[written - 1] == '\n' || text[written - 1] == '\r')) {
        text[--written] = '\0';
    }
    if (written == 0) {
        snprintf(text, sizeof text, "error %lu", (unsigned long)code);
    }
    if (what != NULL && what[0] != '\0') {
        nupp_fail_format("%s: %s (os error %lu)", what, text, (unsigned long)code);
    } else {
        nupp_fail_format("%s (os error %lu)", text, (unsigned long)code);
    }
    return false;
}

/* --- paths -------------------------------------------------------------- */

/* One widened path. The `\\?\` prefix is deliberately not added: it lifts the
 * length limit but also stops the system normalizing `..` and `/`, and the paths
 * arriving here are written the way the rest of Nupp writes them. */
typedef struct {
    wchar_t *value;
    wchar_t inlined[260];
    bool heap;
} Wide;

static void wide_free(Wide *wide) {
    if (wide->heap) {
        free(wide->value);
        wide->heap = false;
    }
    wide->value = wide->inlined;
}

static bool widen(Wide *wide, const char *utf8) {
    int needed;
    wide->heap = false;
    wide->value = wide->inlined;
    wide->inlined[0] = L'\0';
    needed = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, -1, NULL, 0);
    if (needed <= 0) {
        nupp_fail_format("%s is not a usable path", utf8);
        return false;
    }
    if ((size_t)needed > sizeof wide->inlined / sizeof wide->inlined[0]) {
        wide->value = malloc((size_t)needed * sizeof(wchar_t));
        if (wide->value == NULL) {
            wide->value = wide->inlined;
            nupp_fail("out of memory");
            return false;
        }
        wide->heap = true;
    }
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, -1, wide->value, needed)
        <= 0) {
        wide_free(wide);
        nupp_fail_format("%s is not a usable path", utf8);
        return false;
    }
    return true;
}

/* Narrows `count` UTF-16 units onto a buffer. A count of -1 means the value is
 * terminated and the terminator is not appended. */
static bool narrow(NuppBuffer *into, const wchar_t *value, int count) {
    int needed = WideCharToMultiByte(CP_UTF8, 0, value, count, NULL, 0, NULL, NULL);
    char *scratch;
    if (needed <= 0) {
        nupp_fail("the platform answered a path that is not representable");
        return false;
    }
    scratch = malloc((size_t)needed);
    if (scratch == NULL) {
        nupp_fail("out of memory");
        return false;
    }
    if (WideCharToMultiByte(CP_UTF8, 0, value, count, scratch, needed, NULL, NULL) <= 0) {
        free(scratch);
        nupp_fail("the platform answered a path that is not representable");
        return false;
    }
    /* A terminated source counts its terminator; the buffer does not carry one. */
    nupp_buffer_append(into, scratch, count < 0 ? (size_t)needed - 1 : (size_t)needed);
    free(scratch);
    return true;
}

/* --- metadata ----------------------------------------------------------- */

/* FILETIME counts hundred-nanosecond intervals from 1601; the answer here counts
 * seconds from 1970. */
static double unix_seconds(FILETIME stamp) {
    ULARGE_INTEGER packed;
    packed.LowPart = stamp.dwLowDateTime;
    packed.HighPart = stamp.dwHighDateTime;
    return (double)packed.QuadPart / 1.0e7 - 11644473600.0;
}

static void fill_info(const WIN32_FILE_ATTRIBUTE_DATA *found, bool reparse, NuppFileInfo *out) {
    ULARGE_INTEGER size;
    if (reparse && (found->dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
        out->kind = NUPP_KIND_SYMLINK;
    } else if ((found->dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
        out->kind = NUPP_KIND_DIRECTORY;
    } else {
        out->kind = NUPP_KIND_FILE;
    }
    out->readOnly = (found->dwFileAttributes & FILE_ATTRIBUTE_READONLY) != 0;
    size.LowPart = found->nFileSizeLow;
    size.HighPart = found->nFileSizeHigh;
    out->size = size.QuadPart;
    out->modified = unix_seconds(found->ftLastWriteTime);
}

bool nupp_fs_stat(const char *path, bool follow, NuppFileInfo *out) {
    Wide wide;
    WIN32_FILE_ATTRIBUTE_DATA found;
    if (!widen(&wide, path)) {
        return false;
    }
    if (!GetFileAttributesExW(wide.value, GetFileExInfoStandard, &found)) {
        wide_free(&wide);
        return fail_last(path);
    }
    if (follow && (found.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
        /* The attribute call reports the link; opening without the reparse flag
         * reports whatever it points at, which is what following means. */
        HANDLE handle = CreateFileW(
            wide.value, 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
        BY_HANDLE_FILE_INFORMATION resolved;
        if (handle == INVALID_HANDLE_VALUE) {
            wide_free(&wide);
            return fail_last(path);
        }
        if (!GetFileInformationByHandle(handle, &resolved)) {
            CloseHandle(handle);
            wide_free(&wide);
            return fail_last(path);
        }
        CloseHandle(handle);
        found.dwFileAttributes = resolved.dwFileAttributes;
        found.ftLastWriteTime = resolved.ftLastWriteTime;
        found.nFileSizeLow = resolved.nFileSizeLow;
        found.nFileSizeHigh = resolved.nFileSizeHigh;
    }
    wide_free(&wide);
    fill_info(&found, !follow, out);
    return true;
}

/* The reparse point layout, which the public headers do not carry. */
#define NUPP_IO_REPARSE_TAG_SYMLINK 0xA000000CUL
#define NUPP_IO_REPARSE_TAG_MOUNT_POINT 0xA0000003UL
#define NUPP_FSCTL_GET_REPARSE_POINT 0x000900A8UL
#define NUPP_MAXIMUM_REPARSE_DATA_BUFFER_SIZE 16384

typedef struct {
    ULONG ReparseTag;
    USHORT ReparseDataLength;
    USHORT Reserved;
    USHORT SubstituteNameOffset;
    USHORT SubstituteNameLength;
    USHORT PrintNameOffset;
    USHORT PrintNameLength;
    ULONG Flags;
    WCHAR PathBuffer[1];
} NuppSymbolicLinkReparse;

bool nupp_fs_read_link(const char *path, NuppBuffer *into) {
    Wide wide;
    HANDLE handle;
    unsigned char *scratch;
    DWORD returned = 0;
    bool ok = false;

    if (!widen(&wide, path)) {
        return false;
    }
    handle = CreateFileW(
        wide.value, 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
        OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
    wide_free(&wide);
    if (handle == INVALID_HANDLE_VALUE) {
        return fail_last(path);
    }
    scratch = malloc(NUPP_MAXIMUM_REPARSE_DATA_BUFFER_SIZE);
    if (scratch == NULL) {
        CloseHandle(handle);
        nupp_fail("out of memory");
        return false;
    }
    if (!DeviceIoControl(
            handle, NUPP_FSCTL_GET_REPARSE_POINT, NULL, 0, scratch,
            NUPP_MAXIMUM_REPARSE_DATA_BUFFER_SIZE, &returned, NULL)) {
        fail_last(path);
    } else {
        const NuppSymbolicLinkReparse *reparse = (const NuppSymbolicLinkReparse *)scratch;
        if (reparse->ReparseTag != NUPP_IO_REPARSE_TAG_SYMLINK
            && reparse->ReparseTag != NUPP_IO_REPARSE_TAG_MOUNT_POINT) {
            nupp_fail_format("%s is not a symbolic link", path);
        } else {
            /* The print name is what the link was created with; the substitute
             * name is the same target spelled for the object manager, and is all
             * there is when the print name was left empty. */
            const WCHAR *base;
            USHORT offset = reparse->PrintNameOffset;
            USHORT count = reparse->PrintNameLength;
            if (count == 0) {
                offset = reparse->SubstituteNameOffset;
                count = reparse->SubstituteNameLength;
            }
            base = (const WCHAR *)((const unsigned char *)reparse->PathBuffer + offset);
            {
                int units = (int)(count / sizeof(WCHAR));
                if (units >= 4 && wcsncmp(base, L"\\??\\", 4) == 0) {
                    base += 4;
                    units -= 4;
                }
                ok = narrow(into, base, units);
            }
        }
    }
    free(scratch);
    CloseHandle(handle);
    return ok;
}

bool nupp_fs_create_symlink(const char *target, const char *link, bool directory) {
    Wide to, at;
    DWORD flags = directory ? SYMBOLIC_LINK_FLAG_DIRECTORY : 0;
    bool ok;
    if (!widen(&to, target)) {
        return false;
    }
    if (!widen(&at, link)) {
        wide_free(&to);
        return false;
    }
    /* Creating a link is a privilege on Windows unless the machine is in
     * developer mode, which is what the unprivileged flag asks for. An older
     * system rejects the flag itself, so the call is repeated without it. */
    ok = CreateSymbolicLinkW(
        at.value, to.value, flags | SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE) != 0;
    if (!ok && GetLastError() == ERROR_INVALID_PARAMETER) {
        ok = CreateSymbolicLinkW(at.value, to.value, flags) != 0;
    }
    if (!ok) {
        fail_last(link);
    }
    wide_free(&to);
    wide_free(&at);
    return ok;
}

bool nupp_fs_set_read_only(const char *path, bool readOnly) {
    Wide wide;
    DWORD attributes;
    bool ok;
    if (!widen(&wide, path)) {
        return false;
    }
    attributes = GetFileAttributesW(wide.value);
    if (attributes == INVALID_FILE_ATTRIBUTES) {
        wide_free(&wide);
        return fail_last(path);
    }
    if (readOnly) {
        attributes |= FILE_ATTRIBUTE_READONLY;
    } else {
        attributes &= ~(DWORD)FILE_ATTRIBUTE_READONLY;
    }
    ok = SetFileAttributesW(wide.value, attributes) != 0;
    if (!ok) {
        fail_last(path);
    }
    wide_free(&wide);
    return ok;
}

/* --- directories -------------------------------------------------------- */

bool nupp_fs_create_directory_all(const char *path) {
    char *copy;
    size_t length = strlen(path);
    size_t at;
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
    for (at = 1; at <= length; at++) {
        char saved;
        Wide wide;
        if (at != length && copy[at] != '/' && copy[at] != '\\') {
            continue;
        }
        saved = copy[at];
        copy[at] = '\0';
        /* `C:` on its own is a drive rather than a directory, and creating it is
         * neither possible nor wanted. */
        if (!(at == 2 && copy[1] == ':') && widen(&wide, copy)) {
            if (!CreateDirectoryW(wide.value, NULL)
                && GetLastError() != ERROR_ALREADY_EXISTS) {
                fail_last(copy);
                wide_free(&wide);
                copy[at] = saved;
                free(copy);
                return false;
            }
            wide_free(&wide);
        }
        copy[at] = saved;
    }
    free(copy);
    return true;
}

struct NuppDirectory {
    HANDLE search;
    WIN32_FIND_DATAW found;
    bool pending;
    char name[MAX_PATH * 4];
    char *path;
};

NuppDirectory *nupp_fs_open_directory(const char *path) {
    NuppDirectory *directory;
    NuppBuffer pattern;
    Wide wide;
    size_t pathLength = strlen(path);

    nupp_buffer_init(&pattern);
    nupp_buffer_append(&pattern, path, pathLength);
    if (pathLength != 0 && path[pathLength - 1] != '/' && path[pathLength - 1] != '\\') {
        nupp_buffer_push(&pattern, '\\');
    }
    nupp_buffer_append(&pattern, "*", 1);
    nupp_buffer_push(&pattern, 0);
    if (pattern.failed) {
        nupp_buffer_free(&pattern);
        nupp_fail("out of memory");
        return NULL;
    }
    if (!widen(&wide, (const char *)pattern.data)) {
        nupp_buffer_free(&pattern);
        return NULL;
    }
    nupp_buffer_free(&pattern);

    directory = calloc(1, sizeof *directory);
    if (directory == NULL) {
        wide_free(&wide);
        nupp_fail("out of memory");
        return NULL;
    }
    directory->path = malloc(pathLength + 1);
    if (directory->path == NULL) {
        wide_free(&wide);
        free(directory);
        nupp_fail("out of memory");
        return NULL;
    }
    memcpy(directory->path, path, pathLength + 1);
    directory->search = FindFirstFileW(wide.value, &directory->found);
    wide_free(&wide);
    if (directory->search == INVALID_HANDLE_VALUE) {
        fail_last(path);
        free(directory->path);
        free(directory);
        return NULL;
    }
    directory->pending = true;
    return directory;
}

static char entry_kind(const WIN32_FIND_DATAW *found) {
    if ((found->dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) {
        return 'l';
    }
    if ((found->dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
        return 'd';
    }
    return 'f';
}

int nupp_fs_next_entry(NuppDirectory *directory, const char **name, char *kind) {
    for (;;) {
        if (!directory->pending) {
            if (!FindNextFileW(directory->search, &directory->found)) {
                if (GetLastError() == ERROR_NO_MORE_FILES) {
                    return 0;
                }
                fail_last(directory->path);
                return -1;
            }
        }
        directory->pending = false;
        if (wcscmp(directory->found.cFileName, L".") == 0
            || wcscmp(directory->found.cFileName, L"..") == 0) {
            continue;
        }
        if (WideCharToMultiByte(
                CP_UTF8, 0, directory->found.cFileName, -1, directory->name,
                (int)sizeof directory->name, NULL, NULL) <= 0) {
            nupp_fail("a directory entry name is not representable");
            return -1;
        }
        *name = directory->name;
        *kind = entry_kind(&directory->found);
        return 1;
    }
}

void nupp_fs_close_directory(NuppDirectory *directory) {
    if (directory != NULL) {
        FindClose(directory->search);
        free(directory->path);
        free(directory);
    }
}

/* --- removal ------------------------------------------------------------ */

static bool remove_one(const char *path, bool directory) {
    Wide wide;
    bool ok;
    if (!widen(&wide, path)) {
        return false;
    }
    if (directory) {
        ok = RemoveDirectoryW(wide.value) != 0;
    } else {
        /* A read-only file refuses to be deleted, and the caller asking for it
         * gone has already said what it wants. */
        DWORD attributes = GetFileAttributesW(wide.value);
        if (attributes != INVALID_FILE_ATTRIBUTES
            && (attributes & FILE_ATTRIBUTE_READONLY) != 0) {
            SetFileAttributesW(wide.value, attributes & ~(DWORD)FILE_ATTRIBUTE_READONLY);
        }
        ok = DeleteFileW(wide.value) != 0;
    }
    if (!ok) {
        fail_last(path);
    }
    wide_free(&wide);
    return ok;
}

static bool remove_tree(const char *path) {
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
        /* A directory is descended into; a link to one is removed as the link it
         * is, because following it would delete somewhere the caller did not
         * name. A directory link is removed with RemoveDirectory even so. */
        if (kind == 'd') {
            ok = remove_tree(child);
        } else if (kind == 'l') {
            ok = remove_one(child, false) || remove_one(child, true);
        } else {
            ok = remove_one(child, false);
        }
        free(child);
        if (!ok) {
            break;
        }
    }
    nupp_fs_close_directory(directory);
    return ok && remove_one(path, true);
}

bool nupp_fs_remove(const char *path, bool recursive) {
    NuppFileInfo info;
    if (!nupp_fs_stat(path, false, &info)) {
        return false;
    }
    if (info.kind == NUPP_KIND_DIRECTORY) {
        return recursive ? remove_tree(path) : remove_one(path, true);
    }
    if (info.kind == NUPP_KIND_SYMLINK) {
        return remove_one(path, false) || remove_one(path, true);
    }
    return remove_one(path, false);
}

bool nupp_fs_canonicalize(const char *path, NuppBuffer *into) {
    Wide wide;
    HANDLE handle;
    DWORD needed;
    wchar_t *resolved;
    bool ok;

    if (!widen(&wide, path)) {
        return false;
    }
    handle = CreateFileW(
        wide.value, 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
        OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
    wide_free(&wide);
    if (handle == INVALID_HANDLE_VALUE) {
        return fail_last(path);
    }
    needed = GetFinalPathNameByHandleW(handle, NULL, 0, FILE_NAME_NORMALIZED);
    if (needed == 0) {
        CloseHandle(handle);
        return fail_last(path);
    }
    resolved = malloc((size_t)needed * sizeof(wchar_t));
    if (resolved == NULL) {
        CloseHandle(handle);
        nupp_fail("out of memory");
        return false;
    }
    if (GetFinalPathNameByHandleW(handle, resolved, needed, FILE_NAME_NORMALIZED) == 0) {
        free(resolved);
        CloseHandle(handle);
        return fail_last(path);
    }
    CloseHandle(handle);
    {
        /* The answer is verbatim -- `\\?\C:\...` -- and a caller that asked
         * for a path wants the one it can pass to anything else. The UNC form
         * keeps its double separator, so only the drive form is unwrapped. */
        const wchar_t *base = resolved;
        if (wcsncmp(base, L"\\\\?\\UNC\\", 8) == 0) {
            base += 6;
        } else if (wcsncmp(base, L"\\\\?\\", 4) == 0) {
            base += 4;
        }
        ok = narrow(into, base, -1);
    }
    free(resolved);
    return ok;
}

static bool move_file(const char *from, const char *to, DWORD flags) {
    Wide source, destination;
    bool ok;
    if (!widen(&source, from)) {
        return false;
    }
    if (!widen(&destination, to)) {
        wide_free(&source);
        return false;
    }
    ok = MoveFileExW(source.value, destination.value, flags) != 0;
    if (!ok) {
        fail_last(from);
    }
    wide_free(&source);
    wide_free(&destination);
    return ok;
}

bool nupp_fs_rename(const char *from, const char *to) {
    return move_file(from, to, MOVEFILE_REPLACE_EXISTING);
}

bool nupp_fs_replace(const char *from, const char *to) {
    return move_file(from, to, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
}

bool nupp_fs_copy(const char *from, const char *to) {
    Wide source, destination;
    bool ok;
    if (!widen(&source, from)) {
        return false;
    }
    if (!widen(&destination, to)) {
        wide_free(&source);
        return false;
    }
    ok = CopyFileW(source.value, destination.value, FALSE) != 0;
    if (!ok) {
        fail_last(from);
    }
    wide_free(&source);
    wide_free(&destination);
    return ok;
}

/* --- open files --------------------------------------------------------- */

struct NuppFile {
    HANDLE handle;
    bool appending;
};

static NuppFile *wrap(HANDLE handle, bool appending) {
    NuppFile *file = malloc(sizeof *file);
    if (file == NULL) {
        CloseHandle(handle);
        nupp_fail("out of memory");
        return NULL;
    }
    file->handle = handle;
    file->appending = appending;
    return file;
}

NuppFile *nupp_fs_open(const char *path, uint32_t mode) {
    Wide wide;
    DWORD access;
    DWORD disposition;
    bool appending = false;
    HANDLE handle;

    switch (mode) {
        case 0: access = GENERIC_READ; disposition = OPEN_EXISTING; break;
        case 1: access = GENERIC_WRITE; disposition = CREATE_ALWAYS; break;
        case 2: access = FILE_APPEND_DATA; disposition = OPEN_ALWAYS; appending = true; break;
        case 3: access = GENERIC_READ | GENERIC_WRITE; disposition = OPEN_EXISTING; break;
        case 4: access = GENERIC_READ | GENERIC_WRITE; disposition = CREATE_ALWAYS; break;
        case 5:
            access = GENERIC_READ | FILE_APPEND_DATA;
            disposition = OPEN_ALWAYS;
            appending = true;
            break;
        default:
            nupp_fail("unknown file mode");
            return NULL;
    }
    if (!widen(&wide, path)) {
        return NULL;
    }
    handle = CreateFileW(
        wide.value, access, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        NULL, disposition, FILE_ATTRIBUTE_NORMAL, NULL);
    wide_free(&wide);
    if (handle == INVALID_HANDLE_VALUE) {
        fail_last(path);
        return NULL;
    }
    return wrap(handle, appending);
}

NuppFile *nupp_fs_create_new(const char *path, bool *taken) {
    Wide wide;
    HANDLE handle;
    *taken = false;
    if (!widen(&wide, path)) {
        return NULL;
    }
    handle = CreateFileW(
        wide.value, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    wide_free(&wide);
    if (handle == INVALID_HANDLE_VALUE) {
        if (GetLastError() == ERROR_FILE_EXISTS || GetLastError() == ERROR_ALREADY_EXISTS) {
            *taken = true;
        } else {
            fail_last(path);
        }
        return NULL;
    }
    return wrap(handle, false);
}

bool nupp_fs_create_directory_new(const char *path, bool *taken) {
    Wide wide;
    bool ok;
    *taken = false;
    if (!widen(&wide, path)) {
        return false;
    }
    ok = CreateDirectoryW(wide.value, NULL) != 0;
    if (!ok) {
        if (GetLastError() == ERROR_ALREADY_EXISTS) {
            *taken = true;
        } else {
            fail_last(path);
        }
    }
    wide_free(&wide);
    return ok;
}

int64_t nupp_fs_read(NuppFile *file, uint8_t *into, size_t length) {
    DWORD got = 0;
    DWORD wanted = length > 0x40000000u ? 0x40000000u : (DWORD)length;
    if (!ReadFile(file->handle, into, wanted, &got, NULL)) {
        if (GetLastError() == ERROR_BROKEN_PIPE) {
            return 0;
        }
        fail_last("cannot read");
        return -1;
    }
    return (int64_t)got;
}

int64_t nupp_fs_write(NuppFile *file, const uint8_t *from, size_t length) {
    size_t written = 0;
    while (written < length) {
        DWORD step = 0;
        size_t remaining = length - written;
        DWORD wanted = remaining > 0x40000000u ? 0x40000000u : (DWORD)remaining;
        if (!WriteFile(file->handle, from + written, wanted, &step, NULL)) {
            fail_last("cannot write");
            return -1;
        }
        if (step == 0) {
            nupp_fail("the write made no progress");
            return -1;
        }
        written += step;
    }
    return (int64_t)length;
}

int64_t nupp_fs_seek(NuppFile *file, int64_t offset, uint32_t whence) {
    LARGE_INTEGER move, moved;
    DWORD origin;
    switch (whence) {
        case 0:
            origin = FILE_BEGIN;
            if (offset < 0) {
                offset = 0;
            }
            break;
        case 1: origin = FILE_CURRENT; break;
        case 2: origin = FILE_END; break;
        default:
            nupp_fail("unknown seek origin");
            return -1;
    }
    move.QuadPart = offset;
    if (!SetFilePointerEx(file->handle, move, &moved, origin)) {
        fail_last("cannot seek");
        return -1;
    }
    return (int64_t)moved.QuadPart;
}

int64_t nupp_fs_size(NuppFile *file) {
    LARGE_INTEGER size;
    if (!GetFileSizeEx(file->handle, &size)) {
        fail_last("cannot size");
        return -1;
    }
    return (int64_t)size.QuadPart;
}

bool nupp_fs_flush(NuppFile *file) {
    (void)file;
    return true;
}

bool nupp_fs_sync(NuppFile *file) {
    if (!FlushFileBuffers(file->handle)) {
        return fail_last("cannot sync");
    }
    return true;
}

bool nupp_fs_close(NuppFile *file) {
    bool ok = true;
    if (file == NULL) {
        return true;
    }
    if (!CloseHandle(file->handle)) {
        ok = fail_last("cannot close");
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

/* --- the environment ---------------------------------------------------- */

bool nupp_fs_current_directory(NuppBuffer *into) {
    DWORD needed = GetCurrentDirectoryW(0, NULL);
    wchar_t *scratch;
    bool ok;
    if (needed == 0) {
        return fail_last("cannot read the working directory");
    }
    scratch = malloc((size_t)needed * sizeof(wchar_t));
    if (scratch == NULL) {
        nupp_fail("out of memory");
        return false;
    }
    if (GetCurrentDirectoryW(needed, scratch) == 0) {
        free(scratch);
        return fail_last("cannot read the working directory");
    }
    ok = narrow(into, scratch, -1);
    free(scratch);
    return ok;
}

bool nupp_fs_temporary_directory(NuppBuffer *into) {
    wchar_t scratch[MAX_PATH + 2];
    DWORD written = GetTempPathW(MAX_PATH + 1, scratch);
    if (written == 0) {
        return fail_last("cannot find the temporary directory");
    }
    /* GetTempPath answers a trailing separator; the callers here join with one. */
    while (written > 1 && (scratch[written - 1] == L'\\' || scratch[written - 1] == L'/')) {
        written--;
    }
    return narrow(into, scratch, (int)written);
}

const char *nupp_environment(const char *name) {
    const char *value = getenv(name);
    return (value != NULL && value[0] != '\0') ? value : NULL;
}

void nupp_fs_random(void *into, size_t length) {
    if (BCryptGenRandom(
            NULL, into, (ULONG)length, BCRYPT_USE_SYSTEM_PREFERRED_RNG) == 0) {
        return;
    }
    {
        uint64_t mixed = (uint64_t)GetCurrentProcessId();
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
    CRITICAL_SECTION handle;
};

struct NuppCondition {
    CONDITION_VARIABLE handle;
};

NuppMutex *nupp_mutex_new(void) {
    NuppMutex *mutex = malloc(sizeof *mutex);
    if (mutex != NULL) {
        InitializeCriticalSection(&mutex->handle);
    }
    return mutex;
}

void nupp_mutex_free(NuppMutex *mutex) {
    if (mutex != NULL) {
        DeleteCriticalSection(&mutex->handle);
        free(mutex);
    }
}

void nupp_mutex_lock(NuppMutex *mutex) {
    EnterCriticalSection(&mutex->handle);
}

void nupp_mutex_unlock(NuppMutex *mutex) {
    LeaveCriticalSection(&mutex->handle);
}

NuppCondition *nupp_condition_new(void) {
    NuppCondition *condition = malloc(sizeof *condition);
    if (condition != NULL) {
        InitializeConditionVariable(&condition->handle);
    }
    return condition;
}

void nupp_condition_free(NuppCondition *condition) {
    /* A condition variable owns nothing the system has to be told about. */
    free(condition);
}

void nupp_condition_wait(NuppCondition *condition, NuppMutex *mutex) {
    SleepConditionVariableCS(&condition->handle, &mutex->handle, INFINITE);
}

bool nupp_condition_wait_for(
    NuppCondition *condition, NuppMutex *mutex, uint64_t milliseconds
) {
    DWORD wait = milliseconds > 0xFFFFFFFEu ? 0xFFFFFFFEu : (DWORD)milliseconds;
    if (SleepConditionVariableCS(&condition->handle, &mutex->handle, wait)) {
        return true;
    }
    return GetLastError() != ERROR_TIMEOUT;
}

void nupp_condition_signal(NuppCondition *condition) {
    WakeConditionVariable(&condition->handle);
}

void nupp_condition_broadcast(NuppCondition *condition) {
    WakeAllConditionVariable(&condition->handle);
}

typedef struct {
    void (*entry)(void *);
    void *argument;
} Spawned;

static DWORD WINAPI thread_trampoline(LPVOID raw) {
    Spawned *spawned = raw;
    void (*entry)(void *) = spawned->entry;
    void *argument = spawned->argument;
    free(spawned);
    entry(argument);
    return 0;
}

bool nupp_thread_spawn(void (*entry)(void *), void *argument) {
    HANDLE thread;
    Spawned *spawned = malloc(sizeof *spawned);
    if (spawned == NULL) {
        nupp_fail("out of memory");
        return false;
    }
    spawned->entry = entry;
    spawned->argument = argument;
    thread = CreateThread(NULL, 0, thread_trampoline, spawned, 0, NULL);
    if (thread == NULL) {
        free(spawned);
        return fail_last("cannot start a worker thread");
    }
    /* Nothing joins these: the lanes outlive every caller and go when the
     * process does. */
    CloseHandle(thread);
    return true;
}

/* --- child processes ---------------------------------------------------- */

/* Pipes here are named pipes with unique names rather than the anonymous kind.
 *
 * An anonymous pipe cannot be opened overlapped, and without overlap there is no
 * nonblocking read, no nonblocking write and nothing for a readiness wait to
 * wait on. A named pipe with a name nobody else will guess is the documented way
 * to get an anonymous pipe that can do those three things: this process keeps
 * the overlapped server end, and the child receives an ordinary inheritable
 * client end that behaves exactly as it expects.
 *
 * Each end carries the buffer its pending operation is using. A read is issued
 * ahead of being asked for, so that a readiness wait has an event to watch; a
 * write copies the caller's bytes and reports them accepted, because an
 * overlapped write cannot say how much it took until it finishes and a caller
 * counting bytes cannot wait for that.
 */

#define NUPP_PIPE_BUFFER 65536

struct NuppPipeEnd {
    HANDLE handle;
    HANDLE event;
    OVERLAPPED overlapped;
    bool closed;
    bool reading;
    bool pending;
    bool broken;
    uint8_t *buffer;
    DWORD available;
    DWORD consumed;
};

static NuppPipeEnd *wrap_handle(HANDLE handle, bool reading) {
    NuppPipeEnd *end = calloc(1, sizeof *end);
    if (end == NULL) {
        CloseHandle(handle);
        nupp_fail("out of memory");
        return NULL;
    }
    end->handle = handle;
    end->reading = reading;
    end->buffer = malloc(NUPP_PIPE_BUFFER);
    end->event = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (end->buffer == NULL || end->event == NULL) {
        if (end->event != NULL) {
            CloseHandle(end->event);
        }
        free(end->buffer);
        free(end);
        CloseHandle(handle);
        nupp_fail("out of memory");
        return NULL;
    }
    end->overlapped.hEvent = end->event;
    return end;
}

bool nupp_pipe_is_closed(const NuppPipeEnd *end) {
    return end == NULL || end->closed;
}

void nupp_pipe_close(NuppPipeEnd *end) {
    if (end == NULL || end->closed) {
        return;
    }
    if (end->pending) {
        /* A cancelled operation still owns the buffer until the wait below says
         * the kernel has let go of it. */
        CancelIoEx(end->handle, &end->overlapped);
        {
            DWORD moved = 0;
            GetOverlappedResult(end->handle, &end->overlapped, &moved, TRUE);
        }
        end->pending = false;
    }
    CloseHandle(end->handle);
    end->handle = INVALID_HANDLE_VALUE;
    end->closed = true;
}

void nupp_pipe_destroy(NuppPipeEnd *end) {
    if (end != NULL) {
        nupp_pipe_close(end);
        if (end->event != NULL) {
            CloseHandle(end->event);
        }
        free(end->buffer);
        free(end);
    }
}

/* Issues the read this end will be asked for, so the wait has something to
 * watch. Answers false when the pipe has ended or failed. */
static bool begin_read(NuppPipeEnd *end) {
    DWORD moved = 0;
    if (end->pending || end->broken || end->available > end->consumed) {
        return true;
    }
    end->available = 0;
    end->consumed = 0;
    ResetEvent(end->event);
    end->overlapped.Offset = 0;
    end->overlapped.OffsetHigh = 0;
    if (ReadFile(end->handle, end->buffer, NUPP_PIPE_BUFFER, &moved, &end->overlapped)) {
        end->available = moved;
        if (moved == 0) {
            end->broken = true;
        }
        return true;
    }
    if (GetLastError() == ERROR_IO_PENDING) {
        end->pending = true;
        return true;
    }
    /* A closed far end is the ordinary way a read finishes, not a failure. */
    if (GetLastError() == ERROR_BROKEN_PIPE || GetLastError() == ERROR_PIPE_NOT_CONNECTED) {
        end->broken = true;
        return true;
    }
    return false;
}

/* Collects a pending operation when it has finished. */
static bool settle(NuppPipeEnd *end, bool wait) {
    DWORD moved = 0;
    if (!end->pending) {
        return true;
    }
    if (GetOverlappedResult(end->handle, &end->overlapped, &moved, wait ? TRUE : FALSE)) {
        end->pending = false;
        if (end->reading) {
            end->available = moved;
            if (moved == 0) {
                end->broken = true;
            }
        }
        return true;
    }
    if (GetLastError() == ERROR_IO_INCOMPLETE) {
        return true;
    }
    end->pending = false;
    if (GetLastError() == ERROR_BROKEN_PIPE || GetLastError() == ERROR_PIPE_NOT_CONNECTED) {
        end->broken = true;
        return true;
    }
    return false;
}

intptr_t nupp_pipe_read(NuppPipeEnd *end, uint8_t *into, size_t length) {
    DWORD ready;
    if (!settle(end, false)) {
        fail_last("cannot read from the child");
        return NUPP_FAILED;
    }
    if (end->available == end->consumed) {
        if (end->broken) {
            return NUPP_GONE;
        }
        if (!begin_read(end)) {
            fail_last("cannot read from the child");
            return NUPP_FAILED;
        }
        if (end->pending) {
            return NUPP_WOULD_BLOCK;
        }
        if (end->broken && end->available == 0) {
            return NUPP_GONE;
        }
    }
    ready = end->available - end->consumed;
    if (ready == 0) {
        return end->broken ? NUPP_GONE : NUPP_WOULD_BLOCK;
    }
    if ((size_t)ready > length) {
        ready = (DWORD)length;
    }
    memcpy(into, end->buffer + end->consumed, ready);
    end->consumed += ready;
    return (intptr_t)ready;
}

intptr_t nupp_pipe_write(NuppPipeEnd *end, const uint8_t *from, size_t length) {
    DWORD moved = 0;
    DWORD wanted;
    if (!settle(end, false)) {
        if (end->broken) {
            return NUPP_GONE;
        }
        fail_last("cannot write to the child");
        return NUPP_FAILED;
    }
    if (end->broken) {
        return NUPP_GONE;
    }
    if (end->pending) {
        return NUPP_WOULD_BLOCK;
    }
    /* The bytes are copied and reported accepted. An overlapped write cannot say
     * how much it took until it finishes, and a caller counting bytes cannot
     * wait for that -- so this end owns them until they land, which is what a
     * pipe buffer would have done anyway. */
    wanted = length > NUPP_PIPE_BUFFER ? NUPP_PIPE_BUFFER : (DWORD)length;
    memcpy(end->buffer, from, wanted);
    ResetEvent(end->event);
    end->overlapped.Offset = 0;
    end->overlapped.OffsetHigh = 0;
    if (WriteFile(end->handle, end->buffer, wanted, &moved, &end->overlapped)) {
        return (intptr_t)wanted;
    }
    if (GetLastError() == ERROR_IO_PENDING) {
        end->pending = true;
        return (intptr_t)wanted;
    }
    if (GetLastError() == ERROR_BROKEN_PIPE || GetLastError() == ERROR_NO_DATA) {
        end->broken = true;
        return NUPP_GONE;
    }
    fail_last("cannot write to the child");
    return NUPP_FAILED;
}

/* One pipe: an overlapped server end this process keeps, and an inheritable
 * client end the child receives. */
static bool make_pipe(HANDLE *parentEnd, HANDLE *childEnd, bool parentReads) {
    static LONG counter;
    wchar_t name[128];
    SECURITY_ATTRIBUTES inheritable;
    HANDLE server, client;

    _snwprintf(name, sizeof name / sizeof name[0], L"\\\\.\\pipe\\nupp-%lu-%ld",
        (unsigned long)GetCurrentProcessId(), InterlockedIncrement(&counter));
    server = CreateNamedPipeW(
        name,
        (parentReads ? PIPE_ACCESS_INBOUND : PIPE_ACCESS_OUTBOUND) | FILE_FLAG_OVERLAPPED
            | FILE_FLAG_FIRST_PIPE_INSTANCE,
        PIPE_TYPE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
        1, NUPP_PIPE_BUFFER, NUPP_PIPE_BUFFER, 0, NULL);
    if (server == INVALID_HANDLE_VALUE) {
        return fail_last("cannot create a pipe");
    }
    inheritable.nLength = sizeof inheritable;
    inheritable.lpSecurityDescriptor = NULL;
    inheritable.bInheritHandle = TRUE;
    client = CreateFileW(
        name, parentReads ? GENERIC_WRITE : GENERIC_READ, 0, &inheritable,
        OPEN_EXISTING, 0, NULL);
    if (client == INVALID_HANDLE_VALUE) {
        CloseHandle(server);
        return fail_last("cannot open the child's end of a pipe");
    }
    *parentEnd = server;
    *childEnd = client;
    return true;
}

/* One argument, quoted the way `CommandLineToArgvW` reads it back. */
static void quote_argument(NuppBuffer *into, const char *argument) {
    size_t at;
    bool needs = argument[0] == '\0';
    for (at = 0; argument[at] != '\0'; at++) {
        if (argument[at] == ' ' || argument[at] == '\t' || argument[at] == '"') {
            needs = true;
        }
    }
    if (!needs) {
        nupp_buffer_append(into, argument, strlen(argument));
        return;
    }
    nupp_buffer_push(into, '"');
    for (at = 0; argument[at] != '\0'; at++) {
        size_t slashes = 0;
        while (argument[at] == '\\') {
            slashes++;
            at++;
        }
        if (argument[at] == '\0') {
            /* Backslashes before the closing quote are doubled, so the quote is
             * read as a quote rather than escaped by the last of them. */
            size_t step;
            for (step = 0; step < slashes * 2; step++) {
                nupp_buffer_push(into, '\\');
            }
            break;
        }
        {
            size_t step;
            size_t doubled = argument[at] == '"' ? slashes * 2 + 1 : slashes;
            for (step = 0; step < doubled; step++) {
                nupp_buffer_push(into, '\\');
            }
        }
        nupp_buffer_push(into, (uint8_t)argument[at]);
    }
    nupp_buffer_push(into, '"');
}

/* The environment block: NUL-separated entries, double-NUL terminated, in
 * UTF-16. Entries modify the inherited environment rather than replacing it,
 * unless the request cleared first. */
static wchar_t *build_environment(const NuppSpawnRequest *request) {
    NuppBuffer flat;
    wchar_t *wide;
    int needed;
    size_t at;

    nupp_buffer_init(&flat);
    if (!request->clearEnv) {
        LPWCH inherited = GetEnvironmentStringsW();
        LPWCH scan = inherited;
        while (inherited != NULL && *scan != L'\0') {
            size_t length = wcslen(scan);
            NuppBuffer entry;
            nupp_buffer_init(&entry);
            if (narrow(&entry, scan, (int)length)) {
                /* An entry the request also names is dropped here and added
                 * below, so the request wins without the block holding both. */
                bool replaced = false;
                if (request->envp != NULL) {
                    const char *equals = memchr(entry.data, '=', entry.length);
                    size_t nameLength = equals != NULL
                        ? (size_t)(equals - (const char *)entry.data) : entry.length;
                    for (at = 0; request->envp[at] != NULL; at++) {
                        if (strncmp(request->envp[at], (const char *)entry.data, nameLength) == 0
                            && request->envp[at][nameLength] == '=') {
                            replaced = true;
                            break;
                        }
                    }
                }
                /* A block begins with `=C:=...` drive entries the process needs
                 * kept; they have an empty name and never collide. */
                if (!replaced) {
                    nupp_buffer_append(&flat, entry.data, entry.length);
                    nupp_buffer_push(&flat, 0);
                }
            }
            nupp_buffer_free(&entry);
            scan += length + 1;
        }
        if (inherited != NULL) {
            FreeEnvironmentStringsW(inherited);
        }
    }
    if (request->envp != NULL) {
        for (at = 0; request->envp[at] != NULL; at++) {
            nupp_buffer_append(&flat, request->envp[at], strlen(request->envp[at]));
            nupp_buffer_push(&flat, 0);
        }
    }
    nupp_buffer_push(&flat, 0);
    if (flat.failed) {
        nupp_buffer_free(&flat);
        nupp_fail("out of memory");
        return NULL;
    }
    /* One conversion of the whole block, terminators included, which is why the
     * length is given rather than letting the call stop at the first NUL. */
    needed = MultiByteToWideChar(CP_UTF8, 0, (const char *)flat.data, (int)flat.length, NULL, 0);
    if (needed <= 0) {
        nupp_buffer_free(&flat);
        nupp_fail("the environment is not representable");
        return NULL;
    }
    wide = malloc(((size_t)needed + 1) * sizeof(wchar_t));
    if (wide == NULL) {
        nupp_buffer_free(&flat);
        nupp_fail("out of memory");
        return NULL;
    }
    MultiByteToWideChar(
        CP_UTF8, 0, (const char *)flat.data, (int)flat.length, wide, needed);
    wide[needed] = L'\0';
    nupp_buffer_free(&flat);
    return wide;
}

bool nupp_spawn(const NuppSpawnRequest *request, NuppSpawnResult *result) {
    HANDLE parentEnds[3] = {INVALID_HANDLE_VALUE, INVALID_HANDLE_VALUE, INVALID_HANDLE_VALUE};
    HANDLE childEnds[3] = {INVALID_HANDLE_VALUE, INVALID_HANDLE_VALUE, INVALID_HANDLE_VALUE};
    HANDLE devNull = INVALID_HANDLE_VALUE;
    HANDLE inherited[3];
    DWORD inheritedCount = 0;
    NuppBuffer command;
    Wide wideCommand;
    Wide wideCwd;
    wchar_t *environment = NULL;
    STARTUPINFOEXW startup;
    PROCESS_INFORMATION information;
    SIZE_T attributeSize = 0;
    LPPROC_THREAD_ATTRIBUTE_LIST attributes = NULL;
    bool merged = false;
    bool haveCwd = false;
    size_t which;
    size_t at;

    memset(result, 0, sizeof *result);
    memset(&startup, 0, sizeof startup);
    memset(&information, 0, sizeof information);
    nupp_buffer_init(&command);
    wideCommand.value = wideCommand.inlined;
    wideCommand.heap = false;
    wideCwd.value = wideCwd.inlined;
    wideCwd.heap = false;

    for (which = 0; which < 3; which++) {
        uint8_t mode = request->modes[which];
        if (which == 2 && mode == NUPP_MODE_STDOUT) {
            continue;
        }
        if (mode == NUPP_MODE_PIPE) {
            if (!make_pipe(&parentEnds[which], &childEnds[which], which != 0)) {
                goto fail;
            }
        } else if (mode == NUPP_MODE_NULL) {
            if (devNull == INVALID_HANDLE_VALUE) {
                SECURITY_ATTRIBUTES inheritable;
                inheritable.nLength = sizeof inheritable;
                inheritable.lpSecurityDescriptor = NULL;
                inheritable.bInheritHandle = TRUE;
                devNull = CreateFileW(
                    L"NUL", GENERIC_READ | GENERIC_WRITE,
                    FILE_SHARE_READ | FILE_SHARE_WRITE, &inheritable, OPEN_EXISTING,
                    0, NULL);
                if (devNull == INVALID_HANDLE_VALUE) {
                    fail_last("cannot open NUL");
                    goto fail;
                }
            }
            childEnds[which] = devNull;
        } else {
            /* Inherit: the child receives this process's own standard handle. */
            childEnds[which] = GetStdHandle(
                which == 0 ? STD_INPUT_HANDLE
                    : which == 1 ? STD_OUTPUT_HANDLE : STD_ERROR_HANDLE);
        }
    }
    if (request->modes[2] == NUPP_MODE_STDOUT) {
        /* Both of the child's streams land in one pipe with one reader, or in
         * whatever destination stdout already had. */
        childEnds[2] = childEnds[1];
        merged = request->modes[1] == NUPP_MODE_PIPE;
    }

    for (at = 0; at < 3; at++) {
        if (childEnds[at] != INVALID_HANDLE_VALUE && childEnds[at] != NULL) {
            size_t scan;
            bool already = false;
            for (scan = 0; scan < inheritedCount; scan++) {
                if (inherited[scan] == childEnds[at]) {
                    already = true;
                    break;
                }
            }
            if (!already) {
                inherited[inheritedCount++] = childEnds[at];
            }
        }
    }

    for (at = 0; request->argv[at] != NULL; at++) {
        if (at != 0) {
            nupp_buffer_push(&command, ' ');
        }
        quote_argument(&command, request->argv[at]);
    }
    nupp_buffer_push(&command, 0);
    if (command.failed) {
        nupp_fail("out of memory");
        goto fail;
    }
    if (!widen(&wideCommand, (const char *)command.data)) {
        goto fail;
    }
    if (request->cwd != NULL) {
        if (!widen(&wideCwd, request->cwd)) {
            goto fail;
        }
        haveCwd = true;
    }
    environment = build_environment(request);
    if (environment == NULL) {
        goto fail;
    }

    /* Naming the handles the child may inherit, rather than letting it inherit
     * every inheritable handle this process happens to hold. That is what
     * close-on-exec buys on POSIX, and without it a concurrent spawn's pipe ends
     * travel into this child and hold them open against a reader waiting for end
     * of stream. */
    InitializeProcThreadAttributeList(NULL, 1, 0, &attributeSize);
    attributes = malloc(attributeSize);
    if (attributes == NULL) {
        nupp_fail("out of memory");
        goto fail;
    }
    if (!InitializeProcThreadAttributeList(attributes, 1, 0, &attributeSize)) {
        fail_last("cannot describe the child's handles");
        goto fail;
    }
    if (inheritedCount != 0 && !UpdateProcThreadAttribute(
            attributes, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, inherited,
            inheritedCount * sizeof inherited[0], NULL, NULL)) {
        fail_last("cannot name the child's handles");
        goto fail;
    }

    startup.StartupInfo.cb = sizeof startup;
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startup.StartupInfo.hStdInput = childEnds[0];
    startup.StartupInfo.hStdOutput = childEnds[1];
    startup.StartupInfo.hStdError = childEnds[2];
    startup.lpAttributeList = attributes;

    if (!CreateProcessW(
            NULL, wideCommand.value, NULL, NULL, TRUE,
            EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
            environment, haveCwd ? wideCwd.value : NULL,
            &startup.StartupInfo, &information)) {
        fail_last(request->argv[0]);
        goto fail;
    }

    DeleteProcThreadAttributeList(attributes);
    free(attributes);
    free(environment);
    nupp_buffer_free(&command);
    wide_free(&wideCommand);
    wide_free(&wideCwd);
    CloseHandle(information.hThread);

    for (which = 0; which < 3; which++) {
        if (request->modes[which] == NUPP_MODE_PIPE
            && !(which == 2 && request->modes[2] == NUPP_MODE_STDOUT)) {
            CloseHandle(childEnds[which]);
        }
    }
    if (devNull != INVALID_HANDLE_VALUE) {
        CloseHandle(devNull);
    }

    result->child = (uintptr_t)information.hProcess;
    result->id = information.dwProcessId;
    result->merged = merged;
    for (which = 0; which < 3; which++) {
        if (parentEnds[which] != INVALID_HANDLE_VALUE) {
            result->ends[which] = wrap_handle(parentEnds[which], which != 0);
            if (result->ends[which] == NULL) {
                return false;
            }
        }
    }
    return true;

fail:
    if (attributes != NULL) {
        DeleteProcThreadAttributeList(attributes);
        free(attributes);
    }
    free(environment);
    nupp_buffer_free(&command);
    wide_free(&wideCommand);
    wide_free(&wideCwd);
    for (which = 0; which < 3; which++) {
        if (parentEnds[which] != INVALID_HANDLE_VALUE) {
            CloseHandle(parentEnds[which]);
        }
        if (request->modes[which] == NUPP_MODE_PIPE
            && childEnds[which] != INVALID_HANDLE_VALUE
            && !(which == 2 && request->modes[2] == NUPP_MODE_STDOUT)) {
            CloseHandle(childEnds[which]);
        }
    }
    if (devNull != INVALID_HANDLE_VALUE) {
        CloseHandle(devNull);
    }
    return false;
}

bool nupp_child_kill(const NuppSpawnResult *child, bool force) {
    /* Windows has no polite request to end, so both forms are the same act. A
     * child that has already ended is not a failure: what was asked for has
     * happened. */
    (void)force;
    if (TerminateProcess((HANDLE)child->child, 1)) {
        return true;
    }
    if (GetLastError() == ERROR_ACCESS_DENIED) {
        DWORD code = 0;
        if (GetExitCodeProcess((HANDLE)child->child, &code) && code != STILL_ACTIVE) {
            return true;
        }
    }
    return fail_last("cannot signal the child");
}

int nupp_child_poll(NuppSpawnResult *child, int32_t *code, bool *killed) {
    DWORD status = 0;
    DWORD waited = WaitForSingleObject((HANDLE)child->child, 0);
    if (waited == WAIT_TIMEOUT) {
        return 0;
    }
    if (waited != WAIT_OBJECT_0) {
        fail_last("cannot ask after the child");
        return -1;
    }
    if (!GetExitCodeProcess((HANDLE)child->child, &status)) {
        fail_last("cannot read the child's exit");
        return -1;
    }
    /* There is no signal here, so nothing was killed in the sense the ABI means
     * -- a terminated child reports the code the terminator gave it. */
    *code = (int32_t)status;
    *killed = false;
    return 1;
}

void nupp_child_release(NuppSpawnResult *child) {
    if (child->child != 0) {
        CloseHandle((HANDLE)child->child);
        child->child = 0;
    }
}

int nupp_pipe_wait(
    NuppPipeEnd *const *readable, size_t readableCount,
    NuppPipeEnd *const *writable, size_t writableCount,
    int32_t timeoutMs
) {
    HANDLE events[MAXIMUM_WAIT_OBJECTS];
    DWORD count = 0;
    size_t at;
    DWORD waited;
    int ready = 0;

    for (at = 0; at < readableCount && count < MAXIMUM_WAIT_OBJECTS; at++) {
        NuppPipeEnd *end = readable[at];
        if (end == NULL || end->closed) {
            continue;
        }
        settle(end, false);
        /* Bytes already in hand, or a pipe that has ended, are ready now. */
        if (end->available > end->consumed || end->broken) {
            ready++;
            continue;
        }
        if (!begin_read(end)) {
            continue;
        }
        if (!end->pending) {
            ready++;
            continue;
        }
        events[count++] = end->event;
    }
    for (at = 0; at < writableCount && count < MAXIMUM_WAIT_OBJECTS; at++) {
        NuppPipeEnd *end = writable[at];
        if (end == NULL || end->closed) {
            continue;
        }
        settle(end, false);
        /* An end with no write in flight can take bytes this instant. */
        if (!end->pending || end->broken) {
            ready++;
            continue;
        }
        events[count++] = end->event;
    }
    if (ready > 0) {
        return ready;
    }
    if (count == 0) {
        /* Nothing to watch, so this is a bounded sleep and nothing else, which
         * is what waiting on the child alone amounts to. */
        Sleep(timeoutMs < 0 ? 0 : (DWORD)timeoutMs);
        return 0;
    }
    waited = WaitForMultipleObjects(count, events, FALSE, timeoutMs < 0 ? 0 : (DWORD)timeoutMs);
    if (waited == WAIT_TIMEOUT) {
        return 0;
    }
    if (waited >= WAIT_OBJECT_0 && waited < WAIT_OBJECT_0 + count) {
        return 1;
    }
    fail_last("cannot wait for the child's streams");
    return -1;
}

#endif /* NUPP_WINDOWS */
