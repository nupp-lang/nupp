/* Path text.
 *
 * Every operation here is a rule about characters, not a question for the
 * filesystem -- the two exceptions, resolving a relative path against the
 * working directory and canonicalising one, say so by calling into the platform.
 *
 * A path is read as a sequence of components: an optional prefix, an optional
 * root, and then the names between separators, with `.` dropped and `..` kept.
 * Everything below is written against that view, because the alternative is
 * string arithmetic that is wrong for one path in ten.
 *
 * POSIX has one separator and no prefix. Windows has two separators and three
 * prefixes that matter: a drive, a UNC share, and the verbatim form. A verbatim
 * path is carried and rebuilt but not otherwise reasoned about, since its whole
 * point is that the system does not normalise it either.
 */

#include "platform.h"

#include <stdlib.h>
#include <string.h>

#if NUPP_WINDOWS
#   define PRIMARY_SEPARATOR '\\'
#else
#   define PRIMARY_SEPARATOR '/'
#endif

static bool is_separator(char value) {
#if NUPP_WINDOWS
    return value == '/' || value == '\\';
#else
    return value == '/';
#endif
}

/* --- components --------------------------------------------------------- */

typedef enum {
    COMPONENT_PREFIX,
    COMPONENT_ROOT,
    COMPONENT_PARENT,
    COMPONENT_NORMAL
} ComponentKind;

typedef struct {
    const char *text;
    size_t length;
    ComponentKind kind;
} Component;

typedef struct {
    Component *items;
    size_t count;
    size_t capacity;
    bool failed;
} Components;

static void components_init(Components *list) {
    list->items = NULL;
    list->count = 0;
    list->capacity = 0;
    list->failed = false;
}

static void components_free(Components *list) {
    free(list->items);
    components_init(list);
}

static void components_push(Components *list, const char *text, size_t length, ComponentKind kind) {
    if (list->failed) {
        return;
    }
    if (list->count == list->capacity) {
        size_t next = list->capacity < 8 ? 8 : list->capacity * 2;
        Component *grown = realloc(list->items, next * sizeof *grown);
        if (grown == NULL) {
            list->failed = true;
            return;
        }
        list->items = grown;
        list->capacity = next;
    }
    list->items[list->count].text = text;
    list->items[list->count].length = length;
    list->items[list->count].kind = kind;
    list->count++;
}

/* How many leading characters of `path` are its prefix. Zero on POSIX, and on
 * Windows the drive, the share, or the verbatim marker. */
static size_t prefix_length(const char *path, size_t length) {
#if NUPP_WINDOWS
    if (length >= 2 && path[1] == ':'
        && ((path[0] >= 'A' && path[0] <= 'Z') || (path[0] >= 'a' && path[0] <= 'z'))) {
        return 2;
    }
    if (length >= 2 && is_separator(path[0]) && is_separator(path[1])) {
        /* `\\?\` and `\\.\` reach as far as the next separator; a share reaches
         * past the server and the share name both. */
        size_t at = 2;
        int parts = (length >= 4 && (path[2] == '?' || path[2] == '.')
            && is_separator(path[3])) ? 1 : 2;
        int seen = 0;
        while (seen < parts) {
            while (at < length && !is_separator(path[at])) {
                at++;
            }
            seen++;
            if (seen < parts) {
                while (at < length && is_separator(path[at])) {
                    at++;
                }
                if (at == length) {
                    break;
                }
            }
        }
        return at;
    }
    return 0;
#else
    (void)path;
    (void)length;
    return 0;
#endif
}

/* Reads a path into components. `.` is dropped, `..` is kept, and repeated
 * separators collapse -- which is what makes every operation below able to work
 * on the list rather than on the spelling. */
static void parse(Components *list, const char *path, size_t length) {
    size_t at = prefix_length(path, length);
    components_init(list);
    if (at != 0) {
        components_push(list, path, at, COMPONENT_PREFIX);
    }
    if (at < length && is_separator(path[at])) {
        components_push(list, path + at, 1, COMPONENT_ROOT);
        while (at < length && is_separator(path[at])) {
            at++;
        }
    }
    while (at < length) {
        size_t start = at;
        while (at < length && !is_separator(path[at])) {
            at++;
        }
        if (at != start) {
            size_t width = at - start;
            if (width == 1 && path[start] == '.') {
                /* Dropped, as the component view drops it everywhere. */
            } else if (width == 2 && path[start] == '.' && path[start + 1] == '.') {
                components_push(list, path + start, 2, COMPONENT_PARENT);
            } else {
                components_push(list, path + start, width, COMPONENT_NORMAL);
            }
        }
        while (at < length && is_separator(path[at])) {
            at++;
        }
    }
}

/* Writes components back out. The root carries its own separator, so a name
 * after it is not given a second one. */
static void render(NuppBuffer *into, const Component *items, size_t count) {
    size_t at;
    bool needsSeparator = false;
    for (at = 0; at < count; at++) {
        switch (items[at].kind) {
            case COMPONENT_PREFIX:
                nupp_buffer_append(into, items[at].text, items[at].length);
                needsSeparator = false;
                break;
            case COMPONENT_ROOT:
                nupp_buffer_push(into, PRIMARY_SEPARATOR);
                needsSeparator = false;
                break;
            default:
                if (needsSeparator) {
                    nupp_buffer_push(into, PRIMARY_SEPARATOR);
                }
                nupp_buffer_append(into, items[at].text, items[at].length);
                needsSeparator = true;
                break;
        }
    }
}

static bool components_absolute(const Components *list) {
#if NUPP_WINDOWS
    /* A drive without a root -- `C:file` -- names a directory the process keeps
     * per drive, so it is relative however much it looks otherwise. */
    bool prefix = list->count > 0 && list->items[0].kind == COMPONENT_PREFIX;
    bool root = list->count > (prefix ? 1u : 0u)
        && list->items[prefix ? 1 : 0].kind == COMPONENT_ROOT;
    if (prefix && list->items[0].length >= 2 && list->items[0].text[1] == ':') {
        return root;
    }
    return prefix || root;
#else
    return list->count > 0 && list->items[0].kind == COMPONENT_ROOT;
#endif
}

/* --- answering ---------------------------------------------------------- */

/* One path out, with separators as `/` whatever this platform writes them as. */
static NuppBytes *answer(NuppBuffer *buffer) {
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

static NuppBytes *answer_components(const Component *items, size_t count) {
    NuppBuffer out;
    nupp_buffer_init(&out);
    render(&out, items, count);
    return answer(&out);
}

static NuppBytes *answer_text(const char *text, size_t length) {
    NuppBuffer out;
    nupp_buffer_init(&out);
    nupp_buffer_append(&out, text, length);
    return answer(&out);
}

/* --- joining ------------------------------------------------------------ */

/* What the binding passes an array of. */
typedef struct {
    const uint8_t *data;
    size_t length;
} NuppStringView;

/* Appends one part, replacing what came before when the part says so: an
 * absolute part names a place of its own, and on Windows a part with a prefix
 * does too, while a rooted part without one keeps the prefix and nothing else. */
static void push_part(NuppBuffer *into, const char *part, size_t length) {
    Components parsed;
    bool rooted;
    parse(&parsed, part, length);
    rooted = parsed.count > 0
        && (parsed.items[0].kind == COMPONENT_ROOT
            || parsed.items[0].kind == COMPONENT_PREFIX);
    if (rooted) {
        Components current;
        size_t keep = 0;
        parse(&current, (const char *)into->data, into->length);
        if (parsed.items[0].kind == COMPONENT_ROOT && current.count > 0
            && current.items[0].kind == COMPONENT_PREFIX) {
            keep = 1;
        }
        into->length = 0;
        if (keep != 0) {
            render(into, current.items, keep);
        }
        components_free(&current);
    } else if (into->length != 0 && !is_separator((char)into->data[into->length - 1])) {
        nupp_buffer_push(into, PRIMARY_SEPARATOR);
    }
    /* The part is appended as it was written, not as it parsed: pushing keeps a
     * trailing separator or a `.` the caller put there, and normalising is a
     * separate request. */
    nupp_buffer_append(into, part, length);
    if (parsed.failed) {
        into->failed = true;
    }
    components_free(&parsed);
}

NUPP_EXPORT NuppBytes *nuppcPathJoin(const NuppStringView *parts, size_t count) {
    NuppBuffer out;
    size_t at;
    if (parts == NULL && count != 0) {
        nupp_fail("path parts are null");
        return NULL;
    }
    nupp_buffer_init(&out);
    for (at = 0; at < count; at++) {
        NuppText part;
        if (!nupp_text(&part, parts[at].data, parts[at].length, "path")) {
            nupp_buffer_free(&out);
            return NULL;
        }
        push_part(&out, part.value, part.length);
        nupp_text_free(&part);
        if (out.failed) {
            nupp_buffer_free(&out);
            nupp_fail("out of memory");
            return NULL;
        }
    }
    return answer(&out);
}

/* --- normalising -------------------------------------------------------- */

/* Resolves what can be resolved without asking the filesystem: `.` is already
 * gone, and each `..` cancels the name before it. One at the root has nothing to
 * cancel and disappears; one with no name before it is kept, because a relative
 * path that starts by going up has nowhere to put the answer. */
static void clean(Components *out, const Components *in) {
    size_t at;
    components_init(out);
    for (at = 0; at < in->count; at++) {
        const Component *component = &in->items[at];
        if (component->kind == COMPONENT_PARENT && out->count > 0) {
            ComponentKind last = out->items[out->count - 1].kind;
            if (last == COMPONENT_NORMAL) {
                out->count--;
                continue;
            }
            if (last == COMPONENT_ROOT) {
                continue;
            }
        }
        components_push(out, component->text, component->length, component->kind);
    }
}

NUPP_EXPORT NuppBytes *nuppcPathNormalize(const uint8_t *data, size_t length) {
    NuppText path;
    Components parsed, cleaned;
    NuppBytes *bytes;
    if (!nupp_text(&path, data, length, "path")) {
        return NULL;
    }
    parse(&parsed, path.value, path.length);
    clean(&cleaned, &parsed);
    if (parsed.failed || cleaned.failed) {
        components_free(&parsed);
        components_free(&cleaned);
        nupp_text_free(&path);
        nupp_fail("out of memory");
        return NULL;
    }
    /* Nothing left means the path described where it already was. */
    bytes = cleaned.count == 0
        ? answer_text(".", 1)
        : answer_components(cleaned.items, cleaned.count);
    components_free(&parsed);
    components_free(&cleaned);
    nupp_text_free(&path);
    return bytes;
}

/* --- resolving ---------------------------------------------------------- */

/* Joins with the working directory when the path is relative, then removes `.`
 * and repeated separators. `..` is left alone: resolving it needs to know what
 * the names before it are, and a name can be a symbolic link pointing somewhere
 * a lexical answer would get wrong. */
NUPP_EXPORT NuppBytes *nuppcPathAbsolute(const uint8_t *data, size_t length) {
    NuppText path;
    NuppBuffer joined;
    Components parsed;
    NuppBytes *bytes;

    if (!nupp_text(&path, data, length, "path")) {
        return NULL;
    }
    if (path.length == 0) {
        nupp_text_free(&path);
        nupp_fail("cannot make an empty path absolute");
        return NULL;
    }
    nupp_buffer_init(&joined);
    parse(&parsed, path.value, path.length);
    if (!components_absolute(&parsed)) {
        components_free(&parsed);
        if (!nupp_fs_current_directory(&joined)) {
            nupp_buffer_free(&joined);
            nupp_text_free(&path);
            return NULL;
        }
        push_part(&joined, path.value, path.length);
        if (joined.failed) {
            nupp_buffer_free(&joined);
            nupp_text_free(&path);
            nupp_fail("out of memory");
            return NULL;
        }
        joined.data[joined.length] = 0;
        parse(&parsed, (const char *)joined.data, joined.length);
    }
    if (parsed.failed) {
        components_free(&parsed);
        nupp_buffer_free(&joined);
        nupp_text_free(&path);
        nupp_fail("out of memory");
        return NULL;
    }
    bytes = answer_components(parsed.items, parsed.count);
    components_free(&parsed);
    nupp_buffer_free(&joined);
    nupp_text_free(&path);
    return bytes;
}

NUPP_EXPORT NuppBytes *nuppcPathCanonicalize(const uint8_t *data, size_t length) {
    NuppText path;
    NuppBuffer out;
    if (!nupp_text(&path, data, length, "path")) {
        return NULL;
    }
    nupp_buffer_init(&out);
    if (!nupp_fs_canonicalize(path.value, &out)) {
        nupp_buffer_free(&out);
        nupp_text_free(&path);
        return NULL;
    }
    nupp_text_free(&path);
    return answer(&out);
}

/* --- relating ----------------------------------------------------------- */

static bool same_component(const Component *left, const Component *right) {
    if (left->kind != right->kind || left->length != right->length) {
        return false;
    }
    return memcmp(left->text, right->text, left->length) == 0;
}

/* The path that leads from `base` to `path`.
 *
 * Both have to be anchored the same way. One absolute and one relative do not
 * share a coordinate system, and the only sound answer is the absolute one when
 * that is the target and nothing at all when it is the base.
 */
NUPP_EXPORT NuppBytes *nuppcPathRelative(
    const uint8_t *data, size_t length, const uint8_t *base, size_t baseLength
) {
    NuppText target, from;
    Components targetParts, baseParts;
    Components out;
    size_t shared = 0;
    NuppBytes *bytes = NULL;

    if (!nupp_text(&target, data, length, "path")) {
        return NULL;
    }
    if (!nupp_text(&from, base, baseLength, "path")) {
        nupp_text_free(&target);
        return NULL;
    }
    parse(&targetParts, target.value, target.length);
    parse(&baseParts, from.value, from.length);
    components_init(&out);

    if (components_absolute(&targetParts) != components_absolute(&baseParts)) {
        if (components_absolute(&targetParts)) {
            bytes = answer_components(targetParts.items, targetParts.count);
        } else {
            nupp_fail("paths do not share a relative coordinate system");
        }
        goto done;
    }

    while (shared < targetParts.count && shared < baseParts.count
        && same_component(&targetParts.items[shared], &baseParts.items[shared])) {
        shared++;
    }
    /* Every base component past the shared prefix is one step back up. A `..`
     * among them cannot be stepped back over, because what it named depends on
     * where the walk started. */
    {
        size_t at;
        for (at = shared; at < baseParts.count; at++) {
            if (baseParts.items[at].kind == COMPONENT_PARENT) {
                nupp_fail("paths do not share a relative coordinate system");
                goto done;
            }
            components_push(&out, "..", 2, COMPONENT_PARENT);
        }
        for (at = shared; at < targetParts.count; at++) {
            components_push(&out, targetParts.items[at].text,
                targetParts.items[at].length, targetParts.items[at].kind);
        }
    }
    if (out.failed) {
        nupp_fail("out of memory");
        goto done;
    }
    bytes = answer_components(out.items, out.count);

done:
    components_free(&targetParts);
    components_free(&baseParts);
    components_free(&out);
    nupp_text_free(&target);
    nupp_text_free(&from);
    return bytes;
}

/* --- parts -------------------------------------------------------------- */

/* Where the path's own text ends once the last component is taken off it.
 *
 * Sliced rather than rebuilt, because asking for a path's parent asks about that
 * path: `alpha/./beta/../file` has parent `alpha/./beta/..`, spelled the way the
 * caller spelled it. Rebuilding would quietly normalise, and normalising is a
 * separate request with its own answer.
 *
 * The trim stops at the root, so the parent of `/foo` is `/` and not the empty
 * path that trimming one more separator would give.
 */
static size_t without_last(const char *path, const Components *list) {
    size_t anchored = 0;
    size_t at;
    if (list->count == 0) {
        return 0;
    }
    for (at = 0; at < list->count; at++) {
        if (list->items[at].kind == COMPONENT_PREFIX
            || list->items[at].kind == COMPONENT_ROOT) {
            anchored = (size_t)(list->items[at].text - path) + list->items[at].length;
        }
    }
    at = (size_t)(list->items[list->count - 1].text - path);
    while (at > anchored && is_separator(path[at - 1])) {
        at--;
    }
    return at;
}

/* The final component, when it is a name. A path ending in a root, a prefix or
 * `..` has no file name: none of those is something a caller could rename. */
static const Component *file_name(const Components *list) {
    if (list->count == 0) {
        return NULL;
    }
    if (list->items[list->count - 1].kind != COMPONENT_NORMAL) {
        return NULL;
    }
    return &list->items[list->count - 1];
}

/* Splits a name at its final dot. A leading dot is not a separator -- `.bashrc`
 * is a name, not an extension -- so a split that would leave nothing before it
 * is no split at all. */
static void split_name(
    const Component *name, const char **stem, size_t *stemLength,
    const char **extension, size_t *extensionLength
) {
    size_t at = name->length;
    *stem = name->text;
    *stemLength = name->length;
    *extension = NULL;
    *extensionLength = 0;
    if (name->length == 2 && name->text[0] == '.' && name->text[1] == '.') {
        return;
    }
    while (at > 0) {
        at--;
        if (name->text[at] == '.') {
            if (at == 0) {
                return;
            }
            *stemLength = at;
            *extension = name->text + at + 1;
            *extensionLength = name->length - at - 1;
            return;
        }
    }
}

NUPP_EXPORT NuppBytes *nuppcPathPart(const uint8_t *data, size_t length, uint32_t kind) {
    NuppText path;
    Components parsed;
    const Component *name;
    NuppBytes *bytes = NULL;

    if (!nupp_text(&path, data, length, "path")) {
        return NULL;
    }
    parse(&parsed, path.value, path.length);
    if (parsed.failed) {
        components_free(&parsed);
        nupp_text_free(&path);
        nupp_fail("out of memory");
        return NULL;
    }

    if (kind == 0) {
        /* A path that is only a root or a prefix has no parent: there is nowhere
         * further up to go. */
        if (parsed.count == 0
            || parsed.items[parsed.count - 1].kind == COMPONENT_ROOT
            || parsed.items[parsed.count - 1].kind == COMPONENT_PREFIX) {
            components_free(&parsed);
            nupp_text_free(&path);
            return NULL;
        }
        bytes = answer_text(path.value, without_last(path.value, &parsed));
        components_free(&parsed);
        nupp_text_free(&path);
        return bytes;
    }

    name = file_name(&parsed);
    if (name != NULL) {
        const char *stem;
        const char *extension;
        size_t stemLength, extensionLength;
        split_name(name, &stem, &stemLength, &extension, &extensionLength);
        if (kind == 1) {
            bytes = answer_text(name->text, name->length);
        } else if (kind == 2) {
            bytes = answer_text(stem, stemLength);
        } else if (extension != NULL) {
            bytes = answer_text(extension, extensionLength);
        }
    }
    components_free(&parsed);
    nupp_text_free(&path);
    return bytes;
}

/* Replaces the final name, or the extension on it. The caller has already held
 * the replacement to one ordinary component, so what is left here is where it
 * goes. */
NUPP_EXPORT NuppBytes *nuppcPathWith(
    const uint8_t *data, size_t length,
    const uint8_t *value, size_t valueLength,
    bool extension
) {
    NuppText path, replacement;
    Components parsed;
    const Component *name;
    NuppBuffer out;

    if (!nupp_text(&path, data, length, "path")) {
        return NULL;
    }
    if (!nupp_text(&replacement, value, valueLength, "path")) {
        nupp_text_free(&path);
        return NULL;
    }
    parse(&parsed, path.value, path.length);
    if (parsed.failed) {
        components_free(&parsed);
        nupp_text_free(&path);
        nupp_text_free(&replacement);
        nupp_fail("out of memory");
        return NULL;
    }
    name = file_name(&parsed);
    nupp_buffer_init(&out);

    if (extension) {
        if (name == NULL) {
            /* Nothing to put an extension on, so the path is its own answer. */
            components_free(&parsed);
            nupp_buffer_free(&out);
            nupp_text_free(&replacement);
            {
                NuppBytes *bytes = answer_text(path.value, path.length);
                nupp_text_free(&path);
                return bytes;
            }
        }
        {
            /* Everything up to the end of the stem, in the caller's own
             * spelling, and then the new extension on the end of it. */
            const char *stem;
            const char *unused;
            size_t stemLength, unusedLength;
            split_name(name, &stem, &stemLength, &unused, &unusedLength);
            nupp_buffer_append(
                &out, path.value, (size_t)(stem - path.value) + stemLength);
            if (replacement.length != 0) {
                nupp_buffer_push(&out, '.');
                nupp_buffer_append(&out, replacement.value, replacement.length);
            }
        }
    } else {
        /* The name is dropped where there is one and kept where there is not,
         * which is what makes `a/b` become `a/c` and `a/..` become `a/../c`. */
        if (name != NULL) {
            nupp_buffer_append(&out, path.value, without_last(path.value, &parsed));
        } else {
            nupp_buffer_append(&out, path.value, path.length);
        }
        if (out.length != 0 && !is_separator((char)out.data[out.length - 1])) {
            nupp_buffer_push(&out, PRIMARY_SEPARATOR);
        }
        nupp_buffer_append(&out, replacement.value, replacement.length);
    }

    components_free(&parsed);
    nupp_text_free(&path);
    nupp_text_free(&replacement);
    return answer(&out);
}

NUPP_EXPORT bool nuppcPathIsAbsolute(const uint8_t *data, size_t length) {
    NuppText path;
    Components parsed;
    bool absolute;
    if (!nupp_text(&path, data, length, "path")) {
        return false;
    }
    parse(&parsed, path.value, path.length);
    absolute = components_absolute(&parsed);
    components_free(&parsed);
    nupp_text_free(&path);
    return absolute;
}
