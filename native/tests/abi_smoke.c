#include "nupp_native_v2.h"

#include <stdio.h>
#include <string.h>

/* These records are read and written directly across the C/Rust boundary.
 * Keep the offsets explicit so every platform's smoke build checks the layout
 * LuaJIT's FFI and the Rust repr(C) facade agree on. */
_Static_assert(offsetof(NuppNativeV2HttpSlice, data) == 0,
    "HTTP slice data moved");
_Static_assert(offsetof(NuppNativeV2HttpSlice, length) == sizeof(void *),
    "HTTP slice length has an unexpected offset");
_Static_assert(offsetof(NuppNativeV2HttpHead, state) == 0,
    "HTTP head state moved");
_Static_assert(offsetof(NuppNativeV2HttpHead, status) == 4,
    "HTTP head status has an unexpected offset");
_Static_assert(offsetof(NuppNativeV2HttpHead, version) == 6,
    "HTTP head version has an unexpected offset");
_Static_assert(offsetof(NuppNativeV2HttpHead, url_length) == 8,
    "HTTP head URL length has an unexpected offset");
_Static_assert(offsetof(NuppNativeV2HttpHead, headers_length)
        == 8 + sizeof(size_t),
    "HTTP head header length has an unexpected offset");
_Static_assert(offsetof(NuppNativeV2HttpReady, transfer) == 0,
    "HTTP ready handle moved");
_Static_assert(offsetof(NuppNativeV2HttpReady, tokens) == sizeof(uint64_t),
    "HTTP ready tokens have an unexpected offset");
_Static_assert(offsetof(NuppNativeV2FilesSlice, length) == sizeof(void *),
    "filesystem slice length has an unexpected offset");
_Static_assert(offsetof(NuppNativeV2FilesInfo, read_only) == 4,
    "filesystem info read-only flag has an unexpected offset");
_Static_assert(offsetof(NuppNativeV2FilesInfo, size) == 8,
    "filesystem info size has an unexpected offset");
_Static_assert(offsetof(NuppNativeV2FilesInfo, modified) == 16,
    "filesystem info modification time has an unexpected offset");
_Static_assert(offsetof(NuppNativeV2TlsOptions, certificate)
        == sizeof(NuppNativeV2NetSlice),
    "TLS certificate slice has an unexpected offset");
_Static_assert(offsetof(NuppNativeV2TlsOptions, authority_present)
        == 5 * sizeof(NuppNativeV2NetSlice),
    "TLS authority-present flag has an unexpected offset");
_Static_assert(offsetof(NuppNativeV2TlsOptions, verify)
        == 5 * sizeof(NuppNativeV2NetSlice) + 2 * sizeof(int32_t),
    "TLS verify flag has an unexpected offset");

static int failed(const char *operation, int32_t status) {
    fprintf(stderr, "%s: status %d: %s\n", operation, status,
        nuppNativeV2LastError());
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
    NuppNativeV2FilesInfo file_info = {0};
    NuppNativeV2FilesSlice current = {
        (const uint8_t *)".", sizeof "." - 1};
    NuppNativeV2FilesSlice cargo = {
        (const uint8_t *)"Cargo.toml", sizeof "Cargo.toml" - 1};
    NuppNativeV2HttpClientOptions http_options = {0};
    int32_t status;

    if (nuppNativeV2AbiVersion() != NUPP_NATIVE_V2_ABI_VERSION) {
        fprintf(stderr, "unexpected ABI version\n");
        return 1;
    }
    if ((nuppNativeV2Features() & (NUPP_NATIVE_V2_FEATURE_BASE
            | NUPP_NATIVE_V2_FEATURE_UUID | NUPP_NATIVE_V2_FEATURE_GPU
            | NUPP_NATIVE_V2_FEATURE_URI | NUPP_NATIVE_V2_FEATURE_HTTP
            | NUPP_NATIVE_V2_FEATURE_PROCESS
            | NUPP_NATIVE_V2_FEATURE_FILESYSTEM
            | NUPP_NATIVE_V2_FEATURE_FILES | NUPP_NATIVE_V2_FEATURE_NET
            | NUPP_NATIVE_V2_FEATURE_TLS))
        != (NUPP_NATIVE_V2_FEATURE_BASE | NUPP_NATIVE_V2_FEATURE_UUID
            | NUPP_NATIVE_V2_FEATURE_GPU | NUPP_NATIVE_V2_FEATURE_URI
            | NUPP_NATIVE_V2_FEATURE_HTTP | NUPP_NATIVE_V2_FEATURE_PROCESS
            | NUPP_NATIVE_V2_FEATURE_FILESYSTEM
            | NUPP_NATIVE_V2_FEATURE_FILES | NUPP_NATIVE_V2_FEATURE_NET
            | NUPP_NATIVE_V2_FEATURE_TLS)) {
        fprintf(stderr, "a requested Rust-native feature bit is absent\n");
        return 1;
    }
    {
        NuppNativeV2ProcessExit process_exit = {0};
        if (nuppNativeV2ProcessPollExit(0, &process_exit)
            != NUPP_NATIVE_V2_STALE_HANDLE) {
            fprintf(stderr, "invalid process handle was accepted\n");
            return 1;
        }
    }
    {
        int32_t connected = 0;
        if (nuppNativeV2TlsConnected(0, &connected)
                != NUPP_NATIVE_V2_STALE_HANDLE
            || nuppNativeV2TlsConnected(0, NULL)
                != NUPP_NATIVE_V2_INVALID_ARGUMENT) {
            fprintf(stderr, "invalid TLS handle or output was accepted\n");
            return 1;
        }
    }
    if (nuppNativeV2GpuBufferRelease(0, 1)
        != NUPP_NATIVE_V2_STALE_HANDLE) {
        fprintf(stderr, "invalid GPU context was accepted\n");
        return 1;
    }
    if (nuppNativeV2GpuContextDescription(
            0, adapter, sizeof adapter, &adapter_length)
        != NUPP_NATIVE_V2_STALE_HANDLE) {
        fprintf(stderr, "invalid GPU context description was accepted\n");
        return 1;
    }
    status = nuppNativeV2FilesInfo(current, 1, &file_info);
    if (status != NUPP_NATIVE_V2_OK) return failed("filesystem info", status);
    if (file_info.kind != 2) {
        fprintf(stderr, "current directory is not a directory\n");
        return 1;
    }
    status = nuppNativeV2FileOpen(cargo, 0, &file);
    if (status != NUPP_NATIVE_V2_OK) return failed("file open", status);
    status = nuppNativeV2FileSize(file, &file_size);
    if (status != NUPP_NATIVE_V2_OK) return failed("file size", status);
    if (file_size <= 0) {
        fprintf(stderr, "Cargo.toml is unexpectedly empty\n");
        return 1;
    }
    if (nuppNativeV2FilesTransferStatus(file, &transfer_state)
        != NUPP_NATIVE_V2_INVALID_ARGUMENT) {
        fprintf(stderr, "open file was accepted as a transfer\n");
        return 1;
    }
    status = nuppNativeV2FileRelease(file);
    if (status != NUPP_NATIVE_V2_OK) return failed("file release", status);
    if (nuppNativeV2FileRelease(file) != NUPP_NATIVE_V2_STALE_HANDLE) {
        fprintf(stderr, "released file handle was revived\n");
        return 1;
    }
    status = nuppNativeV2BytesCreate(expected, sizeof expected - 1, &handle);
    if (status != NUPP_NATIVE_V2_OK) return failed("bytes create", status);
    status = nuppNativeV2BytesCopy(handle, view, sizeof view, &length);
    if (status != NUPP_NATIVE_V2_OK) return failed("bytes copy", status);
    if (length != sizeof expected - 1 || memcmp(view, expected, length) != 0) {
        fprintf(stderr, "byte view changed its payload\n");
        return 1;
    }
    status = nuppNativeV2BytesRelease(handle);
    if (status != NUPP_NATIVE_V2_OK) return failed("bytes release", status);
    if (nuppNativeV2BytesRelease(handle) != NUPP_NATIVE_V2_STALE_HANDLE) {
        fprintf(stderr, "released handle was revived\n");
        return 1;
    }
    status = nuppNativeV2Uuid4(uuid, sizeof uuid);
    if (status != NUPP_NATIVE_V2_OK) return failed("uuid4", status);
    if (uuid[14] != '4' || uuid[36] != '\0') {
        fprintf(stderr, "uuid4 is not canonical\n");
        return 1;
    }
    status = nuppNativeV2Uuid7(uuid, sizeof uuid);
    if (status != NUPP_NATIVE_V2_OK) return failed("uuid7", status);
    if (uuid[14] != '7' || uuid[36] != '\0') {
        fprintf(stderr, "uuid7 is not canonical\n");
        return 1;
    }
    if (nuppNativeV2Uuid4(uuid, sizeof uuid - 1)
        != NUPP_NATIVE_V2_CAPACITY) {
        fprintf(stderr, "uuid4 accepted a short output\n");
        return 1;
    }
    status = nuppNativeV2Xxh64Digest(NULL, 0, digest, sizeof digest);
    if (status != NUPP_NATIVE_V2_OK) return failed("xxh64", status);
    status = nuppNativeV2TrailerDigest(NULL, 0, trailer);
    if (status != NUPP_NATIVE_V2_OK) return failed("trailer digest", status);
    if (memcmp(trailer, "\x99\xe9\xd8\x51\x37\xdb\x46\xef", 8) != 0) {
        fprintf(stderr, "trailer digest did not match the published vector\n");
        return 1;
    }
    status = nuppNativeV2SleepMs(-1.0);
    if (status != NUPP_NATIVE_V2_INVALID_ARGUMENT) {
        fprintf(stderr, "negative sleep duration was accepted\n");
        return 1;
    }
    if (memcmp(digest, "ef46db3751d8e999", 16) != 0) {
        fprintf(stderr, "XXH64 digest changed\n");
        return 1;
    }
    status = nuppNativeV2UriParse((const uint8_t *)"https://EXAMPLE.com",
        sizeof "https://EXAMPLE.com" - 1, &uri);
    if (status != NUPP_NATIVE_V2_OK) return failed("URI parse", status);
    status = nuppNativeV2UriRelease(uri);
    if (status != NUPP_NATIVE_V2_OK) return failed("URI release", status);
    if (nuppNativeV2UriRelease(uri) != NUPP_NATIVE_V2_STALE_HANDLE) {
        fprintf(stderr, "released URI handle was revived\n");
        return 1;
    }
    http_options.connect_timeout_ms = 1000;
    http_options.max_pending_requests = 1;
    http_options.max_connections = 1;
    http_options.max_connections_per_host = 1;
    http_options.proxy_mode = 1;
    status = nuppNativeV2HttpClientCreate(&http_options, &client);
    if (status != NUPP_NATIVE_V2_OK) return failed("HTTP client create", status);
    status = nuppNativeV2HttpClientRelease(client);
    if (status != NUPP_NATIVE_V2_OK) return failed("HTTP client release", status);
    if (nuppNativeV2HttpClientPending(client, &length)
        != NUPP_NATIVE_V2_STALE_HANDLE) {
        fprintf(stderr, "released HTTP client handle was revived\n");
        return 1;
    }
    return 0;
}
