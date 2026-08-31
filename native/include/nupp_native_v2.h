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

#endif /* NUPP_NATIVE_V2_H */
