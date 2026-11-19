/* The entropy failure guard (catalog-entropy-failure). The guest runner
 * builds this file with cc and inserts it with DYLD_INSERT_LIBRARIES, so the
 * getentropy the guest finds by name is this one. It fails the guard's one
 * request of a known size, after writing part of it, with EACCES; every
 * other request is the C library's.
 *
 * The partial write is the point: a caller that trusted the bytes of a
 * failed request would hand them out, and the guard can see them. */

#include <dlfcn.h>
#include <errno.h>
#include <stddef.h>
#include <string.h>

/* The size of the one request the guard makes, which no other caller in the
 * guest asks for, and how many of its bytes are written before it fails. */
#define GUARDED_REQUEST_BYTES 64
#define BYTES_WRITTEN_BEFORE_FAILURE 17

/* The byte the partial write fills with, recognizable in a leaked buffer. */
#define PARTIAL_WRITE_BYTE 0xA5

typedef int (*getentropyfunction)(void *buffer, size_t size);

int getentropy (void *buffer, size_t size) {
  if (size == GUARDED_REQUEST_BYTES) {
    memset(buffer, PARTIAL_WRITE_BYTE, BYTES_WRITTEN_BEFORE_FAILURE);
    errno = EACCES;

    return -1;
  }

  getentropyfunction real = (getentropyfunction)dlsym(RTLD_NEXT, "getentropy");

  return real(buffer, size);
}
