/* The versioned Rust-native ABI. Legacy nupp_native symbols are intentionally
 * absent: a migration must select this provider rather than accidentally link
 * half of each ownership model. */

#ifndef NUPP_NATIVE_H
#define NUPP_NATIVE_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#   if defined(NUPP_NATIVE_STATIC)
#       define NUPP_NATIVE_EXPORT
#   elif defined(NUPP_NATIVE_BUILD)
#       define NUPP_NATIVE_EXPORT __declspec(dllexport)
#   else
#       define NUPP_NATIVE_EXPORT __declspec(dllimport)
#   endif
#else
#   define NUPP_NATIVE_EXPORT __attribute__((visibility("default")))
#endif

#define NUPP_NATIVE_ABI_VERSION 2u

#define NUPP_NATIVE_OK 0
#define NUPP_NATIVE_INVALID_ARGUMENT 1
#define NUPP_NATIVE_CAPACITY 2
#define NUPP_NATIVE_STALE_HANDLE 3
#define NUPP_NATIVE_CLOSED 4
#define NUPP_NATIVE_INTERNAL 5

#define NUPP_NATIVE_FEATURE_BASE (UINT64_C(1) << 0)
#define NUPP_NATIVE_FEATURE_UUID (UINT64_C(1) << 1)
#define NUPP_NATIVE_FEATURE_GPU (UINT64_C(1) << 2)
#define NUPP_NATIVE_FEATURE_URI (UINT64_C(1) << 3)
#define NUPP_NATIVE_FEATURE_HTTP (UINT64_C(1) << 4)
#define NUPP_NATIVE_FEATURE_PROCESS (UINT64_C(1) << 5)
#define NUPP_NATIVE_FEATURE_FILESYSTEM (UINT64_C(1) << 6)
#define NUPP_NATIVE_FEATURE_FILES (UINT64_C(1) << 7)
#define NUPP_NATIVE_FEATURE_NET (UINT64_C(1) << 8)
#define NUPP_NATIVE_FEATURE_TLS (UINT64_C(1) << 9)
#define NUPP_NATIVE_FEATURE_COMPRESSION (UINT64_C(1) << 10)

#ifdef __cplusplus
extern "C" {
#endif

NUPP_NATIVE_EXPORT uint32_t nuppNativeAbiVersion(void);
NUPP_NATIVE_EXPORT uint64_t nuppNativeFeatures(void);
NUPP_NATIVE_EXPORT const char *nuppNativeLastError(void);

NUPP_NATIVE_EXPORT int32_t nuppNativeBytesCreate(
    const uint8_t *data, size_t length, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeBytesCopy(
    uint64_t handle, uint8_t *data, size_t capacity, size_t *length);
NUPP_NATIVE_EXPORT int32_t nuppNativeBytesRelease(uint64_t handle);

NUPP_NATIVE_EXPORT uint64_t nuppNativeMonotonicNs(void);
NUPP_NATIVE_EXPORT uint64_t nuppNativeWallMs(void);
NUPP_NATIVE_EXPORT int32_t nuppNativeSleepMs(double milliseconds);
NUPP_NATIVE_EXPORT size_t nuppNativeAvailableParallelism(void);
NUPP_NATIVE_EXPORT int32_t nuppNativeRandomBytes(uint8_t *output, size_t length);
NUPP_NATIVE_EXPORT int32_t nuppNativeXxh64Digest(
    const uint8_t *data, size_t length, uint8_t *output, size_t capacity);
NUPP_NATIVE_EXPORT int32_t nuppNativeTrailerDigest(
    const uint8_t *data, size_t length, uint8_t output[8]);

/* Present when NUPP_NATIVE_FEATURE_COMPRESSION is set. Formats are 1 gzip,
 * 2 zlib and 3 raw DEFLATE. Step states are 1 need input, 2 need output and
 * 3 finished. Input and output ranges are borrowed only for one call. */
NUPP_NATIVE_EXPORT int32_t nuppNativeCompressionEncoderCreate(
    uint32_t format, uint32_t level, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeCompressionEncoderWrite(
    uint64_t encoder, const uint8_t *input, size_t input_length,
    uint8_t *output, size_t output_capacity, size_t *consumed,
    size_t *written, uint32_t *state);
NUPP_NATIVE_EXPORT int32_t nuppNativeCompressionEncoderFlush(
    uint64_t encoder, uint8_t *output, size_t output_capacity,
    size_t *written, uint32_t *state);
NUPP_NATIVE_EXPORT int32_t nuppNativeCompressionEncoderFinish(
    uint64_t encoder, uint8_t *output, size_t output_capacity,
    size_t *written, uint32_t *state);
NUPP_NATIVE_EXPORT int32_t nuppNativeCompressionEncoderRelease(
    uint64_t encoder);
NUPP_NATIVE_EXPORT int32_t nuppNativeCompressionDecoderCreate(
    uint32_t format, int32_t concatenated_members, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeCompressionDecoderRead(
    uint64_t decoder, const uint8_t *input, size_t input_length,
    uint8_t *output, size_t output_capacity, size_t *consumed,
    size_t *written, uint32_t *state);
NUPP_NATIVE_EXPORT int32_t nuppNativeCompressionDecoderFinishInput(
    uint64_t decoder, uint8_t *output, size_t output_capacity,
    size_t *written, uint32_t *state);
NUPP_NATIVE_EXPORT int32_t nuppNativeCompressionDecoderRelease(
    uint64_t decoder);

/* Present when NUPP_NATIVE_FEATURE_FILESYSTEM is set. Path values are
 * length-delimited platform-native bytes and variable outputs are owned byte
 * handles. NUPP_NATIVE_FEATURE_FILES adds the bounded shared whole-file
 * transfer lane. */
typedef struct {
    const uint8_t *data;
    size_t length;
} NuppNativeFilesSlice;

typedef struct {
    uint32_t kind;
    int32_t read_only;
    uint64_t size;
    double modified;
} NuppNativeFilesInfo;

NUPP_NATIVE_EXPORT int32_t nuppNativeFilesInfo(
    NuppNativeFilesSlice path, int32_t follow,
    NuppNativeFilesInfo *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeFilesReadLink(
    NuppNativeFilesSlice path, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeFilesList(
    NuppNativeFilesSlice path, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeFilesGlob(
    NuppNativeFilesSlice pattern, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeFilesCreateTemporary(
    NuppNativeFilesSlice directory, NuppNativeFilesSlice prefix,
    NuppNativeFilesSlice suffix, int32_t as_directory, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeFilesCurrentDirectory(
    uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeFilesCanonicalize(
    NuppNativeFilesSlice path, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeFilesUserFolder(
    uint32_t kind, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeFilesCreateSymlink(
    NuppNativeFilesSlice target, NuppNativeFilesSlice link,
    int32_t directory);
NUPP_NATIVE_EXPORT int32_t nuppNativeFilesSetReadOnly(
    NuppNativeFilesSlice path, int32_t read_only);
NUPP_NATIVE_EXPORT int32_t nuppNativeFilesCreateDirectory(
    NuppNativeFilesSlice path);
NUPP_NATIVE_EXPORT int32_t nuppNativeFilesRemove(
    NuppNativeFilesSlice path, int32_t recursive);
NUPP_NATIVE_EXPORT int32_t nuppNativeFilesRename(
    NuppNativeFilesSlice from, NuppNativeFilesSlice to);

NUPP_NATIVE_EXPORT int32_t nuppNativeFileOpen(
    NuppNativeFilesSlice path, uint32_t mode, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeFileRead(
    uint64_t file, uint8_t *output, size_t capacity, size_t *length);
NUPP_NATIVE_EXPORT int32_t nuppNativeFileWrite(
    uint64_t file, const uint8_t *data, size_t length, size_t *written);
NUPP_NATIVE_EXPORT int32_t nuppNativeFileSeek(
    uint64_t file, int64_t offset, uint32_t origin, int64_t *position);
NUPP_NATIVE_EXPORT int32_t nuppNativeFileSize(
    uint64_t file, int64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeFileFlush(uint64_t file);
NUPP_NATIVE_EXPORT int32_t nuppNativeFileRelease(uint64_t file);

NUPP_NATIVE_EXPORT int32_t nuppNativeFilesTransferSubmitRead(
    NuppNativeFilesSlice path, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeFilesTransferSubmitWrite(
    NuppNativeFilesSlice path, NuppNativeFilesSlice data,
    uint32_t mode, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeFilesTransferSubmitCopy(
    NuppNativeFilesSlice from, NuppNativeFilesSlice to,
    uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeFilesTransferStatus(
    uint64_t transfer, uint32_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeFilesTransferTakeBytes(
    uint64_t transfer, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeFilesTransferCancel(
    uint64_t transfer);
NUPP_NATIVE_EXPORT int32_t nuppNativeFilesTransferRelease(
    uint64_t transfer);
NUPP_NATIVE_EXPORT int32_t nuppNativeFilesTransferPoll(size_t *ready);
NUPP_NATIVE_EXPORT int32_t nuppNativeFilesTransferWait(
    uint64_t timeout_ms, size_t *ready);
NUPP_NATIVE_EXPORT int32_t nuppNativeFilesTransferPending(
    size_t *pending);

/* Present when NUPP_NATIVE_FEATURE_NET is set. Rust owns the resolver,
 * sockets and worker tasks. Host names and write bytes are copied during the
 * call; listeners, connects and streams are distinct generational handles. */
typedef struct {
    const uint8_t *data;
    size_t length;
} NuppNativeNetSlice;

typedef struct {
    NuppNativeNetSlice host;
    uint16_t port;
    uint32_t backlog;
    int32_t reuse_port;
} NuppNativeNetListenOptions;

typedef struct {
    NuppNativeNetSlice host;
    uint16_t port;
    uint64_t timeout_ms;
} NuppNativeNetConnectOptions;

typedef struct {
    NuppNativeNetSlice path;
    uint32_t backlog;
} NuppNativeNetPathListenOptions;

typedef struct {
    NuppNativeNetSlice path;
    uint64_t timeout_ms;
} NuppNativeNetPathConnectOptions;

typedef struct {
    NuppNativeNetSlice host;
    uint16_t port;
    int32_t reuse_port;
} NuppNativeNetDatagramOptions;

typedef struct {
    uint8_t address[16];
    uint16_t port;
    uint8_t family;
} NuppNativeNetAddress;

#define NUPP_NATIVE_NET_ADDRESS_NONE 0u
#define NUPP_NATIVE_NET_ADDRESS_V4 4u
#define NUPP_NATIVE_NET_ADDRESS_V6 6u
#define NUPP_NATIVE_NET_LISTENER_TCP 0u
#define NUPP_NATIVE_NET_LISTENER_PATH 1u
#define NUPP_NATIVE_NET_ACCEPTED 0u
#define NUPP_NATIVE_NET_PENDING 1u
#define NUPP_NATIVE_NET_READ_DATA 0u
#define NUPP_NATIVE_NET_READ_EOF 2u
#define NUPP_NATIVE_NET_WRITE_ACCEPTED 0u
#define NUPP_NATIVE_NET_WRITE_CLOSED 2u
#define NUPP_NATIVE_NET_CONNECT_PENDING 0u
#define NUPP_NATIVE_NET_CONNECT_READY 1u
#define NUPP_NATIVE_NET_CONNECT_FAILED 2u
#define NUPP_NATIVE_NET_DATAGRAM_MESSAGE 0u
#define NUPP_NATIVE_NET_DATAGRAM_PENDING 1u
#define NUPP_NATIVE_NET_DATAGRAM_SENT 0u
#define NUPP_NATIVE_NET_DATAGRAM_SEND_PENDING 1u
#define NUPP_NATIVE_NET_DATAGRAM_SEND_CLOSED 2u
#define NUPP_NATIVE_NET_STREAM_READ_EOF (UINT32_C(1) << 0)
#define NUPP_NATIVE_NET_STREAM_WRITE_CLOSED (UINT32_C(1) << 1)
#define NUPP_NATIVE_NET_STREAM_CLOSED (UINT32_C(1) << 2)
#define NUPP_NATIVE_NET_STREAM_SHUTTING_DOWN (UINT32_C(1) << 3)
#define NUPP_NATIVE_NET_STREAM_READ_FAILED (UINT32_C(1) << 4)
#define NUPP_NATIVE_NET_STREAM_WRITE_FAILED (UINT32_C(1) << 5)

NUPP_NATIVE_EXPORT int32_t nuppNativeNetListenerCreate(
    const NuppNativeNetListenOptions *options, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetPathListenerCreate(
    const NuppNativeNetPathListenOptions *options, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetListenerPort(
    uint64_t listener, uint16_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetListenerKind(
    uint64_t listener, uint32_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetListenerAccept(
    uint64_t listener, uint32_t *state, uint64_t *stream);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetListenerRelease(
    uint64_t listener);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetConnectCreate(
    const NuppNativeNetConnectOptions *options, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetPathConnectCreate(
    const NuppNativeNetPathConnectOptions *options, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetConnectPoll(
    uint64_t connect, uint32_t *state, uint64_t *stream);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetConnectCancel(
    uint64_t connect);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetConnectRelease(
    uint64_t connect);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetStreamRead(
    uint64_t stream, uint8_t *output, size_t capacity,
    uint32_t *state, size_t *length);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetStreamWrite(
    uint64_t stream, const uint8_t *data, size_t length,
    uint32_t *state, size_t *accepted);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetStreamPendingWrite(
    uint64_t stream, size_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetStreamState(
    uint64_t stream, uint32_t *flags);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetStreamShutdownWrite(
    uint64_t stream);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetStreamClose(uint64_t stream);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetStreamLocalAddress(
    uint64_t stream, NuppNativeNetAddress *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetStreamPeerAddress(
    uint64_t stream, NuppNativeNetAddress *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetStreamSetNoDelay(
    uint64_t stream, int32_t enabled);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetStreamSetKeepAlive(
    uint64_t stream, int32_t enabled, uint32_t delay_seconds);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetStreamRelease(uint64_t stream);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetAddressParse(
    NuppNativeNetSlice host, uint16_t port,
    NuppNativeNetAddress *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetAddressText(
    const NuppNativeNetAddress *address, uint8_t *output,
    size_t capacity, size_t *length);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetDatagramCreate(
    const NuppNativeNetDatagramOptions *options, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetDatagramPort(
    uint64_t datagram, uint16_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetDatagramReceive(
    uint64_t datagram, uint8_t *output, size_t capacity,
    uint32_t *state, size_t *length, NuppNativeNetAddress *address,
    int32_t *truncated);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetDatagramSend(
    uint64_t datagram, const NuppNativeNetAddress *address,
    const uint8_t *data, size_t length, uint32_t *state, size_t *sent);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetDatagramSetBroadcast(
    uint64_t datagram, int32_t enabled);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetDatagramSetMulticastTtl(
    uint64_t datagram, uint32_t ttl);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetDatagramSetMulticastLoop(
    uint64_t datagram, int32_t enabled);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetDatagramMembership(
    uint64_t datagram, NuppNativeNetSlice group,
    NuppNativeNetSlice interface_address, uint32_t interface_index,
    uint8_t interface_kind, int32_t join);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetDatagramRelease(
    uint64_t datagram);
/* Poll snapshots a monotonic activity generation. Recheck resource state
 * before waiting from that generation so no readiness edge can be lost. */
NUPP_NATIVE_EXPORT int32_t nuppNativeNetPoll(uint64_t *generation);
NUPP_NATIVE_EXPORT int32_t nuppNativeNetWait(
    uint64_t generation, uint64_t timeout_ms, uint64_t *output_generation);

/* Present when NUPP_NATIVE_FEATURE_TLS is set. Creating a session consumes
 * its Rust network stream handle on both success and failure. Protocols are a
 * sequence of nonempty names separated and terminated by NUL bytes. */
typedef struct {
    NuppNativeNetSlice hostname;
    NuppNativeNetSlice certificate;
    NuppNativeNetSlice private_key;
    NuppNativeNetSlice authority;
    NuppNativeNetSlice protocols;
    int32_t authority_present;
    int32_t server;
    int32_t verify;
} NuppNativeTlsOptions;

#define NUPP_NATIVE_TLS_HANDSHAKE_PENDING 0u
#define NUPP_NATIVE_TLS_HANDSHAKE_READY 1u
#define NUPP_NATIVE_TLS_READ_DATA 0u
#define NUPP_NATIVE_TLS_READ_PENDING 1u
#define NUPP_NATIVE_TLS_READ_EOF 2u
#define NUPP_NATIVE_TLS_WRITE_ACCEPTED 0u
#define NUPP_NATIVE_TLS_WRITE_PENDING 1u
#define NUPP_NATIVE_TLS_WRITE_CLOSED 2u

NUPP_NATIVE_EXPORT int32_t nuppNativeTlsCreate(
    uint64_t stream, const NuppNativeTlsOptions *options, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeTlsHandshake(
    uint64_t session, uint32_t *state);
NUPP_NATIVE_EXPORT int32_t nuppNativeTlsRead(
    uint64_t session, uint8_t *output, size_t capacity,
    uint32_t *state, size_t *length);
NUPP_NATIVE_EXPORT int32_t nuppNativeTlsWrite(
    uint64_t session, const uint8_t *data, size_t length,
    uint32_t *state, size_t *accepted);
NUPP_NATIVE_EXPORT int32_t nuppNativeTlsFlushed(
    uint64_t session, int32_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeTlsCloseNotify(
    uint64_t session, int32_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeTlsConnected(
    uint64_t session, int32_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeTlsVerified(
    uint64_t session, int32_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeTlsResumed(
    uint64_t session, int32_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeTlsProtocol(
    uint64_t session, uint8_t *output, size_t capacity,
    size_t *length, int32_t *present);
NUPP_NATIVE_EXPORT int32_t nuppNativeTlsRelease(uint64_t session);

/* Present when NUPP_NATIVE_FEATURE_UUID is set. Both outputs require a
 * capacity of at least 37 bytes and include their trailing NUL. */
NUPP_NATIVE_EXPORT int32_t nuppNativeUuid4(uint8_t *output, size_t capacity);
NUPP_NATIVE_EXPORT int32_t nuppNativeUuid7(uint8_t *output, size_t capacity);

/* Present when NUPP_NATIVE_FEATURE_URI is set. URI values are immutable
 * generational handles. Text and components are copied into caller-owned
 * storage; a zero-capacity call queries the required byte count. */
NUPP_NATIVE_EXPORT int32_t nuppNativeUriParse(
    const uint8_t *data, size_t length, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeUriRelease(uint64_t uri);
NUPP_NATIVE_EXPORT int32_t nuppNativeUriPart(
    uint64_t uri, uint32_t kind, uint8_t *output, size_t capacity,
    size_t *length, int32_t *present);
NUPP_NATIVE_EXPORT int32_t nuppNativeUriPort(
    uint64_t uri, int32_t *port);
NUPP_NATIVE_EXPORT int32_t nuppNativeUriWithText(
    uint64_t uri, uint32_t kind, const uint8_t *data, size_t length,
    int32_t present, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeUriWithPort(
    uint64_t uri, int32_t port, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeUriConcatPath(
    uint64_t uri, const uint8_t *suffix, size_t length, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeUriWithEndpoint(
    uint64_t uri, uint64_t endpoint, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeUriResolve(
    uint64_t uri, const uint8_t *reference, size_t length, uint64_t *output);

/* Present when NUPP_NATIVE_FEATURE_HTTP is set. Rust owns every client,
 * transfer, body and worker task; the ABI carries generational handles and
 * copies request/response bytes at each synchronous call boundary. */
typedef struct {
    const uint8_t *data;
    size_t length;
} NuppNativeHttpSlice;

typedef struct {
    NuppNativeHttpSlice name;
    NuppNativeHttpSlice value;
} NuppNativeHttpHeader;

typedef struct {
    uint64_t connect_timeout_ms;
    uint32_t max_redirects;
    uint32_t max_pending_requests;
    uint32_t max_connections;
    uint32_t max_connections_per_host;
    int32_t compressed;
    int32_t has_insecure_hosts;
    int32_t proxy_mode;
    NuppNativeHttpSlice proxy;
    int32_t no_proxy_set;
    NuppNativeHttpSlice no_proxy;
    NuppNativeHttpSlice proxy_credentials;
} NuppNativeHttpClientOptions;

typedef struct {
    NuppNativeHttpSlice url;
    NuppNativeHttpSlice method;
    const NuppNativeHttpHeader *headers;
    size_t header_count;
    NuppNativeHttpSlice body;
    uint32_t body_kind;
    int64_t body_length;
    uint64_t timeout_ms;
    uint64_t stall_timeout_ms;
    uint64_t max_bytes;
    int32_t insecure;
} NuppNativeHttpRequest;

typedef struct {
    uint32_t state;
    uint16_t status;
    uint8_t version;
    size_t url_length;
    size_t headers_length;
} NuppNativeHttpHead;

typedef struct {
    uint64_t transfer;
    uint32_t tokens;
} NuppNativeHttpReady;

NUPP_NATIVE_EXPORT int32_t nuppNativeHttpClientCreate(
    const NuppNativeHttpClientOptions *options, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeHttpClientRelease(uint64_t client);
NUPP_NATIVE_EXPORT int32_t nuppNativeHttpClientSend(
    uint64_t client, const NuppNativeHttpRequest *request, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeHttpClientPending(
    uint64_t client, size_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeHttpTransferCancel(uint64_t transfer);
NUPP_NATIVE_EXPORT int32_t nuppNativeHttpTransferRelease(uint64_t transfer);
NUPP_NATIVE_EXPORT int32_t nuppNativeHttpTransferOffer(
    uint64_t transfer, const uint8_t *data, size_t length, int32_t finished,
    int32_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeHttpTransferPollHead(
    uint64_t transfer, NuppNativeHttpHead *output,
    uint8_t *url, size_t url_capacity,
    uint8_t *headers, size_t headers_capacity);
NUPP_NATIVE_EXPORT int32_t nuppNativeHttpTransferError(
    uint64_t transfer, uint8_t *output, size_t capacity, size_t *length);
NUPP_NATIVE_EXPORT int32_t nuppNativeHttpTransferTakeBody(
    uint64_t transfer, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeHttpBodyArm(uint64_t body);
NUPP_NATIVE_EXPORT int32_t nuppNativeHttpBodyRead(
    uint64_t body, uint8_t *output, size_t capacity,
    uint32_t *state, size_t *length);
NUPP_NATIVE_EXPORT int32_t nuppNativeHttpBodyError(
    uint64_t body, uint8_t *output, size_t capacity, size_t *length);
NUPP_NATIVE_EXPORT int32_t nuppNativeHttpClientPoll(
    uint64_t client, NuppNativeHttpReady *output, size_t capacity,
    size_t *count, int32_t *more);
NUPP_NATIVE_EXPORT int32_t nuppNativeHttpClientWait(
    uint64_t client, uint64_t wait_ms,
    NuppNativeHttpReady *output, size_t capacity,
    size_t *count, int32_t *more);

/* Present when NUPP_NATIVE_FEATURE_PROCESS is set. The complete spawn
 * descriptor is copied synchronously. Child and stream values are opaque
 * generational handles; absent streams are zero. */
typedef struct {
    const uint8_t *data;
    size_t length;
} NuppNativeProcessSlice;

typedef struct {
    NuppNativeProcessSlice name;
    NuppNativeProcessSlice value;
} NuppNativeProcessEnv;

typedef struct {
    const NuppNativeProcessSlice *args;
    size_t arg_count;
    const NuppNativeProcessEnv *env;
    size_t env_count;
    NuppNativeProcessSlice cwd;
    int32_t cwd_present;
    int32_t clear_env;
    uint8_t stdin_mode;
    uint8_t stdout_mode;
    uint8_t stderr_mode;
} NuppNativeProcessSpawn;

typedef struct {
    uint64_t process;
    uint64_t stdin_stream;
    uint64_t stdout_stream;
    uint64_t stderr_stream;
    uint32_t pid;
} NuppNativeProcessStarted;

typedef struct {
    int32_t ready;
    int32_t code;
    int32_t killed;
} NuppNativeProcessExit;

NUPP_NATIVE_EXPORT int32_t nuppNativeProcessSpawn(
    const NuppNativeProcessSpawn *spawn, NuppNativeProcessStarted *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeProcessPollExit(
    uint64_t process, NuppNativeProcessExit *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeProcessKill(
    uint64_t process, int32_t force);
NUPP_NATIVE_EXPORT int32_t nuppNativeProcessRelease(uint64_t process);
NUPP_NATIVE_EXPORT int32_t nuppNativeProcessStreamRead(
    uint64_t stream, uint8_t *output, size_t capacity,
    uint32_t *state, size_t *length);
NUPP_NATIVE_EXPORT int32_t nuppNativeProcessStreamWrite(
    uint64_t stream, const uint8_t *data, size_t length,
    uint32_t *state, size_t *accepted);
NUPP_NATIVE_EXPORT int32_t nuppNativeProcessStreamRelease(uint64_t stream);
NUPP_NATIVE_EXPORT int32_t nuppNativeProcessWait(
    uint64_t process,
    const uint64_t *readable, size_t readable_count,
    const uint64_t *writable, size_t writable_count,
    uint64_t timeout_ms, size_t *ready);
NUPP_NATIVE_EXPORT size_t nuppNativeProcessAbandonedTotal(void);

/* Present when NUPP_NATIVE_FEATURE_GPU is set. Every object is an opaque,
 * generational integer handle; no provider-owned pointer crosses the ABI. */
/* Empty path restores NUPP_GPU_COSTS. Nonempty paths select process-local JSONL. */
NUPP_NATIVE_EXPORT int32_t nuppNativeGpuCostsOutput(const uint8_t *path, size_t length);
NUPP_NATIVE_EXPORT int32_t nuppNativeGpuCostsEnabled(void);
NUPP_NATIVE_EXPORT int32_t nuppNativeGpuCostMetadata(
    uint64_t context, uint64_t handle, int32_t kernel, const uint8_t *json, size_t length);
NUPP_NATIVE_EXPORT int32_t nuppNativeGpuContextCreate(uint64_t *output);
/* `length` receives the byte count excluding the trailing NUL. A NULL output
 * with zero capacity queries that count without copying. */
NUPP_NATIVE_EXPORT int32_t nuppNativeGpuContextDescription(
    uint64_t context, uint8_t *output, size_t capacity, size_t *length);
NUPP_NATIVE_EXPORT int32_t nuppNativeGpuContextRelease(uint64_t context);
NUPP_NATIVE_EXPORT int32_t nuppNativeGpuBufferCreate(
    uint64_t context, uint64_t size, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeGpuBufferRelease(
    uint64_t context, uint64_t buffer);
NUPP_NATIVE_EXPORT int32_t nuppNativeGpuBufferUpload(
    uint64_t context, uint64_t buffer, uint64_t offset,
    const void *data, size_t length);
NUPP_NATIVE_EXPORT int32_t nuppNativeGpuKernelCreate(
    uint64_t context, const uint8_t *spirv, size_t spirv_length,
    const char *entrypoint, size_t entrypoint_length,
    uint32_t readonly_bindings, uint32_t writable_bindings,
    uint64_t uniform_size, uint32_t workgroup_x, uint32_t workgroup_y,
    uint32_t workgroup_z, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeGpuKernelRelease(
    uint64_t context, uint64_t kernel);
NUPP_NATIVE_EXPORT int32_t nuppNativeGpuBindingsCreate(
    uint64_t context, uint64_t kernel, uint64_t *output);
NUPP_NATIVE_EXPORT int32_t nuppNativeGpuBindingsRelease(
    uint64_t context, uint64_t bindings);
NUPP_NATIVE_EXPORT int32_t nuppNativeGpuBindingsSetBuffer(
    uint64_t context, uint64_t bindings, int32_t writable, uint32_t slot,
    uint64_t buffer, uint64_t offset, uint64_t size);
NUPP_NATIVE_EXPORT int32_t nuppNativeGpuDispatch(
    uint64_t context, uint64_t bindings,
    uint32_t work_items_x, uint32_t work_items_y, uint32_t work_items_z,
    const uint8_t *uniforms, size_t uniform_length);
NUPP_NATIVE_EXPORT int32_t nuppNativeGpuDownloadQueue(
    uint64_t context, uint64_t buffer, uint64_t offset, uint64_t size);
NUPP_NATIVE_EXPORT int32_t nuppNativeGpuSynchronize(uint64_t context);
NUPP_NATIVE_EXPORT int32_t nuppNativeGpuDownloadRead(
    uint64_t context, uint64_t buffer, uint64_t offset, uint64_t size,
    void *output, size_t capacity);

#ifdef __cplusplus
}
#endif

#endif /* NUPP_NATIVE_H */
