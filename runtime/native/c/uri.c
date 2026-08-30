/* URI parsing, on ada.
 *
 * `nupp.io.uri` promises the WHATWG model: a host written in another case is
 * the same host, a default port is not part of what a URI names, and everything
 * after the colon of a scheme with no `//` is opaque -- `mailto:someone@x` has a
 * path and no host. Ada is that model, and it is the one Node.js parses URLs
 * with, so what this file does is hold the ABI still over it.
 *
 * What the ABI asks for that ada does not offer directly is small and all of it
 * is here: the authority as one span, the reason a bad URI is bad, and joining
 * path text without interpreting it as a reference.
 *
 * A component is answered as a pointer into storage the handle owns, which is
 * why nothing here mutates a parsed URI. Every derivation copies, changes the
 * copy, and answers a new handle -- ada's own documentation is explicit that a
 * mutation invalidates the pointers it handed out, and this ABI has handed
 * several to Lua by then.
 */

#include "nupp_native.h"

#include <ada_c.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct NuppUri {
    ada_url url;
};

typedef struct NuppUri NuppUri;

/* --- answering ---------------------------------------------------------- */

static NuppUri *hold(ada_url url) {
    NuppUri *uri;
    if (!ada_is_valid(url)) {
        ada_free(url);
        return NULL;
    }
    uri = malloc(sizeof *uri);
    if (uri == NULL) {
        ada_free(url);
        nupp_fail("out of memory");
        return NULL;
    }
    uri->url = url;
    return uri;
}

/* Why one piece of text is not a URI.
 *
 * Ada answers whether it parsed, not what went wrong, and the reason is what a
 * caller validating text from outside the program shows a person. These are the
 * three faults worth telling apart, tested the way ada would have found them
 * and named the way this library has always named them. */
static const char *why_not(const char *text, size_t length) {
    size_t at = 0;
    bool special;
    size_t schemeEnd;

    if (length == 0 || !((text[0] >= 'a' && text[0] <= 'z')
        || (text[0] >= 'A' && text[0] <= 'Z'))) {
        return "relative URL without a base";
    }
    while (at < length && text[at] != ':') {
        char letter = text[at];
        bool ordinary = (letter >= 'a' && letter <= 'z')
            || (letter >= 'A' && letter <= 'Z')
            || (letter >= '0' && letter <= '9')
            || letter == '+' || letter == '-' || letter == '.';
        if (!ordinary) {
            return "relative URL without a base";
        }
        at++;
    }
    if (at == length) {
        return "relative URL without a base";
    }
    schemeEnd = at;
    at++;

    /* An authority that opens a bracket and never closes it is an address that
     * was going to be IPv6 and is not. */
    if (at + 1 < length && text[at] == '/' && text[at + 1] == '/') {
        size_t scan = at + 2;
        size_t authorityEnd = scan;
        bool opened = false;
        bool closed = false;
        while (authorityEnd < length && text[authorityEnd] != '/'
            && text[authorityEnd] != '?' && text[authorityEnd] != '#') {
            if (text[authorityEnd] == '[') {
                opened = true;
            }
            if (text[authorityEnd] == ']') {
                closed = true;
            }
            authorityEnd++;
        }
        if (opened && !closed) {
            return "invalid IPv6 address";
        }
        if (authorityEnd == scan) {
            return "empty host";
        }
    } else {
        /* A scheme that must have a host and was given none. */
        static const char *SPECIAL[] = {"http", "https", "ws", "wss", "ftp", "file"};
        size_t which;
        special = false;
        for (which = 0; which < sizeof SPECIAL / sizeof SPECIAL[0]; which++) {
            size_t nameLength = strlen(SPECIAL[which]);
            size_t step;
            if (nameLength != schemeEnd) {
                continue;
            }
            for (step = 0; step < nameLength; step++) {
                char letter = text[step];
                char lowered = (letter >= 'A' && letter <= 'Z')
                    ? (char)(letter - 'A' + 'a') : letter;
                if (lowered != SPECIAL[which][step]) {
                    break;
                }
            }
            if (step == nameLength) {
                special = true;
                break;
            }
        }
        if (special) {
            return "empty host";
        }
    }
    return "the URI is not valid";
}

NUPP_EXPORT NuppUri *nuppUriParse(const uint8_t *data, size_t length) {
    NuppText text;
    NuppUri *uri;
    ada_url url;
    if (!nupp_text(&text, data, length, "URI")) {
        return NULL;
    }
    url = ada_parse(text.value, text.length);
    if (!ada_is_valid(url)) {
        ada_free(url);
        nupp_fail(why_not(text.value, text.length));
        nupp_text_free(&text);
        return NULL;
    }
    /* `hold` refuses only for want of memory now, and that reason stands. */
    uri = hold(url);
    nupp_text_free(&text);
    return uri;
}

NUPP_EXPORT void nuppUriDestroy(NuppUri *uri) {
    if (uri != NULL) {
        ada_free(uri->url);
        free(uri);
    }
}

/* --- reading ------------------------------------------------------------ */

static const uint8_t *answer(ada_string value, bool present, size_t skip, size_t *length) {
    if (!present) {
        if (length != NULL) {
            *length = 0;
        }
        return NULL;
    }
    if (length != NULL) {
        *length = value.length > skip ? value.length - skip : 0;
    }
    return (const uint8_t *)value.data + skip;
}

NUPP_EXPORT const uint8_t *nuppUriPart(const NuppUri *uri, uint32_t kind, size_t *length) {
    ada_url url;
    if (uri == NULL) {
        if (length != NULL) {
            *length = 0;
        }
        return NULL;
    }
    url = uri->url;
    switch (kind) {
        case 0: return answer(ada_get_href(url), true, 0, length);
        /* The protocol carries its colon, and the scheme is the part before it. */
        case 1: {
            ada_string protocol = ada_get_protocol(url);
            if (length != NULL) {
                *length = protocol.length > 0 ? protocol.length - 1 : 0;
            }
            return (const uint8_t *)protocol.data;
        }
        case 2: {
            /* Everything between the `//` and the path, which is the one part
             * the getters do not name: `host` there is the hostname and port
             * without the user information. */
            ada_string href = ada_get_href(url);
            const ada_url_components *parts = ada_get_components(url);
            size_t start, end;
            if (parts == NULL || parts->protocol_end + 1 >= href.length
                || href.data[parts->protocol_end] != '/'
                || href.data[parts->protocol_end + 1] != '/') {
                if (length != NULL) {
                    *length = 0;
                }
                return NULL;
            }
            start = parts->protocol_end + 2;
            end = parts->pathname_start == ada_url_omitted
                ? href.length : parts->pathname_start;
            if (length != NULL) {
                *length = end - start;
            }
            return (const uint8_t *)href.data + start;
        }
        case 3: return answer(ada_get_username(url), true, 0, length);
        case 4: return answer(ada_get_password(url), ada_has_password(url), 0, length);
        /* An authority with nothing in its host names no host, which is what a
         * local file URL is. */
        case 5: {
            ada_string host = ada_get_hostname(url);
            return answer(host, host.length != 0, 0, length);
        }
        case 6: return answer(ada_get_pathname(url), true, 0, length);
        /* The query and the fragment carry their own punctuation. */
        case 7: return answer(ada_get_search(url), ada_has_search(url), 1, length);
        default: return answer(ada_get_hash(url), ada_has_hash(url), 1, length);
    }
}

NUPP_EXPORT bool nuppUriPort(const NuppUri *uri, uint16_t *port) {
    ada_string text;
    unsigned long value = 0;
    size_t at;
    if (uri == NULL || !ada_has_port(uri->url)) {
        return false;
    }
    text = ada_get_port(uri->url);
    for (at = 0; at < text.length; at++) {
        value = value * 10 + (unsigned long)(text.data[at] - '0');
    }
    if (port != NULL) {
        *port = (uint16_t)value;
    }
    return true;
}

/* --- deriving ----------------------------------------------------------- */

/* A copy to change, so the original keeps the storage it has handed pointers
 * into. */
static ada_url borrowed(const NuppUri *uri) {
    return uri != NULL ? ada_copy(uri->url) : NULL;
}

static NuppUri *refused(ada_url url, const char *reason) {
    if (url != NULL) {
        ada_free(url);
    }
    nupp_fail(reason);
    return NULL;
}

NUPP_EXPORT NuppUri *nuppUriWithText(
    const NuppUri *uri, uint32_t kind, const uint8_t *value, size_t length, bool present
) {
    NuppText replacement;
    ada_url url;
    bool ok = true;

    if (uri == NULL) {
        nupp_fail("URI is null");
        return NULL;
    }
    if (!nupp_text(&replacement, value, length, "URI component")) {
        return NULL;
    }
    url = borrowed(uri);
    if (url == NULL) {
        nupp_text_free(&replacement);
        nupp_fail("out of memory");
        return NULL;
    }

    switch (kind) {
        case 0:
            ok = ada_set_protocol(url, replacement.value, replacement.length);
            if (!ok) {
                nupp_text_free(&replacement);
                return refused(url, "URI scheme is invalid");
            }
            break;
        case 1: {
            /* User information is one field to a caller and two to the grammar,
             * split at the first colon. */
            const char *colon = present
                ? memchr(replacement.value, ':', replacement.length) : NULL;
            const char *name = present ? replacement.value : "";
            size_t nameLength = present
                ? (colon != NULL ? (size_t)(colon - replacement.value) : replacement.length)
                : 0;
            ok = ada_set_username(url, name, nameLength);
            if (ok) {
                ok = colon != NULL
                    ? ada_set_password(url, colon + 1,
                        replacement.length - nameLength - 1)
                    : ada_set_password(url, "", 0);
            }
            if (!ok) {
                nupp_text_free(&replacement);
                return refused(url, "URI user information is invalid");
            }
            break;
        }
        case 2:
            ok = ada_set_hostname(url, present ? replacement.value : "",
                present ? replacement.length : 0);
            if (!ok) {
                nupp_text_free(&replacement);
                return refused(url, "URI host is invalid");
            }
            break;
        case 3:
            ok = ada_set_pathname(url, replacement.value, replacement.length);
            if (!ok) {
                nupp_text_free(&replacement);
                return refused(url, "URI path is invalid");
            }
            break;
        case 4:
            if (present) {
                ada_set_search(url, replacement.value, replacement.length);
            } else {
                ada_clear_search(url);
            }
            break;
        default:
            if (present) {
                ada_set_hash(url, replacement.value, replacement.length);
            } else {
                ada_clear_hash(url);
            }
            break;
    }
    nupp_text_free(&replacement);
    return hold(url);
}

NUPP_EXPORT NuppUri *nuppUriWithPort(const NuppUri *uri, int32_t port) {
    ada_url url;
    if (uri == NULL) {
        nupp_fail("URI is null");
        return NULL;
    }
    if (port < -1 || port > 65535) {
        nupp_fail("URI port must be from 0 through 65535, or -1 for none");
        return NULL;
    }
    url = borrowed(uri);
    if (url == NULL) {
        nupp_fail("out of memory");
        return NULL;
    }
    if (port < 0) {
        ada_clear_port(url);
    } else {
        char digits[8];
        int written = snprintf(digits, sizeof digits, "%d", (int)port);
        if (!ada_set_port(url, digits, (size_t)(written < 0 ? 0 : written))) {
            return refused(url, "URI port is invalid for this scheme");
        }
    }
    return hold(url);
}

/* --- joining paths ------------------------------------------------------ */

/* One separator between the two, whichever of them wrote it. This is not
 * reference resolution: the suffix is path text, and a `..` in it is a segment
 * named `..` until the grammar normalises it. */
static NuppUri *joined(const NuppUri *uri, const char *base, size_t baseLength,
    const char *suffix, size_t suffixLength, ada_url url
) {
    NuppBuffer out;
    bool baseSlash = baseLength != 0 && base[baseLength - 1] == '/';
    bool suffixSlash = suffixLength != 0 && suffix[0] == '/';
    bool ok;
    (void)uri;

    nupp_buffer_init(&out);
    nupp_buffer_append(&out, base, baseLength);
    if (baseSlash && suffixSlash) {
        nupp_buffer_append(&out, suffix + 1, suffixLength - 1);
    } else {
        if (!baseSlash && !suffixSlash) {
            nupp_buffer_push(&out, '/');
        }
        nupp_buffer_append(&out, suffix, suffixLength);
    }
    if (out.failed) {
        nupp_buffer_free(&out);
        return refused(url, "out of memory");
    }
    ok = ada_set_pathname(url, (const char *)out.data, out.length);
    nupp_buffer_free(&out);
    if (!ok) {
        return refused(url, "URI path is invalid");
    }
    return hold(url);
}

NUPP_EXPORT NuppUri *nuppUriConcatPath(
    const NuppUri *uri, const uint8_t *suffix, size_t length
) {
    NuppText addition;
    ada_string path;
    ada_url url;
    NuppUri *answered;

    if (uri == NULL) {
        nupp_fail("URI is null");
        return NULL;
    }
    if (!nupp_text(&addition, suffix, length, "URI path")) {
        return NULL;
    }
    url = borrowed(uri);
    if (url == NULL) {
        nupp_text_free(&addition);
        nupp_fail("out of memory");
        return NULL;
    }
    path = ada_get_pathname(url);
    answered = joined(uri, path.data, path.length, addition.value, addition.length, url);
    nupp_text_free(&addition);
    return answered;
}

/* The endpoint supplies where to go; the receiver supplies what to ask for. */
NUPP_EXPORT NuppUri *nuppUriWithEndpoint(const NuppUri *uri, const NuppUri *endpoint) {
    ada_url url;
    ada_string ourPath, theirPath, search, hash;
    NuppBuffer path;
    bool hadSearch, hadHash;

    if (uri == NULL || endpoint == NULL) {
        nupp_fail("URI is null");
        return NULL;
    }
    url = borrowed(endpoint);
    if (url == NULL) {
        nupp_fail("out of memory");
        return NULL;
    }
    ourPath = ada_get_pathname(uri->url);
    theirPath = ada_get_pathname(url);
    nupp_buffer_init(&path);
    nupp_buffer_append(&path, ourPath.data, ourPath.length);
    if (path.failed) {
        nupp_buffer_free(&path);
        return refused(url, "out of memory");
    }

    hadSearch = ada_has_search(uri->url);
    search = ada_get_search(uri->url);
    hadHash = ada_has_hash(uri->url);
    hash = ada_get_hash(uri->url);
    {
        /* Copied before the endpoint is changed: these point into the
         * receiver's storage, which the setters below do not touch, but the
         * path does point into the copy and that one is about to move. */
        NuppBuffer keptSearch, keptHash;
        NuppUri *answered;
        nupp_buffer_init(&keptSearch);
        nupp_buffer_init(&keptHash);
        if (hadSearch && search.length > 1) {
            nupp_buffer_append(&keptSearch, search.data + 1, search.length - 1);
        }
        if (hadHash && hash.length > 1) {
            nupp_buffer_append(&keptHash, hash.data + 1, hash.length - 1);
        }
        if (keptSearch.failed || keptHash.failed) {
            nupp_buffer_free(&path);
            nupp_buffer_free(&keptSearch);
            nupp_buffer_free(&keptHash);
            return refused(url, "out of memory");
        }
        answered = joined(uri, theirPath.data, theirPath.length,
            (const char *)path.data, path.length, url);
        nupp_buffer_free(&path);
        if (answered == NULL) {
            nupp_buffer_free(&keptSearch);
            nupp_buffer_free(&keptHash);
            return NULL;
        }
        if (hadSearch) {
            ada_set_search(answered->url,
                keptSearch.data != NULL ? (const char *)keptSearch.data : "",
                keptSearch.length);
        } else {
            ada_clear_search(answered->url);
        }
        if (hadHash) {
            ada_set_hash(answered->url,
                keptHash.data != NULL ? (const char *)keptHash.data : "",
                keptHash.length);
        } else {
            ada_clear_hash(answered->url);
        }
        nupp_buffer_free(&keptSearch);
        nupp_buffer_free(&keptHash);
        return answered;
    }
}

/* Reference resolution: what a link on a page means, given the page. */
NUPP_EXPORT NuppUri *nuppUriResolve(
    const NuppUri *uri, const uint8_t *reference, size_t length
) {
    NuppText text;
    ada_string base;
    ada_url url;
    NuppUri *answered;

    if (uri == NULL) {
        nupp_fail("URI is null");
        return NULL;
    }
    if (!nupp_text(&text, reference, length, "URI reference")) {
        return NULL;
    }
    base = ada_get_href(uri->url);
    url = ada_parse_with_base(text.value, text.length, base.data, base.length);
    if (!ada_is_valid(url)) {
        ada_free(url);
        nupp_fail("the URI reference cannot be resolved against this URI");
        nupp_text_free(&text);
        return NULL;
    }
    /* `hold` refuses only for want of memory now, and that reason stands. */
    answered = hold(url);
    nupp_text_free(&text);
    return answered;
}
