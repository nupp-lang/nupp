/* Filesystem globbing through SDL.
 *
 * SDL owns directory traversal and the ordinary `*`/`?` matcher. Nupp keeps
 * one extension that its own builds rely on: a `**` path component crosses
 * directory boundaries. For those patterns SDL enumerates the tree and this
 * file applies a small component matcher to the relative names it returns.
 */

#include "nupp_native.h"

#include <SDL3/SDL.h>

#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
#else
#include <sys/stat.h>
#endif

static bool path_is_link(const char *path) {
#if defined(_WIN32)
    DWORD attributes;
    int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
    wchar_t *wide;
    if (count <= 0) {
        return false;
    }
    wide = malloc((size_t)count * sizeof *wide);
    if (wide == NULL) {
        return false;
    }
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide, count) <= 0) {
        free(wide);
        return false;
    }
    attributes = GetFileAttributesW(wide);
    free(wide);
    return attributes != INVALID_FILE_ATTRIBUTES
        && (attributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
#else
    struct stat info;
    return lstat(path, &info) == 0 && S_ISLNK(info.st_mode);
#endif
}

/* SDL_GlobDirectory follows directory links during a recursive walk. Reject a
 * result as soon as one discovered path component is a link: this preserves a
 * literal symlink prefix while preventing cycles and duplicate aliases below
 * the wildcard root. */
static bool has_linked_prefix(const char *base, const char *relative) {
    size_t base_length = strlen(base);
    size_t relative_length = strlen(relative);
    char *joined = malloc(base_length + relative_length + 2);
    char *component;
    char *slash;
    bool linked = false;
    if (joined == NULL) {
        return false;
    }
    memcpy(joined, base, base_length);
    joined[base_length] = '/';
    memcpy(joined + base_length + 1, relative, relative_length + 1);
    component = joined + base_length + 1;
    while ((slash = strchr(component, '/')) != NULL) {
        *slash = 0;
        if (path_is_link(joined)) {
            linked = true;
            break;
        }
        *slash = '/';
        component = slash + 1;
    }
    free(joined);
    return linked;
}

static bool matches_component(
    const char *pattern, size_t pattern_length, const char *name, size_t name_length
) {
    size_t pattern_at = 0;
    size_t name_at = 0;
    size_t star_at = SIZE_MAX;
    size_t star_name = 0;

    while (name_at < name_length) {
        if (pattern_at < pattern_length) {
            char token = pattern[pattern_at];
            if (token == '*') {
                star_at = pattern_at++;
                star_name = name_at;
                continue;
            }
            if (token == '?' || token == name[name_at]) {
                pattern_at++;
                name_at++;
                continue;
            }
        }
        if (star_at == SIZE_MAX) {
            return false;
        }
        pattern_at = star_at + 1;
        name_at = ++star_name;
    }
    while (pattern_at < pattern_length && pattern[pattern_at] == '*') {
        pattern_at++;
    }
    return pattern_at == pattern_length;
}

static const char *separator(const char *text) {
    return strchr(text, '/');
}

/* A whole `**` component consumes zero or more path components. Pattern and
 * path are relative names using SDL's `/` separator. */
static bool matches_path(const char *pattern, const char *path) {
    const char *pattern_slash = separator(pattern);
    const char *path_slash = separator(path);
    size_t pattern_length = pattern_slash != NULL
        ? (size_t)(pattern_slash - pattern) : strlen(pattern);
    size_t path_length = path_slash != NULL ? (size_t)(path_slash - path) : strlen(path);

    if (pattern_length == 2 && pattern[0] == '*' && pattern[1] == '*') {
        const char *rest = pattern_slash != NULL ? pattern_slash + 1 : NULL;
        if (rest == NULL || matches_path(rest, path)) {
            return true;
        }
        return path_slash != NULL && matches_path(pattern, path_slash + 1);
    }
    if (!matches_component(pattern, pattern_length, path, path_length)) {
        return false;
    }
    if (pattern_slash == NULL || path_slash == NULL) {
        return pattern_slash == NULL && path_slash == NULL;
    }
    return matches_path(pattern_slash + 1, path_slash + 1);
}

static bool check_pattern(const char *pattern, size_t length, bool *recursive) {
    size_t component = 0;
    size_t at;

    *recursive = false;
    if (length == 0) {
        nupp_fail("the pattern names no path");
        return false;
    }
    for (at = 0; at <= length; at++) {
        if (at == length || pattern[at] == '/') {
            size_t index;
            size_t component_length = at - component;
            for (index = component; index + 1 < at; index++) {
                if (pattern[index] == '*' && pattern[index + 1] == '*') {
                    if (component_length != 2) {
                        nupp_fail("a recursive wildcard must be a whole path component");
                        return false;
                    }
                    *recursive = true;
                    break;
                }
            }
            component = at + 1;
        }
    }
    return true;
}

static int compare_matches(const void *left, const void *right) {
    return strcmp(*(const char *const *)left, *(const char *const *)right);
}

static NuppBytes *empty_answer(void) {
    return nupp_bytes_copy(NULL, 0);
}

/* Expands a filesystem glob into a NUL-separated, sorted list of paths. */
NUPP_EXPORT NuppBytes *nuppFilesGlob(const uint8_t *data, size_t length) {
    NuppText text;
    SDL_PathInfo info;
    NuppBuffer out;
    char **matches = NULL;
    char *base = NULL;
    const char *relative;
    const char *wildcard;
    const char *slash;
    size_t prefix_length;
    int count = 0;
    int at;
    bool recursive;
    NuppBytes *answer = NULL;

    if (!nupp_text(&text, data, length, "glob pattern")) {
        return NULL;
    }
    if (!check_pattern(text.value, text.length, &recursive)) {
        nupp_text_free(&text);
        return NULL;
    }

    wildcard = strpbrk(text.value, "*?");
    if (wildcard == NULL) {
        answer = SDL_GetPathInfo(text.value, &info)
            ? nupp_bytes_copy((const uint8_t *)text.value, text.length)
            : empty_answer();
        nupp_text_free(&text);
        return answer;
    }

    slash = wildcard;
    while (slash != text.value && slash[-1] != '/') {
        slash--;
    }
    if (slash == text.value) {
        base = SDL_strdup(".");
        relative = text.value;
        prefix_length = 0;
    } else if (slash == text.value + 1 && text.value[0] == '/') {
        base = SDL_strdup("/");
        relative = slash;
        prefix_length = 1;
    } else {
        prefix_length = (size_t)(slash - text.value - 1);
        base = SDL_strndup(text.value, prefix_length);
        relative = slash;
    }
    if (base == NULL) {
        nupp_fail("out of memory");
        goto done;
    }

    /* A missing literal prefix is an empty match, as it was in the old walk. */
    if (!SDL_GetPathInfo(base, &info) || info.type != SDL_PATHTYPE_DIRECTORY) {
        answer = empty_answer();
        goto done;
    }
    matches = SDL_GlobDirectory(base, recursive ? NULL : relative, 0, &count);
    if (matches == NULL) {
        nupp_fail_format("glob: %s", SDL_GetError());
        goto done;
    }

    if (recursive) {
        int kept = 0;
        for (at = 0; at < count; at++) {
            if (!has_linked_prefix(base, matches[at]) && matches_path(relative, matches[at])) {
                matches[kept++] = matches[at];
            }
        }
        count = kept;
    }
    qsort(matches, (size_t)count, sizeof *matches, compare_matches);

    nupp_buffer_init(&out);
    for (at = 0; at < count; at++) {
        if (at != 0) {
            nupp_buffer_push(&out, 0);
        }
        if (prefix_length != 0) {
            nupp_buffer_append(&out, text.value, prefix_length);
            if (text.value[prefix_length - 1] != '/') {
                nupp_buffer_push(&out, '/');
            }
        }
        nupp_buffer_append(&out, matches[at], strlen(matches[at]));
    }
    if (out.failed) {
        nupp_buffer_free(&out);
        nupp_fail("out of memory");
    } else {
        answer = nupp_buffer_finish(&out);
    }

done:
    SDL_free(matches);
    SDL_free(base);
    nupp_text_free(&text);
    return answer;
}
