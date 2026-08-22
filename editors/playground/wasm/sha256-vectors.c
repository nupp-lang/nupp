#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "sha-256.h"

struct vector {
    const char *message;
    const char *digest;
};

static void to_hex(const uint8_t digest[32], char out[65]) {
    static const char digits[] = "0123456789abcdef";
    int index;
    for (index = 0; index < 32; ++index) {
        out[index * 2] = digits[digest[index] >> 4];
        out[index * 2 + 1] = digits[digest[index] & 15];
    }
    out[64] = '\0';
}

int main(void) {
    static const struct vector vectors[] = {
        {"", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},
        {"abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"},
        {"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
         "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"},
    };
    uint8_t digest[32];
    char hex[65];
    unsigned index;

    for (index = 0; index < sizeof(vectors) / sizeof(vectors[0]); ++index) {
        calc_sha_256(digest, vectors[index].message, strlen(vectors[index].message));
        to_hex(digest, hex);
        if (strcmp(hex, vectors[index].digest) != 0) {
            fprintf(stderr, "SHA-256 vector %u failed: %s\n", index, hex);
            return 1;
        }
    }
    return 0;
}
