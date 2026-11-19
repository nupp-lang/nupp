/**
 * @file
 * @brief CBMC proof of file ticket ownership and two-job completion order.
 */

#include "proofintrinsics.h"
#include "../../native/core-bridge/filetickets.h"

#include <stdlib.h>

/** Admits a fresh heap ticket with an arbitrary small byte charge. */
static FileTicket *admit (FileTickets *queue, uint64_t id) {
  FileTicket *ticket = calloc(1, sizeof(*ticket));

  if (!ticket) {
    __CPROVER_assume(0);
    abort();
  }

  ticket->id = id;
  ticket->count = nondet_byte();
  fileticketadmit(queue, ticket);

  return ticket;
}

/** Releases a returned ticket only after checking its identity and result. */
static void release (FileTicket *ticket, uint64_t id, int64_t result) {
  __CPROVER_assert(ticket && ticket->id == id && ticket->result == result,
                   "the released ticket retains its identity and result");
  free(ticket);
}

/** Checks that removal cleared both queues and fully restored capacity. */
static void checkempty (FileTickets *queue) {
  __CPROVER_assert(!queue->jobs && !queue->finished &&
                       queue->tail == &queue->finished && !queue->count &&
                       !queue->active && !queue->bytes,
                   "the empty queue retains neither references nor charges");
}

/** Exercises cancellation before submission and during an outstanding job. */
static void provecancel (void) {
  FileTickets queue = {0};
  fileticketsinit(&queue);
  FileTicket *active = admit(&queue, 1);
  admit(&queue, 2);
  size_t bytes = active->count;
  fileticketsubmit(&queue, active);

  FileTicket **at = fileticketfind(&queue, 2);
  release(fileticketcancel(&queue, at), 2, 0);
  __CPROVER_assert(!fileticketcancel(&queue, fileticketfind(&queue, 2)),
                   "canceling a removed ticket again changes nothing");

  at = fileticketfind(&queue, 1);
  __CPROVER_assert(!fileticketcancel(&queue, at) &&
                       !fileticketcollect(&queue, at, 1) &&
                       !fileticketcollect(&queue, at, 0),
                   "no operation can release a ticket with a callback due");
  __CPROVER_assert(queue.jobs == active && !active->next && queue.count == 1 &&
                       queue.active == 1 && queue.bytes == bytes &&
                       !queue.finished,
                   "only the in-flight job stays charged after cancellation");

  int64_t result = nondet_byte() & 1 ? -1 : (int64_t)bytes;
  fileticketcomplete(&queue, active, result);
  __CPROVER_assert(queue.active == 0 && queue.bytes == bytes,
                   "the callback leaves result storage charged");
  __CPROVER_assert(!fileticketcancel(&queue, at),
                   "a completed native job still requires collection");
  int finish = nondet_byte() & 1;

  if (finish) {
    __CPROVER_assert(filetickettake(&queue) == active,
                     "the callback publishes one collectable ticket");
  }

  release(fileticketcollect(&queue, at, finish), 1, result);
  __CPROVER_assert(!fileticketcollect(&queue, fileticketfind(&queue, 1), 0),
                   "collection cannot spend the same ticket twice");
  checkempty(&queue);
}

/** Exercises either completion order and collection of either queued result. */
static void proveorder (void) {
  FileTickets queue = {0};
  fileticketsinit(&queue);
  FileTicket *one = admit(&queue, 1);
  FileTicket *two = admit(&queue, 2);
  fileticketsubmit(&queue, one);
  fileticketsubmit(&queue, two);
  int forward = nondet_byte() & 1;
  FileTicket *first = forward ? one : two;
  FileTicket *second = forward ? two : one;
  uint64_t firstid = forward ? 1 : 2;
  uint64_t secondid = forward ? 2 : 1;
  size_t firstbytes = first->count;
  size_t secondbytes = second->count;
  int64_t firstresult = nondet_byte() & 1 ? -1 : (int64_t)firstbytes;
  int64_t secondresult = nondet_byte() & 1 ? -1 : (int64_t)secondbytes;
  fileticketcomplete(&queue, first, firstresult);

  if (nondet_byte() & 1) {
    release(fileticketcollect(&queue, fileticketfind(&queue, firstid), 0),
            firstid, firstresult);
    __CPROVER_assert(!queue.finished && queue.tail == &queue.finished &&
                         queue.count == 1 && queue.active == 1 &&
                         queue.bytes == secondbytes,
                     "settling the only result restores the tail for reuse");
    fileticketcomplete(&queue, second, secondresult);
  }
  else {
    int takefirst = nondet_byte() & 1;

    if (takefirst) {
      __CPROVER_assert(filetickettake(&queue) == first,
                       "taking a result leaves its ticket live");
    }

    fileticketcomplete(&queue, second, secondresult);
    __CPROVER_assert(queue.count == 2 && queue.active == 0 &&
                         queue.bytes == firstbytes + secondbytes,
                     "both completed jobs remain charged");

    if (takefirst || (nondet_byte() & 1)) {
      release(
          fileticketcollect(&queue, fileticketfind(&queue, firstid), takefirst),
          firstid, firstresult);
    }
    else {
      release(fileticketcollect(&queue, fileticketfind(&queue, secondid), 0),
              secondid, secondresult);
      second = first;
      secondid = firstid;
      secondresult = firstresult;
      secondbytes = firstbytes;
    }
  }

  __CPROVER_assert(queue.jobs == second && !second->next && queue.count == 1 &&
                       queue.bytes == secondbytes && queue.active == 0 &&
                       queue.finished == second && !second->finished &&
                       queue.tail == &second->finished,
                   "collecting either result preserves the other queue entry");
  FileTicket **at = fileticketfind(&queue, secondid);
  __CPROVER_assert(!fileticketcollect(&queue, at, 1),
                   "finish requires that take returned the ticket");
  __CPROVER_assert(filetickettake(&queue) == second && !filetickettake(&queue),
                   "the remaining completion is taken once");
  release(fileticketcollect(&queue, at, 1), secondid, secondresult);
  checkempty(&queue);
}

int main (void) {
  provecancel();
  proveorder();

  return 0;
}
