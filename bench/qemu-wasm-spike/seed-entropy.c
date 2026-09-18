#include <fcntl.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <unistd.h>

/* Linux's RNDADDENTROPY ABI. The bytes come from browser crypto.getRandomValues. */
#define RNDADDENTROPY _IOW('R', 0x03, int[2])

int main(void) {
    struct {
        int entropy_count;
        int buf_size;
        unsigned char bytes[32];
    } seed = {256, 32, {0}};
    int input = open("/nupp/entropy.bin", O_RDONLY);
    if (input < 0 || read(input, seed.bytes, sizeof(seed.bytes)) != sizeof(seed.bytes)) {
        perror("read browser entropy");
        return 1;
    }
    close(input);
    int random = open("/dev/random", O_RDWR);
    if (random < 0 || ioctl(random, RNDADDENTROPY, &seed) < 0) {
        perror("seed guest entropy");
        return 1;
    }
    close(random);
    return 0;
}
