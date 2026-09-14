#include "nupp_native.h"

#include <stdio.h>
#include <string.h>

/* These records are read and written directly across the C/Rust boundary.
 * Keep the offsets explicit so every platform's smoke build checks the layout
 * LuaJIT's FFI and the Rust repr(C) facade agree on. */
_Static_assert(offsetof(NuppNativeHttpSlice, data) == 0,
    "HTTP slice data moved");
_Static_assert(offsetof(NuppNativeHttpSlice, length) == sizeof(void *),
    "HTTP slice length has an unexpected offset");
_Static_assert(offsetof(NuppNativeHttpHead, state) == 0,
    "HTTP head state moved");
_Static_assert(offsetof(NuppNativeHttpHead, status) == 4,
    "HTTP head status has an unexpected offset");
_Static_assert(offsetof(NuppNativeHttpHead, version) == 6,
    "HTTP head version has an unexpected offset");
_Static_assert(offsetof(NuppNativeHttpHead, url_length) == 8,
    "HTTP head URL length has an unexpected offset");
_Static_assert(offsetof(NuppNativeHttpHead, headers_length)
        == 8 + sizeof(size_t),
    "HTTP head header length has an unexpected offset");
_Static_assert(offsetof(NuppNativeHttpReady, transfer) == 0,
    "HTTP ready handle moved");
_Static_assert(offsetof(NuppNativeHttpReady, tokens) == sizeof(uint64_t),
    "HTTP ready tokens have an unexpected offset");
_Static_assert(offsetof(NuppNativeFilesSlice, length) == sizeof(void *),
    "filesystem slice length has an unexpected offset");
_Static_assert(offsetof(NuppNativeFilesInfo, read_only) == 4,
    "filesystem info read-only flag has an unexpected offset");
_Static_assert(offsetof(NuppNativeFilesInfo, size) == 8,
    "filesystem info size has an unexpected offset");
_Static_assert(offsetof(NuppNativeFilesInfo, modified) == 16,
    "filesystem info modification time has an unexpected offset");
_Static_assert(offsetof(NuppNativeTlsOptions, certificate)
        == sizeof(NuppNativeNetSlice),
    "TLS certificate slice has an unexpected offset");
_Static_assert(offsetof(NuppNativeTlsOptions, authority_present)
        == 5 * sizeof(NuppNativeNetSlice),
    "TLS authority-present flag has an unexpected offset");
_Static_assert(offsetof(NuppNativeTlsOptions, verify)
        == 5 * sizeof(NuppNativeNetSlice) + 2 * sizeof(int32_t),
    "TLS verify flag has an unexpected offset");

static int failed(const char *operation, int32_t status) {
    fprintf(stderr, "%s: status %d: %s\n", operation, status,
        nuppNativeLastError());
    return 1;
}

int main(void) {
    static const uint8_t expected[] = "payload";
    uint8_t view[sizeof expected - 1];
    size_t length = 0;
    uint64_t handle = 0;
    uint8_t uuid[37];
    uint8_t digest[32];
    uint8_t trailer[8];
    uint8_t adapter[64];
    size_t adapter_length = 0;
    uint64_t uri = 0;
    uint64_t client = 0;
    uint64_t file = 0;
    int64_t file_size = 0;
    uint32_t transfer_state = 0;
    NuppNativeFilesInfo file_info = {0};
    NuppNativeFilesSlice current = {
        (const uint8_t *)".", sizeof "." - 1};
    NuppNativeFilesSlice cargo = {
        (const uint8_t *)"Cargo.toml", sizeof "Cargo.toml" - 1};
    NuppNativeHttpClientOptions http_options = {0};
    int32_t status;

    if (nuppNativeAbiVersion() != NUPP_NATIVE_ABI_VERSION) {
        fprintf(stderr, "unexpected ABI version\n");
        return 1;
    }
    if ((nuppNativeFeatures() & (NUPP_NATIVE_FEATURE_BASE
            | NUPP_NATIVE_FEATURE_UUID | NUPP_NATIVE_FEATURE_GPU
            | NUPP_NATIVE_FEATURE_URI | NUPP_NATIVE_FEATURE_HTTP
            | NUPP_NATIVE_FEATURE_PROCESS
            | NUPP_NATIVE_FEATURE_FILESYSTEM
            | NUPP_NATIVE_FEATURE_FILES | NUPP_NATIVE_FEATURE_NET
            | NUPP_NATIVE_FEATURE_TLS))
        != (NUPP_NATIVE_FEATURE_BASE | NUPP_NATIVE_FEATURE_UUID
            | NUPP_NATIVE_FEATURE_GPU | NUPP_NATIVE_FEATURE_URI
            | NUPP_NATIVE_FEATURE_HTTP | NUPP_NATIVE_FEATURE_PROCESS
            | NUPP_NATIVE_FEATURE_FILESYSTEM
            | NUPP_NATIVE_FEATURE_FILES | NUPP_NATIVE_FEATURE_NET
            | NUPP_NATIVE_FEATURE_TLS)) {
        fprintf(stderr, "a requested Rust-native feature bit is absent\n");
        return 1;
    }
    {
        NuppNativeProcessExit process_exit = {0};
        if (nuppNativeProcessPollExit(0, &process_exit)
            != NUPP_NATIVE_STALE_HANDLE) {
            fprintf(stderr, "invalid process handle was accepted\n");
            return 1;
        }
    }
    {
        int32_t connected = 0;
        if (nuppNativeTlsConnected(0, &connected)
                != NUPP_NATIVE_STALE_HANDLE
            || nuppNativeTlsConnected(0, NULL)
                != NUPP_NATIVE_INVALID_ARGUMENT) {
            fprintf(stderr, "invalid TLS handle or output was accepted\n");
            return 1;
        }
    }
    if (nuppNativeGpuBufferRelease(0, 1)
        != NUPP_NATIVE_STALE_HANDLE) {
        fprintf(stderr, "invalid GPU context was accepted\n");
        return 1;
    }
    if (nuppNativeGpuContextDescription(
            0, adapter, sizeof adapter, &adapter_length)
        != NUPP_NATIVE_STALE_HANDLE) {
        fprintf(stderr, "invalid GPU context description was accepted\n");
        return 1;
    }
    status = nuppNativeFilesInfo(current, 1, &file_info);
    if (status != NUPP_NATIVE_OK) return failed("filesystem info", status);
    if (file_info.kind != 2) {
        fprintf(stderr, "current directory is not a directory\n");
        return 1;
    }
    status = nuppNativeFileOpen(cargo, 0, &file);
    if (status != NUPP_NATIVE_OK) return failed("file open", status);
    status = nuppNativeFileSize(file, &file_size);
    if (status != NUPP_NATIVE_OK) return failed("file size", status);
    if (file_size <= 0) {
        fprintf(stderr, "Cargo.toml is unexpectedly empty\n");
        return 1;
    }
    if (nuppNativeFilesTransferStatus(file, &transfer_state)
        != NUPP_NATIVE_INVALID_ARGUMENT) {
        fprintf(stderr, "open file was accepted as a transfer\n");
        return 1;
    }
    status = nuppNativeFileRelease(file);
    if (status != NUPP_NATIVE_OK) return failed("file release", status);
    if (nuppNativeFileRelease(file) != NUPP_NATIVE_STALE_HANDLE) {
        fprintf(stderr, "released file handle was revived\n");
        return 1;
    }
    status = nuppNativeBytesCreate(expected, sizeof expected - 1, &handle);
    if (status != NUPP_NATIVE_OK) return failed("bytes create", status);
    status = nuppNativeBytesCopy(handle, view, sizeof view, &length);
    if (status != NUPP_NATIVE_OK) return failed("bytes copy", status);
    if (length != sizeof expected - 1 || memcmp(view, expected, length) != 0) {
        fprintf(stderr, "byte view changed its payload\n");
        return 1;
    }
    status = nuppNativeBytesRelease(handle);
    if (status != NUPP_NATIVE_OK) return failed("bytes release", status);
    if (nuppNativeBytesRelease(handle) != NUPP_NATIVE_STALE_HANDLE) {
        fprintf(stderr, "released handle was revived\n");
        return 1;
    }
    status = nuppNativeUuid4(uuid, sizeof uuid);
    if (status != NUPP_NATIVE_OK) return failed("uuid4", status);
    if (uuid[14] != '4' || uuid[36] != '\0') {
        fprintf(stderr, "uuid4 is not canonical\n");
        return 1;
    }
    status = nuppNativeUuid7(uuid, sizeof uuid);
    if (status != NUPP_NATIVE_OK) return failed("uuid7", status);
    if (uuid[14] != '7' || uuid[36] != '\0') {
        fprintf(stderr, "uuid7 is not canonical\n");
        return 1;
    }
    if (nuppNativeUuid4(uuid, sizeof uuid - 1)
        != NUPP_NATIVE_CAPACITY) {
        fprintf(stderr, "uuid4 accepted a short output\n");
        return 1;
    }
    status = nuppNativeXxh64Digest(NULL, 0, digest, sizeof digest);
    if (status != NUPP_NATIVE_OK) return failed("xxh64", status);
    status = nuppNativeTrailerDigest(NULL, 0, trailer);
    if (status != NUPP_NATIVE_OK) return failed("trailer digest", status);
    if (memcmp(trailer, "\x99\xe9\xd8\x51\x37\xdb\x46\xef", 8) != 0) {
        fprintf(stderr, "trailer digest did not match the published vector\n");
        return 1;
    }
    status = nuppNativeSleepMs(-1.0);
    if (status != NUPP_NATIVE_INVALID_ARGUMENT) {
        fprintf(stderr, "negative sleep duration was accepted\n");
        return 1;
    }
    if (memcmp(digest, "ef46db3751d8e999", 16) != 0) {
        fprintf(stderr, "XXH64 digest changed\n");
        return 1;
    }
    status = nuppNativeUriParse((const uint8_t *)"https://EXAMPLE.com",
        sizeof "https://EXAMPLE.com" - 1, &uri);
    if (status != NUPP_NATIVE_OK) return failed("URI parse", status);
    status = nuppNativeUriRelease(uri);
    if (status != NUPP_NATIVE_OK) return failed("URI release", status);
    if (nuppNativeUriRelease(uri) != NUPP_NATIVE_STALE_HANDLE) {
        fprintf(stderr, "released URI handle was revived\n");
        return 1;
    }
    http_options.connect_timeout_ms = 1000;
    http_options.max_pending_requests = 1;
    http_options.max_connections = 1;
    http_options.max_connections_per_host = 1;
    http_options.proxy_mode = 1;
    status = nuppNativeHttpClientCreate(&http_options, &client);
    if (status != NUPP_NATIVE_OK) return failed("HTTP client create", status);
    status = nuppNativeHttpClientRelease(client);
    if (status != NUPP_NATIVE_OK) return failed("HTTP client release", status);
    if (nuppNativeHttpClientPending(client, &length)
        != NUPP_NATIVE_STALE_HANDLE) {
        fprintf(stderr, "released HTTP client handle was revived\n");
        return 1;
    }
    return 0;
}
