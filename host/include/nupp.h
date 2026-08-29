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

enum {
    NUPP_EMBED_ABI_VERSION = 1,
    NUPP_CONFIG_OPEN_LIBRARIES = 1,
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

typedef struct nupp_config {
    uint32_t size;
    uint32_t abi_version;
    uint32_t flags;
} nupp_config;

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
