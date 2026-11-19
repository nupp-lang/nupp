/**
 * @file
 * @brief Owner-thread file ticket accounting and completion queue.
 */

#ifndef NUPP_CORE_FILE_TICKETS_H
#define NUPP_CORE_FILE_TICKETS_H

#include <stddef.h>
#include <stdint.h>

/** Lifecycle state embedded as the first member of the reactor's native job. */
typedef struct FileTicket {
  uint64_t id;
  int64_t result;
  size_t count;
  int submitted, done, taken;
  struct FileTicket *next, *finished;
} FileTicket;

/** Owns admitted tickets and the FIFO of completions awaiting collection. */
typedef struct {
  FileTicket *jobs, *finished, **tail;
  size_t count, bytes, active;
} FileTickets;

/** Initializes the tail of an empty, zero-initialized queue. */
static inline void fileticketsinit (FileTickets *queue) {
  queue->tail = &queue->finished;
}

/** Finds a live ticket's link, or the append position for an absent ID. */
static inline FileTicket **fileticketfind (FileTickets *queue, uint64_t id) {
  FileTicket **at = &queue->jobs;

  while (*at && (*at)->id != id) {
    at = &(*at)->next;
  }

  return at;
}

/** Admits a fresh, zero-initialized ticket (apart from its ID and byte count).
 * @pre The ticket ID is nonzero and unique in the queue. The caller has
 * checked the ticket count and byte budgets.
 */
static inline void fileticketadmit (FileTickets *queue, FileTicket *ticket) {
  *fileticketfind(queue, 0) = ticket;
  queue->count++;
  queue->bytes += ticket->count;
}

/** Hands a queued ticket to the native submit path.
 * @pre The ticket is live and has never been submitted.
 */
static inline void fileticketsubmit (FileTickets *queue, FileTicket *ticket) {
  ticket->submitted = 1;
  queue->active++;
}

/** Appends the result of a submitted ticket.
 * @pre The native submit path supplies exactly one result per submission.
 */
static inline void fileticketcomplete (FileTickets *queue, FileTicket *ticket,
                                       int64_t result) {
  ticket->result = result;
  queue->active--;
  ticket->done = 1;
  *queue->tail = ticket;
  queue->tail = &ticket->finished;
}

/** Takes the next completion while leaving its ticket owned by the queue. */
static inline FileTicket *filetickettake (FileTickets *queue) {
  FileTicket *ticket = queue->finished;

  if (ticket) {
    queue->finished = ticket->finished;
    ticket->finished = NULL;

    if (!queue->finished) {
      queue->tail = &queue->finished;
    }

    ticket->taken = 1;
  }

  return ticket;
}

/** Detaches a collectable or unsubmitted ticket and refunds its budget. */
static inline FileTicket *fileticketdetach (FileTickets *queue,
                                            FileTicket **at) {
  FileTicket *ticket = *at;
  *at = ticket->next;
  queue->count--;
  queue->bytes -= ticket->count;

  return ticket;
}

/** Transfers an unsubmitted ticket to the caller for disposal.
 * @pre at is the link returned by fileticketfind(). Submitted tickets stay
 * live.
 */
static inline FileTicket *fileticketcancel (FileTickets *queue,
                                            FileTicket **at) {
  return *at && !(*at)->submitted ? fileticketdetach(queue, at) : NULL;
}

/** Transfers a finished ticket to the caller, including an untaken result
 * when settling.
 * @pre at is the link returned by fileticketfind().
 */
static inline FileTicket *
fileticketcollect (FileTickets *queue, FileTicket **at, int requiretaken) {
  FileTicket *ticket = *at;

  if (!ticket || !ticket->done || (requiretaken && !ticket->taken)) {
    return NULL;
  }

  if (!ticket->taken) {
    FileTicket **queued = &queue->finished;

    while (*queued != ticket) {
      queued = &(*queued)->finished;
    }

    *queued = ticket->finished;

    if (!*queued) {
      queue->tail = queued;
    }
  }

  return fileticketdetach(queue, at);
}

#endif
