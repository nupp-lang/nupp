/**
 * @file
 * @brief CBMC proof of the curl response-header size and wire layout.
 */

#include "proofintrinsics.h"
#include "../../native/http-curl/replyheaders.h"

/** Checks admission for any valid head and arbitrary incoming lengths. */
static void provesizing (void) {
  size_t entries = nondet_size();
  size_t bytes = nondet_size();
  size_t name = nondet_size();
  size_t value = nondet_size();
  __uint128_t before = 4 + 16 * (__uint128_t)entries + bytes;
  __uint128_t after = before + 16 + name + value;
  __CPROVER_assume(before <= HEAD_LIMIT);

  int fits = replyfits(entries, bytes, name, value);
  __CPROVER_assert(fits == (after <= HEAD_LIMIT),
                   "admission preserves the complete head size limit");

  if (fits) {
    __CPROVER_assert(replyroom(entries + 1, bytes + name + value) == after,
                     "admitted headers account for the exact bytes used");
  }

  size_t kept = nondet_size();
  size_t payload = nondet_size();
  __CPROVER_assume(kept <= entries && payload <= bytes);
  __CPROVER_assert(replyroom(kept, payload) <= before,
                   "the retained headers fit the original allocation");
}

/** Reads one little-endian word from a packed head. */
static uint32_t decodedword (const unsigned char *word) {
  return (uint32_t)word[0] | (uint32_t)word[1] << 8 | (uint32_t)word[2] << 16 |
         (uint32_t)word[3] << 24;
}

/** Makes one valid list node with arbitrary value bytes. */
static Reply *sample (const char *name, size_t length, size_t value,
                      Reply *next) {
  Reply *header = malloc(sizeof(*header) + length + value);

  if (!header) {
    __CPROVER_assume(0);
    abort();
  }

  header->next = next;
  header->name = length;
  header->value = value;
  memcpy(header->text, name, length);

  for (size_t i = 0; i < value; i++) {
    header->text[length + i] = (char)nondet_byte();
  }

  return header;
}

/** Checks one entry against its expected position and source payload. */
static size_t checkentry (const PackedHead *head, size_t entry, size_t offset,
                          const Reply *input, const char *lowercase) {
  const unsigned char *slot = head->bytes + 4 + 16 * entry;
  __CPROVER_assert(decodedword(slot) == offset &&
                       decodedword(slot + 4) == input->name,
                   "the name span starts at the next payload byte");
  __CPROVER_assert(memcmp(head->bytes + offset, lowercase, input->name) == 0,
                   "the name is lowercased in input order");
  offset += input->name;
  __CPROVER_assert(decodedword(slot + 8) == offset &&
                       decodedword(slot + 12) == input->value,
                   "the value span follows its name");
  __CPROVER_assert(memcmp(head->bytes + offset, input->text + input->name,
                          input->value) == 0,
                   "the value is copied intact");

  return offset + input->value;
}

/** Checks a four-entry chain with arbitrary values and either decoding mode. */
static void provepacking (void) {
  Reply *last = sample("X-Z", 3, 2, NULL);
  Reply *length = sample("Content-Length", 14, 1, last);
  Reply *encoding = sample("Content-Encoding", 16, 3, length);
  Reply *first = sample("X-A", 3, 0, encoding);
  size_t bytes = first->name + first->value + encoding->name + encoding->value +
                 length->name + length->value + last->name + last->value;
  int strip = nondet_byte() != 0;
  PackedHead head = packhead(first, 4, bytes, strip);

  if (head.bytes) {
    size_t kept = strip ? 2 : 4;
    __CPROVER_assert(decodedword(head.bytes) == kept,
                     "the count includes exactly the retained headers");
    size_t offset = checkentry(&head, 0, 4 + 16 * kept, first, "x-a");

    if (!strip) {
      offset = checkentry(&head, 1, offset, encoding, "content-encoding");
      offset = checkentry(&head, 2, offset, length, "content-length");
    }

    offset = checkentry(&head, kept - 1, offset, last, "x-z");
    __CPROVER_assert(head.length == offset && offset <= 4 + 16 * 4 + bytes,
                     "the produced head uses exactly its table and payload");
    free(head.bytes);
  }
  else {
    __CPROVER_assert(head.length == 0, "allocation failure returns no head");
  }

  free(first);
  free(encoding);
  free(length);
  free(last);
}

int main (void) {
  provesizing();
  provepacking();

  return 0;
}
