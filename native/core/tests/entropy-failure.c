// The entropy failure guard (catalog-entropy-failure): the C library's
// getentropy, as the guest finds it by name, fails the guard's one 64-byte
// request after writing part of it, with EACCES; every other request is the
// C library's. The guest runner builds this with cc and inserts it with
// DYLD_INSERT_LIBRARIES.
#include <dlfcn.h>
#include <errno.h>
#include <stddef.h>
#include <string.h>

#define GUARDED 64
#define WRITTEN 17

int getentropy(void *buffer, size_t size) {
    if (size == GUARDED) {
        memset(buffer, 0xA5, WRITTEN);
        errno = EACCES;
        return -1;
    }
    int (*real)(void *, size_t) = (int (*)(void *, size_t))dlsym(RTLD_NEXT, "getentropy");
    return real(buffer, size);
}
