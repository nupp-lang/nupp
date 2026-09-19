/* Hot reload driven from a host's own loop.
 *
 * Usage: reload COMPILER_DIR PROJECT_DIR ENTRY.nupp
 *
 * COMPILER_DIR is a directory of the compiler's Lua modules -- what
 * `nupp build --target bootstrapCompiler` writes. The entry is compiled in
 * watch mode, `game.update` is taken once, and every poll below is a commit
 * boundary this program chose: edit the entry while it runs and the next poll
 * publishes the new body to the handle already held. */

#include "nupp.h"

#include <stdio.h>
#include <string.h>

static int report(nupp_status status, nupp_error *error) {
    if (status == NUPP_STATUS_OK) {
        return 0;
    }
    fprintf(stderr, "nupp: %s\n", error ? nupp_error_message(error) : "unknown error");
    nupp_error_free(error);
    return 1;
}

static const char *verdict_name(uint32_t verdict) {
    switch (verdict) {
        case NUPP_RELOAD_COMMITTED: return "committed";
        case NUPP_RELOAD_REJECTED: return "rejected";
        case NUPP_RELOAD_RESTART_REQUIRED: return "restart required";
        default: return "no change";
    }
}

int main(int argc, char **argv) {
    nupp_runtime *runtime = NULL;
    nupp_reload *reload = NULL;
    nupp_handle *update = NULL;
    nupp_error *error = NULL;
    nupp_config config;
    nupp_reload_config reloading;
    nupp_value result = {0};
    size_t result_count = 0;
    uint32_t verdict = 0;
    uint64_t generation = 0;
    nupp_status status;
    int failed = 1;
    int frame;

    if (argc != 4) {
        fprintf(stderr, "usage: %s COMPILER_DIR PROJECT_DIR ENTRY.nupp\n", argv[0]);
        return 2;
    }
    nupp_config_init(&config);
    status = nupp_runtime_new(&config, &runtime, &error);
    if (report(status, error)) goto done;

    nupp_reload_config_init(&reloading);
    reloading.compiler_path = argv[1];
    reloading.root = argv[2];
    reloading.entry = argv[3];
    error = NULL;
    status = nupp_reload_open(runtime, &reloading, &reload, &error);
    if (report(status, error)) goto done;

    /* Taken once. A watch build dispatches a named function through a slot, so
     * this handle keeps working after every commit below. */
    error = NULL;
    status = nupp_reload_find(runtime, reload, "update", &update, &error);
    if (report(status, error)) goto done;

    for (frame = 0; frame < 3; ++frame) {
        /* The host's own safe point: no frame is half drawn here. */
        error = NULL;
        status = nupp_reload_poll(runtime, reload, &verdict, &generation, &error);
        if (report(status, error)) goto done;
        printf("poll %d: %s, generation %llu\n", frame, verdict_name(verdict),
            (unsigned long long)generation);
        if (nupp_reload_message(reload)) {
            printf("  %s\n", nupp_reload_message(reload));
        }

        error = NULL;
        result_count = 0;
        status = nupp_call(runtime, update, NULL, 0, &result, 1, &result_count, &error);
        if (report(status, error)) goto done;
        if (result_count == 1 && result.kind == NUPP_VALUE_NUMBER) {
            printf("  update() = %.0f\n", result.number);
        }
        error = NULL;
        nupp_value_release(runtime, &result, &error);
        nupp_error_free(error);

        if (frame == 0) {
            printf("edit %s/%s now; polls continue\n", argv[2], argv[3]);
            fflush(stdout);
            getchar();
        }
    }
    failed = 0;

done:
    if (reload) {
        error = NULL;
        nupp_reload_close(runtime, reload, failed == 0, &error);
        nupp_error_free(error);
        nupp_reload_free(reload);
    }
    error = NULL;
    nupp_handle_release(runtime, update, &error);
    nupp_error_free(error);
    if (runtime) {
        error = NULL;
        nupp_runtime_shutdown(runtime, &error);
        nupp_error_free(error);
        nupp_runtime_free(runtime);
    }
    return failed;
}
