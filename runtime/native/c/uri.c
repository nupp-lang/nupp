/* URI parsing.
 *
 * A URI is held as one normalised serialisation plus the offsets of its parts,
 * so reading a component is a slice of storage the handle already owns and
 * costs no allocation. That is what lets the binding above take a pointer and a
 * length and keep them until it destroys the handle.
 *
 * Deriving a URI goes the long way round on purpose: the parts are taken apart,
 * the one that changed is replaced, and the result is written out and parsed
 * again. One grammar then decides what is valid, rather than one grammar for
 * text arriving from outside and a second, quietly different one for text the
 * program builds.
 *
 * Two kinds of URI behave differently and the difference is where the `//` is.
 * With an authority, the path is a hierarchy: it always starts at `/`, and `.`
 * and `..` in it mean what they mean in a filesystem. Without one -- `mailto:`,
 * `urn:`, `data:` -- everything after the colon is opaque, and normalising it
 * would change what it names.
 */

#include "nupp_native.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* --- schemes ------------------------------------------------------------ */

/* The schemes with a default port and a mandatory host. Nothing else gets its
 * host lowercased or its empty path filled in, because for any other scheme
 * those are not known to be the same URI. */
static const struct {
    const char *name;
    int port;
} SPECIAL[] = {
    {"http", 80},
    {"https", 443},
    {"ws", 80},
    {"wss", 443},
    {"ftp", 21},
    {"file", -1},
};

static int special_port(const char *scheme, bool *special) {
    size_t at;
    *special = false;
    for (at = 0; at < sizeof SPECIAL / sizeof SPECIAL[0]; at++) {
        if (strcmp(scheme, SPECIAL[at].name) == 0) {
            *special = true;
            return SPECIAL[at].port;
        }
    }
    return -1;
}

static bool is_alpha(char value) {
    return (value >= 'a' && value <= 'z') || (value >= 'A' && value <= 'Z');
}

static bool is_digit(char value) {
    return value >= '0' && value <= '9';
}

static char lowered(char value) {
    return (value >= 'A' && value <= 'Z') ? (char)(value - 'A' + 'a') : value;
}

/* --- the handle --------------------------------------------------------- */

/* One parsed URI: the serialisation, and where each component sits in it.
 *
 * A `Start`/`End` pair with `Start` past `End` never happens; a component that
 * is absent says so with its own flag, because an empty query and no query are
 * different URIs and a pair of offsets cannot tell them apart.
 */
struct NuppUri {
    char *text;
    size_t length;

    size_t schemeEnd;
    bool hasAuthority;
    size_t usernameStart, usernameEnd;
    bool hasPassword;
    size_t passwordStart, passwordEnd;
    size_t hostStart, hostEnd;
    bool hasPort;
    unsigned port;
    size_t authorityStart, authorityEnd;
    size_t pathStart, pathEnd;
    bool hasQuery;
    size_t queryStart, queryEnd;
    bool hasFragment;
    size_t fragmentStart, fragmentEnd;
};

typedef struct NuppUri NuppUri;

/* The same URI taken apart into owned strings, which is what a derivation edits
 * before writing it out again. */
typedef struct {
    char *scheme;
    bool hasAuthority;
    char *username;
    char *password;
    bool hasPassword;
    char *host;
    bool hasPort;
    unsigned port;
    char *path;
    char *query;
    bool hasQuery;
    char *fragment;
    bool hasFragment;
} UriParts;

static char *duplicate(const char *value, size_t length) {
    char *copy = malloc(length + 1);
    if (copy == NULL) {
        return NULL;
    }
    if (length != 0) {
        memcpy(copy, value, length);
    }
    copy[length] = '\0';
    return copy;
}

static void parts_free(UriParts *parts) {
    free(parts->scheme);
    free(parts->username);
    free(parts->password);
    free(parts->host);
    free(parts->path);
    free(parts->query);
    free(parts->fragment);
    memset(parts, 0, sizeof *parts);
}

/* --- percent-encoding --------------------------------------------------- */

/* What has to be escaped where. A `%` is never escaped: text arriving already
 * encoded stays as it was written, which is why `%7e` comes back `%7e` rather
 * than becoming `%257e` or being decoded to `~`.
 */
typedef enum { ESCAPE_PATH, ESCAPE_QUERY, ESCAPE_FRAGMENT, ESCAPE_USERINFO } EscapeSet;

static bool needs_escape(unsigned char value, EscapeSet set) {
    if (value <= 0x20 || value >= 0x7F) {
        return true;
    }
    switch (set) {
        case ESCAPE_PATH:
            return value == '"' || value == '<' || value == '>' || value == '`'
                || value == '?' || value == '#' || value == '{' || value == '}';
        case ESCAPE_QUERY:
            return value == '"' || value == '<' || value == '>' || value == '#';
        case ESCAPE_FRAGMENT:
            return value == '"' || value == '<' || value == '>' || value == '`';
        default:
            return value == '"' || value == '<' || value == '>' || value == '`'
                || value == '#' || value == '?' || value == '{' || value == '}'
                || value == '/' || value == ':' || value == ';' || value == '='
                || value == '@' || value == '[' || value == '\\' || value == ']'
                || value == '^' || value == '|';
    }
}

static void append_escaped(NuppBuffer *into, const char *value, size_t length, EscapeSet set) {
    static const char HEX[] = "0123456789ABCDEF";
    size_t at;
    for (at = 0; at < length; at++) {
        unsigned char byte = (unsigned char)value[at];
        if (needs_escape(byte, set)) {
            nupp_buffer_push(into, '%');
            nupp_buffer_push(into, (uint8_t)HEX[byte >> 4]);
            nupp_buffer_push(into, (uint8_t)HEX[byte & 15]);
        } else {
            nupp_buffer_push(into, byte);
        }
    }
}

/* --- dot segments ------------------------------------------------------- */

/* RFC 3986's remove_dot_segments, which is what makes `/a/../b` and `/b` the
 * same place. Empty segments are not touched: `/a//b` names something with an
 * empty directory in it, and collapsing that would be a different path. */
static bool remove_dot_segments(const char *path, size_t length, NuppBuffer *into) {
    size_t at = 0;
    /* Where each output segment started, so `..` can take the last one back
     * off without re-scanning what has been written. */
    size_t *starts = NULL;
    size_t count = 0, capacity = 0;
    bool absolute = length != 0 && path[0] == '/';

    if (absolute) {
        nupp_buffer_push(into, '/');
        at = 1;
    }
    while (at <= length) {
        size_t start = at;
        size_t width;
        while (at < length && path[at] != '/') {
            at++;
        }
        width = at - start;
        if (width == 1 && path[start] == '.') {
            /* Dropped, but a trailing `.` still leaves the directory it named. */
            if (at == length) {
                if (into->length != 0 && into->data[into->length - 1] != '/') {
                    nupp_buffer_push(into, '/');
                }
            }
            at++;
            continue;
        }
        if (width == 2 && path[start] == '.' && path[start + 1] == '.') {
            if (count != 0) {
                count--;
                into->length = starts[count];
            } else if (!absolute) {
                /* A relative path that starts by going up has nowhere to put
                 * the answer, so the step is kept. */
                if (into->length != 0 && into->data[into->length - 1] != '/') {
                    nupp_buffer_push(into, '/');
                }
                nupp_buffer_append(into, "..", 2);
            }
            if (at == length) {
                if (into->length != 0 && into->data[into->length - 1] != '/') {
                    nupp_buffer_push(into, '/');
                }
            }
            at++;
            continue;
        }
        if (count == capacity) {
            size_t next = capacity < 16 ? 16 : capacity * 2;
            size_t *grown = realloc(starts, next * sizeof *grown);
            if (grown == NULL) {
                free(starts);
                return false;
            }
            starts = grown;
            capacity = next;
        }
        starts[count++] = into->length;
        nupp_buffer_append(into, path + start, width);
        if (at < length) {
            nupp_buffer_push(into, '/');
        }
        at++;
    }
    free(starts);
    return !into->failed;
}

/* --- serialising -------------------------------------------------------- */

/* Writes the parts out as one URI. Nothing here validates: what this produces
 * is parsed straight afterwards, and that is where a derivation finds out it
 * asked for something the grammar cannot express. */
static char *serialize(const UriParts *parts, size_t *length) {
    NuppBuffer out;
    char *text;
    nupp_buffer_init(&out);
    nupp_buffer_append(&out, parts->scheme, strlen(parts->scheme));
    nupp_buffer_push(&out, ':');
    if (parts->hasAuthority) {
        nupp_buffer_append(&out, "//", 2);
        if ((parts->username != NULL && parts->username[0] != '\0') || parts->hasPassword) {
            if (parts->username != NULL) {
                nupp_buffer_append(&out, parts->username, strlen(parts->username));
            }
            if (parts->hasPassword) {
                nupp_buffer_push(&out, ':');
                if (parts->password != NULL) {
                    nupp_buffer_append(&out, parts->password, strlen(parts->password));
                }
            }
            nupp_buffer_push(&out, '@');
        }
        if (parts->host != NULL) {
            nupp_buffer_append(&out, parts->host, strlen(parts->host));
        }
        if (parts->hasPort) {
            char digits[8];
            int written = snprintf(digits, sizeof digits, ":%u", parts->port);
            nupp_buffer_append(&out, digits, (size_t)(written < 0 ? 0 : written));
        }
    }
    if (parts->path != NULL) {
        /* With an authority, the path is a hierarchy rooted at `/`, and a path
         * written without one would run into the host rather than follow it. */
        if (parts->hasAuthority && parts->path[0] != '\0' && parts->path[0] != '/') {
            nupp_buffer_push(&out, '/');
        }
        nupp_buffer_append(&out, parts->path, strlen(parts->path));
    }
    if (parts->hasQuery) {
        nupp_buffer_push(&out, '?');
        if (parts->query != NULL) {
            nupp_buffer_append(&out, parts->query, strlen(parts->query));
        }
    }
    if (parts->hasFragment) {
        nupp_buffer_push(&out, '#');
        if (parts->fragment != NULL) {
            nupp_buffer_append(&out, parts->fragment, strlen(parts->fragment));
        }
    }
    if (out.failed) {
        nupp_buffer_free(&out);
        nupp_fail("out of memory");
        return NULL;
    }
    out.data[out.length] = 0;
    *length = out.length;
    text = (char *)out.data;
    nupp_buffer_init(&out);
    return text;
}

/* --- parsing ------------------------------------------------------------ */

static NuppUri *refused(const char *reason) {
    nupp_fail(reason);
    return NULL;
}

/* Takes ownership of `text` however it ends. */
static NuppUri *parse_owned(char *text, size_t length) {
    NuppUri *uri;
    size_t at = 0;
    size_t schemeEnd;
    bool special;
    int defaultPort;
    UriParts parts;

    memset(&parts, 0, sizeof parts);

    /* A scheme is a letter and then letters, digits and three punctuation
     * marks, and it is what tells a URI from a piece of text that looks like
     * one. Without it there is nothing to resolve against. */
    if (length == 0 || !is_alpha(text[0])) {
        free(text);
        return refused("relative URL without a base");
    }
    while (at < length && (is_alpha(text[at]) || is_digit(text[at])
        || text[at] == '+' || text[at] == '-' || text[at] == '.')) {
        at++;
    }
    if (at == length || text[at] != ':') {
        free(text);
        return refused("relative URL without a base");
    }
    schemeEnd = at;
    parts.scheme = duplicate(text, schemeEnd);
    if (parts.scheme == NULL) {
        free(text);
        return refused("out of memory");
    }
    for (at = 0; at < schemeEnd; at++) {
        parts.scheme[at] = lowered(parts.scheme[at]);
    }
    defaultPort = special_port(parts.scheme, &special);
    at = schemeEnd + 1;

    if (at + 1 < length && text[at] == '/' && text[at + 1] == '/') {
        size_t authorityStart = at + 2;
        size_t authorityEnd = authorityStart;
        size_t userEnd = authorityStart;
        size_t hostStart;
        bool sawUser = false;

        parts.hasAuthority = true;
        while (authorityEnd < length && text[authorityEnd] != '/'
            && text[authorityEnd] != '?' && text[authorityEnd] != '#') {
            authorityEnd++;
        }
        /* The last `@` and not the first: a password may contain one, and the
         * host may not. */
        {
            size_t scan;
            for (scan = authorityStart; scan < authorityEnd; scan++) {
                if (text[scan] == '@') {
                    userEnd = scan;
                    sawUser = true;
                }
            }
        }
        hostStart = sawUser ? userEnd + 1 : authorityStart;
        if (sawUser) {
            size_t colon = authorityStart;
            while (colon < userEnd && text[colon] != ':') {
                colon++;
            }
            parts.username = duplicate(text + authorityStart, colon - authorityStart);
            if (colon < userEnd) {
                parts.hasPassword = true;
                parts.password = duplicate(text + colon + 1, userEnd - colon - 1);
            }
        } else {
            parts.username = duplicate("", 0);
        }

        {
            size_t hostEnd = hostStart;
            size_t portStart = authorityEnd;
            if (hostStart < authorityEnd && text[hostStart] == '[') {
                while (hostEnd < authorityEnd && text[hostEnd] != ']') {
                    hostEnd++;
                }
                if (hostEnd == authorityEnd) {
                    free(text);
                    parts_free(&parts);
                    return refused("invalid IPv6 address");
                }
                hostEnd++;
                portStart = hostEnd;
            } else {
                while (hostEnd < authorityEnd && text[hostEnd] != ':') {
                    hostEnd++;
                }
                portStart = hostEnd;
            }
            if (portStart < authorityEnd) {
                if (text[portStart] != ':') {
                    free(text);
                    parts_free(&parts);
                    return refused("invalid port number");
                }
                {
                    unsigned long value = 0;
                    size_t scan = portStart + 1;
                    if (scan == authorityEnd) {
                        /* `host:` with nothing after it names the default. */
                        parts.hasPort = false;
                    } else {
                        for (; scan < authorityEnd; scan++) {
                            if (!is_digit(text[scan])) {
                                free(text);
                                parts_free(&parts);
                                return refused("invalid port number");
                            }
                            value = value * 10 + (unsigned long)(text[scan] - '0');
                            if (value > 65535) {
                                free(text);
                                parts_free(&parts);
                                return refused("invalid port number");
                            }
                        }
                        parts.hasPort = true;
                        parts.port = (unsigned)value;
                    }
                }
            }
            parts.host = duplicate(text + hostStart, hostEnd - hostStart);
            if (parts.host == NULL) {
                free(text);
                parts_free(&parts);
                return refused("out of memory");
            }
            /* A host is a name, and a name written in another case is the same
             * name -- but only where the scheme says so. */
            if (special) {
                size_t scan;
                for (scan = 0; parts.host[scan] != '\0'; scan++) {
                    parts.host[scan] = lowered(parts.host[scan]);
                }
                if (parts.host[0] == '\0' && strcmp(parts.scheme, "file") != 0) {
                    free(text);
                    parts_free(&parts);
                    return refused("empty host");
                }
            }
            /* A port that is the scheme's own is not part of what the URI
             * names, so two URIs that differ only in writing it are equal. */
            if (parts.hasPort && defaultPort >= 0 && (int)parts.port == defaultPort) {
                parts.hasPort = false;
            }
        }
        at = authorityEnd;
    } else if (special) {
        free(text);
        parts_free(&parts);
        return refused("empty host");
    }

    /* Path, query and fragment, in the order they can appear. */
    {
        size_t pathStart = at;
        size_t pathEnd = at;
        while (pathEnd < length && text[pathEnd] != '?' && text[pathEnd] != '#') {
            pathEnd++;
        }
        if (parts.hasAuthority) {
            NuppBuffer path;
            NuppBuffer cleaned;
            nupp_buffer_init(&path);
            if (pathEnd == pathStart) {
                nupp_buffer_push(&path, '/');
            } else {
                if (text[pathStart] != '/') {
                    nupp_buffer_push(&path, '/');
                }
                nupp_buffer_append(&path, text + pathStart, pathEnd - pathStart);
            }
            nupp_buffer_push(&path, 0);
            if (path.failed) {
                nupp_buffer_free(&path);
                free(text);
                parts_free(&parts);
                return refused("out of memory");
            }
            nupp_buffer_init(&cleaned);
            if (!remove_dot_segments((const char *)path.data, path.length - 1, &cleaned)) {
                nupp_buffer_free(&path);
                nupp_buffer_free(&cleaned);
                free(text);
                parts_free(&parts);
                return refused("out of memory");
            }
            nupp_buffer_free(&path);
            {
                NuppBuffer escaped;
                nupp_buffer_init(&escaped);
                append_escaped(&escaped, (const char *)cleaned.data, cleaned.length, ESCAPE_PATH);
                nupp_buffer_free(&cleaned);
                nupp_buffer_push(&escaped, 0);
                if (escaped.failed) {
                    nupp_buffer_free(&escaped);
                    free(text);
                    parts_free(&parts);
                    return refused("out of memory");
                }
                parts.path = (char *)escaped.data;
                nupp_buffer_init(&escaped);
            }
        } else {
            /* Opaque: what follows the colon names something the scheme
             * understands, and this is not the place to tidy it. */
            NuppBuffer escaped;
            nupp_buffer_init(&escaped);
            append_escaped(&escaped, text + pathStart, pathEnd - pathStart, ESCAPE_PATH);
            nupp_buffer_push(&escaped, 0);
            if (escaped.failed) {
                nupp_buffer_free(&escaped);
                free(text);
                parts_free(&parts);
                return refused("out of memory");
            }
            parts.path = (char *)escaped.data;
            nupp_buffer_init(&escaped);
        }

        at = pathEnd;
        if (at < length && text[at] == '?') {
            size_t queryEnd = at + 1;
            NuppBuffer escaped;
            while (queryEnd < length && text[queryEnd] != '#') {
                queryEnd++;
            }
            nupp_buffer_init(&escaped);
            append_escaped(&escaped, text + at + 1, queryEnd - at - 1, ESCAPE_QUERY);
            nupp_buffer_push(&escaped, 0);
            parts.hasQuery = true;
            parts.query = (char *)escaped.data;
            nupp_buffer_init(&escaped);
            at = queryEnd;
        }
        if (at < length && text[at] == '#') {
            NuppBuffer escaped;
            nupp_buffer_init(&escaped);
            append_escaped(&escaped, text + at + 1, length - at - 1, ESCAPE_FRAGMENT);
            nupp_buffer_push(&escaped, 0);
            parts.hasFragment = true;
            parts.fragment = (char *)escaped.data;
            nupp_buffer_init(&escaped);
        }
    }
    free(text);

    /* Written out and measured, so the handle's offsets describe the
     * normalised text rather than what arrived. */
    {
        size_t serializedLength = 0;
        char *serialized = serialize(&parts, &serializedLength);
        if (serialized == NULL) {
            parts_free(&parts);
            return NULL;
        }
        uri = calloc(1, sizeof *uri);
        if (uri == NULL) {
            free(serialized);
            parts_free(&parts);
            return refused("out of memory");
        }
        uri->text = serialized;
        uri->length = serializedLength;
        uri->schemeEnd = strlen(parts.scheme);
        uri->hasAuthority = parts.hasAuthority;
        {
            size_t cursor = uri->schemeEnd + 1;
            if (parts.hasAuthority) {
                cursor += 2;
                uri->authorityStart = cursor;
                uri->usernameStart = cursor;
                uri->usernameEnd = cursor + (parts.username ? strlen(parts.username) : 0);
                cursor = uri->usernameEnd;
                if (parts.hasPassword) {
                    uri->hasPassword = true;
                    uri->passwordStart = cursor + 1;
                    uri->passwordEnd =
                        uri->passwordStart + (parts.password ? strlen(parts.password) : 0);
                    cursor = uri->passwordEnd;
                }
                if ((parts.username != NULL && parts.username[0] != '\0') || parts.hasPassword) {
                    cursor += 1; /* the `@` */
                } else {
                    uri->usernameStart = cursor;
                    uri->usernameEnd = cursor;
                }
                uri->hostStart = cursor;
                uri->hostEnd = cursor + (parts.host ? strlen(parts.host) : 0);
                cursor = uri->hostEnd;
                if (parts.hasPort) {
                    uri->hasPort = true;
                    uri->port = parts.port;
                    while (cursor < serializedLength && serialized[cursor] != '/'
                        && serialized[cursor] != '?' && serialized[cursor] != '#') {
                        cursor++;
                    }
                }
                uri->authorityEnd = cursor;
            }
            uri->pathStart = cursor;
            uri->pathEnd = cursor + (parts.path ? strlen(parts.path) : 0);
            cursor = uri->pathEnd;
            if (parts.hasQuery) {
                uri->hasQuery = true;
                uri->queryStart = cursor + 1;
                uri->queryEnd = uri->queryStart + (parts.query ? strlen(parts.query) : 0);
                cursor = uri->queryEnd;
            }
            if (parts.hasFragment) {
                uri->hasFragment = true;
                uri->fragmentStart = cursor + 1;
                uri->fragmentEnd =
                    uri->fragmentStart + (parts.fragment ? strlen(parts.fragment) : 0);
            }
        }
        parts_free(&parts);
    }
    return uri;
}

/* Takes the handle apart into owned strings a derivation can edit. */
static bool decompose(const NuppUri *uri, UriParts *parts) {
    memset(parts, 0, sizeof *parts);
    parts->scheme = duplicate(uri->text, uri->schemeEnd);
    parts->hasAuthority = uri->hasAuthority;
    if (uri->hasAuthority) {
        parts->username = duplicate(
            uri->text + uri->usernameStart, uri->usernameEnd - uri->usernameStart);
        if (uri->hasPassword) {
            parts->hasPassword = true;
            parts->password = duplicate(
                uri->text + uri->passwordStart, uri->passwordEnd - uri->passwordStart);
        }
        parts->host = duplicate(uri->text + uri->hostStart, uri->hostEnd - uri->hostStart);
        parts->hasPort = uri->hasPort;
        parts->port = uri->port;
    }
    parts->path = duplicate(uri->text + uri->pathStart, uri->pathEnd - uri->pathStart);
    if (uri->hasQuery) {
        parts->hasQuery = true;
        parts->query = duplicate(uri->text + uri->queryStart, uri->queryEnd - uri->queryStart);
    }
    if (uri->hasFragment) {
        parts->hasFragment = true;
        parts->fragment = duplicate(
            uri->text + uri->fragmentStart, uri->fragmentEnd - uri->fragmentStart);
    }
    if (parts->scheme == NULL || parts->path == NULL) {
        parts_free(parts);
        nupp_fail("out of memory");
        return false;
    }
    return true;
}

/* Writes the parts out and parses the result, which is what makes a derived URI
 * exactly as valid as one that arrived as text. */
static NuppUri *reparse(UriParts *parts) {
    size_t length = 0;
    char *text = serialize(parts, &length);
    parts_free(parts);
    if (text == NULL) {
        return NULL;
    }
    return parse_owned(text, length);
}

/* --- entry points ------------------------------------------------------- */

NUPP_EXPORT NuppUri *nuppUriParse(const uint8_t *data, size_t length) {
    NuppText input;
    char *owned;
    if (!nupp_text(&input, data, length, "URI")) {
        return NULL;
    }
    owned = duplicate(input.value, input.length);
    nupp_text_free(&input);
    if (owned == NULL) {
        return refused("out of memory");
    }
    return parse_owned(owned, strlen(owned));
}

NUPP_EXPORT void nuppUriDestroy(NuppUri *uri) {
    if (uri != NULL) {
        free(uri->text);
        free(uri);
    }
}

static const uint8_t *slice(
    const NuppUri *uri, bool present, size_t start, size_t end, size_t *length
) {
    if (!present) {
        if (length != NULL) {
            *length = 0;
        }
        return NULL;
    }
    if (length != NULL) {
        *length = end - start;
    }
    return (const uint8_t *)uri->text + start;
}

NUPP_EXPORT const uint8_t *nuppUriPart(const NuppUri *uri, uint32_t kind, size_t *length) {
    if (uri == NULL) {
        if (length != NULL) {
            *length = 0;
        }
        return NULL;
    }
    switch (kind) {
        case 0: return slice(uri, true, 0, uri->length, length);
        case 1: return slice(uri, true, 0, uri->schemeEnd, length);
        case 2: return slice(uri, uri->hasAuthority, uri->authorityStart, uri->authorityEnd, length);
        case 3: return slice(uri, true, uri->usernameStart, uri->usernameEnd, length);
        case 4: return slice(uri, uri->hasPassword, uri->passwordStart, uri->passwordEnd, length);
        /* An authority with nothing in its host names no host, which is what
         * `file://` is: an authority that is present and empty. */
        case 5: return slice(uri, uri->hasAuthority && uri->hostEnd > uri->hostStart,
            uri->hostStart, uri->hostEnd, length);
        case 6: return slice(uri, true, uri->pathStart, uri->pathEnd, length);
        case 7: return slice(uri, uri->hasQuery, uri->queryStart, uri->queryEnd, length);
        default: return slice(uri, uri->hasFragment, uri->fragmentStart, uri->fragmentEnd, length);
    }
}

NUPP_EXPORT bool nuppUriPort(const NuppUri *uri, uint16_t *port) {
    if (uri == NULL || !uri->hasPort) {
        return false;
    }
    if (port != NULL) {
        *port = (uint16_t)uri->port;
    }
    return true;
}

NUPP_EXPORT NuppUri *nuppUriWithText(
    const NuppUri *uri, uint32_t kind, const uint8_t *value, size_t length, bool present
) {
    UriParts parts;
    NuppText replacement;
    if (uri == NULL) {
        return refused("URI is null");
    }
    if (!nupp_text(&replacement, value, length, "URI component")) {
        return NULL;
    }
    if (!decompose(uri, &parts)) {
        nupp_text_free(&replacement);
        return NULL;
    }

    switch (kind) {
        case 0: {
            /* A scheme decides whether the rest is a hierarchy, so changing one
             * kind into the other would leave a URI whose parts describe
             * something its scheme does not. */
            bool wasSpecial, willBeSpecial;
            char *lower = duplicate(replacement.value, replacement.length);
            size_t at;
            if (lower == NULL) {
                parts_free(&parts);
                nupp_text_free(&replacement);
                return refused("out of memory");
            }
            for (at = 0; lower[at] != '\0'; at++) {
                lower[at] = lowered(lower[at]);
            }
            special_port(parts.scheme, &wasSpecial);
            special_port(lower, &willBeSpecial);
            if (wasSpecial != willBeSpecial) {
                free(lower);
                parts_free(&parts);
                nupp_text_free(&replacement);
                return refused("URI scheme is invalid");
            }
            free(parts.scheme);
            parts.scheme = lower;
            break;
        }
        case 1: {
            if (!parts.hasAuthority) {
                parts_free(&parts);
                nupp_text_free(&replacement);
                return refused("URI user information is invalid");
            }
            free(parts.username);
            free(parts.password);
            parts.password = NULL;
            parts.hasPassword = false;
            if (!present) {
                parts.username = duplicate("", 0);
            } else {
                const char *colon = memchr(replacement.value, ':', replacement.length);
                if (colon != NULL) {
                    size_t split = (size_t)(colon - replacement.value);
                    parts.username = duplicate(replacement.value, split);
                    parts.hasPassword = true;
                    parts.password =
                        duplicate(colon + 1, replacement.length - split - 1);
                } else {
                    parts.username = duplicate(replacement.value, replacement.length);
                }
            }
            break;
        }
        case 2: {
            if (!parts.hasAuthority && present) {
                parts_free(&parts);
                nupp_text_free(&replacement);
                return refused("cannot set a host on a URI that has no authority");
            }
            free(parts.host);
            parts.host = duplicate(present ? replacement.value : "",
                present ? replacement.length : 0);
            break;
        }
        case 3:
            free(parts.path);
            parts.path = duplicate(replacement.value, replacement.length);
            break;
        case 4:
            free(parts.query);
            parts.query = present ? duplicate(replacement.value, replacement.length) : NULL;
            parts.hasQuery = present;
            break;
        default:
            free(parts.fragment);
            parts.fragment = present ? duplicate(replacement.value, replacement.length) : NULL;
            parts.hasFragment = present;
            break;
    }
    nupp_text_free(&replacement);
    return reparse(&parts);
}

NUPP_EXPORT NuppUri *nuppUriWithPort(const NuppUri *uri, int32_t port) {
    UriParts parts;
    if (uri == NULL) {
        return refused("URI is null");
    }
    if (port < -1 || port > 65535) {
        return refused("URI port must be from 0 through 65535, or -1 for none");
    }
    if (!decompose(uri, &parts)) {
        return NULL;
    }
    if (!parts.hasAuthority) {
        parts_free(&parts);
        return refused("URI port is invalid for this scheme");
    }
    parts.hasPort = port >= 0;
    parts.port = port >= 0 ? (unsigned)port : 0;
    return reparse(&parts);
}

/* Joins two path texts with exactly one separator between them, which is what
 * appending a path segment means whichever of them wrote the slash. */
static char *joined_path(const char *base, const char *suffix) {
    NuppBuffer out;
    size_t baseLength = strlen(base);
    bool baseSlash = baseLength != 0 && base[baseLength - 1] == '/';
    bool suffixSlash = suffix[0] == '/';
    nupp_buffer_init(&out);
    nupp_buffer_append(&out, base, baseLength);
    if (baseSlash && suffixSlash) {
        nupp_buffer_append(&out, suffix + 1, strlen(suffix) - 1);
    } else {
        if (!baseSlash && !suffixSlash) {
            nupp_buffer_push(&out, '/');
        }
        nupp_buffer_append(&out, suffix, strlen(suffix));
    }
    nupp_buffer_push(&out, 0);
    if (out.failed) {
        nupp_buffer_free(&out);
        nupp_fail("out of memory");
        return NULL;
    }
    return (char *)out.data;
}

NUPP_EXPORT NuppUri *nuppUriConcatPath(
    const NuppUri *uri, const uint8_t *suffix, size_t length
) {
    UriParts parts;
    NuppText addition;
    char *combined;
    if (uri == NULL) {
        return refused("URI is null");
    }
    if (!nupp_text(&addition, suffix, length, "URI path")) {
        return NULL;
    }
    if (!decompose(uri, &parts)) {
        nupp_text_free(&addition);
        return NULL;
    }
    combined = joined_path(parts.path, addition.value);
    nupp_text_free(&addition);
    if (combined == NULL) {
        parts_free(&parts);
        return NULL;
    }
    free(parts.path);
    parts.path = combined;
    return reparse(&parts);
}

NUPP_EXPORT NuppUri *nuppUriWithEndpoint(const NuppUri *uri, const NuppUri *endpoint) {
    UriParts parts;
    UriParts base;
    char *combined;
    if (uri == NULL || endpoint == NULL) {
        return refused("URI is null");
    }
    if (!decompose(uri, &parts)) {
        return NULL;
    }
    if (!decompose(endpoint, &base)) {
        parts_free(&parts);
        return NULL;
    }
    combined = joined_path(base.path, parts.path);
    if (combined == NULL) {
        parts_free(&parts);
        parts_free(&base);
        return NULL;
    }
    free(base.path);
    base.path = combined;
    /* The endpoint supplies where to go; the receiver supplies what to ask for. */
    base.hasQuery = parts.hasQuery;
    free(base.query);
    base.query = parts.query;
    parts.query = NULL;
    base.hasFragment = parts.hasFragment;
    free(base.fragment);
    base.fragment = parts.fragment;
    parts.fragment = NULL;
    parts_free(&parts);
    return reparse(&base);
}

/* RFC 3986 reference resolution: what a link on a page means, given the page. */
NUPP_EXPORT NuppUri *nuppUriResolve(
    const NuppUri *uri, const uint8_t *reference, size_t length
) {
    NuppText text;
    UriParts base;
    UriParts out;
    const char *value;
    size_t valueLength;

    if (uri == NULL) {
        return refused("URI is null");
    }
    if (!nupp_text(&text, reference, length, "URI reference")) {
        return NULL;
    }
    value = text.value;
    valueLength = text.length;

    /* A reference with a scheme of its own is not relative to anything. */
    {
        size_t at = 0;
        if (valueLength != 0 && is_alpha(value[0])) {
            while (at < valueLength && (is_alpha(value[at]) || is_digit(value[at])
                || value[at] == '+' || value[at] == '-' || value[at] == '.')) {
                at++;
            }
            if (at < valueLength && value[at] == ':') {
                char *owned = duplicate(value, valueLength);
                nupp_text_free(&text);
                if (owned == NULL) {
                    return refused("out of memory");
                }
                return parse_owned(owned, valueLength);
            }
        }
    }

    if (!decompose(uri, &base)) {
        nupp_text_free(&text);
        return NULL;
    }
    memset(&out, 0, sizeof out);
    out.scheme = duplicate(base.scheme, strlen(base.scheme));

    if (valueLength >= 2 && value[0] == '/' && value[1] == '/') {
        /* A network-path reference keeps only the scheme. */
        NuppBuffer rebuilt;
        char *whole;
        nupp_buffer_init(&rebuilt);
        nupp_buffer_append(&rebuilt, base.scheme, strlen(base.scheme));
        nupp_buffer_push(&rebuilt, ':');
        nupp_buffer_append(&rebuilt, value, valueLength);
        nupp_buffer_push(&rebuilt, 0);
        parts_free(&base);
        parts_free(&out);
        nupp_text_free(&text);
        if (rebuilt.failed) {
            nupp_buffer_free(&rebuilt);
            return refused("out of memory");
        }
        whole = (char *)rebuilt.data;
        return parse_owned(whole, strlen(whole));
    }

    out.hasAuthority = base.hasAuthority;
    out.username = base.username != NULL ? duplicate(base.username, strlen(base.username)) : NULL;
    out.hasPassword = base.hasPassword;
    out.password = base.password != NULL ? duplicate(base.password, strlen(base.password)) : NULL;
    out.host = base.host != NULL ? duplicate(base.host, strlen(base.host)) : NULL;
    out.hasPort = base.hasPort;
    out.port = base.port;

    {
        /* Where the reference's own path, query and fragment start. */
        size_t pathEnd = 0;
        size_t queryStart = valueLength;
        size_t fragmentStart = valueLength;
        while (pathEnd < valueLength && value[pathEnd] != '?' && value[pathEnd] != '#') {
            pathEnd++;
        }
        if (pathEnd < valueLength && value[pathEnd] == '?') {
            queryStart = pathEnd + 1;
            fragmentStart = queryStart;
            while (fragmentStart < valueLength && value[fragmentStart] != '#') {
                fragmentStart++;
            }
            out.hasQuery = true;
            out.query = duplicate(value + queryStart, fragmentStart - queryStart);
        } else {
            fragmentStart = pathEnd;
        }
        if (fragmentStart < valueLength && value[fragmentStart] == '#') {
            out.hasFragment = true;
            out.fragment = duplicate(
                value + fragmentStart + 1, valueLength - fragmentStart - 1);
        }

        if (pathEnd == 0) {
            /* No path of its own, so the base's is kept -- and with it the
             * base's query, unless the reference wrote one. */
            out.path = duplicate(base.path, strlen(base.path));
            if (!out.hasQuery) {
                out.hasQuery = base.hasQuery;
                out.query = base.query != NULL
                    ? duplicate(base.query, strlen(base.query)) : NULL;
            }
        } else if (value[0] == '/') {
            out.path = duplicate(value, pathEnd);
        } else {
            /* Merged against everything in the base up to its last separator,
             * which is the directory the reference is written relative to. */
            NuppBuffer merged;
            const char *lastSlash = strrchr(base.path, '/');
            nupp_buffer_init(&merged);
            if (lastSlash != NULL) {
                nupp_buffer_append(&merged, base.path, (size_t)(lastSlash - base.path) + 1);
            } else if (base.hasAuthority) {
                nupp_buffer_push(&merged, '/');
            }
            nupp_buffer_append(&merged, value, pathEnd);
            nupp_buffer_push(&merged, 0);
            if (merged.failed) {
                nupp_buffer_free(&merged);
                parts_free(&base);
                parts_free(&out);
                nupp_text_free(&text);
                return refused("out of memory");
            }
            out.path = (char *)merged.data;
        }
    }
    parts_free(&base);
    nupp_text_free(&text);
    if (out.scheme == NULL || out.path == NULL) {
        parts_free(&out);
        return refused("out of memory");
    }
    return reparse(&out);
}
