/**
 * @file
 * @brief Packs the curl response head for the core HTTP bridge.
 */

#ifndef NUPP_HTTP_CURL_REPLY_HEADERS_H
#define NUPP_HTTP_CURL_REPLY_HEADERS_H

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

enum {
  HEAD_LIMIT = 256 * 1024,
  HEAD_WORD_BYTES = 4,
  HEAD_NAME_LENGTH_OFFSET = HEAD_WORD_BYTES,
  HEAD_VALUE_OFFSET = 2 * HEAD_WORD_BYTES,
  HEAD_VALUE_LENGTH_OFFSET = 3 * HEAD_WORD_BYTES,
  HEAD_ENTRY_BYTES = 4 * HEAD_WORD_BYTES
};

/** One response header with its name and value stored back to back. */
typedef struct Reply {
  struct Reply *next;
  size_t name, value;
  char text[];
} Reply;

/** The packed response buffer and the number of bytes it uses. */
typedef struct {
  unsigned char *bytes;
  size_t length;
} PackedHead;

/** Sizes the count, offset table and payload for a head within HEAD_LIMIT. */
static inline size_t replyroom (size_t count, size_t bytes) {
  return HEAD_WORD_BYTES + HEAD_ENTRY_BYTES * count + bytes;
}

/** Tests whether a new header fits in a head already within HEAD_LIMIT. */
static inline int replyfits (size_t count, size_t bytes, size_t name,
                             size_t value) {
  size_t left = HEAD_LIMIT - replyroom(count, bytes);

  return left >= HEAD_ENTRY_BYTES && name <= left - HEAD_ENTRY_BYTES &&
         value <= left - HEAD_ENTRY_BYTES - name;
}

/** Lowercases an ASCII header byte. */
static inline int lower (unsigned char value) {
  return value >= 'A' && value <= 'Z' ? value + ('a' - 'A') : value;
}

/** Compares a header name with a lowercase ASCII literal. */
static inline int matches (const char *bytes, size_t length, const char *name) {
  if (length != strlen(name)) {
    return 0;
  }

  for (size_t i = 0; i < length; i++) {
    if (lower((unsigned char)bytes[i]) != name[i]) {
      return 0;
    }
  }

  return 1;
}

/** Stores a value that fits in an unsigned 32-bit little-endian word. */
static inline void encode32 (unsigned char *out, size_t value) {
  for (unsigned i = 0; i < HEAD_WORD_BYTES; i++) {
    out[i] = (unsigned char)(value >> (i * 8));
  }
}

/** Drops headers whose wire values describe a body that was decoded. */
static inline int omitheader (int stripencoding, const char *name, size_t n) {
  return stripencoding && (matches(name, n, "content-encoding") ||
                           matches(name, n, "content-length"));
}

/** Packs the retained headers in input order into an owned byte buffer.
 * @pre entries and bytes describe the list, whose packed size fits HEAD_LIMIT.
 * @return The caller-owned buffer and its used length, or a null buffer
 * and zero length if allocation fails.
 */
static inline PackedHead packhead (const Reply *reply, size_t entries,
                                   size_t bytes, int stripencoding) {
  PackedHead head = {malloc(replyroom(entries, bytes)), 0};

  if (!head.bytes) {
    return head;
  }

  size_t count = 0;

  for (const Reply *h = reply; h; h = h->next) {
    count += !omitheader(stripencoding, h->text, h->name);
  }

  encode32(head.bytes, count);
  size_t index = HEAD_WORD_BYTES, offset = replyroom(count, 0);

  for (const Reply *h = reply; h; h = h->next) {
    if (omitheader(stripencoding, h->text, h->name)) {
      continue;
    }

    size_t n = h->name, v = h->value;
    encode32(head.bytes + index, offset);
    encode32(head.bytes + index + HEAD_NAME_LENGTH_OFFSET, n);

    for (size_t i = 0; i < n; i++) {
      head.bytes[offset + i] = (unsigned char)lower((unsigned char)h->text[i]);
    }

    offset += n;
    encode32(head.bytes + index + HEAD_VALUE_OFFSET, offset);
    encode32(head.bytes + index + HEAD_VALUE_LENGTH_OFFSET, v);
    memcpy(head.bytes + offset, h->text + n, v);
    offset += v;
    index += HEAD_ENTRY_BYTES;
  }

  head.length = offset;

  return head;
}

#endif
