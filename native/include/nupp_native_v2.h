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
#define NUPP_NATIVE_V2_FEATURE_PROCESS (UINT64_C(1) << 5)
#define NUPP_NATIVE_V2_FEATURE_FILESYSTEM (UINT64_C(1) << 6)
#define NUPP_NATIVE_V2_FEATURE_FILES (UINT64_C(1) << 7)
#define NUPP_NATIVE_V2_FEATURE_NET (UINT64_C(1) << 8)

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
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2SleepMs(double milliseconds);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2Xxh64Digest(
    const uint8_t *data, size_t length, uint8_t *output, size_t capacity);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2TrailerDigest(
    const uint8_t *data, size_t length, uint8_t output[8]);

/* Present when NUPP_NATIVE_V2_FEATURE_FILESYSTEM is set. Path values are
 * length-delimited platform-native bytes and variable outputs are owned byte
 * handles. NUPP_NATIVE_V2_FEATURE_FILES adds the bounded shared whole-file
 * transfer lane. */
typedef struct {
    const uint8_t *data;
    size_t length;
} NuppNativeV2FilesSlice;

typedef struct {
    uint32_t kind;
    int32_t read_only;
    uint64_t size;
    double modified;
} NuppNativeV2FilesInfo;

NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesInfo(
    NuppNativeV2FilesSlice path, int32_t follow,
    NuppNativeV2FilesInfo *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesReadLink(
    NuppNativeV2FilesSlice path, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesList(
    NuppNativeV2FilesSlice path, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesGlob(
    NuppNativeV2FilesSlice pattern, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesCreateTemporary(
    NuppNativeV2FilesSlice directory, NuppNativeV2FilesSlice prefix,
    NuppNativeV2FilesSlice suffix, int32_t as_directory, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesCurrentDirectory(
    uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesCanonicalize(
    NuppNativeV2FilesSlice path, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesUserFolder(
    uint32_t kind, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesCreateSymlink(
    NuppNativeV2FilesSlice target, NuppNativeV2FilesSlice link,
    int32_t directory);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesSetReadOnly(
    NuppNativeV2FilesSlice path, int32_t read_only);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesCreateDirectory(
    NuppNativeV2FilesSlice path);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesRemove(
    NuppNativeV2FilesSlice path, int32_t recursive);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesRename(
    NuppNativeV2FilesSlice from, NuppNativeV2FilesSlice to);

NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FileOpen(
    NuppNativeV2FilesSlice path, uint32_t mode, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FileRead(
    uint64_t file, uint8_t *output, size_t capacity, size_t *length);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FileWrite(
    uint64_t file, const uint8_t *data, size_t length, size_t *written);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FileSeek(
    uint64_t file, int64_t offset, uint32_t origin, int64_t *position);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FileSize(
    uint64_t file, int64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FileFlush(uint64_t file);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FileRelease(uint64_t file);

NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesTransferSubmitRead(
    NuppNativeV2FilesSlice path, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesTransferSubmitWrite(
    NuppNativeV2FilesSlice path, NuppNativeV2FilesSlice data,
    uint32_t mode, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesTransferSubmitCopy(
    NuppNativeV2FilesSlice from, NuppNativeV2FilesSlice to,
    uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesTransferStatus(
    uint64_t transfer, uint32_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesTransferTakeBytes(
    uint64_t transfer, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesTransferCancel(
    uint64_t transfer);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesTransferRelease(
    uint64_t transfer);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesTransferPoll(size_t *ready);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesTransferWait(
    uint64_t timeout_ms, size_t *ready);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2FilesTransferPending(
    size_t *pending);

/* Present when NUPP_NATIVE_V2_FEATURE_NET is set. Rust owns the resolver,
 * sockets and worker tasks. Host names and write bytes are copied during the
 * call; listeners, connects and streams are distinct generational handles. */
typedef struct {
    const uint8_t *data;
    size_t length;
} NuppNativeV2NetSlice;

typedef struct {
    NuppNativeV2NetSlice host;
    uint16_t port;
    uint32_t backlog;
    int32_t reuse_port;
} NuppNativeV2NetListenOptions;

typedef struct {
    NuppNativeV2NetSlice host;
    uint16_t port;
    uint64_t timeout_ms;
} NuppNativeV2NetConnectOptions;

typedef struct {
    uint8_t address[16];
    uint16_t port;
    uint8_t family;
} NuppNativeV2NetAddress;

#define NUPP_NATIVE_V2_NET_ACCEPTED 0u
#define NUPP_NATIVE_V2_NET_PENDING 1u
#define NUPP_NATIVE_V2_NET_READ_DATA 0u
#define NUPP_NATIVE_V2_NET_READ_EOF 2u
#define NUPP_NATIVE_V2_NET_WRITE_ACCEPTED 0u
#define NUPP_NATIVE_V2_NET_WRITE_CLOSED 2u
#define NUPP_NATIVE_V2_NET_CONNECT_PENDING 0u
#define NUPP_NATIVE_V2_NET_CONNECT_READY 1u
#define NUPP_NATIVE_V2_NET_CONNECT_FAILED 2u
#define NUPP_NATIVE_V2_NET_STREAM_READ_EOF (UINT32_C(1) << 0)
#define NUPP_NATIVE_V2_NET_STREAM_WRITE_CLOSED (UINT32_C(1) << 1)
#define NUPP_NATIVE_V2_NET_STREAM_CLOSED (UINT32_C(1) << 2)
#define NUPP_NATIVE_V2_NET_STREAM_SHUTTING_DOWN (UINT32_C(1) << 3)
#define NUPP_NATIVE_V2_NET_STREAM_READ_FAILED (UINT32_C(1) << 4)
#define NUPP_NATIVE_V2_NET_STREAM_WRITE_FAILED (UINT32_C(1) << 5)

NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2NetListenerCreate(
    const NuppNativeV2NetListenOptions *options, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2NetListenerPort(
    uint64_t listener, uint16_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2NetListenerAccept(
    uint64_t listener, uint32_t *state, uint64_t *stream);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2NetListenerRelease(
    uint64_t listener);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2NetConnectCreate(
    const NuppNativeV2NetConnectOptions *options, uint64_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2NetConnectPoll(
    uint64_t connect, uint32_t *state, uint64_t *stream);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2NetConnectCancel(
    uint64_t connect);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2NetConnectRelease(
    uint64_t connect);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2NetStreamRead(
    uint64_t stream, uint8_t *output, size_t capacity,
    uint32_t *state, size_t *length);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2NetStreamWrite(
    uint64_t stream, const uint8_t *data, size_t length,
    uint32_t *state, size_t *accepted);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2NetStreamPendingWrite(
    uint64_t stream, size_t *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2NetStreamState(
    uint64_t stream, uint32_t *flags);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2NetStreamShutdownWrite(
    uint64_t stream);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2NetStreamClose(uint64_t stream);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2NetStreamLocalAddress(
    uint64_t stream, NuppNativeV2NetAddress *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2NetStreamPeerAddress(
    uint64_t stream, NuppNativeV2NetAddress *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2NetStreamSetNoDelay(
    uint64_t stream, int32_t enabled);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2NetStreamSetKeepAlive(
    uint64_t stream, int32_t enabled, uint32_t delay_seconds);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2NetStreamRelease(uint64_t stream);
/* Poll snapshots a monotonic activity generation. Recheck resource state
 * before waiting from that generation so no readiness edge can be lost. */
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2NetPoll(uint64_t *generation);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2NetWait(
    uint64_t generation, uint64_t timeout_ms, uint64_t *output_generation);

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

/* Present when NUPP_NATIVE_V2_FEATURE_PROCESS is set. The complete spawn
 * descriptor is copied synchronously. Child and stream values are opaque
 * generational handles; absent streams are zero. */
typedef struct {
    const uint8_t *data;
    size_t length;
} NuppNativeV2ProcessSlice;

typedef struct {
    NuppNativeV2ProcessSlice name;
    NuppNativeV2ProcessSlice value;
} NuppNativeV2ProcessEnv;

typedef struct {
    const NuppNativeV2ProcessSlice *args;
    size_t arg_count;
    const NuppNativeV2ProcessEnv *env;
    size_t env_count;
    NuppNativeV2ProcessSlice cwd;
    int32_t cwd_present;
    int32_t clear_env;
    uint8_t stdin_mode;
    uint8_t stdout_mode;
    uint8_t stderr_mode;
} NuppNativeV2ProcessSpawn;

typedef struct {
    uint64_t process;
    uint64_t stdin_stream;
    uint64_t stdout_stream;
    uint64_t stderr_stream;
    uint32_t pid;
} NuppNativeV2ProcessStarted;

typedef struct {
    int32_t ready;
    int32_t code;
    int32_t killed;
} NuppNativeV2ProcessExit;

NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2ProcessSpawn(
    const NuppNativeV2ProcessSpawn *spawn, NuppNativeV2ProcessStarted *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2ProcessPollExit(
    uint64_t process, NuppNativeV2ProcessExit *output);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2ProcessKill(
    uint64_t process, int32_t force);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2ProcessRelease(uint64_t process);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2ProcessStreamRead(
    uint64_t stream, uint8_t *output, size_t capacity,
    uint32_t *state, size_t *length);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2ProcessStreamWrite(
    uint64_t stream, const uint8_t *data, size_t length,
    uint32_t *state, size_t *accepted);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2ProcessStreamRelease(uint64_t stream);
NUPP_NATIVE_V2_EXPORT int32_t nuppNativeV2ProcessWait(
    uint64_t process,
    const uint64_t *readable, size_t readable_count,
    const uint64_t *writable, size_t writable_count,
    uint64_t timeout_ms, size_t *ready);
NUPP_NATIVE_V2_EXPORT size_t nuppNativeV2ProcessAbandonedTotal(void);

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
