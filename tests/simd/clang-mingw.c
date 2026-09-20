/* Keep the normal Windows compiler process boundary: this is a native exe,
 * not a shell alias or an MSVC-targeting clang invocation. */
#include <process.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* _spawnv joins these strings into a command line without escaping them. */
static char *quote_argument(const char *value) {
    size_t length = strlen(value), slashes = 0;
    if (length > (SIZE_MAX - 3) / 2) return NULL;
    char *quoted = malloc(length * 2 + 3);
    if (!quoted) return NULL;
    char *out = quoted;
    *out++ = '"';
    for (const char *in = value; *in; ++in) {
        if (*in == '\\') {
            ++slashes;
            continue;
        }
        size_t count = *in == '"' ? slashes * 2 + 1 : slashes;
        while (count--) *out++ = '\\';
        *out++ = *in;
        slashes = 0;
    }
    while (slashes--) { *out++ = '\\'; *out++ = '\\'; }
    *out++ = '"';
    *out = '\0';
    return quoted;
}

int main(int argc, char **argv) {
    const char *clang = getenv("NUPP_SIMD_CLANG");
    const char *root = getenv("NUPP_SIMD_GNU_ROOT");
    const char *target = getenv("NUPP_SIMD_GNU_TARGET");
    if (!clang || !root || !target) {
        fputs("Missing SIMD MinGW compiler configuration\n", stderr);
        return 2;
    }
    char **args = calloc((size_t)argc + 4, sizeof(*args));
    char *sysroot = malloc(strlen(root) + 12);
    char *triple = malloc(strlen(target) + 10);
    if (!args || !sysroot || !triple) return 2;
    sprintf(sysroot, "--sysroot=%s", root);
    sprintf(triple, "--target=%s", target);
    args[0] = (char *)clang;
    args[1] = triple;
    args[2] = sysroot;
    for (int i = 1; i < argc; ++i) args[i + 2] = argv[i];
    for (int i = 0; i < argc + 2; ++i) {
        char *quoted = quote_argument(args[i]);
        if (!quoted) {
            for (int j = 0; j < i; ++j) free(args[j]);
            free(args);
            free(sysroot);
            free(triple);
            return 2;
        }
        args[i] = quoted;
    }
    intptr_t result = _spawnv(_P_WAIT, clang, (const char *const *)args);
    if (result == -1) perror("clang-mingw");
    for (int i = 0; i < argc + 2; ++i) free(args[i]);
    free(args);
    free(sysroot);
    free(triple);
    return result == -1 ? 2 : (int)result;
}
