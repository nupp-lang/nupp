/* Native oracle for the library loader and callback tests. No VM code lives here. */
#ifndef _WIN32
#define _GNU_SOURCE
#include <dlfcn.h>
#include <pthread.h>
#include <stdio.h>
#endif
#include <stddef.h>
#include <stdint.h>

#ifdef _WIN32
#define API __declspec(dllexport)
#else
#define API __attribute__((visibility("default")))
#endif

API int32_t loader_add(int32_t a, int32_t b) { return a + b; }
API int32_t loader_twice(int32_t value) { return value * 2; }
API int32_t loader_apply(int32_t (*callback)(int32_t, int32_t), int32_t a, int32_t b) {
    return callback(a, b);
}
API double loader_apply_double(double (*callback)(double), double value) { return callback(value); }

static int32_t (*kept)(int32_t, int32_t);
API void loader_keep(int32_t (*callback)(int32_t, int32_t)) { kept = callback; }
API int32_t loader_call_kept(int32_t a, int32_t b) { return kept ? kept(a, b) : -1; }
API uint64_t loader_kept_address(void) { return (uint64_t)(uintptr_t)kept; }

static int32_t context_value = 40;
API void *loader_context(void) { return &context_value; }
API int32_t loader_read(const void *pointer) { return *(const int32_t *)pointer; }
API int32_t loader_with_context(int32_t (*callback)(void *, int32_t), void *context, int32_t value) {
    return callback(context, value);
}
API void *loader_produce(void *(*callback)(int32_t), int32_t value) { return callback(value); }

#ifndef _WIN32
struct ThreadCall {
    int32_t (*callback)(int32_t, int32_t);
    int32_t result;
};
static void *loader_thread(void *data) {
    struct ThreadCall *call = data;
    call->result = call->callback(20, 22);
    return NULL;
}
/* Calls the callback from a thread the VM did not create, as a C library's worker would. */
API int32_t loader_call_from_thread(int32_t (*callback)(int32_t, int32_t)) {
    struct ThreadCall call = {callback, -1};
    pthread_t thread;
    if (pthread_create(&thread, NULL, loader_thread, &call) != 0) return -2;
    pthread_join(thread, NULL);
    return call.result;
}

/* Leaves `<library path>.unloaded` behind when the platform unloads this library. */
__attribute__((destructor)) static void loader_unloaded(void) {
    Dl_info info;
    if (dladdr((void *)&loader_add, &info) && info.dli_fname) {
        char path[4096];
        snprintf(path, sizeof path, "%s.unloaded", info.dli_fname);
        FILE *file = fopen(path, "w");
        if (file) fclose(file);
    }
}
#endif
