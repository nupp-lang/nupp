/* Filesystem globbing.
 *
 * A pattern is split on `/` into components and the tree is walked one component
 * at a time, so `*` and `?` never cross a separator by accident: they are matched
 * against one name, and a name has no separator in it. `**` is the exception and
 * says so by being a whole component, which is also the only place it is
 * allowed -- `a**b` reads as two wildcards with nothing between them, and
 * refusing it is better than guessing which one was meant.
 *
 * Matches are sorted before they are answered, so one pattern gives one answer
 * whatever order the platform walked the directories in.
 */

#include "nupp_native.h"

#include <uv.h>

#include <stdlib.h>
#include <string.h>

/* --- matching one name -------------------------------------------------- */

/* Advances past a bracket expression, answering where it ends or NULL when it
 * never does. The first character may be `]`, which is then a literal, because
 * an expression that started by closing itself would be empty. */
static const char *class_end(const char *at, const char *stop) {
    if (at == stop) {
        return NULL;
    }
    if (*at == '!' || *at == '^') {
        at++;
    }
    if (at != stop && *at == ']') {
        at++;
    }
    while (at != stop && *at != ']') {
        at++;
    }
    return at != stop ? at : NULL;
}

/* Whether one bracket expression accepts `candidate`. `at` points just past the
 * `[` and `end` at the closing `]`. */
static bool class_accepts(const char *at, const char *end, char candidate) {
    bool negated = false;
    bool found = false;
    if (at != end && (*at == '!' || *at == '^')) {
        negated = true;
        at++;
    }
    while (at != end) {
        char low = *at++;
        if (at != end && at + 1 != end && *at == '-') {
            char high = at[1];
            at += 2;
            if (candidate >= low && candidate <= high) {
                found = true;
            }
            continue;
        }
        if (candidate == low) {
            found = true;
        }
    }
    return negated ? !found : found;
}

/* One pattern component against one directory entry name.
 *
 * The `*` case backtracks rather than recursing: a component is short, and a
 * loop that remembers where the last star was matches in linear time where the
 * obvious recursion is exponential on a name full of them.
 */
static bool matches_name(const char *pattern, size_t patternLength, const char *name) {
    size_t patternAt = 0;
    size_t nameAt = 0;
    size_t nameLength = strlen(name);
    size_t starAt = (size_t)-1;
    size_t starName = 0;

    while (nameAt < nameLength) {
        if (patternAt < patternLength) {
            char token = pattern[patternAt];
            if (token == '*') {
                starAt = patternAt++;
                starName = nameAt;
                continue;
            }
            if (token == '?') {
                patternAt++;
                nameAt++;
                continue;
            }
            if (token == '[') {
                const char *end = class_end(pattern + patternAt + 1, pattern + patternLength);
                if (end != NULL
                    && class_accepts(pattern + patternAt + 1, end, name[nameAt])) {
                    patternAt = (size_t)(end - pattern) + 1;
                    nameAt++;
                    continue;
                }
                if (end != NULL) {
                    /* The class is well formed and rejected this character, so
                     * the only way on is through an earlier star. */
                    if (starAt == (size_t)-1) {
                        return false;
                    }
                    patternAt = starAt + 1;
                    nameAt = ++starName;
                    continue;
                }
            } else if (token == name[nameAt]) {
                patternAt++;
                nameAt++;
                continue;
            }
        }
        if (starAt == (size_t)-1) {
            return false;
        }
        patternAt = starAt + 1;
        nameAt = ++starName;
    }
    while (patternAt < patternLength && pattern[patternAt] == '*') {
        patternAt++;
    }
    return patternAt == patternLength;
}

static bool has_wildcard(const char *pattern, size_t length) {
    size_t at;
    for (at = 0; at < length; at++) {
        if (pattern[at] == '*' || pattern[at] == '?' || pattern[at] == '[') {
            return true;
        }
    }
    return false;
}

/* --- the walk ----------------------------------------------------------- */

typedef struct {
    const char *pattern;
    size_t *starts;
    size_t *lengths;
    size_t count;

    char **matches;
    size_t matchCount;
    size_t matchCapacity;
    bool failed;
} Walk;

static void collect(Walk *walk, const char *path, size_t length) {
    char *copy;
    if (walk->failed) {
        return;
    }
    if (walk->matchCount == walk->matchCapacity) {
        size_t next = walk->matchCapacity < 16 ? 16 : walk->matchCapacity * 2;
        char **grown = realloc(walk->matches, next * sizeof *grown);
        if (grown == NULL) {
            walk->failed = true;
            return;
        }
        walk->matches = grown;
        walk->matchCapacity = next;
    }
    copy = malloc(length + 1);
    if (copy == NULL) {
        walk->failed = true;
        return;
    }
    memcpy(copy, path, length);
    copy[length] = '\0';
    walk->matches[walk->matchCount++] = copy;
}

static void descend(Walk *walk, NuppBuffer *prefix, size_t component);

/* Appends one name to the accumulated path, walks on, and takes it back off, so
 * one buffer serves the whole traversal rather than one string per node. */
static void with_child(
    Walk *walk, NuppBuffer *prefix, const char *name, size_t nameLength, size_t component
) {
    size_t restore = prefix->length;
    if (prefix->length != 0 && prefix->data[prefix->length - 1] != '/') {
        nupp_buffer_push(prefix, '/');
    }
    nupp_buffer_append(prefix, name, nameLength);
    if (prefix->failed) {
        walk->failed = true;
        return;
    }
    descend(walk, prefix, component);
    prefix->length = restore;
}

/* Where a walk currently is, as a directory the platform will open. An empty
 * prefix is the working directory, which the pattern did not name and the answer
 * must not either. */
static const char *opening(NuppBuffer *prefix) {
    if (prefix->length == 0) {
        return ".";
    }
    prefix->data[prefix->length] = 0;
    return (const char *)prefix->data;
}

/* `**`: this directory, then every directory under it, each visited once. */
static void recurse(Walk *walk, NuppBuffer *prefix, size_t component) {
    uv_fs_t request;
    uv_dirent_t entry;
    descend(walk, prefix, component + 1);
    if (walk->failed) {
        return;
    }
    uv_fs_scandir(NULL, &request, opening(prefix), 0, NULL);
    if (request.result < 0) {
        /* A directory that cannot be listed is not a match and not a failure:
         * the pattern asked what is under it, and the answer is nothing this
         * process can see. */
        uv_fs_req_cleanup(&request);
        return;
    }
    while (uv_fs_scandir_next(&request, &entry) != UV_EOF) {
        const char *name = entry.name;
        if (entry.type != UV_DIRENT_DIR && entry.type != UV_DIRENT_UNKNOWN) {
            continue;
        }
        {
            size_t restore = prefix->length;
            if (prefix->length != 0 && prefix->data[prefix->length - 1] != '/') {
                nupp_buffer_push(prefix, '/');
            }
            nupp_buffer_append(prefix, name, strlen(name));
            if (prefix->failed) {
                walk->failed = true;
                break;
            }
            /* Some filesystems answer a scan without types; asking again keeps
             * `**` from silently skipping their directories. Links are not
             * followed: a walk that followed them could visit forever. */
            if (entry.type == UV_DIRENT_UNKNOWN) {
                uv_fs_t look;
                bool directory;
                uv_fs_lstat(NULL, &look, opening(prefix), NULL);
                directory = look.result >= 0 && S_ISDIR(look.statbuf.st_mode);
                uv_fs_req_cleanup(&look);
                if (!directory) {
                    prefix->length = restore;
                    continue;
                }
            }
            recurse(walk, prefix, component);
            prefix->length = restore;
        }
        if (walk->failed) {
            break;
        }
    }
    uv_fs_req_cleanup(&request);
}

static void descend(Walk *walk, NuppBuffer *prefix, size_t component) {
    const char *text;
    size_t length;

    if (walk->failed) {
        return;
    }
    if (component == walk->count) {
        uv_fs_t request;
        /* The path is a match only if it is there. `**` and a literal component
         * both propose names without having looked. */
        if (prefix->length != 0) {
            uv_fs_lstat(NULL, &request, opening(prefix), NULL);
            if (request.result >= 0) {
                collect(walk, (const char *)prefix->data, prefix->length);
            }
            uv_fs_req_cleanup(&request);
        }
        return;
    }

    text = walk->pattern + walk->starts[component];
    length = walk->lengths[component];

    if (length == 2 && text[0] == '*' && text[1] == '*') {
        recurse(walk, prefix, component);
        return;
    }
    if (!has_wildcard(text, length)) {
        with_child(walk, prefix, text, length, component + 1);
        return;
    }
    {
        uv_fs_t request;
        uv_dirent_t entry;
        uv_fs_scandir(NULL, &request, opening(prefix), 0, NULL);
        if (request.result < 0) {
            uv_fs_req_cleanup(&request);
            return;
        }
        while (uv_fs_scandir_next(&request, &entry) != UV_EOF) {
            if (!matches_name(text, length, entry.name)) {
                continue;
            }
            with_child(walk, prefix, entry.name, strlen(entry.name), component + 1);
            if (walk->failed) {
                break;
            }
        }
        uv_fs_req_cleanup(&request);
    }
}

/* --- entry -------------------------------------------------------------- */

static int compare_matches(const void *left, const void *right) {
    return strcmp(*(const char *const *)left, *(const char *const *)right);
}

/* Splits the pattern and rejects the shapes that have no meaning, before a
 * single directory is opened. A malformed pattern is a failed query rather than
 * an empty answer: nothing matched is a fact about the tree, and this is a fact
 * about the pattern. */
static bool remember(Walk *walk, size_t *capacity, size_t start, size_t length) {
    if (walk->count == *capacity) {
        size_t next = *capacity * 2;
        size_t *starts = realloc(walk->starts, next * sizeof *starts);
        size_t *lengths;
        if (starts == NULL) {
            nupp_fail("out of memory");
            return false;
        }
        walk->starts = starts;
        lengths = realloc(walk->lengths, next * sizeof *lengths);
        if (lengths == NULL) {
            nupp_fail("out of memory");
            return false;
        }
        walk->lengths = lengths;
        *capacity = next;
    }
    walk->starts[walk->count] = start;
    walk->lengths[walk->count] = length;
    walk->count++;
    return true;
}

/* Every bracket expression closes, and a recursive wildcard is the whole
 * component. `a**b` reads as two wildcards with nothing between them, which is
 * why it is refused rather than guessed at. */
static bool check_component(const char *pattern, size_t start, size_t length) {
    const char *at = pattern + start;
    const char *stop = at + length;
    while (at != stop) {
        if (*at == '[') {
            const char *end = class_end(at + 1, stop);
            if (end == NULL) {
                nupp_fail("the pattern has an unclosed [");
                return false;
            }
            at = end + 1;
            continue;
        }
        if (*at == '*' && at + 1 != stop && at[1] == '*' && length != 2) {
            nupp_fail("a recursive wildcard must be a whole path component");
            return false;
        }
        at++;
    }
    return true;
}

static bool split(Walk *walk, const char *pattern, size_t length) {
    size_t capacity = 8;
    size_t at = 0;
    walk->pattern = pattern;
    walk->count = 0;
    walk->starts = malloc(capacity * sizeof *walk->starts);
    walk->lengths = malloc(capacity * sizeof *walk->lengths);
    if (walk->starts == NULL || walk->lengths == NULL) {
        nupp_fail("out of memory");
        return false;
    }
    /* A leading separator is the root, kept as an empty component because
     * dropping it would move the walk to wherever the process happens to be. */
    if (length != 0 && pattern[0] == '/') {
        if (!remember(walk, &capacity, 0, 0)) {
            return false;
        }
        at = 1;
    }
    while (at < length) {
        size_t start = at;
        while (at < length && pattern[at] != '/') {
            at++;
        }
        /* A repeated or trailing separator describes the path without it. */
        if (at != start) {
            if (!check_component(pattern, start, at - start)
                || !remember(walk, &capacity, start, at - start)) {
                return false;
            }
        }
        if (at != length) {
            at++;
        }
    }
    if (walk->count == 0) {
        nupp_fail("the pattern names no path");
        return false;
    }
    return true;
}

/* Expands a filesystem glob into a NUL-separated, sorted list of paths. */
NUPP_EXPORT NuppBytes *nuppFilesGlob(const uint8_t *data, size_t length) {
    NuppText pattern;
    Walk walk;
    NuppBuffer prefix;
    NuppBuffer out;
    NuppBytes *answer = NULL;
    size_t at;

    if (!nupp_text(&pattern, data, length, "glob pattern")) {
        return NULL;
    }

    memset(&walk, 0, sizeof walk);
    if (!split(&walk, pattern.value, pattern.length)) {
        free(walk.starts);
        free(walk.lengths);
        nupp_text_free(&pattern);
        return NULL;
    }

    nupp_buffer_init(&prefix);
    /* A leading empty component is the root: the walk starts at `/` and the
     * component itself contributes nothing more. */
    if (walk.count > 0 && walk.lengths[0] == 0) {
        nupp_buffer_push(&prefix, '/');
        descend(&walk, &prefix, 1);
    } else {
        descend(&walk, &prefix, 0);
    }
    nupp_buffer_free(&prefix);

    if (!walk.failed) {
        size_t kept = 0;
        qsort(walk.matches, walk.matchCount, sizeof *walk.matches, compare_matches);
        nupp_buffer_init(&out);
        for (at = 0; at < walk.matchCount; at++) {
            /* A path reachable through more than one assignment of `**`
             * components arrives once per route; the answer is a set. */
            if (at != 0 && strcmp(walk.matches[at], walk.matches[at - 1]) == 0) {
                continue;
            }
            if (kept != 0) {
                nupp_buffer_push(&out, 0);
            }
            nupp_buffer_append(&out, walk.matches[at], strlen(walk.matches[at]));
            kept++;
        }
        if (out.failed) {
            nupp_buffer_free(&out);
            nupp_fail("out of memory");
        } else {
            answer = nupp_buffer_finish(&out);
        }
    } else {
        nupp_fail("out of memory");
    }

    for (at = 0; at < walk.matchCount; at++) {
        free(walk.matches[at]);
    }
    free(walk.matches);
    free(walk.starts);
    free(walk.lengths);
    nupp_text_free(&pattern);
    return answer;
}
