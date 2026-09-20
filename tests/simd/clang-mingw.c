/* Keep the normal Windows compiler process boundary: this is a native exe,
 * not a shell alias or an MSVC-targeting clang invocation. */
#include <process.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

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
    intptr_t result = _spawnv(_P_WAIT, clang, (const char *const *)args);
    if (result == -1) perror("clang-mingw");
    free(args);
    free(sysroot);
    free(triple);
    return result == -1 ? 2 : (int)result;
}
