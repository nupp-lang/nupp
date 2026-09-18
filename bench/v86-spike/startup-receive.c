#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <unistd.h>

/* The snapshot stops here, before host data, entropy seeding, or LuaJIT startup. */
static int save_file(const char *name, const void *data, size_t length) {
    int fd = open(name, O_CREAT | O_TRUNC | O_WRONLY, 0600);
    if (fd < 0) return -1;
    const unsigned char *bytes = data;
    while (length) {
        ssize_t count = write(fd, bytes, length);
        if (count <= 0) { close(fd); return -1; }
        bytes += count; length -= count;
    }
    return close(fd);
}

static int scrub_free_pages(void) {
    FILE *info = fopen("/proc/meminfo", "r");
    if (!info) return -1;
    char line[256];
    unsigned long free_kib = 0;
    while (fgets(line, sizeof(line), info)) {
        if (sscanf(line, "MemFree: %lu kB", &free_kib) == 1) break;
    }
    fclose(info);
    if (free_kib < 1024) return -1;
    size_t length = (free_kib - 1024) * 1024;
    void *pages = mmap(NULL, length, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (pages == MAP_FAILED) return -1;
    memset(pages, 0, length);
    __asm__ volatile("" : : "r"(pages) : "memory");
    printf("Scrubbed %lu free bytes before snapshot\n", (unsigned long)length);
    return munmap(pages, length);
}

static int seed_random(const unsigned char *bytes) {
    struct { int bits, length; unsigned char bytes[32]; } seed = {256, 32, {0}};
    memcpy(seed.bytes, bytes, sizeof(seed.bytes));
    int fd = open("/dev/random", O_RDWR);
    if (fd < 0) return -1;
    /* Force a new CRNG key even if boot already initialized the saved pool.
       Linux v6.8 drivers/char/random.c random_ioctl defines these operations. */
    int result = ioctl(fd, _IOW('R', 0x03, int[2]), &seed);
    if (!result) result = ioctl(fd, _IO('R', 0x07), 0);
    memset(&seed, 0, sizeof(seed));
    close(fd);
    return result;
}

int main(void) {
    if (scrub_free_pages()) { perror("scrub free pages"); return 1; }
    int fd = open("/dev/mem", O_RDWR);
    if (fd < 0) { perror("startup /dev/mem"); return 1; }
    unsigned char *memory = mmap(NULL, 8 * 1024 * 1024, PROT_READ | PROT_WRITE,
        MAP_SHARED, fd, (off_t)48 * 1024 * 1024);
    close(fd);
    if (memory == MAP_FAILED) { perror("startup mmap"); return 1; }
    puts("@@NUPP_SNAPSHOT_READY@@");
    fflush(stdout);
    char command[16];
    if (!fgets(command, sizeof(command), stdin) || strcmp(command, "start\n")) return 2;
    const uint32_t *header = (const uint32_t *)memory;
    if (header[0] != 0x5350554e || header[1] != 1 || !header[2] || header[2] > 65536 ||
        !header[3] || header[3] > 2 * 1024 * 1024) return 3;
    if (save_file("/host/config.json", memory + 4096, header[2]) ||
        save_file("/host/app.lua", memory + 1024 * 1024, header[3]) ||
        save_file("/nupp/entropy.bin", memory + 512, 32)) return 4;
    if (seed_random(memory + 512)) { perror("reseed restored guest"); return 5; }
    struct timeval now = {.tv_sec = header[4], .tv_usec = header[5]};
    if (settimeofday(&now, NULL)) { perror("restore wall clock"); return 6; }
    memset(memory, 0, 1024 * 1024 + header[3]);
    munmap(memory, 8 * 1024 * 1024);
    return 0;
}
