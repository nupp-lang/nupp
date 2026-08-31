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
    uint8_t adapter[64];
    size_t adapter_length = 0;
    uint64_t uri = 0;
    uint64_t client = 0;
    NuppNativeV2HttpClientOptions http_options = {0};
    int32_t status;

    if (nuppNativeV2AbiVersion() != NUPP_NATIVE_V2_ABI_VERSION) {
        fprintf(stderr, "unexpected ABI version\n");
        return 1;
    }
    if ((nuppNativeV2Features() & (NUPP_NATIVE_V2_FEATURE_BASE
            | NUPP_NATIVE_V2_FEATURE_UUID | NUPP_NATIVE_V2_FEATURE_GPU
            | NUPP_NATIVE_V2_FEATURE_URI | NUPP_NATIVE_V2_FEATURE_HTTP))
        != (NUPP_NATIVE_V2_FEATURE_BASE | NUPP_NATIVE_V2_FEATURE_UUID
            | NUPP_NATIVE_V2_FEATURE_GPU | NUPP_NATIVE_V2_FEATURE_URI
            | NUPP_NATIVE_V2_FEATURE_HTTP)) {
        fprintf(stderr, "a requested Rust-native feature bit is absent\n");
        return 1;
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
