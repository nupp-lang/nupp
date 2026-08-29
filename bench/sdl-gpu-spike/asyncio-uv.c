#include "nupp_native.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct NuppRequest NuppRequest;
NuppRequest *nuppFsSubmitRead(const uint8_t *data, size_t length);
int32_t nuppFsStatus(const NuppRequest *request);
const char *nuppFsError(const NuppRequest *request);
void nuppFsDestroy(NuppRequest *request);
size_t nuppFsWait(uint64_t milliseconds);

static void fail(const char *what) {
    fprintf(stderr, "%s: %s\n", what, nuppNativeError());
    exit(1);
}

static double batch(const char *path, int concurrency) {
    NuppRequest **requests = calloc((size_t)concurrency, sizeof *requests);
    double started = nupp_monotonic_ms();
    int submitted;
    int pending = concurrency;
    int index;

    if (!requests) fail("allocate requests");
    for (submitted = 0; submitted < concurrency; submitted++) {
        requests[submitted] = nuppFsSubmitRead((const uint8_t *)path, strlen(path));
        if (!requests[submitted]) fail("nuppFsSubmitRead");
    }
    while (pending != 0) {
        nuppFsWait(1000);
        for (index = 0; index < concurrency; index++) {
            if (requests[index] != NULL && nuppFsStatus(requests[index]) != 0) {
                if (nuppFsStatus(requests[index]) != 1) {
                    fprintf(stderr, "read: %s\n", nuppFsError(requests[index]));
                    exit(1);
                }
                nuppFsDestroy(requests[index]);
                requests[index] = NULL;
                pending--;
            }
        }
    }
    free(requests);
    return nupp_monotonic_ms() - started;
}

int main(int argc, char **argv) {
    double total = 0.0;
    int concurrency;
    int repeats;
    int iteration;

    if (argc != 4) {
        fprintf(stderr, "usage: asyncio-uv FILE CONCURRENCY REPEATS\n");
        return 2;
    }
    concurrency = atoi(argv[2]);
    repeats = atoi(argv[3]);
    (void)batch(argv[1], concurrency);
    for (iteration = 0; iteration < repeats; iteration++) {
        total += batch(argv[1], concurrency);
    }
    printf("libuv lane: %d reads, %.3f ms/batch, %.3f ms/read\n",
        concurrency, total / repeats, total / repeats / concurrency);
    return 0;
}
