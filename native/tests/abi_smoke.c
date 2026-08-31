#include "nupp_native_v2.h"

#include <stdio.h>
#include <string.h>

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
    int32_t status;

    if (nuppNativeV2AbiVersion() != NUPP_NATIVE_V2_ABI_VERSION) {
        fprintf(stderr, "unexpected ABI version\n");
        return 1;
    }
    if ((nuppNativeV2Features() & (NUPP_NATIVE_V2_FEATURE_BASE
            | NUPP_NATIVE_V2_FEATURE_UUID | NUPP_NATIVE_V2_FEATURE_GPU))
        != (NUPP_NATIVE_V2_FEATURE_BASE | NUPP_NATIVE_V2_FEATURE_UUID
            | NUPP_NATIVE_V2_FEATURE_GPU)) {
        fprintf(stderr, "base/UUID/GPU feature bits are absent\n");
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
    status = nuppNativeV2Xxh64Digest(NULL, 0, digest, sizeof digest);
    if (status != NUPP_NATIVE_V2_OK) return failed("xxh64", status);
    if (memcmp(digest, "ef46db3751d8e999", 16) != 0) {
        fprintf(stderr, "XXH64 digest changed\n");
        return 1;
    }
    return 0;
}
