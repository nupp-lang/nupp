#include "nupp.h"

#include <stdio.h>
#include <stdlib.h>

static int report(nupp_status status, nupp_error *error) {
    if (status == NUPP_STATUS_OK) {
        return 0;
    }
    fprintf(stderr, "nupp: %s\n", error ? nupp_error_message(error) : "unknown error");
    nupp_error_free(error);
    return 1;
}

static unsigned char *read_all(const char *path, size_t *length) {
    FILE *file = fopen(path, "rb");
    unsigned char *bytes;
    long end;
    if (!file || fseek(file, 0, SEEK_END) != 0 || (end = ftell(file)) < 0 ||
        fseek(file, 0, SEEK_SET) != 0) {
        if (file) fclose(file);
        return NULL;
    }
    bytes = (unsigned char *)malloc((size_t)end);
    if (end != 0 && (!bytes || fread(bytes, 1, (size_t)end, file) != (size_t)end)) {
        free(bytes);
        fclose(file);
        return NULL;
    }
    fclose(file);
    *length = (size_t)end;
    return bytes;
}

int main(int argc, char **argv) {
    nupp_runtime *runtime = NULL;
    nupp_component *component = NULL;
    nupp_handle *answer = NULL;
    nupp_error *error = NULL;
    nupp_config config;
    nupp_value argument = {0};
    nupp_value result = {0};
    unsigned char *bytes;
    size_t length = 0;
    size_t result_count = 0;
    nupp_status status;
    int failed = 1;

    if (argc != 2 || !(bytes = read_all(argv[1], &length))) {
        fprintf(stderr, "usage: %s COMPONENT.nuppc\n", argv[0]);
        return 2;
    }
    nupp_config_init(&config);
    status = nupp_runtime_new(&config, &runtime, &error);
    if (report(status, error)) goto done;
    error = NULL;
    status = nupp_component_load(runtime, bytes, length, argv[1], &component, &error);
    if (report(status, error)) goto done;
    error = NULL;
    status = nupp_export_find(runtime, component, "game.answer", &answer, &error);
    if (report(status, error)) goto done;

    argument.kind = NUPP_VALUE_NUMBER;
    argument.number = 41.0;
    error = NULL;
    status = nupp_call(runtime, answer, &argument, 1, &result, 1, &result_count, &error);
    if (report(status, error)) goto done;
    if (result_count != 1 || result.kind != NUPP_VALUE_NUMBER) {
        fprintf(stderr, "nupp: game.answer returned an unexpected value\n");
        goto done;
    }
    printf("game.answer(41) = %.0f\n", result.number);

    error = NULL;
    status = nupp_component_start(runtime, component, 0, NULL, &error);
    if (report(status, error)) goto done;
    failed = 0;

done:
    error = NULL;
    nupp_value_release(runtime, &result, &error);
    nupp_error_free(error);
    error = NULL;
    nupp_handle_release(runtime, answer, &error);
    nupp_error_free(error);
    nupp_component_release(component);
    free(bytes);
    if (runtime) {
        error = NULL;
        nupp_runtime_shutdown(runtime, &error);
        nupp_error_free(error);
        nupp_runtime_free(runtime);
    }
    return failed;
}
