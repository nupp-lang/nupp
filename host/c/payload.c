/* Finding the payload appended to this executable.
 *
 * The trailer is the last 48 bytes of an unsigned file and says where the
 * payload starts, how long it is, and what its digest begins with. A signed
 * Mach-O puts Apple's code-signature blob after that trailer; its load command
 * gives the boundary. A file with no magic at either valid boundary has no
 * payload; a file with a version this stub does not know is refused rather than
 * read hopefully.
 */

#include "nupp_host.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAGIC "NUPPLOAD"
#define TRAILER_LENGTH 48u
#define FORMAT_VERSION 1u

/* The payload is precompiled LuaJIT bytecode rather than Lua source.
 *
 * Nothing here has to act on it: luaL_loadbuffer takes either, and tells them
 * apart by the header the dump already carries. The bit is here so the file says
 * what it holds rather than leaving it to be sniffed, and so a stub that predates
 * it refuses on the reserved bytes instead of loading bytecode it was never told
 * to expect. Bits outside this set still mean the file was written by something
 * newer than this host. */
#define PAYLOAD_FLAG_BYTECODE 1u
#define PAYLOAD_FLAGS_KNOWN PAYLOAD_FLAG_BYTECODE

/* The trailer's digest is checked before a byte of the payload is handed to
 * Lua, on every run. The Rust base provider is linked statically into the host,
 * so this check does not depend on loading the payload or a sidecar first. */
#include "nupp_native_v2.h"

void nupp_host_digest_prefix(const uint8_t *bytes, size_t length, uint8_t out[8]) {
    if (nuppNativeV2TrailerDigest(bytes, length, out) != NUPP_NATIVE_V2_OK) {
        /* The host always supplies a valid slice and fixed output. Keep a
         * deterministic mismatch if an incompatible static provider somehow
         * reaches this impossible branch; the ordinary integrity error remains
         * safer than handing an unchecked payload to Lua. */
        memset(out, 0, 8);
    }
}

static uint32_t read32(const uint8_t *bytes, size_t at) {
    return (uint32_t)bytes[at] | ((uint32_t)bytes[at + 1] << 8)
        | ((uint32_t)bytes[at + 2] << 16) | ((uint32_t)bytes[at + 3] << 24);
}

static uint64_t read64(const uint8_t *bytes, size_t at) {
    return (uint64_t)read32(bytes, at) | ((uint64_t)read32(bytes, at + 4) << 32);
}

/* Where a thin little-endian 64-bit Mach-O's code signature begins, when it has
 * one that reaches the end of the file. The catalog has one architecture per
 * artifact on purpose; a universal one would need its own outer selection
 * before reaching this. */
static bool signature_offset(const uint8_t *bytes, size_t size, size_t *out) {
    size_t commands, commandBytes, commandEnd, cursor;
    uint32_t index;

    if (size < 32 || bytes[0] != 0xcf || bytes[1] != 0xfa || bytes[2] != 0xed
        || bytes[3] != 0xfe) {
        return false;
    }
    commands = read32(bytes, 16);
    commandBytes = read32(bytes, 20);
    commandEnd = 32 + commandBytes;
    if (commandEnd < 32 || commandEnd > size) {
        return false;
    }
    cursor = 32;
    for (index = 0; index < commands; index++) {
        uint32_t command;
        size_t commandSize;
        if (cursor + 8 > commandEnd) {
            return false;
        }
        command = read32(bytes, cursor);
        commandSize = read32(bytes, cursor + 4);
        if (commandSize < 8 || cursor + commandSize > commandEnd) {
            return false;
        }
        if (command == 0x1d) {
            size_t offset, blob;
            if (commandSize < 16) {
                return false;
            }
            offset = read32(bytes, cursor + 8);
            blob = read32(bytes, cursor + 12);
            if (offset + blob == size) {
                *out = offset;
                return true;
            }
            return false;
        }
        cursor += commandSize;
    }
    return false;
}

/* `codesign` aligns the signature blob and fills the gap with zero bytes. The
 * trailer stays immediately before that padding, so it is looked for at each
 * distance back from the blob until one is found with only zeroes after it. */
static bool signed_trailer_start(const uint8_t *bytes, size_t size, size_t *out) {
    size_t signatureAt;
    size_t padding;
    size_t limit;

    if (!signature_offset(bytes, size, &signatureAt)) {
        return false;
    }
    limit = signatureAt < 4095 ? signatureAt : 4095;
    for (padding = 0; padding <= limit; padding++) {
        size_t trailerEnd = signatureAt - padding;
        size_t trailerStart;
        size_t scan;
        bool clean = true;
        if (trailerEnd < TRAILER_LENGTH) {
            return false;
        }
        trailerStart = trailerEnd - TRAILER_LENGTH;
        if (memcmp(bytes + trailerStart, MAGIC, 8) != 0) {
            continue;
        }
        for (scan = trailerEnd; scan < signatureAt; scan++) {
            if (bytes[scan] != 0) {
                clean = false;
                break;
            }
        }
        if (clean) {
            *out = trailerStart;
            return true;
        }
    }
    return false;
}

static char *complain(const char *format, ...) {
    char scratch[512];
    va_list arguments;
    char *copy;
    va_start(arguments, format);
    vsnprintf(scratch, sizeof scratch, format, arguments);
    va_end(arguments);
    copy = malloc(strlen(scratch) + 1);
    if (copy != NULL) {
        strcpy(copy, scratch);
    }
    return copy;
}

NuppPayloadOutcome nupp_host_read_payload(
    const char *path, uint8_t **bytes, size_t *length, char **problem
) {
    FILE *file;
    uint8_t *whole = NULL;
    long size = 0;
    size_t trailerStart;
    const uint8_t *trailer;
    uint32_t version;
    uint64_t offset, claimed;
    uint8_t prefix[8];

    *bytes = NULL;
    *length = 0;
    *problem = NULL;

    file = fopen(path, "rb");
    if (file == NULL) {
        *problem = complain("cannot read this executable: %s", path);
        return NUPP_PAYLOAD_FAILED;
    }
    if (fseek(file, 0, SEEK_END) != 0 || (size = ftell(file)) < 0
        || fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        *problem = complain("cannot read this executable: %s", path);
        return NUPP_PAYLOAD_FAILED;
    }
    whole = malloc((size_t)size + 1);
    if (whole == NULL) {
        fclose(file);
        *problem = complain("cannot read this executable: out of memory");
        return NUPP_PAYLOAD_FAILED;
    }
    if (fread(whole, 1, (size_t)size, file) != (size_t)size) {
        free(whole);
        fclose(file);
        *problem = complain("cannot read this executable: %s", path);
        return NUPP_PAYLOAD_FAILED;
    }
    fclose(file);

    if ((size_t)size < TRAILER_LENGTH) {
        free(whole);
        return NUPP_PAYLOAD_NONE;
    }
    trailerStart = (size_t)size - TRAILER_LENGTH;
    if (memcmp(whole + trailerStart, MAGIC, 8) != 0
        && !signed_trailer_start(whole, (size_t)size, &trailerStart)) {
        free(whole);
        return NUPP_PAYLOAD_NONE;
    }
    trailer = whole + trailerStart;

    version = read32(trailer, 8);
    if (version != FORMAT_VERSION) {
        free(whole);
        *problem = complain(
            "this executable carries a payload in format version %u, and this host "
            "only knows version %u", (unsigned)version, FORMAT_VERSION);
        return NUPP_PAYLOAD_FAILED;
    }
    if ((read32(trailer, 12) & ~PAYLOAD_FLAGS_KNOWN) != 0) {
        free(whole);
        *problem = complain(
            "the payload's trailer sets bytes this version reserves, so it was "
            "written by something newer than this host");
        return NUPP_PAYLOAD_FAILED;
    }

    offset = read64(trailer, 16);
    claimed = read64(trailer, 24);
    /* Checked before slicing, so a damaged file is a message rather than a read
     * off the end of a buffer in a binary somebody else is running. */
    if (offset > (uint64_t)size || claimed > (uint64_t)size - offset
        || offset + claimed > (uint64_t)trailerStart) {
        free(whole);
        *problem = complain(
            "the payload claims %llu bytes at %llu but the file is only %llu bytes; "
            "it was probably truncated in transit",
            (unsigned long long)claimed, (unsigned long long)offset,
            (unsigned long long)size);
        return NUPP_PAYLOAD_FAILED;
    }

    nupp_host_digest_prefix(whole + offset, (size_t)claimed, prefix);
    if (memcmp(prefix, trailer + 32, 8) != 0) {
        free(whole);
        *problem = complain(
            "the payload does not match the digest recorded beside it; it was "
            "probably damaged in transit");
        return NUPP_PAYLOAD_FAILED;
    }

    /* The payload alone, so the executable around it is not kept in memory for
     * as long as the program runs. */
    *bytes = malloc((size_t)claimed + 1);
    if (*bytes == NULL) {
        free(whole);
        *problem = complain("cannot read this executable: out of memory");
        return NUPP_PAYLOAD_FAILED;
    }
    memcpy(*bytes, whole + offset, (size_t)claimed);
    (*bytes)[claimed] = 0;
    *length = (size_t)claimed;
    free(whole);
    return NUPP_PAYLOAD_FOUND;
}
