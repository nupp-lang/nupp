/**
 * @file
 * @brief Public C API for loading and running Nupp components in a host.
 *
 * Use a runtime on the thread that created or attached it. Status-returning
 * functions accept a null error output. When given an error output, they
 * set it to null on success or return an owned error on failure. Release
 * that error with nupp_error_free() before reusing the output.
 */

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
/** Lua C callback. Returns the number of results left on the Lua stack. */
typedef int (*nupp_lua_CFunction)(lua_State *state);

/** A runtime pointer addresses the runtime. Components, handles and reload
 * sessions are opaque names instead: a released name is refused by every later
 * call that is given it, and is never issued again. */
typedef struct nupp_runtime nupp_runtime;
typedef struct nupp_component nupp_component;
typedef struct nupp_handle nupp_handle;
typedef struct nupp_error nupp_error;
typedef struct nupp_reload nupp_reload;

/** The version nupp_config::abi_version names. */
enum { NUPP_EMBED_ABI_VERSION = 2 };

/** Bits of nupp_config::flags. */
typedef enum nupp_config_flags {
    NUPP_CONFIG_OPEN_LIBRARIES = 1, /**< Open LuaJIT's standard libraries. */
} nupp_config_flags;

/** Result of a status-returning call. */
typedef enum nupp_status {
    NUPP_STATUS_OK = 0,
    NUPP_STATUS_INVALID_ARGUMENT = 1,
    NUPP_STATUS_INCOMPATIBLE = 2,
    NUPP_STATUS_RUNTIME = 3,
    NUPP_STATUS_BUFFER_TOO_SMALL = 4,
} nupp_status;

/** Subsystem responsible for an error. */
typedef enum nupp_error_category_code {
    NUPP_ERROR_CONFIGURATION = 1,
    NUPP_ERROR_COMPATIBILITY = 2,
    NUPP_ERROR_COMPONENT = 3,
    NUPP_ERROR_RUNTIME = 4,
} nupp_error_category_code;

/** Selects the payload of a nupp_value. */
typedef enum nupp_value_kind {
    NUPP_VALUE_NIL = 0,
    NUPP_VALUE_BOOLEAN = 1,
    NUPP_VALUE_NUMBER = 2,
    NUPP_VALUE_STRING = 3,
    NUPP_VALUE_BYTES = 4,
    NUPP_VALUE_HANDLE = 5,
} nupp_value_kind;

/**
 * @brief Argument or result passed across the embedding boundary.
 *
 * The kind selects boolean, number, data with a byte length, or a handle.
 * Strings are counted UTF-8 bytes. Release owned results with
 * nupp_value_release().
 */
typedef struct nupp_value {
    uint32_t kind;
    int boolean;
    double number;
    unsigned char *data;
    size_t length;
    nupp_handle *handle;
} nupp_value;

/** Outcome of preparing or applying a reload patch. */
typedef enum nupp_reload_verdict {
    NUPP_RELOAD_NO_CHANGE = 0,
    NUPP_RELOAD_COMMITTED = 1,
    NUPP_RELOAD_REJECTED = 2,
    NUPP_RELOAD_RESTART_REQUIRED = 3,
    NUPP_RELOAD_PREPARED = 4,
} nupp_reload_verdict;

/** Runtime configuration initialized by nupp_config_init(). */
typedef struct nupp_config {
    uint32_t size;
    uint32_t abi_version;
    uint32_t flags;
} nupp_config;

/** Development hot reload compiles the project while the program runs, so
 * `compiler_path` names a directory holding the compiler's own Lua modules --
 * what `nupp build --target bootstrapCompiler` writes. It may be null when the
 * state already reaches them. `root` defaults to the process's directory.
 * `flags` is reserved and must be zero. */
typedef struct nupp_reload_config {
    uint32_t size;
    uint32_t flags;
    const char *compiler_path;
    const char *root;
    const char *entry;
} nupp_reload_config;

/**
 * @brief Initializes the size, ABI version, and default configuration flags.
 *
 * @param[out] config The configuration to initialize, or null to do nothing.
 * @see NUPP_CONFIG_OPEN_LIBRARIES
 */
NUPP_API void nupp_config_init(nupp_config *config);

/**
 * @brief Creates a runtime with its own LuaJIT state.
 *
 * @param[in] config Configuration, or null to open the standard Lua libraries
 *                   with the default settings.
 * @param[out] out The owned runtime on success, or null on failure.
 * @param[out] error Optional error output.
 * @see nupp_runtime_free()
 */
NUPP_API nupp_status nupp_runtime_new(
    const nupp_config *config,
    nupp_runtime **out,
    nupp_error **error
);

/**
 * @brief Attaches a runtime to a caller-owned LuaJIT state.
 *
 * Keep the state alive until the runtime is freed. The caller closes the state.
 *
 * @param[in] state Live, compatible LuaJIT state owned by the calling thread.
 * @param[in] config Configuration, or null to leave library loading to the host.
 * @param[out] out The owned runtime on success, or null on failure.
 * @param[out] error Optional error output.
 */
NUPP_API nupp_status nupp_runtime_attach(
    lua_State *state,
    const nupp_config *config,
    nupp_runtime **out,
    nupp_error **error
);

/**
 * @brief Borrows the runtime's LuaJIT state.
 *
 * @retval NULL The runtime is null, has shut down, or belongs to another thread.
 */
NUPP_API lua_State *nupp_runtime_lua_state(nupp_runtime *runtime);

/**
 * @brief Declares a deployment capability before loading the first component.
 *
 * The embedding ABI cannot install the worker adapter, so it rejects the
 * `workers` feature.
 */
NUPP_API nupp_status nupp_runtime_add_feature(
    nupp_runtime *runtime,
    const char *feature,
    nupp_error **error
);

/**
 * @brief Copies a resource into the runtime before loading the first component.
 *
 * @param[in] runtime The runtime that will provide the resource.
 * @param[in] path NUL-terminated UTF-8 resource path.
 * @param[in] bytes The bytes to copy. May be null if length is zero.
 * @param[in] length Resource size in bytes.
 * @param[out] error Optional error output.
 */
NUPP_API nupp_status nupp_runtime_add_resource(
    nupp_runtime *runtime,
    const char *path,
    const void *bytes,
    size_t length,
    nupp_error **error
);

/**
 * @brief Registers a Lua C module opener before loading the first component.
 *
 * @param[in] runtime The runtime where the module can be required.
 * @param[in] module NUL-terminated UTF-8 module name.
 * @param[in] opener Callback installed in Lua's preload table.
 * @param[out] error Optional error output.
 */
NUPP_API nupp_status nupp_runtime_preload(
    nupp_runtime *runtime,
    const char *module,
    nupp_lua_CFunction opener,
    nupp_error **error
);

/**
 * @brief Registers a compiled archive's Lua builder table.
 *
 * Calls the registrar with this runtime's Lua state and stores the returned
 * table under `key`. Register the archive before loading a component that uses it.
 */
NUPP_API nupp_status nupp_runtime_register_aot_builders(
    nupp_runtime *runtime,
    const char *key,
    nupp_lua_CFunction registrar,
    nupp_error **error
);

/**
 * @brief Loads a compiled component and installs its modules in the runtime.
 *
 * @param[in] runtime The runtime that will own the component.
 * @param[in] bytes The compiled component bytes, borrowed for this call.
 * @param[in] length Component size in bytes.
 * @param[in] name Optional NUL-terminated UTF-8 name used in diagnostics.
 * @param[out] out Component name on success. Release it with
 *                 nupp_component_release().
 * @param[out] error Optional error output.
 */
NUPP_API nupp_status nupp_component_load(
    nupp_runtime *runtime,
    const void *bytes,
    size_t length,
    const char *name,
    nupp_component **out,
    nupp_error **error
);

/**
 * @brief Runs a loaded component's entry with host-supplied arguments.
 *
 * A component can be started successfully only once.
 *
 * @param[in] runtime The runtime that loaded the component.
 * @param[in] component Name returned by nupp_component_load().
 * @param[in] argc Nonnegative number of arguments.
 * @param[in] argv Array of `argc` NUL-terminated strings, or null if `argc` is zero.
 * @param[out] error Optional error output.
 */
NUPP_API nupp_status nupp_component_start(
    nupp_runtime *runtime,
    const nupp_component *component,
    int argc,
    const char *const *argv,
    nupp_error **error
);

/**
 * @brief Obtains a managed handle to a named component export.
 *
 * @param[in] runtime The runtime that loaded the component.
 * @param[in] component Name returned by nupp_component_load().
 * @param[in] name NUL-terminated UTF-8 export name.
 * @param[out] out Handle on success. Release it with nupp_handle_release().
 * @param[out] error Optional error output.
 */
NUPP_API nupp_status nupp_export_find(
    nupp_runtime *runtime,
    const nupp_component *component,
    const char *name,
    nupp_handle **out,
    nupp_error **error
);

/**
 * @brief Invokes a managed callable and writes its results to a caller buffer.
 *
 * Release each returned value with nupp_value_release(). If the buffer is too
 * small, the call has already run and its results are discarded. Repeating the
 * call runs the function again.
 *
 * @param[in] runtime The runtime that owns the callable.
 * @param[in] callable Handle to the function to invoke.
 * @param[in] arguments Argument array, or null when `argument_count` is zero.
 * @param[in] argument_count Number of entries in `arguments`.
 * @param[out] results Result array, or null when `result_capacity` is zero.
 * @param[in] result_capacity Number of entries available in `results`.
 * @param[out] result_count Optional count of values returned by the function.
 * @param[out] error Optional error output.
 * @retval NUPP_STATUS_BUFFER_TOO_SMALL The required count is written to
 *         `result_count` if supplied. `results` remains untouched.
 */
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

/**
 * @brief Releases a managed handle through its owning runtime.
 *
 * A released handle can no longer be used.
 */
NUPP_API nupp_status nupp_handle_release(
    nupp_runtime *runtime,
    nupp_handle *handle,
    nupp_error **error
);

/**
 * @brief Releases a result's owned storage or handle and resets it to nil.
 *
 * Pass values returned by the runtime. A null value pointer does nothing.
 */
NUPP_API nupp_status nupp_value_release(
    nupp_runtime *runtime,
    nupp_value *value,
    nupp_error **error
);

/**
 * @brief Shuts down the runtime and releases its references into LuaJIT.
 *
 * Call nupp_runtime_free() to release the runtime object itself.
 * @retval NUPP_STATUS_RUNTIME A call is still running in this Lua state,
 *         for example when a host callback tries to shut down its runtime.
 */
NUPP_API nupp_status nupp_runtime_shutdown(
    nupp_runtime *runtime,
    nupp_error **error
);

/**
 * @brief Polls the runtime's readiness sources without blocking.
 *
 * Drives sources that modules registered with `nupp.suspension`, such as
 * network, HTTP, process, and timer pumps. Call it again from the host's loop.
 * A state that never loaded `nupp.suspension` has nothing to drive.
 */
NUPP_API nupp_status nupp_runtime_poll(
    nupp_runtime *runtime,
    nupp_error **error
);

/** Answers an `os.host` request of one kind. `arguments` are borrowed for the
 * length of the call: copy what an answer given later needs. A handler answers
 * with nupp_host_answer or nupp_host_fail, at once or later from the host's
 * loop, and either way the waiting task resumes at the next nupp_runtime_poll.
 * It may call back into the runtime. */
typedef void (*nupp_host_handler)(
    nupp_runtime *runtime,
    uint64_t request,
    const char *kind,
    const nupp_value *arguments,
    size_t argument_count,
    void *userdata
);

/** Tells a host that nothing waits for `request` any more. Advisory: the request
 * may still be answered, and its answer goes to the caller's late cleanup. */
typedef void (*nupp_host_cancel)(nupp_runtime *runtime, uint64_t request, void *userdata);

/**
 * @brief Registers, replaces, or removes a handler for a host request kind.
 *
 * `kind` has two or more dot-separated names outside `nupp.`. Pass a null
 * `handler` to remove it.
 * @retval NUPP_STATUS_INCOMPATIBLE Another runtime already answers host requests
 *         in this Lua state.
 */
NUPP_API nupp_status nupp_host_register(
    nupp_runtime *runtime,
    const char *kind,
    nupp_host_handler handler,
    nupp_host_cancel cancel,
    void *userdata,
    nupp_error **error
);

/**
 * @brief Answers a host request with values copied before this call returns.
 *
 * Accepts nil, booleans, finite numbers, UTF-8 strings up to 64 KiB, and bytes
 * up to 8 MiB. Handles are refused. Ownership of whatever the results name
 * passes to the program here. An answer to an abandoned request goes to the
 * caller's late cleanup. An answer to a post is discarded.
 */
NUPP_API nupp_status nupp_host_answer(
    nupp_runtime *runtime,
    uint64_t request,
    const nupp_value *results,
    size_t result_count,
    nupp_error **error
);

/**
 * @brief Queues an inbound message for delivery at the next nupp_runtime_poll().
 *
 * The program receives it on the route declared for `kind`. The queue copies
 * nil, booleans, finite numbers, and UTF-8 strings. Once 4096 messages are
 * waiting, a new push drops the oldest. An outbound stream send reaches the
 * kind's handler with request 0 and is never answered.
 */
NUPP_API nupp_status nupp_host_push(
    nupp_runtime *runtime,
    const char *kind,
    const nupp_value *values,
    size_t value_count,
    nupp_error **error
);

/**
 * @brief Fails a host request so the waiting caller raises `message`.
 *
 * A failed post is reported.
 */
NUPP_API nupp_status nupp_host_fail(
    nupp_runtime *runtime,
    uint64_t request,
    const char *message,
    nupp_error **error
);

/**
 * @brief Sets the reload configuration size and clears its flags and paths.
 *
 * @param[out] config The configuration to initialize, or null to do nothing.
 */
NUPP_API void nupp_reload_config_init(nupp_reload_config *config);

/**
 * @brief Builds and runs the entry in watch mode, then opens a reload session.
 *
 * A watch build is development-only, with optimization disabled and every
 * named function called through a slot. A commit reaches this state alone.
 * A state running native workers cannot open a session, and workers cannot be
 * installed while a session is open.
 */
NUPP_API nupp_status nupp_reload_open(
    nupp_runtime *runtime,
    const nupp_reload_config *config,
    nupp_reload **out,
    nupp_error **error
);

/**
 * @brief Opens a reload session for components already loaded with `reload = true`.
 *
 * The components name their own modules. Attaching recompiles each one from
 * `root` to check that it matches the running code. The entry path is ignored.
 * Load the component before the compiler because a component refuses to
 * install a module the state already has. The worker restriction on
 * nupp_reload_open() also applies to workers from another runtime in this state.
 */
NUPP_API nupp_status nupp_reload_attach(
    nupp_runtime *runtime,
    const nupp_reload_config *config,
    nupp_reload **out,
    nupp_error **error
);

/**
 * @brief Gets a handle to a member of the reloading entry by dotted name.
 *
 * The handle stays valid across commits. Release it with nupp_handle_release().
 */
NUPP_API nupp_status nupp_reload_find(
    nupp_runtime *runtime,
    nupp_reload *reload,
    const char *name,
    nupp_handle **out,
    nupp_error **error
);

/**
 * @name Reload steps
 * Pass null for either output to ignore it. The verdict is a
 * nupp_reload_verdict written as a uint32_t to give it a fixed ABI width.
 * @{
 */

/**
 * @brief Checks for source changes and stages a patch without applying it.
 *
 * The host can prepare before reaching its safe point.
 * `NUPP_RELOAD_PREPARED` means a patch is waiting for nupp_reload_apply().
 * A subsequent prepare replaces the staged patch.
 */
NUPP_API nupp_status nupp_reload_prepare(
    nupp_runtime *runtime,
    nupp_reload *reload,
    uint32_t *verdict,
    uint64_t *generation,
    nupp_error **error
);

/**
 * @brief Publishes the staged patch at a safe point chosen by the host.
 *
 * Call this once no work is half applied. It is the only step that changes
 * a live implementation. The verdict is `NUPP_RELOAD_NO_CHANGE` with nothing
 * staged or `NUPP_RELOAD_REJECTED` if the staged patch is out of date.
 */
NUPP_API nupp_status nupp_reload_apply(
    nupp_runtime *runtime,
    nupp_reload *reload,
    uint32_t *verdict,
    uint64_t *generation,
    nupp_error **error
);

/**
 * @brief Prepares and applies a patch in one call at the host's safe point.
 *
 * Each step initializes the verdict to `NUPP_RELOAD_NO_CHANGE` and the
 * generation to zero. Those values remain if the step fails.
 */
NUPP_API nupp_status nupp_reload_poll(
    nupp_runtime *runtime,
    nupp_reload *reload,
    uint32_t *verdict,
    uint64_t *generation,
    nupp_error **error
);

/** @} */

/**
 * @brief Returns the diagnostic message from the most recent reload step.
 *
 * @return A pointer owned by the session. A subsequent reload step replaces it
 *         and freeing the session invalidates it.
 * @retval NULL The session has no diagnostic message.
 */
NUPP_API const char *nupp_reload_message(const nupp_reload *reload);

/**
 * @brief Retires the active reload session.
 *
 * For a session started by nupp_reload_open(), pass a nonzero `ok` when the
 * program succeeded. Zero records a failed run and discards the entry's
 * recorded load. An attached session ignores `ok`.
 */
NUPP_API nupp_status nupp_reload_close(
    nupp_runtime *runtime,
    nupp_reload *reload,
    int ok,
    nupp_error **error
);

/**
 * @brief Releases the opaque reload session name.
 *
 * Call nupp_reload_close() to retire an active session before freeing its name.
 */
NUPP_API void nupp_reload_free(nupp_reload *reload);

/**
 * @brief Releases the component's name.
 *
 * Modules installed by the component stay in the Lua state until it closes.
 * A null component does nothing.
 */
NUPP_API nupp_status nupp_component_release(
    nupp_runtime *runtime,
    nupp_component *component,
    nupp_error **error
);
/**
 * @brief Frees the runtime and closes its Lua state if it owns the state.
 *
 * When called beneath a running call, the free waits until the last call
 * running in the runtime's Lua state returns. A null runtime does nothing.
 */
NUPP_API void nupp_runtime_free(nupp_runtime *runtime);

/**
 * @brief Returns the status of the failed call.
 *
 * @retval NUPP_STATUS_OK The error pointer was null.
 */
NUPP_API nupp_status nupp_error_status(const nupp_error *error);
/**
 * @brief Returns the category identifying where the failure occurred.
 *
 * @retval 0 The error pointer was null.
 */
NUPP_API nupp_error_category_code nupp_error_category(const nupp_error *error);
/**
 * @brief Returns a NUL-terminated message borrowed until nupp_error_free().
 *
 * A null error returns an empty string.
 */
NUPP_API const char *nupp_error_message(const nupp_error *error);
/**
 * @brief Returns the message length in bytes, excluding the NUL terminator.
 *
 * A null error returns zero.
 */
NUPP_API size_t nupp_error_message_length(const nupp_error *error);
/**
 * @brief Releases an owned error. A null error does nothing.
 */
NUPP_API void nupp_error_free(nupp_error *error);

#ifdef __cplusplus
}
#endif

#endif
