/* The versioned Rust-native ABI. Legacy nupp_native symbols are intentionally
 * absent: a migration must select this provider rather than accidentally link
 * half of each ownership model. */

#ifndef NUPP_NATIVE_V2_H
#define NUPP_NATIVE_V2_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#   if defined(NUPP_NATIVE_V2_STATIC)
#       define NUPP_NATIVE_V2_EXPORT
#   elif defined(NUPP_NATIVE_V2_BUILD)
#       define NUPP_NATIVE_V2_EXPORT __declspec(dllexport)
#   else
#       define NUPP_NATIVE_V2_EXPORT __declspec(dllimport)
#   endif
#else
#   define NUPP_NATIVE_V2_EXPORT __attribute__((visibility("default")))
#endif

#define NUPP_NATIVE_V2_ABI_VERSION 2u

#define NUPP_NATIVE_V2_OK 0
#define NUPP_NATIVE_V2_INVALID_ARGUMENT 1
#define NUPP_NATIVE_V2_CAPACITY 2
#define NUPP_NATIVE_V2_STALE_HANDLE 3
#define NUPP_NATIVE_V2_CLOSED 4
#define NUPP_NATIVE_V2_INTERNAL 5

#define NUPP_NATIVE_V2_FEATURE_BASE (UINT64_C(1) << 0)
#define NUPP_NATIVE_V2_FEATURE_UUID (UINT64_C(1) << 1)
#define NUPP_NATIVE_V2_FEATURE_GPU (UINT64_C(1) << 2)
#define NUPP_NATIVE_V2_FEATURE_URI (UINT64_C(1) << 3)
#define NUPP_NATIVE_V2_FEATURE_HTTP (UINT64_C(1) << 4)

#ifdef __cplusplus
extern "C" {
#endif

NUPP_NATIVE_V2_EXPORT uint32_t nuppNativeV2AbiVersion(void);
NUPP_NATIVE_V2_EXPORT uint64_t nuppNativeV2Features(void);
NUPP_NATIVE_V2_EXPORT const char *nuppNativeV2LastError(void);

NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2BytesCreate(
    const uint8_t *data, size_t length, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2BytesCopy(
    uint64_t handle, uint8_t *data, size_t capacity, size_t *length);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2BytesRelease(uint64_t handle);

NUPP_NATIVE_V2_EXPORT uint64_t nuppNativeV2MonotonicNs(void);
NUPP_NATIVE_V2_EXPORT uint64_t nuppNativeV2WallMs(void);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2SleepMs(uint64_t milliseconds);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2Xxh64Digest(
    const uint8_t *data, size_t length, uint8_t *output, size_t capacity);

/* Present when NUPP_NATIVE_V2_FEATURE_UUID is set. Both outputs require a
 * capacity of at least 37 bytes and include their trailing NUL. */
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2Uuid4(uint8_t *output, size_t capacity);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2Uuid7(uint8_t *output, size_t capacity);

/* Present when NUPP_NATIVE_V2_FEATURE_URI is set. URI values are immutable
 * generational handles. Text and components are copied into caller-owned
 * storage; a zero-capacity call queries the required byte count. */
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2UriParse(
    const uint8_t *data, size_t length, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2UriRelease(uint64_t uri);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2UriPart(
    uint64_t uri, uint32_t kind, uint8_t *output, size_t capacity,
    size_t *length, int32_t *present);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2UriPort(
    uint64_t uri, int32_t *port);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2UriWithText(
    uint64_t uri, uint32_t kind, const uint8_t *data, size_t length,
    int32_t present, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2UriWithPort(
    uint64_t uri, int32_t port, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2UriConcatPath(
    uint64_t uri, const uint8_t *suffix, size_t length, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2UriWithEndpoint(
    uint64_t uri, uint64_t endpoint, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2UriResolve(
    uint64_t uri, const uint8_t *reference, size_t length, uint64_t *output);

/* Present when NUPP_NATIVE_V2_FEATURE_HTTP is set. Rust owns every client,
 * transfer, body and worker task; the ABI carries generational handles and
 * copies request/response bytes at each synchronous call boundary. */
typedef struct {
    const uint8_t *data;
    size_t length;
} NuppNativeV2HttpSlice;

typedef struct {
    NuppNativeV2HttpSlice name;
    NuppNativeV2HttpSlice value;
} NuppNativeV2HttpHeader;

typedef struct {
    uint64_t connect_timeout_ms;
    uint32_t max_redirects;
    uint32_t max_pending_requests;
    uint32_t max_connections;
    uint32_t max_connections_per_host;
    int32_t compressed;
    int32_t has_insecure_hosts;
    int32_t proxy_mode;
    NuppNativeV2HttpSlice proxy;
    int32_t no_proxy_set;
    NuppNativeV2HttpSlice no_proxy;
    NuppNativeV2HttpSlice proxy_credentials;
} NuppNativeV2HttpClientOptions;

typedef struct {
    NuppNativeV2HttpSlice url;
    NuppNativeV2HttpSlice method;
    const NuppNativeV2HttpHeader *headers;
    size_t header_count;
    NuppNativeV2HttpSlice body;
    uint32_t body_kind;
    int64_t body_length;
    uint64_t timeout_ms;
    uint64_t stall_timeout_ms;
    uint64_t max_bytes;
    int32_t insecure;
} NuppNativeV2HttpRequest;

typedef struct {
    uint32_t state;
    uint16_t status;
    uint8_t version;
    size_t url_length;
    size_t headers_length;
} NuppNativeV2HttpHead;

typedef struct {
    uint64_t transfer;
    uint32_t tokens;
} NuppNativeV2HttpReady;

NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2HttpClientCreate(
    const NuppNativeV2HttpClientOptions *options, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2HttpClientRelease(uint64_t client);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2HttpClientSend(
    uint64_t client, const NuppNativeV2HttpRequest *request, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2HttpClientPending(
    uint64_t client, size_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2HttpTransferCancel(uint64_t transfer);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2HttpTransferRelease(uint64_t transfer);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2HttpTransferOffer(
    uint64_t transfer, const uint8_t *data, size_t length, int32_t finished,
    int32_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2HttpTransferPollHead(
    uint64_t transfer, NuppNativeV2HttpHead *output,
    uint8_t *url, size_t url_capacity,
    uint8_t *headers, size_t headers_capacity);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2HttpTransferError(
    uint64_t transfer, uint8_t *output, size_t capacity, size_t *length);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2HttpTransferTakeBody(
    uint64_t transfer, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2HttpBodyArm(uint64_t body);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2HttpBodyRead(
    uint64_t body, uint8_t *output, size_t capacity,
    uint32_t *state, size_t *length);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2HttpBodyError(
    uint64_t body, uint8_t *output, size_t capacity, size_t *length);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2HttpClientPoll(
    uint64_t client, NuppNativeV2HttpReady *output, size_t capacity,
    size_t *count, int32_t *more);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2HttpClientWait(
    uint64_t client, uint64_t wait_ms,
    NuppNativeV2HttpReady *output, size_t capacity,
    size_t *count, int32_t *more);

/* Present when NUPP_NATIVE_V2_FEATURE_GPU is set. Every object is an opaque,
 * generational integer handle; no provider-owned pointer crosses the ABI. */
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2GpuContextCreate(uint64_t *output);
/* `length` receives the byte count excluding the trailing NUL. A NULL output
 * with zero capacity queries that count without copying. */
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2GpuContextDescription(
    uint64_t context, uint8_t *output, size_t capacity, size_t *length);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2GpuContextRelease(uint64_t context);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2GpuBufferCreate(
    uint64_t context, uint64_t size, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2GpuBufferRelease(
    uint64_t context, uint64_t buffer);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2GpuBufferUpload(
    uint64_t context, uint64_t buffer, uint64_t offset,
    const void *data, size_t length);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2GpuKernelCreate(
    uint64_t context, const uint8_t *spirv, size_t spirv_length,
    const char *entrypoint, size_t entrypoint_length,
    uint32_t readonly_bindings, uint32_t writable_bindings,
    uint64_t uniform_size, uint32_t workgroup_x, uint32_t workgroup_y,
    uint32_t workgroup_z, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2GpuKernelRelease(
    uint64_t context, uint64_t kernel);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2GpuBindingsCreate(
    uint64_t context, uint64_t kernel, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2GpuBindingsRelease(
    uint64_t context, uint64_t bindings);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2GpuBindingsSetBuffer(
    uint64_t context, uint64_t bindings, int32_t writable, uint32_t slot,
    uint64_t buffer, uint64_t offset, uint64_t size);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2GpuDispatch(
    uint64_t context, uint64_t bindings,
    uint32_t work_items_x, uint32_t work_items_y, uint32_t work_items_z,
    const uint8_t *uniforms, size_t uniform_length);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2GpuDownloadQueue(
    uint64_t context, uint64_t buffer, uint64_t offset, uint64_t size);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2GpuSynchronize(uint64_t context);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2GpuDownloadRead(
    uint64_t context, uint64_t buffer, uint64_t offset, uint64_t size,
    void *output, size_t capacity);

#ifdef __cplusplus
}
#endif

#endif /* NUPP_NATIVE_V2_H */
