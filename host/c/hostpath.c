/* Where this executable is.
 *
 * Three platforms, three answers, and none of them is `argv[0]`: that is
 * whatever the caller decided to say, and a stub reading its own payload from a
 * file somebody else named would run somebody else's program.
 */

#include "nupp_host.h"

#include <stdlib.h>
#include <string.h>

#if defined(__APPLE__)
#   include <mach-o/dyld.h>
#elif defined(_WIN32)
#   include <windows.h>
#else
#   include <unistd.h>
#endif

char *nupp_host_executable_path(void) {
#if defined(__APPLE__)
    uint32_t capacity = 1024;
    char *path = malloc(capacity);
    if (path == NULL) {
        return NULL;
    }
    if (_NSGetExecutablePath(path, &capacity) != 0) {
        /* The call reports the size it wanted, so the second attempt fits. */
        char *grown = realloc(path, capacity);
        if (grown == NULL) {
            free(path);
            return NULL;
        }
        path = grown;
        if (_NSGetExecutablePath(path, &capacity) != 0) {
            free(path);
            return NULL;
        }
    }
    return path;
#elif defined(_WIN32)
    DWORD capacity = 1024;
    for (;;) {
        wchar_t *wide = malloc(capacity * sizeof *wide);
        DWORD written;
        if (wide == NULL) {
            return NULL;
        }
        written = GetModuleFileNameW(NULL, wide, capacity);
        if (written == 0) {
            free(wide);
            return NULL;
        }
        if (written < capacity) {
            int needed = WideCharToMultiByte(CP_UTF8, 0, wide, -1, NULL, 0, NULL, NULL);
            char *path = needed > 0 ? malloc((size_t)needed) : NULL;
            if (path != NULL) {
                WideCharToMultiByte(CP_UTF8, 0, wide, -1, path, needed, NULL, NULL);
            }
            free(wide);
            return path;
        }
        free(wide);
        if (capacity > (1u << 16)) {
            return NULL;
        }
        capacity *= 2;
    }
#else
    size_t capacity = 1024;
    for (;;) {
        char *path = malloc(capacity);
        ssize_t written;
        if (path == NULL) {
            return NULL;
        }
        written = readlink("/proc/self/exe", path, capacity - 1);
        if (written < 0) {
            free(path);
            return NULL;
        }
        if ((size_t)written < capacity - 1) {
            path[written] = '\0';
            return path;
        }
        free(path);
        if (capacity > (1u << 20)) {
            return NULL;
        }
        capacity *= 2;
    }
#endif
}
