/* What the host's own files share.
 *
 * The public surface is `host/include/nupp.h`, which an embedding application
 * includes and this implements. Nothing here appears there: a runtime, a
 * component and a handle are opaque on that side, and this is what they are.
 */

#ifndef NUPP_HOST_H
#define NUPP_HOST_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>

/* --- errors ------------------------------------------------------------- */

/* One failure, carried back to the caller as an owned object because a message
 * in shared storage cannot survive two runtimes failing at once. */
struct nupp_error {
    int status;
    int category;
    char *message;
    size_t length;
};

typedef struct nupp_error NuppHostError;

/* Fills `*out` when the caller asked for it, and answers the status either way,
 * so every failing path is one line. */
int nupp_host_fail(
    struct nupp_error **out, int status, int category, const char *format, ...);

/* --- the runtime -------------------------------------------------------- */

struct nupp_runtime;
typedef struct nupp_runtime NuppRuntime;

/* Creates a runtime around a new LuaJIT state, or around one the host owns. An
 * attached state is left open when the runtime shuts down. */
NuppRuntime *nupp_host_runtime_new(bool openLibraries, char **problem);
NuppRuntime *nupp_host_runtime_attach(lua_State *state, bool openLibraries, char **problem);

lua_State *nupp_host_runtime_state(NuppRuntime *runtime);
void nupp_host_runtime_free(NuppRuntime *runtime);
char *nupp_host_runtime_shutdown(NuppRuntime *runtime);

/* Every one of these answers NULL for success, or an owned message. The caller
 * frees it. */
char *nupp_host_run(NuppRuntime *runtime, const uint8_t *chunk, size_t length, const char *name);
char *nupp_host_set_arguments(NuppRuntime *runtime, int count, const char *const *arguments);
char *nupp_host_add_feature(NuppRuntime *runtime, const char *feature);
char *nupp_host_add_resource(
    NuppRuntime *runtime, const char *path, const void *bytes, size_t length);
char *nupp_host_preload(NuppRuntime *runtime, const char *module, lua_CFunction opener);

/* A component and a handle are named by a number rather than a pointer, so one
 * belonging to another runtime is refused rather than dereferenced. */
char *nupp_host_load_component(
    NuppRuntime *runtime, const uint8_t *bytes, size_t length, const char *name,
    uint64_t *component);
char *nupp_host_start_component(
    NuppRuntime *runtime, uint64_t component, int count, const char *const *arguments);
char *nupp_host_find_export(
    NuppRuntime *runtime, uint64_t component, const char *name, uint64_t *handle);
char *nupp_host_release_handle(NuppRuntime *runtime, uint64_t handle);
char *nupp_host_poll(NuppRuntime *runtime);
uint64_t nupp_host_runtime_id(const NuppRuntime *runtime);

/* One value crossing the managed call boundary. Mirrors `nupp_value` without
 * depending on the public header, which this side does not include. */
typedef enum {
    NUPP_HOST_NIL = 0,
    NUPP_HOST_BOOLEAN = 1,
    NUPP_HOST_NUMBER = 2,
    NUPP_HOST_STRING = 3,
    NUPP_HOST_BYTES = 4,
    NUPP_HOST_HANDLE = 5
} NuppHostKind;

typedef struct {
    NuppHostKind kind;
    bool boolean;
    double number;
    uint8_t *data;
    size_t length;
    uint64_t handle;
} NuppHostValue;

char *nupp_host_call(
    NuppRuntime *runtime, uint64_t callable,
    const NuppHostValue *arguments, size_t argumentCount,
    NuppHostValue **results, size_t *resultCount);

/* --- the payload -------------------------------------------------------- */

typedef enum {
    NUPP_PAYLOAD_NONE = 0,
    NUPP_PAYLOAD_FOUND = 1,
    NUPP_PAYLOAD_FAILED = 2
} NuppPayloadOutcome;

/* Reads the payload appended to `path`. On success the bytes are the caller's
 * to free; on failure `problem` is. */
NuppPayloadOutcome nupp_host_read_payload(
    const char *path, uint8_t **bytes, size_t *length, char **problem);

/* The first eight bytes of a payload's SHA-256, as the trailer records it. */
void nupp_host_digest_prefix(const uint8_t *bytes, size_t length, uint8_t out[8]);

/* Where this executable is, which is the only file the payload can be in.
 * Guessing from `argv[0]` is how a program ends up reading the wrong one. */
char *nupp_host_executable_path(void);

/* --- workers ------------------------------------------------------------ */

#if NUPP_FEATURE_WORKERS
int nupp_host_workers_open(lua_State *state);
void nupp_host_workers_set_payload(const uint8_t *bytes, size_t length);

/* Holds nearby address space for LuaJIT states created later, and gives it back
 * before the first worker state is made. */
void nupp_host_mcode_reserve(void);
void nupp_host_mcode_release(void);
#endif

#endif /* NUPP_HOST_H */
