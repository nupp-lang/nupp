#ifndef NUPP_H
#define NUPP_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32) && defined(NUPP_SHARED)
#  if defined(NUPP_BUILDING)
#    define NUPP_API __declspec(dllexport)
#  else
#    define NUPP_API __declspec(dllimport)
#  endif
#else
#  define NUPP_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct lua_State lua_State;
typedef int (*nupp_lua_CFunction)(lua_State *state);

typedef struct nupp_runtime nupp_runtime;
typedef struct nupp_component nupp_component;
typedef struct nupp_handle nupp_handle;
typedef struct nupp_error nupp_error;
typedef struct nupp_reload nupp_reload;

enum {
    NUPP_EMBED_ABI_VERSION = 1,
    NUPP_CONFIG_OPEN_LIBRARIES = 1,
    NUPP_RELOAD_STRICT = 1,
};

typedef enum nupp_status {
    NUPP_STATUS_OK = 0,
    NUPP_STATUS_INVALID_ARGUMENT = 1,
    NUPP_STATUS_INCOMPATIBLE = 2,
    NUPP_STATUS_RUNTIME = 3,
    NUPP_STATUS_BUFFER_TOO_SMALL = 4,
} nupp_status;

typedef enum nupp_error_category_code {
    NUPP_ERROR_CONFIGURATION = 1,
    NUPP_ERROR_COMPATIBILITY = 2,
    NUPP_ERROR_COMPONENT = 3,
    NUPP_ERROR_RUNTIME = 4,
} nupp_error_category_code;

typedef enum nupp_value_kind {
    NUPP_VALUE_NIL = 0,
    NUPP_VALUE_BOOLEAN = 1,
    NUPP_VALUE_NUMBER = 2,
    NUPP_VALUE_STRING = 3,
    NUPP_VALUE_BYTES = 4,
    NUPP_VALUE_HANDLE = 5,
} nupp_value_kind;

typedef struct nupp_value {
    uint32_t kind;
    int boolean;
    double number;
    unsigned char *data;
    size_t length;
    nupp_handle *handle;
} nupp_value;

typedef enum nupp_reload_verdict {
    NUPP_RELOAD_NO_CHANGE = 0,
    NUPP_RELOAD_COMMITTED = 1,
    NUPP_RELOAD_REJECTED = 2,
    NUPP_RELOAD_RESTART_REQUIRED = 3,
    NUPP_RELOAD_PREPARED = 4,
} nupp_reload_verdict;

typedef struct nupp_config {
    uint32_t size;
    uint32_t abi_version;
    uint32_t flags;
} nupp_config;

/* Development hot reload compiles the project while the program runs, so
 * `compiler_path` names a directory holding the compiler's own Lua modules --
 * what `nupp build --target bootstrapCompiler` writes. It may be null when the
 * state already reaches them. `root` defaults to the process's directory. */
typedef struct nupp_reload_config {
    uint32_t size;
    uint32_t flags;
    const char *compiler_path;
    const char *root;
    const char *entry;
} nupp_reload_config;

NUPP_API void nupp_config_init(nupp_config *config);

NUPP_API nupp_status nupp_runtime_new(
    const nupp_config *config,
    nupp_runtime **out,
    nupp_error **error
);

NUPP_API nupp_status nupp_runtime_attach(
    lua_State *state,
    const nupp_config *config,
    nupp_runtime **out,
    nupp_error **error
);

NUPP_API lua_State *nupp_runtime_lua_state(nupp_runtime *runtime);

NUPP_API nupp_status nupp_runtime_add_feature(
    nupp_runtime *runtime,
    const char *feature,
    nupp_error **error
);

NUPP_API nupp_status nupp_runtime_add_resource(
    nupp_runtime *runtime,
    const char *path,
    const void *bytes,
    size_t length,
    nupp_error **error
);

NUPP_API nupp_status nupp_runtime_preload(
    nupp_runtime *runtime,
    const char *module,
    nupp_lua_CFunction opener,
    nupp_error **error
);

/* Calls an AOT archive registrar with this runtime's Lua state and stores the
 * returned table under `key`. It must happen before a component using that
 * archive is loaded. */
NUPP_API nupp_status nupp_runtime_register_aot_builders(
    nupp_runtime *runtime,
    const char *key,
    nupp_lua_CFunction registrar,
    nupp_error **error
);

NUPP_API nupp_status nupp_component_load(
    nupp_runtime *runtime,
    const void *bytes,
    size_t length,
    const char *name,
    nupp_component **out,
    nupp_error **error
);

NUPP_API nupp_status nupp_component_start(
    nupp_runtime *runtime,
    const nupp_component *component,
    int argc,
    const char *const *argv,
    nupp_error **error
);

NUPP_API nupp_status nupp_export_find(
    nupp_runtime *runtime,
    const nupp_component *component,
    const char *name,
    nupp_handle **out,
    nupp_error **error
);

NUPP_API nupp_status nupp_call(
    nupp_runtime *runtime,
    const nupp_handle *callable,
    const nupp_value *arguments,
    size_t argument_count,
    nupp_value *results,
    size_t result_capacity,
    size_t *result_count,
    nupp_error **error
);

NUPP_API nupp_status nupp_handle_release(
    nupp_runtime *runtime,
    nupp_handle *handle,
    nupp_error **error
);

NUPP_API nupp_status nupp_value_release(
    nupp_runtime *runtime,
    nupp_value *value,
    nupp_error **error
);

NUPP_API nupp_status nupp_runtime_shutdown(
    nupp_runtime *runtime,
    nupp_error **error
);

NUPP_API nupp_status nupp_runtime_poll(
    nupp_runtime *runtime,
    nupp_error **error
);

NUPP_API void nupp_reload_config_init(nupp_reload_config *config);

/* Builds `entry` in watch mode, runs its chunk, and leaves the session open.
 * Development only: a watch build is -O0 and dispatches every named function
 * through a slot. */
NUPP_API nupp_status nupp_reload_open(
    nupp_runtime *runtime,
    const nupp_reload_config *config,
    nupp_reload **out,
    nupp_error **error
);

/* Attaches a session to the components already loaded here that were built with
 * `reload = true`. `entry` is not read: a component named its own modules when
 * it installed them, and attaching recompiles each one to prove the source in
 * `root` is still what it is running. Load the component before the compiler,
 * because a component refuses to install a module the state already has. */
NUPP_API nupp_status nupp_reload_attach(
    nupp_runtime *runtime,
    const nupp_reload_config *config,
    nupp_reload **out,
    nupp_error **error
);

/* One member of the reloading entry, by dotted name. The handle keeps working
 * across every commit, which is what a watch build's stable identity buys. */
NUPP_API nupp_status nupp_reload_find(
    nupp_runtime *runtime,
    nupp_reload *reload,
    const char *name,
    nupp_handle **out,
    nupp_error **error
);

/* Checks what changed and stages a patch. Nothing that is running changes here,
 * so a host may prepare away from its safe point: `NUPP_RELOAD_PREPARED` says a
 * complete patch is waiting for `nupp_reload_apply`, and a second prepare
 * replaces what the first staged. */
NUPP_API nupp_status nupp_reload_prepare(
    nupp_runtime *runtime,
    nupp_reload *reload,
    uint32_t *verdict,
    uint64_t *generation,
    nupp_error **error
);

/* Publishes what `nupp_reload_prepare` staged: the commit boundary, called
 * where the host knows no work is half applied. It is the only call in a
 * session that changes a live implementation. With nothing staged it answers
 * `NUPP_RELOAD_NO_CHANGE`, and a patch the running generation has moved past
 * answers `NUPP_RELOAD_REJECTED`. */
NUPP_API nupp_status nupp_reload_apply(
    nupp_runtime *runtime,
    nupp_reload *reload,
    uint32_t *verdict,
    uint64_t *generation,
    nupp_error **error
);

/* Preparing and applying at one point, for a host with nothing to gain by
 * separating them. */
NUPP_API nupp_status nupp_reload_poll(
    nupp_runtime *runtime,
    nupp_reload *reload,
    uint32_t *verdict,
    uint64_t *generation,
    nupp_error **error
);

/* The diagnostics behind the last poll, or null. Owned by the session and
 * replaced by the next poll. */
NUPP_API const char *nupp_reload_message(const nupp_reload *reload);

NUPP_API nupp_status nupp_reload_close(
    nupp_runtime *runtime,
    nupp_reload *reload,
    int ok,
    nupp_error **error
);

NUPP_API void nupp_reload_free(nupp_reload *reload);

NUPP_API void nupp_component_release(nupp_component *component);
NUPP_API void nupp_runtime_free(nupp_runtime *runtime);

NUPP_API int nupp_error_status(const nupp_error *error);
NUPP_API int nupp_error_category(const nupp_error *error);
NUPP_API const char *nupp_error_message(const nupp_error *error);
NUPP_API size_t nupp_error_message_length(const nupp_error *error);
NUPP_API void nupp_error_free(nupp_error *error);

#ifdef __cplusplus
}
#endif

#endif
