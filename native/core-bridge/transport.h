/* The I/O pool io.c runs for the Nupp code main.c enters. main.c passes these
 * six functions' addresses in the packet's import table, and the Nupp reactor
 * calls them; nothing in C calls them but tests/core/bridge-contracts.c.
 *
 * A job copies its bytes in on submission and out on finishing, so a worker
 * thread never touches Nupp memory. Every function answers a negative errno,
 * as a uint64, when it fails. */
#ifndef NUPP_CORE_TRANSPORT_H
#define NUPP_CORE_TRANSPORT_H
#include <stdint.h>

/* The work a job does, and what its word and bytes are. */
enum nupp_io_kind {
  NUPP_IO_OPEN = 1, /* bytes: the path; word: flags, with the mode above */
  NUPP_IO_READ = 2, /* word: the descriptor; bytes: how many to read */
  NUPP_IO_WRITE = 3, /* word: the descriptor; bytes: what to write */
};

/* Starts the workers once and answers the read end of the pipe that becomes
 * readable when a job finishes. Later calls answer the same descriptor. */
uint64_t nupp_io_start (uint64_t threads);

/* Queues a job and answers its ticket. */
uint64_t nupp_io_submit (uint64_t kind, uint64_t word, uint64_t base,
                         uint64_t bytes);

/* Answers the ticket of a finished job not yet taken, or zero if none. */
uint64_t nupp_io_take (void);

/* Answers a taken job's result, copying at most room bytes a read produced
 * to out, and forgets the ticket. */
uint64_t nupp_io_finish (uint64_t ticket, uint64_t out, uint64_t room);

/* Withdraws a job no worker has started, answering 1, or answers 0. */
uint64_t nupp_io_cancel (uint64_t ticket);

/* Waits for a job to finish, answers its result, and forgets the ticket. */
uint64_t nupp_io_settle (uint64_t ticket);

#endif
