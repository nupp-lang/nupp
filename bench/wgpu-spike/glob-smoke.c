#include "nupp_native.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

NuppBytes *nuppFilesGlob(const uint8_t *data, size_t length);

int main(int argc, char **argv) {
    NuppBytes *answer;
    const uint8_t *data;
    size_t length;
    size_t at;
    int iteration;
    int repeats;

    if (argc < 2 || argc > 3) {
        fprintf(stderr, "usage: glob-smoke PATTERN [REPEATS]\n");
        return 2;
    }
    repeats = argc == 3 ? atoi(argv[2]) : 1;
    answer = NULL;
    for (iteration = 0; iteration < repeats; iteration++) {
        answer = nuppFilesGlob((const uint8_t *)argv[1], strlen(argv[1]));
        if (answer == NULL) {
            fprintf(stderr, "%s\n", nuppNativeError());
            return 1;
        }
        if (iteration + 1 != repeats) {
            nuppBytesDestroy(answer);
        }
    }
    data = nuppBytesData(answer);
    length = nuppBytesLength(answer);
    if (repeats == 1) {
        for (at = 0; at < length; at++) {
            putchar(data[at] == 0 ? '\n' : data[at]);
        }
        if (length != 0) {
            putchar('\n');
        }
    }
    nuppBytesDestroy(answer);
    return 0;
}
