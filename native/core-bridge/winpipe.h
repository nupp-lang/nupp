/**
 * @file
 * @brief Windows child pipe ends on the owning libuv loop.
 */

#ifndef NUPP_CORE_WINPIPE_H
#define NUPP_CORE_WINPIPE_H

#include <stdint.h>

/** True for the reserved synthetic descriptor range, even after close. */
int nuppwinpipekey (int64_t descriptor);

/** Transfers the supplied CRT fd on success and returns its readiness key. */
int nuppwinpipeopen (int fd, int writing);

/** Read or write one copied chunk, using CRT errno and -1 on failure. */
int64_t nuppwinpiperead (int64_t descriptor, void *bytes, uint64_t size);
int64_t nuppwinpipewrite (int64_t descriptor, const void *bytes, uint64_t size);

/** Retires the key immediately and lets an accepted write finish. */
int nuppwinpipeclose (int64_t descriptor);

/** Sets a poller's interest on a synthetic key. Returns negated errno. */
int nuppwinpipearm (uint64_t poller, int64_t descriptor, int interest);

/** Peeks or consumes the next packed descriptor event for this poller. */
int64_t nuppwinpipeevent (uint64_t poller, int take);

/** Removes watches for a closed poller. */
void nuppwinpipeforget (uint64_t poller);

/** Advances deferred close after a loop turn. */
void nuppwinpipesweep (void);

/** Cancels all remaining native pipe operations for loop shutdown. */
void nuppwinpipeshutdown (void);
int nuppwinpipepending (void);

#endif
