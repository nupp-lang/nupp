/*
 * Small modules the embedding tests register in process, one per library,
 * chosen when the library is built:
 *
 * - FIXTURE_NUMERIC: `numeric.boundary`, whose functions answer their argument
 *   unchanged, or a fixed number, so the VM's checks at both ends are what
 *   the tests see.
 * - FIXTURE_UNSAVED: `demo.unsaved`, a resource type without save hooks.
 * - FIXTURE_NAMED: `demo.named`, a function whose result is a named record
 *   type the boundary cannot check.
 */
#include "nupp_extension.h"

#include <stdlib.h>

#define UNUSED (void)host, (void)call, (void)self, (void)data, (void)args, (void)nargs, (void)results, (void)nresults

#if defined(FIXTURE_NUMERIC)

static nupp_status echo(const nupp_host *host, nupp_call *call, void *self, void *data, const nupp_slot *args,
                        size_t nargs, nupp_slot *results, size_t nresults) {
    UNUSED;
    results[0] = args[0];
    return NUPP_OK;
}

static nupp_status narrow_result(const nupp_host *host, nupp_call *call, void *self, void *data, const nupp_slot *args,
                                 size_t nargs, nupp_slot *results, size_t nresults) {
    UNUSED;
    results[0].kind = NUPP_NUMBER;
    results[0].as.number = 0.1;
    return NUPP_OK;
}

static nupp_status float_result(const nupp_host *host, nupp_call *call, void *self, void *data, const nupp_slot *args,
                                size_t nargs, nupp_slot *results, size_t nresults) {
    UNUSED;
    results[0].kind = NUPP_INTEGER;
    results[0].as.integer = 9007199254740993LL;
    return NUPP_OK;
}

static const nupp_function_entry functions[] = {
    {"number", "function(number): number", echo, NULL, 0, 0},
    {"integer", "function(integer): int64", echo, NULL, 0, 0},
    {"float", "function(float): float64", echo, NULL, 0, 0},
    {"float32", "function(float32): float32", echo, NULL, 0, 0},
    {"narrowResult", "function(): float32", narrow_result, NULL, 0, 0},
    {"floatResult", "function(): float64", float_result, NULL, 0, 0},
};
#define MODULE "numeric.boundary"
#define TYPES NULL
#define TYPE_COUNT 0

#elif defined(FIXTURE_UNSAVED)

static nupp_status make(const nupp_host *host, nupp_call *call, void *self, void *data, const nupp_slot *args,
                        size_t nargs, nupp_slot *results, size_t nresults) {
    UNUSED;
    unsigned char *scratch = malloc(3);
    if (!scratch) return host->raise(call, "out of memory", 13);
    scratch[0] = 1, scratch[1] = 2, scratch[2] = 3;
    nupp_handle handle = host->new_resource(call, 0, scratch);
    if (!handle) {
        free(scratch);
        return NUPP_ERROR;
    }
    results[0].kind = NUPP_HANDLE;
    results[0].as.handle = handle;
    return NUPP_OK;
}

static void drop_scratch(void *self, void *type_data, void *data) {
    (void)self, (void)type_data;
    free(data);
}

static const nupp_function_entry functions[] = {
    {"make", "function(): any", make, NULL, 0, 0},
};
static const nupp_resource_type types[] = {
    {"Scratch", NULL, drop_scratch, NULL, NULL},
};
#define MODULE "demo.unsaved"
#define TYPES types
#define TYPE_COUNT 1

#elif defined(FIXTURE_NAMED)

static nupp_status point(const nupp_host *host, nupp_call *call, void *self, void *data, const nupp_slot *args,
                         size_t nargs, nupp_slot *results, size_t nresults) {
    UNUSED;
    return NUPP_OK;
}

static const nupp_function_entry functions[] = {
    {"point", "function(): Point", point, NULL, 0, 0},
};
#define MODULE "demo.named"
#define TYPES NULL
#define TYPE_COUNT 0

#else
#error "define FIXTURE_NUMERIC, FIXTURE_UNSAVED or FIXTURE_NAMED"
#endif

static const nupp_extension extension = {
    NUPP_EXTENSION_ABI_VERSION,
    sizeof(nupp_extension),
    MODULE,
    NUPP_EXTENSION_TARGET,
    functions,
    sizeof functions / sizeof functions[0],
    TYPES,
    TYPE_COUNT,
    NULL,
    NULL,
};

const nupp_extension *NUPP_EXTENSION_ENTRY(void) { return &extension; }
