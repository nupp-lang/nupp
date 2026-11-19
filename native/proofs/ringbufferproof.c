/**
 * @file
 * @brief CBMC proof of HTTP ring-buffer arithmetic and bounded FIFO behavior.
 */

#include "proofintrinsics.h"
#include "../httpcurl/ringbuffer.h"

enum { SAMPLE_CAPACITY = 8 };

/** Checks copy spans and wraparound over the full size_t range. */
static void provespans (void) {
  size_t room = nondet_size();
  size_t start = nondet_size();
  size_t used = nondet_size();
  __CPROVER_assume(start < room && used <= room);

  size_t added = nondet_size();
  __CPROVER_assume(added <= room - used);
  size_t at = bufferadvance(start, used, room);
  size_t first = bufferfirst(at, added, room);
  __uint128_t end = (__uint128_t)start + used;
  __CPROVER_assert(at == (end < room ? end : end - room),
                   "append starts at the logical end");
  __CPROVER_assert(at < room && first <= room - at && first <= added &&
                       added - first <= at,
                   "append uses two disjoint spans within capacity");
  __CPROVER_assert(used + added <= room, "append preserves capacity");

  size_t removed = nondet_size();
  __CPROVER_assume(removed <= used);
  size_t head = bufferadvance(start, removed, room);
  first = bufferfirst(start, removed, room);
  __uint128_t next = (__uint128_t)start + removed;
  __CPROVER_assert(head < room && head == (next < room ? next : next - room),
                   "take advances the head by the bytes removed");
  __CPROVER_assert(first <= room - start && first <= removed &&
                       removed - first <= start,
                   "take uses two disjoint spans within capacity");
  __CPROVER_assert(used - removed <= room, "take preserves capacity");
}

/** Checks a real append and take from any valid small ring state. */
static void provefifo (void) {
  size_t room = nondet_byte();
  size_t start = nondet_byte();
  size_t used = nondet_byte();
  size_t added = nondet_byte();
  __CPROVER_assume(room <= SAMPLE_CAPACITY && start < room && used <= room &&
                   added <= room - used);

  unsigned char storage[SAMPLE_CAPACITY];
  unsigned char incoming[SAMPLE_CAPACITY];
  unsigned char expected[SAMPLE_CAPACITY];
  unsigned char output[SAMPLE_CAPACITY];

  for (size_t i = 0; i < SAMPLE_CAPACITY; i++) {
    storage[i] = nondet_byte();
    incoming[i] = nondet_byte();
  }

  size_t at = start;

  for (size_t i = 0; i < used; i++) {
    expected[i] = storage[at++];

    if (at == room) {
      at = 0;
    }
  }

  for (size_t i = 0; i < added; i++) {
    expected[used + i] = incoming[i];
  }

  Buffer ring = {.bytes = storage, .start = start, .used = used, .room = room};
  int appended = bufferappend(&ring, incoming, added);
  __CPROVER_assert(appended == 1 && ring.bytes == storage &&
                       ring.room == room && ring.start == start &&
                       ring.used == used + added,
                   "append preserves storage and queues all supplied bytes");
  size_t requested = nondet_byte();
  size_t count = buffertake(&ring, output, requested);
  size_t size = used + added;
  __CPROVER_assert(count == (requested < size ? requested : size),
                   "take returns the requested or available count");
  at = start;

  for (size_t i = 0; i < count; i++) {
    __CPROVER_assert(output[i] == expected[i], "take copies in FIFO order");

    if (++at == room) {
      at = 0;
    }
  }

  __CPROVER_assert(ring.bytes == storage && ring.room == room &&
                       ring.start == at && ring.used == size - count,
                   "take retains exactly the unread part of the ring");

  for (size_t i = count; i < size; i++) {
    __CPROVER_assert(storage[at++] == expected[i],
                     "take preserves every unread byte in order");

    if (at == room) {
      at = 0;
    }
  }
}

int main (void) {
  provespans();
  provefifo();

  return 0;
}
