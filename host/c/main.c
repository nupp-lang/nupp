/* The Nupp stub: an executable that runs a payload appended to itself.
 *
 * With a payload it is that program and nothing else. Without one it is a plain
 * Lua interpreter over the file named as its first argument, which is what
 * makes a stub testable before anything has been stamped into it and usable
 * while the thing that stamps is still being written.
 */

#include "nupp_host.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define EXIT_USAGE 2

/* Loads and runs one chunk, with `arg` set from what follows it. */
static int execute(
    const uint8_t *chunk, size_t length, const char *name,
    const char *executable, int count, const char *const *arguments
) {
    char *problem = NULL;
    NuppRuntime *runtime = nupp_host_runtime_new(true, &problem);
    if (runtime == NULL) {
        fprintf(stderr, "nupp: %s\n", problem != NULL ? problem : "cannot create a Lua state");
        free(problem);
        return 1;
    }
    lua_pushstring(nupp_host_runtime_state(runtime), executable);
    lua_setfield(nupp_host_runtime_state(runtime), LUA_GLOBALSINDEX, "__NUPP_EXECUTABLE");
    problem = nupp_host_set_arguments(runtime, count, arguments);
    if (problem == NULL) {
        problem = nupp_host_run(runtime, chunk, length, name);
    }
    if (problem != NULL) {
        fprintf(stderr, "%s\n", problem);
        free(problem);
        nupp_host_runtime_free(runtime);
        return 1;
    }
    nupp_host_runtime_free(runtime);
    return 0;
}

/* No payload: run the Lua file named first, so a stub is useful on its own. */
static int interpret(int argc, char **argv, const char *executable) {
    FILE *file;
    long size;
    uint8_t *chunk;
    char name[1024];
    int status;

    if (argc < 2) {
        fprintf(stderr, "nupp-host: no payload; usage: %s <file.lua> [args...]\n", argv[0]);
        return EXIT_USAGE;
    }
    file = fopen(argv[1], "rb");
    if (file == NULL) {
        fprintf(stderr, "nupp-host: cannot read %s\n", argv[1]);
        return 1;
    }
    if (fseek(file, 0, SEEK_END) != 0 || (size = ftell(file)) < 0
        || fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        fprintf(stderr, "nupp-host: cannot read %s\n", argv[1]);
        return 1;
    }
    chunk = malloc((size_t)size + 1);
    if (chunk == NULL || fread(chunk, 1, (size_t)size, file) != (size_t)size) {
        free(chunk);
        fclose(file);
        fprintf(stderr, "nupp-host: cannot read %s\n", argv[1]);
        return 1;
    }
    fclose(file);
    snprintf(name, sizeof name, "@%s", argv[1]);
    status = execute(
        chunk, (size_t)size, name, executable, argc - 2,
        (const char *const *)argv + 2);
    free(chunk);
    return status;
}

int main(int argc, char **argv) {
    char *executable;
    uint8_t *payload = NULL;
    size_t length = 0;
    char *problem = NULL;
    char name[1024];
    int status;

#if NUPP_FEATURE_WORKERS
    nupp_host_mcode_reserve();
#endif

    executable = nupp_host_executable_path();
    if (executable == NULL) {
        /* Everything below needs to read this file. A stub that cannot find
         * itself cannot know whether it has a payload, and guessing from
         * `argv[0]` is how you end up running the wrong file. */
        fprintf(stderr, "nupp: cannot locate this executable\n");
        return 1;
    }

    switch (nupp_host_read_payload(executable, &payload, &length, &problem)) {
        case NUPP_PAYLOAD_FOUND:
#if NUPP_FEATURE_WORKERS
            nupp_host_workers_set_payload(payload, length);
#endif
            snprintf(name, sizeof name, "@%s", executable);
            status = execute(
                payload, length, name, executable, argc - 1,
                (const char *const *)argv + 1);
            free(payload);
            free(executable);
            return status;

        case NUPP_PAYLOAD_NONE:
            status = interpret(argc, argv, executable);
            free(executable);
            return status;

        default:
            fprintf(stderr, "nupp: %s\n", problem != NULL ? problem : "cannot read the payload");
            free(problem);
            free(executable);
            return 1;
    }
}
