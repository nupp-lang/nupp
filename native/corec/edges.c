/* edges.c: the native core's routines that are not Nupp: the foreign walk's
   collector, called back through a libffi closure. */
#include "servicescope.h"
#include "nuppedges.h"

/* Appends a walked item's words to the record the walk fills: its userdata
   holds the record's address, the expected self, the item's words and the
   failure flag. */
void nupp_collector(void *cif, void *ret, void **args, void *userdata) {
    (void)cif;
    uint64_t *user = (uint64_t *)userdata;
    uint64_t result = 0;
    uint64_t (*self)(void) = (uint64_t (*)(void))(uintptr_t)user[4];
    const uint64_t *item = (const uint64_t *)args[0];
    uint64_t *record = *(uint64_t **)args[2];

    if (self() != user[3] || record == NULL || record[3] != user[5]) {
        user[6] = 1;
        *(uint64_t *)ret = 0;
        return;
    }

    uint64_t words = record[3];
    uint64_t count = record[1];

    if (count < record[2]) {
        uint64_t *destination = (uint64_t *)(uintptr_t)record[0] + count * words;

        for (uint64_t k = 0; k < words; ++k) {
            destination[k] = item[k];
        }

        record[1] = count + 1;
        result = 1;
    }

    *(uint64_t *)ret = result;
}

/* The directory the bridge found the runtime's artifact in (main.c). */
extern const char *nupp_core_artifact_directory;

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

void *nupp_resolve(const char *library, const char *symbol) {
    void *handle = RTLD_DEFAULT;
    char path[4096];

    if (library[0] == '@') {
        const char *relative = library + 1;

        while (*relative == '/') {
            ++relative;
        }

        snprintf(path, sizeof path, "%s/%s", nupp_core_artifact_directory, relative);
        handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    }
    else if (library[0] != '\0') {
        handle = dlopen(library, RTLD_NOW | RTLD_LOCAL);
    }

    void *found = handle != NULL ? dlsym(handle, symbol) : NULL;

    if (found == NULL) {
        fprintf(stderr, "nupp-core: cannot resolve %s in %s\n", symbol, library);
        abort();
    }

    return found;
}
