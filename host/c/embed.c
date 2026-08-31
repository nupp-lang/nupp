/* The embedding ABI, as `host/include/nupp.h` declares it.
 *
 * Everything here is boundary work: checking what an application handed over,
 * turning an owned message into an error object it can read and free, and
 * naming runtime-scoped things by pointer without letting one runtime's pointer
 * be used on another. The behaviour lives in `runtime.c`.
 *
 * No call raises and none aborts. This is a library inside somebody else's
 * process, and a status they can read is the only useful answer.
 */

#include "nupp.h"
#include "nupp_host.h"

#include <stdlib.h>
#include <string.h>

/* A component and a handle are runtime-scoped identifiers rather than
 * pointers into the runtime, so one from another runtime is refused rather
 * than followed. Each is handed out as an opaque pointer the caller frees. */
struct nupp_component {
    uint64_t runtime;
    uint64_t id;
};

struct nupp_handle {
    uint64_t runtime;
    uint64_t id;
};

/* --- errors ------------------------------------------------------------- */

static void begin_error(nupp_error **error) {
    if (error != NULL) {
        *error = NULL;
    }
}

/* Takes an owned message and answers a status. The message is freed whether or
 * not the caller wanted an error object, because it belongs to this call. */
static nupp_status report(
    nupp_error **error, nupp_status status, int category, char *message
) {
    if (error != NULL) {
        nupp_error *made = calloc(1, sizeof *made);
        if (made != NULL) {
            made->status = status;
            made->category = category;
            made->message = message;
            made->length = message != NULL ? strlen(message) : 0;
            *error = made;
            return status;
        }
    }
    free(message);
    return status;
}

static char *duplicate(const char *text) {
    size_t length = strlen(text);
    char *copy = malloc(length + 1);
    if (copy != NULL) {
        memcpy(copy, text, length + 1);
    }
    return copy;
}

static nupp_status refuse(
    nupp_error **error, nupp_status status, int category, const char *text
) {
    return report(error, status, category, duplicate(text));
}

int nupp_error_status(const nupp_error *error) {
    return error != NULL ? error->status : NUPP_STATUS_OK;
}

int nupp_error_category(const nupp_error *error) {
    return error != NULL ? error->category : 0;
}

const char *nupp_error_message(const nupp_error *error) {
    return error != NULL && error->message != NULL ? error->message : "";
}

size_t nupp_error_message_length(const nupp_error *error) {
    return error != NULL ? error->length : 0;
}

void nupp_error_free(nupp_error *error) {
    if (error != NULL) {
        free(error->message);
        free(error);
    }
}

/* --- configuration ------------------------------------------------------ */

void nupp_config_init(nupp_config *config) {
    if (config != NULL) {
        config->size = (uint32_t)sizeof *config;
        config->abi_version = NUPP_EMBED_ABI_VERSION;
        config->flags = NUPP_CONFIG_OPEN_LIBRARIES;
    }
}

/* A config from an application built against a different header is refused
 * rather than read: its fields would be at different offsets, and the fields
 * this reads decide whether the standard library is opened. */
static bool config_flags(
    const nupp_config *config, uint32_t fallback, uint32_t *flags, nupp_error **error,
    nupp_status *status
) {
    if (config == NULL) {
        *flags = fallback;
        return true;
    }
    if (config->size < (uint32_t)sizeof *config) {
        *status = refuse(error, NUPP_STATUS_INCOMPATIBLE, NUPP_ERROR_COMPATIBILITY,
            "nupp_config is smaller than embedding ABI 1 requires");
        return false;
    }
    if (config->abi_version != NUPP_EMBED_ABI_VERSION) {
        *status = report(error, NUPP_STATUS_INCOMPATIBLE, NUPP_ERROR_COMPATIBILITY,
            duplicate("libnupp embedding ABI 1 cannot accept another ABI"));
        return false;
    }
    if ((config->flags & ~(uint32_t)NUPP_CONFIG_OPEN_LIBRARIES) != 0) {
        *status = refuse(error, NUPP_STATUS_INVALID_ARGUMENT, NUPP_ERROR_CONFIGURATION,
            "nupp_config contains unknown flags");
        return false;
    }
    *flags = config->flags;
    return true;
}

/* --- runtimes ----------------------------------------------------------- */

nupp_status nupp_runtime_new(
    const nupp_config *config, nupp_runtime **out, nupp_error **error
) {
    uint32_t flags = 0;
    nupp_status status = NUPP_STATUS_OK;
    char *problem = NULL;
    NuppRuntime *runtime;

    begin_error(error);
    if (out == NULL) {
        return refuse(error, NUPP_STATUS_INVALID_ARGUMENT, NUPP_ERROR_CONFIGURATION,
            "nupp_runtime_new needs somewhere to put the runtime");
    }
    *out = NULL;
    if (!config_flags(config, NUPP_CONFIG_OPEN_LIBRARIES, &flags, error, &status)) {
        return status;
    }
    runtime = nupp_host_runtime_new((flags & NUPP_CONFIG_OPEN_LIBRARIES) != 0, &problem);
    if (runtime == NULL) {
        return report(error, NUPP_STATUS_RUNTIME, NUPP_ERROR_RUNTIME, problem);
    }
    *out = (nupp_runtime *)runtime;
    return NUPP_STATUS_OK;
}

nupp_status nupp_runtime_attach(
    lua_State *state, const nupp_config *config, nupp_runtime **out, nupp_error **error
) {
    uint32_t flags = 0;
    nupp_status status = NUPP_STATUS_OK;
    char *problem = NULL;
    NuppRuntime *runtime;

    begin_error(error);
    if (out == NULL) {
        return refuse(error, NUPP_STATUS_INVALID_ARGUMENT, NUPP_ERROR_CONFIGURATION,
            "nupp_runtime_attach needs somewhere to put the runtime");
    }
    *out = NULL;
    if (state == NULL) {
        return refuse(error, NUPP_STATUS_INVALID_ARGUMENT, NUPP_ERROR_CONFIGURATION,
            "nupp_runtime_attach needs a Lua state");
    }
    /* An attached state belongs to the host, which has already opened whatever
     * it wanted; opening again is the caller's to ask for. */
    if (!config_flags(config, 0, &flags, error, &status)) {
        return status;
    }
    runtime = nupp_host_runtime_attach(
        state, (flags & NUPP_CONFIG_OPEN_LIBRARIES) != 0, &problem);
    if (runtime == NULL) {
        return report(error, NUPP_STATUS_INCOMPATIBLE, NUPP_ERROR_COMPATIBILITY, problem);
    }
    *out = (nupp_runtime *)runtime;
    return NUPP_STATUS_OK;
}

lua_State *nupp_runtime_lua_state(nupp_runtime *runtime) {
    return nupp_host_runtime_state((NuppRuntime *)runtime);
}

/* Every call below answers the same three ways: no runtime is an argument
 * error, a message from the runtime is a runtime error, and success is silence. */
static nupp_status settled(nupp_error **error, char *problem, int category) {
    if (problem == NULL) {
        return NUPP_STATUS_OK;
    }
    return report(error, NUPP_STATUS_RUNTIME, category, problem);
}

static bool have_runtime(nupp_runtime *runtime, nupp_error **error, nupp_status *status) {
    if (runtime == NULL) {
        *status = refuse(error, NUPP_STATUS_INVALID_ARGUMENT, NUPP_ERROR_CONFIGURATION,
            "this call needs a Nupp runtime");
        return false;
    }
    return true;
}

nupp_status nupp_runtime_add_feature(
    nupp_runtime *runtime, const char *feature, nupp_error **error
) {
    nupp_status status = NUPP_STATUS_OK;
    begin_error(error);
    if (!have_runtime(runtime, error, &status)) {
        return status;
    }
    if (feature == NULL) {
        return refuse(error, NUPP_STATUS_INVALID_ARGUMENT, NUPP_ERROR_CONFIGURATION,
            "a host feature needs a name");
    }
    return settled(error,
        nupp_host_add_feature((NuppRuntime *)runtime, feature), NUPP_ERROR_CONFIGURATION);
}

nupp_status nupp_runtime_add_resource(
    nupp_runtime *runtime, const char *path, const void *bytes, size_t length,
    nupp_error **error
) {
    nupp_status status = NUPP_STATUS_OK;
    begin_error(error);
    if (!have_runtime(runtime, error, &status)) {
        return status;
    }
    if (path == NULL || (bytes == NULL && length != 0)) {
        return refuse(error, NUPP_STATUS_INVALID_ARGUMENT, NUPP_ERROR_CONFIGURATION,
            "a host resource needs a path and its bytes");
    }
    return settled(error,
        nupp_host_add_resource((NuppRuntime *)runtime, path, bytes, length),
        NUPP_ERROR_CONFIGURATION);
}

nupp_status nupp_runtime_preload(
    nupp_runtime *runtime, const char *module, nupp_lua_CFunction opener, nupp_error **error
) {
    nupp_status status = NUPP_STATUS_OK;
    begin_error(error);
    if (!have_runtime(runtime, error, &status)) {
        return status;
    }
    if (module == NULL || opener == NULL) {
        return refuse(error, NUPP_STATUS_INVALID_ARGUMENT, NUPP_ERROR_CONFIGURATION,
            "a preloaded module needs a name and an opener");
    }
    return settled(error,
        nupp_host_preload((NuppRuntime *)runtime, module, (lua_CFunction)opener),
        NUPP_ERROR_CONFIGURATION);
}

nupp_status nupp_runtime_register_aot_builders(
    nupp_runtime *runtime, const char *key, nupp_lua_CFunction registrar, nupp_error **error
) {
    nupp_status status = NUPP_STATUS_OK;
    begin_error(error);
    if (!have_runtime(runtime, error, &status)) {
        return status;
    }
    if (key == NULL || key[0] == '\0' || registrar == NULL) {
        return refuse(error, NUPP_STATUS_INVALID_ARGUMENT, NUPP_ERROR_CONFIGURATION,
            "registering AOT builders needs a key and a registrar");
    }
    return settled(error,
        nupp_host_register_aot_builders((NuppRuntime *)runtime, key, (lua_CFunction)registrar),
        NUPP_ERROR_CONFIGURATION);
}

/* --- components --------------------------------------------------------- */

nupp_status nupp_component_load(
    nupp_runtime *runtime, const void *bytes, size_t length, const char *name,
    nupp_component **out, nupp_error **error
) {
    nupp_status status = NUPP_STATUS_OK;
    uint64_t id = 0;
    char *problem;
    nupp_component *component;

    begin_error(error);
    if (!have_runtime(runtime, error, &status)) {
        return status;
    }
    if (out == NULL || bytes == NULL) {
        return refuse(error, NUPP_STATUS_INVALID_ARGUMENT, NUPP_ERROR_COMPONENT,
            "loading a component needs its bytes and somewhere to put it");
    }
    *out = NULL;
    problem = nupp_host_load_component(
        (NuppRuntime *)runtime, bytes, length, name != NULL ? name : "=component", &id);
    if (problem != NULL) {
        return report(error, NUPP_STATUS_RUNTIME, NUPP_ERROR_COMPONENT, problem);
    }
    component = calloc(1, sizeof *component);
    if (component == NULL) {
        return refuse(error, NUPP_STATUS_RUNTIME, NUPP_ERROR_RUNTIME, "out of memory");
    }
    component->runtime = nupp_host_runtime_id((NuppRuntime *)runtime);
    component->id = id;
    *out = component;
    return NUPP_STATUS_OK;
}

/* A component names the runtime it came from, so one used on another is told
 * so rather than resolving to whatever that runtime's component with the same
 * number happens to be. */
static bool component_belongs(
    nupp_runtime *runtime, const nupp_component *component, nupp_error **error,
    nupp_status *status
) {
    if (component == NULL) {
        *status = refuse(error, NUPP_STATUS_INVALID_ARGUMENT, NUPP_ERROR_COMPONENT,
            "this call needs a component");
        return false;
    }
    if (component->runtime != nupp_host_runtime_id((NuppRuntime *)runtime)) {
        *status = refuse(error, NUPP_STATUS_INVALID_ARGUMENT, NUPP_ERROR_COMPONENT,
            "the component belongs to another Nupp runtime");
        return false;
    }
    return true;
}

nupp_status nupp_component_start(
    nupp_runtime *runtime, const nupp_component *component,
    int argc, const char *const *argv, nupp_error **error
) {
    nupp_status status = NUPP_STATUS_OK;
    begin_error(error);
    if (!have_runtime(runtime, error, &status)
        || !component_belongs(runtime, component, error, &status)) {
        return status;
    }
    if (argc < 0 || (argc > 0 && argv == NULL)) {
        return refuse(error, NUPP_STATUS_INVALID_ARGUMENT, NUPP_ERROR_COMPONENT,
            "starting a component was given a count without arguments");
    }
    return settled(error,
        nupp_host_start_component((NuppRuntime *)runtime, component->id, argc, argv),
        NUPP_ERROR_COMPONENT);
}

nupp_status nupp_export_find(
    nupp_runtime *runtime, const nupp_component *component, const char *name,
    nupp_handle **out, nupp_error **error
) {
    nupp_status status = NUPP_STATUS_OK;
    uint64_t id = 0;
    char *problem;
    nupp_handle *handle;

    begin_error(error);
    if (!have_runtime(runtime, error, &status)
        || !component_belongs(runtime, component, error, &status)) {
        return status;
    }
    if (out == NULL || name == NULL) {
        return refuse(error, NUPP_STATUS_INVALID_ARGUMENT, NUPP_ERROR_COMPONENT,
            "finding an export needs a name and somewhere to put it");
    }
    *out = NULL;
    problem = nupp_host_find_export((NuppRuntime *)runtime, component->id, name, &id);
    if (problem != NULL) {
        return report(error, NUPP_STATUS_RUNTIME, NUPP_ERROR_COMPONENT, problem);
    }
    handle = calloc(1, sizeof *handle);
    if (handle == NULL) {
        free(nupp_host_release_handle((NuppRuntime *)runtime, id));
        return refuse(error, NUPP_STATUS_RUNTIME, NUPP_ERROR_RUNTIME, "out of memory");
    }
    handle->runtime = nupp_host_runtime_id((NuppRuntime *)runtime);
    handle->id = id;
    *out = handle;
    return NUPP_STATUS_OK;
}

void nupp_component_release(nupp_component *component) {
    free(component);
}

/* --- calling ------------------------------------------------------------ */

nupp_status nupp_call(
    nupp_runtime *runtime, const nupp_handle *callable,
    const nupp_value *arguments, size_t argumentCount,
    nupp_value *results, size_t resultCapacity, size_t *resultCount,
    nupp_error **error
) {
    nupp_status status = NUPP_STATUS_OK;
    NuppHostValue *passed = NULL;
    NuppHostValue *answered = NULL;
    size_t answeredCount = 0;
    size_t at;
    char *problem;
    uint64_t runtimeId;

    begin_error(error);
    if (!have_runtime(runtime, error, &status)) {
        return status;
    }
    runtimeId = nupp_host_runtime_id((NuppRuntime *)runtime);
    if (callable == NULL || callable->runtime != runtimeId) {
        return refuse(error, NUPP_STATUS_INVALID_ARGUMENT, NUPP_ERROR_RUNTIME,
            "the managed handle belongs to another Nupp runtime");
    }
    if ((argumentCount != 0 && arguments == NULL)
        || (resultCapacity != 0 && results == NULL)) {
        return refuse(error, NUPP_STATUS_INVALID_ARGUMENT, NUPP_ERROR_RUNTIME,
            "a call was given a count without values");
    }
    if (argumentCount != 0) {
        passed = calloc(argumentCount, sizeof *passed);
        if (passed == NULL) {
            return refuse(error, NUPP_STATUS_RUNTIME, NUPP_ERROR_RUNTIME, "out of memory");
        }
        for (at = 0; at < argumentCount; at++) {
            if (arguments[at].kind > NUPP_VALUE_HANDLE) {
                free(passed);
                return refuse(error, NUPP_STATUS_INVALID_ARGUMENT, NUPP_ERROR_RUNTIME,
                    "a call was given a value of an unknown kind");
            }
            if ((arguments[at].kind == NUPP_VALUE_STRING
                    || arguments[at].kind == NUPP_VALUE_BYTES)
                && arguments[at].data == NULL && arguments[at].length != 0) {
                free(passed);
                return refuse(error, NUPP_STATUS_INVALID_ARGUMENT, NUPP_ERROR_RUNTIME,
                    "a call was given a string length without its bytes");
            }
            passed[at].kind = (NuppHostKind)arguments[at].kind;
            passed[at].boolean = arguments[at].boolean != 0;
            passed[at].number = arguments[at].number;
            passed[at].data = arguments[at].data;
            passed[at].length = arguments[at].length;
            if (arguments[at].kind == NUPP_VALUE_HANDLE) {
                if (arguments[at].handle == NULL
                    || arguments[at].handle->runtime != runtimeId) {
                    free(passed);
                    return refuse(error, NUPP_STATUS_INVALID_ARGUMENT, NUPP_ERROR_RUNTIME,
                        "the managed handle belongs to another Nupp runtime");
                }
                passed[at].handle = arguments[at].handle->id;
            }
        }
    }
    problem = nupp_host_call(
        (NuppRuntime *)runtime, callable->id, passed, argumentCount,
        &answered, &answeredCount);
    free(passed);
    if (problem != NULL) {
        free(answered);
        return report(error, NUPP_STATUS_RUNTIME, NUPP_ERROR_RUNTIME, problem);
    }
    if (resultCount != NULL) {
        *resultCount = answeredCount;
    }
    /* Too small is not a failure of the call: it already happened. The caller is
     * told how many there were and asks again with room, which is why the
     * results are released here rather than held for a second attempt. */
    if (answeredCount > resultCapacity) {
        for (at = 0; at < answeredCount; at++) {
            free(answered[at].data);
            if (answered[at].kind == NUPP_HOST_HANDLE) {
                free(nupp_host_release_handle((NuppRuntime *)runtime, answered[at].handle));
            }
        }
        free(answered);
        return refuse(error, NUPP_STATUS_BUFFER_TOO_SMALL, NUPP_ERROR_RUNTIME,
            "the result buffer is smaller than the call answered");
    }
    for (at = 0; at < answeredCount; at++) {
        memset(&results[at], 0, sizeof results[at]);
        results[at].kind = (uint32_t)answered[at].kind;
        results[at].boolean = answered[at].boolean ? 1 : 0;
        results[at].number = answered[at].number;
        results[at].data = answered[at].data;
        results[at].length = answered[at].length;
        if (answered[at].kind == NUPP_HOST_HANDLE) {
            nupp_handle *handle = calloc(1, sizeof *handle);
            if (handle == NULL) {
                /* Undo the whole answer: results already written go back through
                 * the ordinary release path, and the rest are still runtime-owned. */
                size_t back;
                for (back = 0; back < at; back++) {
                    nupp_error *ignored = NULL;
                    nupp_value_release(runtime, &results[back], &ignored);
                    nupp_error_free(ignored);
                }
                for (back = at; back < answeredCount; back++) {
                    free(answered[back].data);
                    if (answered[back].kind == NUPP_HOST_HANDLE) {
                        free(nupp_host_release_handle(
                            (NuppRuntime *)runtime, answered[back].handle));
                    }
                }
                free(answered);
                if (resultCount != NULL) {
                    *resultCount = 0;
                }
                return refuse(error, NUPP_STATUS_RUNTIME, NUPP_ERROR_RUNTIME, "out of memory");
            }
            handle->runtime = runtimeId;
            handle->id = answered[at].handle;
            results[at].handle = handle;
        }
    }
    free(answered);
    return NUPP_STATUS_OK;
}

nupp_status nupp_handle_release(
    nupp_runtime *runtime, nupp_handle *handle, nupp_error **error
) {
    nupp_status status = NUPP_STATUS_OK;
    char *problem;
    begin_error(error);
    if (!have_runtime(runtime, error, &status)) {
        return status;
    }
    if (handle == NULL) {
        return refuse(error, NUPP_STATUS_INVALID_ARGUMENT, NUPP_ERROR_RUNTIME,
            "releasing needs a handle");
    }
    if (handle->runtime != nupp_host_runtime_id((NuppRuntime *)runtime)) {
        return refuse(error, NUPP_STATUS_INVALID_ARGUMENT, NUPP_ERROR_RUNTIME,
            "the managed handle belongs to another Nupp runtime");
    }
    problem = nupp_host_release_handle((NuppRuntime *)runtime, handle->id);
    free(handle);
    return settled(error, problem, NUPP_ERROR_RUNTIME);
}

nupp_status nupp_value_release(
    nupp_runtime *runtime, nupp_value *value, nupp_error **error
) {
    begin_error(error);
    if (value == NULL) {
        return NUPP_STATUS_OK;
    }
    if ((value->kind == NUPP_VALUE_STRING || value->kind == NUPP_VALUE_BYTES)
        && value->data != NULL) {
        free(value->data);
    } else if (value->kind == NUPP_VALUE_HANDLE && value->handle != NULL) {
        nupp_status status = nupp_handle_release(runtime, value->handle, error);
        if (status != NUPP_STATUS_OK) {
            return status;
        }
    }
    memset(value, 0, sizeof *value);
    return NUPP_STATUS_OK;
}

/* --- ending ------------------------------------------------------------- */

nupp_status nupp_runtime_shutdown(nupp_runtime *runtime, nupp_error **error) {
    nupp_status status = NUPP_STATUS_OK;
    begin_error(error);
    if (!have_runtime(runtime, error, &status)) {
        return status;
    }
    return settled(error,
        nupp_host_runtime_shutdown((NuppRuntime *)runtime), NUPP_ERROR_RUNTIME);
}

nupp_status nupp_runtime_poll(nupp_runtime *runtime, nupp_error **error) {
    nupp_status status = NUPP_STATUS_OK;
    begin_error(error);
    if (!have_runtime(runtime, error, &status)) {
        return status;
    }
    return settled(error, nupp_host_poll((NuppRuntime *)runtime), NUPP_ERROR_RUNTIME);
}

void nupp_runtime_free(nupp_runtime *runtime) {
    nupp_host_runtime_free((NuppRuntime *)runtime);
}
