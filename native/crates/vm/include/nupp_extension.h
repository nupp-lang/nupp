/*
 * nupp_extension.h -- the versioned C ABI of Nupp native extensions.
 *
 * A native extension is a shared library that registers one typed Nupp module
 * with the VM that loads it. It exports one entry point, NUPP_EXTENSION_ENTRY,
 * which returns a static description: the module name, the target it was built
 * for, its functions with their declared Nupp signatures, and its resource
 * types. The VM reads that description, checks the ABI version, the target and
 * every signature against the declaration its program was checked against, and
 * only then calls `init`. A mismatch is refused before any extension code runs.
 *
 * Values cross as `nupp_slot`s: scalars and strings by value, everything else
 * as an opaque `nupp_handle`. A handle names a VM value; it is valid for the
 * call that produced it unless the extension retains it. The extension never
 * sees a VM heap address or a Rust type.
 *
 * Every function in `nupp_host` that takes a `nupp_call` must be called on the
 * VM's thread, inside that call. `complete` and `fail` may be called from any
 * thread. Nothing may unwind through these functions.
 *
 * The Rust definitions in the `nupp-extension` crate mirror this header; the
 * VM's `c-headers` test checks the two agree on every size and offset.
 */
#ifndef NUPP_EXTENSION_H
#define NUPP_EXTENSION_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define NUPP_EXTENSION_ABI_VERSION 1u

/* The symbol the VM looks up: a `nupp_extension_entry`. */
#define NUPP_EXTENSION_ENTRY nupp_extension_v1
#define NUPP_EXTENSION_ENTRY_NAME "nupp_extension_v1"

/* The target an extension was built for, as the VM spells its own. */
#if defined(__aarch64__) || defined(_M_ARM64)
#define NUPP_EXTENSION_ARCH "aarch64"
#elif defined(__x86_64__) || defined(_M_X64)
#define NUPP_EXTENSION_ARCH "x86_64"
#else
#define NUPP_EXTENSION_ARCH "unknown"
#endif
#if defined(__APPLE__)
#define NUPP_EXTENSION_OS "macos"
#elif defined(__linux__)
#define NUPP_EXTENSION_OS "linux"
#elif defined(_WIN32)
#define NUPP_EXTENSION_OS "windows"
#else
#define NUPP_EXTENSION_OS "unknown"
#endif
#define NUPP_EXTENSION_TARGET NUPP_EXTENSION_ARCH "-" NUPP_EXTENSION_OS

/* The kinds of value a slot holds. */
#define NUPP_NIL 0u
#define NUPP_BOOLEAN 1u
#define NUPP_INTEGER 2u
#define NUPP_NUMBER 3u
#define NUPP_STRING 4u
#define NUPP_HANDLE 5u

/* What a host function and the host table answer. */
typedef int32_t nupp_status;
#define NUPP_OK 0
#define NUPP_ERROR 1
#define NUPP_SUSPENDED 2

/* A VM value the extension holds without seeing it. Zero is never a handle. */
typedef uint64_t nupp_handle;

/* Bytes the receiver does not own. A string argument stays valid for the call.
 * The VM copies a string result right after the function returns, so its bytes
 * must outlive the function's own frame: static, or owned by the extension. */
typedef struct nupp_string {
    const char *bytes;
    size_t length;
} nupp_string;

typedef struct nupp_slot {
    uint32_t kind;
    uint32_t reserved;
    union {
        int32_t boolean;
        int64_t integer;
        double number;
        nupp_string string;
        nupp_handle handle;
    } as;
} nupp_slot;

/* The VM an extension instance belongs to. */
typedef struct nupp_vm nupp_vm;
/* One call of a host function, valid until that function returns. */
typedef struct nupp_call nupp_call;
/* A suspended call's completion, owned by the extension until it completes
 * or fails it, exactly once. */
typedef struct nupp_request nupp_request;
typedef struct nupp_host nupp_host;

/*
 * A host function. `instance` is what `init` returned for this VM and `data` is
 * the entry's own pointer. The arguments are checked against the declared
 * parameter types before the call; `nresults` slots, set to nil, receive the
 * results, which are checked against the declared result types after it.
 * Return NUPP_OK, NUPP_ERROR after `raise` (or after a failed `invoke`, to
 * propagate its error), or NUPP_SUSPENDED after `suspend`.
 */
typedef nupp_status (*nupp_function)(const nupp_host *host, nupp_call *call, void *instance, void *data,
                                     const nupp_slot *args, size_t nargs, nupp_slot *results, size_t nresults);

/* Receives the bytes a resource's `save` writes. */
typedef void (*nupp_write)(void *sink, const void *bytes, size_t length);

typedef struct nupp_function_entry {
    const char *name;
    /* A Nupp function type: "function(a: integer, b: integer): integer". */
    const char *signature;
    nupp_function function;
    void *data;
    uint32_t flags; /* zero */
    uint32_t reserved;
} nupp_function_entry;

/*
 * A kind of native object the extension hands to Nupp. The VM owns the object
 * and the extension owns `data`. `drop` runs when the object is closed or its
 * VM ends. `save` and `restore` make the object part of a VM checkpoint; a
 * type without them makes a checkpoint holding one fail, naming the type.
 */
typedef struct nupp_resource_type {
    const char *name;
    void *type_data; /* passed to each hook */
    void (*drop)(void *instance, void *type_data, void *data);
    nupp_status (*save)(void *instance, void *type_data, void *data, nupp_write write, void *sink);
    nupp_status (*restore)(void *instance, void *type_data, const void *bytes, size_t length, void **data);
} nupp_resource_type;

typedef struct nupp_extension {
    uint32_t abi_version; /* NUPP_EXTENSION_ABI_VERSION */
    uint32_t size;        /* sizeof(nupp_extension) */
    const char *module;   /* the module name `require` loads */
    const char *target;   /* NUPP_EXTENSION_TARGET */
    const nupp_function_entry *functions;
    size_t function_count;
    const nupp_resource_type *resource_types;
    size_t resource_type_count;
    /* Optional. Runs once per VM after every check passed. Configuration may
     * live in `*instance`; program state belongs in resources, which a
     * checkpoint can save. */
    nupp_status (*init)(const nupp_host *host, nupp_vm *vm, void **instance);
    /* Optional. Runs when the VM ends, after every resource was dropped. */
    void (*shutdown)(const nupp_host *host, void *instance);
} nupp_extension;

typedef const nupp_extension *(*nupp_extension_entry)(void);

struct nupp_host {
    uint32_t abi_version;
    uint32_t size; /* sizeof(nupp_host) as the VM was built; later versions only append */

    /* Records the error the function raises when it returns NUPP_ERROR. */
    nupp_status (*raise)(nupp_call *call, const char *message, size_t length);

    /* A handle that outlives the call, until `release`. Zero when `handle` is
     * not one. Any function taking a handle accepts a retained one. */
    nupp_handle (*retain)(nupp_call *call, nupp_handle handle);
    void (*release)(nupp_vm *vm, nupp_handle handle);

    /* Calls a Nupp function on the VM's thread, inside this call. Results are
     * valid for this call. An error answers NUPP_ERROR; returning NUPP_ERROR
     * from the host function then raises it to the Nupp caller. */
    nupp_status (*invoke)(nupp_call *call, nupp_handle function, const nupp_slot *args, size_t nargs,
                          nupp_slot *results, size_t nresults);

    /* Parks the calling task: the function returns NUPP_SUSPENDED and the
     * task resumes when the request completes. Null, with an error raised,
     * where the caller cannot park. */
    nupp_request *(*suspend)(nupp_call *call);
    /* Thread-safe. Results are copied; handles cannot cross. */
    void (*complete)(nupp_request *request, const nupp_slot *results, size_t nresults);
    void (*fail)(nupp_request *request, const char *message, size_t length);

    /* A managed object of the extension's resource type `type` owning `data`. */
    nupp_handle (*new_resource)(nupp_call *call, uint32_t type, void *data);
    /* The data of a live resource of type `type`, or null. */
    void *(*resource)(nupp_call *call, nupp_handle handle, uint32_t type);
    /* Drops a resource now; later uses of it see null. */
    nupp_status (*close_resource)(nupp_call *call, nupp_handle handle, uint32_t type);

    nupp_vm *(*vm)(nupp_call *call);
};

#ifdef __cplusplus
}
#endif

#endif
