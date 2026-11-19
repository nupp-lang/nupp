/* The libuv file queue runs for the Nupp entry. main.c passes these six
 * functions' addresses in the packet's import table for Nupp's reactor.
 *
 * A job copies its bytes in on submission and out on finishing, so a worker
 * thread never touches Nupp memory. Every function answers a negative errno,
 * as a uint64, when it fails. */

#ifndef NUPP_CORE_TRANSPORT_H
#define NUPP_CORE_TRANSPORT_H

#include <stdint.h>

/* The work a job does, and what its word and bytes are. */
enum nuppiokind {
  NUPP_IO_OPEN = 1, /* bytes: the path; word: flags, with the mode above */
  NUPP_IO_READ = 2, /* word: the descriptor; bytes: how many to read */
  NUPP_IO_WRITE = 3, /* word: the descriptor; bytes: what to write */
};

/* Sets the active job limit once and returns the read end of the completion
 * pipe. Later calls return the same descriptor. */
uint64_t nuppiostart (uint64_t threads);

/* Queues a job and answers its ticket. */
uint64_t nuppiosubmit (uint64_t kind, uint64_t word, uint64_t base,
                       uint64_t bytes);

/* Answers the ticket of a finished job not yet taken, or zero if none. */
uint64_t nuppiotake (void);

/* Answers a taken job's result, copying at most room bytes a read produced
 * to out, and forgets the ticket. */
uint64_t nuppiofinish (uint64_t ticket, uint64_t out, uint64_t room);

/* Withdraws a job before native submission and returns 1. Otherwise returns
 * 0 and retains the job until its callback and collection. */
uint64_t nuppiocancel (uint64_t ticket);

/* Waits for a job to finish, answers its result, and forgets the ticket. */
uint64_t nuppiosettle (uint64_t ticket);

#endif
