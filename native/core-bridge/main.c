/* Initial artifact/entry bootstrap. The code it invokes is Nupp; this file
 * knows no value, frame, task, collector, instruction or optimizer layout. */
#define _DARWIN_C_SOURCE 1
#define _GNU_SOURCE 1
#include "transport.h"
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#ifdef __APPLE__
#include <libkern/OSCacheControl.h>
#endif

enum { HEADER = 72 };
static const uint64_t REGION = UINT64_C(1024) * 1024 * 1024;
static const uint64_t MAX_WORDS = UINT64_C(1024) * 1024;
static uint64_t symbols[1024];
/* Startup metadata, read by the Nupp loader through ordinary checked FFI. */
const char *nupp_core_artifact_directory;
static uint64_t little(const unsigned char *p) {
    uint64_t value = 0;
    for (unsigned i = 0; i < 8; ++i) value |= (uint64_t)p[i] << (i * 8);
    return value;
}
static int error(const char *message) {
    fprintf(stderr, "nupp-core: %s\n", message);
    return 1;
}
static void *mapping(size_t bytes) {
    if (!bytes) return NULL;
    void *value = mmap(NULL, bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    return value == MAP_FAILED ? NULL : value;
}
static int input(const char *name, uint64_t **words, size_t *count) {
    FILE *file = fopen(name, "rb");
    if (!file) return error("input cannot be opened");
    struct stat info;
    if (fstat(fileno(file), &info) || info.st_size < 0 || info.st_size % 8 || (uint64_t)info.st_size / 8 > MAX_WORDS) {
        fclose(file); return error("input must contain bounded complete words");
    }
    size_t bytes = (size_t)info.st_size;
    unsigned char *raw = malloc(bytes ? bytes : 1);
    if (!raw) { fclose(file); return error("input allocation failed"); }
    int okay = fread(raw, 1, bytes, file) == bytes && fgetc(file) == EOF && !ferror(file);
    fclose(file);
    if (!okay) { free(raw); return error("input changed while reading"); }
    *count = bytes / 8;
    *words = (uint64_t *)raw;
    for (size_t i = 0; i < *count; ++i) (*words)[i] = little(raw + i * 8);
    return 0;
}
typedef uint64_t (*Entry)(const uint64_t *, uint64_t *);
#ifdef NUPP_CORE_GUARD
extern void nupp_core_test_abi(Entry, const uint64_t *, uint64_t *, uint64_t *);
#endif
static int execute(const char *name, const uint64_t *words, size_t count, uint64_t **answer, size_t *length, uint64_t *status) {
#if !defined(__aarch64__) && !defined(__arm64__)
    return error("standalone bridge requires little-endian ARM64 macOS or Linux");
#endif
    unsigned char header[HEADER];
    FILE *file = fopen(name, "rb");
    if (!file) return error("bundle cannot be opened");
    struct stat info;
    if (fstat(fileno(file), &info) || info.st_size < HEADER || fread(header, 1, HEADER, file) != HEADER ||
        memcmp(header, "NUPPCORE", 8)) { fclose(file); return error("invalid bundle header"); }
    uint64_t fields[8];
    for (unsigned i = 0; i < 8; ++i) fields[i] = little(header + 8 + i * 8);
    uint64_t entry = fields[2], code_bytes = fields[3], data_bytes = fields[4], scratch_bytes = fields[5], output = fields[6];
    if (fields[0] != 1 || fields[1] != 1 || fields[7]) { fclose(file); return error("unsupported bundle version, architecture or reserved field"); }
    if (!code_bytes || code_bytes % 4 || entry % 4 || entry >= code_bytes) { fclose(file); return error("invalid code extent or entry alignment"); }
    if (code_bytes > REGION || data_bytes > REGION || scratch_bytes > REGION || output > MAX_WORDS) {
        fclose(file); return error("bundle region exceeds transport limit");
    }
    if (code_bytes + data_bytes + scratch_bytes > REGION * 2 || code_bytes + data_bytes + HEADER != (uint64_t)info.st_size) {
        fclose(file); return error("bundle extent differs from file or exceeds total limit");
    }
    long host_page = sysconf(_SC_PAGESIZE);
    if (host_page <= 0 || (host_page & (host_page - 1))) { fclose(file); return error("invalid host page size"); }
    size_t page = (size_t)host_page;
    size_t scratch_extent = (size_t)scratch_bytes;
    size_t high_water = scratch_extent;
#ifdef NUPP_CORE_GUARD
    const char *limit = getenv("CORE_TEST_HIGH_WATER");
    if (limit) {
        char *end;
        errno = 0; unsigned long long parsed = strtoull(limit, &end, 10);
        if (errno || !*limit || *end || parsed > scratch_extent) { fclose(file); return error("invalid scratch high-water"); }
        high_water = (size_t)parsed;
    }
    if (scratch_extent) scratch_extent = ((scratch_extent + page - 1) & ~(page - 1)) + page * 2;
#else
    (void)page; (void)high_water;
#endif
    unsigned char *code = mapping((size_t)code_bytes), *data = mapping((size_t)data_bytes), *scratch_base = mapping(scratch_extent);
    unsigned char *scratch = scratch_base;
    uint64_t *out = calloc(output ? (size_t)output : 1, sizeof(uint64_t));
    int result = 1;
    if (!code || (data_bytes && !data) || (scratch_extent && !scratch_base) || !out) { error("map failed"); goto done; }
    if (fread(code, 1, (size_t)code_bytes, file) != code_bytes || (data_bytes && fread(data, 1, (size_t)data_bytes, file) != data_bytes) ||
        fgetc(file) != EOF || ferror(file)) { error("bundle changed while reading"); goto done; }
    if (mprotect(code, (size_t)code_bytes, PROT_READ | PROT_EXEC)) { error("seal failed"); goto done; }
#ifdef __APPLE__
    sys_icache_invalidate(code, (size_t)code_bytes);
#else
    __builtin___clear_cache((char *)code, (char *)code + code_bytes);
#endif
#ifdef NUPP_CORE_GUARD
    if (scratch_extent) {
        scratch += page;
        if (mprotect(scratch_base, page, PROT_NONE) || mprotect(scratch_base + scratch_extent - page, page, PROT_NONE)) {
            error("test guard protection failed"); goto done;
        }
        memset(scratch + high_water, 0xa5, scratch_extent - page * 2 - high_water);
    }
#endif
    uint64_t edges[] = {(uintptr_t)nupp_io_start, (uintptr_t)nupp_io_submit, (uintptr_t)nupp_io_take,
        (uintptr_t)nupp_io_finish, (uintptr_t)nupp_io_cancel, (uintptr_t)nupp_io_settle,
        (uintptr_t)dlopen, (uintptr_t)dlsym, (uintptr_t)dlclose, (uintptr_t)symbols};
    uint64_t packet[] = {1, (uintptr_t)code, code_bytes, (uintptr_t)data, data_bytes, (uintptr_t)scratch,
        scratch_bytes, (uintptr_t)edges, 10, (uintptr_t)words, count, output};
    Entry function = (Entry)(code + entry);
#ifdef NUPP_CORE_GUARD
    uint64_t report[2] = {0, 0};
    nupp_core_test_abi(function, packet, out, report);
    if (report[1]) { error("C ABI preservation failed"); goto done; }
    *status = report[0];
    for (size_t i = high_water; scratch_extent && i < scratch_extent - page * 2; ++i) {
        if (scratch[i] != 0xa5) { error("scratch high-water canary changed"); goto done; }
    }
#else
    *status = function(packet, out);
#endif
    *answer = out; *length = (size_t)output; out = NULL; result = 0;
done:
    fclose(file);
    if (code) munmap(code, (size_t)code_bytes);
    if (data) munmap(data, (size_t)data_bytes);
    if (scratch_base) munmap(scratch_base, scratch_extent);
    free(out);
    return result;
}
int main(int argc, char **argv) {
    if (argc < 4) return error("usage: nupp-core BUNDLE INPUT OUTPUT [ARGUMENT...]");
    char *canonical = realpath(argv[1], NULL);
    if (!canonical) return error("bundle cannot be resolved");
    char *slash = strrchr(canonical, '/');
    if (!slash) { free(canonical); return error("bundle has no parent directory"); }
    if (slash == canonical) slash[1] = 0; else *slash = 0;
    nupp_core_artifact_directory = canonical;
    uint64_t *words = NULL, *answer = NULL, status = 0;
    size_t count = 0, length = 0;
    int result = input(argv[2], &words, &count);
    if (!result) result = execute(argv[1], words, count, &answer, &length, &status);
    if (!result && status) {
        result = 1;
        if (status != 6) fprintf(stderr, "nupp-core: Nupp entry refused with transport status %llu\n", (unsigned long long)status);
    }
    if (!result) {
        FILE *file = fopen(argv[3], "wb");
        if (!file) result = error("output cannot be opened");
        else {
            for (size_t i = 0; i < length; ++i) {
                unsigned char bytes[8];
                for (unsigned j = 0; j < 8; ++j) bytes[j] = (unsigned char)(answer[i] >> (j * 8));
                if (fwrite(bytes, 1, 8, file) != 8) { result = error("output cannot be written"); break; }
            }
            if (fclose(file)) result = error("output cannot be closed");
        }
    }
    free(answer); free(words); free(canonical);
    return result;
}
