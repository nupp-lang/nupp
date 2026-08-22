/* The error slot, the byte buffers, and the text checking every facility shares. */

#include "nupp_native.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if NUPP_WINDOWS
#   include <windows.h>
#else
#   include <errno.h>
#   include <time.h>
#endif

/* --- the error slot ----------------------------------------------------- */

/* Per thread, because two threads failing at once would otherwise overwrite each
 * other's reason and each read the other's. Fixed rather than grown: a message
 * is a sentence, and an allocator that can fail is the last thing wanted on the
 * path that reports a failure.
 */
#define NUPP_ERROR_CAPACITY 512

static NUPP_THREAD_LOCAL char nupp_error[NUPP_ERROR_CAPACITY] = "no error";

const char *nuppcNativeError(void) {
    return nupp_error;
}

/* A NUL byte would truncate the message where it sits, so an interior one is
 * escaped rather than obeyed. Nothing here produces one; a platform message
 * carrying one would. */
static void nupp_store(const char *message) {
    size_t at = 0;
    for (; message[at] != '\0' && at + 1 < NUPP_ERROR_CAPACITY; at++) {
        nupp_error[at] = message[at];
    }
    nupp_error[at] = '\0';
}

void nupp_fail(const char *message) {
    nupp_store(message);
}

void nupp_fail_format(const char *format, ...) {
    char scratch[NUPP_ERROR_CAPACITY];
    va_list arguments;
    va_start(arguments, format);
    vsnprintf(scratch, sizeof scratch, format, arguments);
    va_end(arguments);
    nupp_store(scratch);
}

void nupp_platform_error_text(int number, char *into, size_t capacity) {
    if (capacity == 0) {
        return;
    }
#if NUPP_WINDOWS
    /* `number` is an errno here as it is everywhere else; the places that have a
     * Windows error code convert it before arriving. */
    if (strerror_s(into, capacity, number) != 0) {
        snprintf(into, capacity, "error %d", number);
    }
#else
    /* The XSI spelling, which is what is declared while `_GNU_SOURCE` is not
     * defined. The GNU one has the same name and answers a pointer instead, so a
     * translation unit that pulls it in gets a different function; nothing here
     * asks for it. */
    if (strerror_r(number, into, capacity) != 0) {
        snprintf(into, capacity, "error %d", number);
    }
#endif
}

void nupp_fail_errno(const char *what, int number) {
    char text[256];
    nupp_platform_error_text(number, text, sizeof text);
    if (what != NULL && what[0] != '\0') {
        nupp_fail_format("%s: %s (os error %d)", what, text, number);
    } else {
        nupp_fail_format("%s (os error %d)", text, number);
    }
}

/* --- returned bytes ----------------------------------------------------- */

struct NuppBytes {
    uint8_t *data;
    size_t length;
};

const uint8_t *nuppcBytesData(const NuppBytes *bytes) {
    return bytes != NULL ? bytes->data : NULL;
}

size_t nuppcBytesLength(const NuppBytes *bytes) {
    return bytes != NULL ? bytes->length : 0;
}

void nuppcBytesDestroy(NuppBytes *bytes) {
    if (bytes != NULL) {
        free(bytes->data);
        free(bytes);
    }
}

NuppBytes *nupp_bytes_adopt(uint8_t *data, size_t length) {
    NuppBytes *bytes = malloc(sizeof *bytes);
    if (bytes == NULL) {
        free(data);
        nupp_fail("out of memory");
        return NULL;
    }
    bytes->data = data;
    bytes->length = length;
    return bytes;
}

NuppBytes *nupp_bytes_copy(const uint8_t *data, size_t length) {
    /* One byte over, so an empty answer still owns an allocation and the three
     * accessors need no special case for it. */
    uint8_t *copy = malloc(length + 1);
    if (copy == NULL) {
        nupp_fail("out of memory");
        return NULL;
    }
    if (length != 0) {
        memcpy(copy, data, length);
    }
    copy[length] = 0;
    return nupp_bytes_adopt(copy, length);
}

/* --- growable byte buffer ----------------------------------------------- */

void nupp_buffer_init(NuppBuffer *buffer) {
    buffer->data = NULL;
    buffer->length = 0;
    buffer->capacity = 0;
    buffer->failed = false;
}

void nupp_buffer_free(NuppBuffer *buffer) {
    free(buffer->data);
    nupp_buffer_init(buffer);
}

static bool nupp_buffer_reserve(NuppBuffer *buffer, size_t extra) {
    size_t wanted;
    uint8_t *grown;
    if (buffer->failed) {
        return false;
    }
    if (extra > SIZE_MAX - buffer->length - 1) {
        buffer->failed = true;
        return false;
    }
    wanted = buffer->length + extra + 1;
    if (wanted <= buffer->capacity) {
        return true;
    }
    /* Doubling, so appending a byte at a time over a large directory is linear
     * rather than quadratic. */
    while (buffer->capacity < wanted) {
        size_t next = buffer->capacity < 64 ? 64 : buffer->capacity * 2;
        if (next < buffer->capacity) {
            buffer->failed = true;
            return false;
        }
        buffer->capacity = next;
    }
    grown = realloc(buffer->data, buffer->capacity);
    if (grown == NULL) {
        buffer->failed = true;
        return false;
    }
    buffer->data = grown;
    return true;
}

void nupp_buffer_append(NuppBuffer *buffer, const void *data, size_t length) {
    if (!nupp_buffer_reserve(buffer, length)) {
        return;
    }
    if (length != 0) {
        memcpy(buffer->data + buffer->length, data, length);
    }
    buffer->length += length;
}

void nupp_buffer_push(NuppBuffer *buffer, uint8_t byte) {
    if (!nupp_buffer_reserve(buffer, 1)) {
        return;
    }
    buffer->data[buffer->length++] = byte;
}

NuppBytes *nupp_buffer_finish(NuppBuffer *buffer) {
    NuppBytes *bytes;
    if (buffer->failed) {
        nupp_buffer_free(buffer);
        nupp_fail("out of memory");
        return NULL;
    }
    if (buffer->data == NULL && !nupp_buffer_reserve(buffer, 0)) {
        nupp_buffer_free(buffer);
        nupp_fail("out of memory");
        return NULL;
    }
    buffer->data[buffer->length] = 0;
    bytes = nupp_bytes_adopt(buffer->data, buffer->length);
    nupp_buffer_init(buffer);
    return bytes;
}

/* --- text from the binding ---------------------------------------------- */

bool nupp_is_utf8(const uint8_t *data, size_t length) {
    size_t at = 0;
    while (at < length) {
        uint8_t lead = data[at];
        size_t following;
        uint32_t code;
        if (lead < 0x80) {
            at++;
            continue;
        }
        if (lead >= 0xC2 && lead <= 0xDF) {
            following = 1;
            code = lead & 0x1Fu;
        } else if (lead >= 0xE0 && lead <= 0xEF) {
            following = 2;
            code = lead & 0x0Fu;
        } else if (lead >= 0xF0 && lead <= 0xF4) {
            following = 3;
            code = lead & 0x07u;
        } else {
            return false;
        }
        if (following >= length - at) {
            return false;
        }
        for (size_t step = 1; step <= following; step++) {
            uint8_t byte = data[at + step];
            if ((byte & 0xC0u) != 0x80u) {
                return false;
            }
            code = (code << 6) | (byte & 0x3Fu);
        }
        /* Overlong forms, surrogates and anything past the last code point are
         * sequences a decoder would accept and a validator must not: they encode
         * a value that has a shorter spelling, or no spelling at all. */
        if (following == 2 && code < 0x800) {
            return false;
        }
        if (following == 3 && (code < 0x10000 || code > 0x10FFFF)) {
            return false;
        }
        if (code >= 0xD800 && code <= 0xDFFF) {
            return false;
        }
        at += following + 1;
    }
    return true;
}

bool nupp_text(NuppText *text, const uint8_t *data, size_t length, const char *what) {
    text->heap = false;
    text->value = text->inlined;
    text->length = 0;
    text->inlined[0] = '\0';

    if (data == NULL && length != 0) {
        nupp_fail_format("%s is null", what);
        return false;
    }
    if (length == 0) {
        return true;
    }
    if (!nupp_is_utf8(data, length)) {
        nupp_fail_format("%s is not valid UTF-8", what);
        return false;
    }
    if (memchr(data, 0, length) != NULL) {
        nupp_fail_format("%s contains a NUL byte", what);
        return false;
    }
    if (length + 1 > NUPP_TEXT_INLINE) {
        text->value = malloc(length + 1);
        if (text->value == NULL) {
            text->value = text->inlined;
            nupp_fail("out of memory");
            return false;
        }
        text->heap = true;
    }
    if (length != 0) {
        memcpy(text->value, data, length);
    }
    text->value[length] = '\0';
    text->length = length;
    return true;
}

void nupp_text_free(NuppText *text) {
    if (text->heap) {
        free(text->value);
        text->heap = false;
    }
    text->value = text->inlined;
    text->length = 0;
}

/* --- platform ----------------------------------------------------------- */

void nupp_normalize_separators(char *path) {
#if NUPP_WINDOWS
    for (; *path != '\0'; path++) {
        if (*path == '\\') {
            *path = '/';
        }
    }
#else
    (void)path;
#endif
}

double nupp_monotonic_ms(void) {
#if NUPP_WINDOWS
    static LARGE_INTEGER frequency;
    LARGE_INTEGER now;
    if (frequency.QuadPart == 0) {
        QueryPerformanceFrequency(&frequency);
    }
    QueryPerformanceCounter(&now);
    return (double)now.QuadPart * 1000.0 / (double)frequency.QuadPart;
#else
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (double)now.tv_sec * 1000.0 + (double)now.tv_nsec / 1.0e6;
#endif
}
