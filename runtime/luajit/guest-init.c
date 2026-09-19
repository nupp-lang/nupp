/* PID 1 and the pre-LuaJIT snapshot gate. No application data enters a snapshot. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

#define MIB (1024u * 1024u)
#define MAILBOX_BYTES (8u * MIB)
#define START_MAGIC UINT32_C(0x5350554e)
#define START_VERSION 1u

static void fail(const char *operation) {
    perror(operation);
    fflush(stderr);
    for (;;) pause();
}

static void save_file(const char *name, const void *data, size_t size) {
    int fd = open(name, O_CREAT | O_TRUNC | O_WRONLY | O_CLOEXEC, 0600);
    if (fd < 0) fail(name);
    const unsigned char *cursor = data;
    while (size) {
        ssize_t count = write(fd, cursor, size);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) fail("write startup file");
        cursor += count;
        size -= (size_t)count;
    }
    if (close(fd)) fail("close startup file");
}

static void scrub_free_pages(void) {
    FILE *info = fopen("/proc/meminfo", "r");
    if (!info) fail("open meminfo");
    char line[256];
    unsigned long free_kib = 0;
    while (fgets(line, sizeof(line), info))
        if (sscanf(line, "MemFree: %lu kB", &free_kib) == 1) break;
    fclose(info);
    if (free_kib < 2048) { errno = ENOMEM; fail("snapshot reserve"); }
    size_t size = (free_kib - 2048) * 1024;
    void *pages = mmap(NULL, size, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (pages == MAP_FAILED) fail("scrub mmap");
    memset(pages, 0, size);
    __asm__ volatile("" : : "r"(pages) : "memory");
    if (munmap(pages, size)) fail("scrub munmap");
}

static off_t mailbox_address(void) {
    FILE *file = fopen("/proc/cmdline", "r");
    if (!file) fail("open cmdline");
    char args[4096];
    if (!fgets(args, sizeof(args), file)) fail("read cmdline");
    fclose(file);
    unsigned long address = 0;
    char *token, *cursor = NULL;
    for (token = strtok_r(args, " \n", &cursor); token; token = strtok_r(NULL, " \n", &cursor))
        if (sscanf(token, "nupp.mailbox=%lu", &address) == 1) break;
    if (address != 48u * MIB && address != 112u * MIB) {
        errno = EINVAL;
        fail("unsupported guest memory profile");
    }
    return (off_t)address;
}

static void reseed(const unsigned char bytes[32]) {
    struct { int bits, length; unsigned char bytes[32]; } seed = {256, 32, {0}};
    memcpy(seed.bytes, bytes, sizeof(seed.bytes));
    int fd = open("/dev/random", O_RDWR | O_CLOEXEC);
    if (fd < 0) fail("open random");
    /* RNDADDENTROPY and RNDRESEEDCRNG, from the pinned Linux random ABI. */
    if (ioctl(fd, _IOW('R', 0x03, int[2]), &seed) || ioctl(fd, _IO('R', 0x07), 0))
        fail("reseed restored guest");
    explicit_bzero(&seed, sizeof(seed));
    if (close(fd)) fail("close random");
}

int main(void) {
    if (mount("proc", "/proc", "proc", 0, NULL)) fail("mount proc");
    if (mount("devtmpfs", "/dev", "devtmpfs", 0, NULL)) fail("mount devtmpfs");
    int terminal = open("/dev/ttyS0", O_RDWR);
    if (terminal < 0) fail("open serial console");
    for (int fd = 0; fd < 3; fd++) if (dup2(terminal, fd) < 0) fail("dup console");
    if (terminal > 2) close(terminal);
    struct termios settings;
    if (tcgetattr(0, &settings)) fail("get console attributes");
    settings.c_lflag &= ~(ECHO | ICANON);
    settings.c_cc[VMIN] = 1;
    settings.c_cc[VTIME] = 0;
    if (tcsetattr(0, TCSANOW, &settings)) fail("set console attributes");
    setvbuf(stdout, NULL, _IONBF, 0);
    int fd = open("/dev/mem", O_RDWR | O_CLOEXEC);
    if (fd < 0) fail("open physical mailbox");
    unsigned char *memory = mmap(NULL, MAILBOX_BYTES, PROT_READ | PROT_WRITE,
        MAP_SHARED, fd, mailbox_address());
    close(fd);
    if (memory == MAP_FAILED) fail("map physical mailbox");
    memset(memory, 0, MAILBOX_BYTES);
    scrub_free_pages();
    puts("@@NUPP_SNAPSHOT_READY@@");
    char command[16];
    if (!fgets(command, sizeof(command), stdin) || strcmp(command, "start\n")) {
        errno = EPROTO;
        fail("snapshot start command");
    }
    const uint32_t *header = (const uint32_t *)memory;
    if (header[0] != START_MAGIC || header[1] != START_VERSION ||
        !header[2] || header[2] > 65536 || !header[3] || header[3] > 7u * MIB ||
        header[5] >= 1000000) {
        errno = EINVAL;
        fail("snapshot startup header");
    }
    save_file("/host/config.json", memory + 4096, header[2]);
    save_file("/host/app.lua", memory + MIB, header[3]);
    save_file("/nupp/entropy.bin", memory + 512, 32);
    reseed(memory + 512);
    struct timeval now = {.tv_sec = header[4], .tv_usec = header[5]};
    if (settimeofday(&now, NULL)) fail("restore wall clock");
    explicit_bzero(memory, MAILBOX_BYTES);
    if (munmap(memory, MAILBOX_BYTES)) fail("unmap startup mailbox");
    setenv("LD_LIBRARY_PATH", "/lib:/nupp", 1);
    setenv("LUA_PATH", "/nupp/?.lua;;", 1);
    setenv("LUA_CPATH", "/nupp/?.so;;", 1);
    puts("@@NUPP_BRIDGE_READY@@");
    pid_t child = fork();
    if (child < 0) fail("fork LuaJIT");
    if (child == 0) {
        execl("/nupp/luajit", "/nupp/luajit", "/nupp/bridge.lua", (char *)NULL);
        perror("exec LuaJIT");
        _exit(127);
    }
    int status;
    while (waitpid(child, &status, 0) < 0) if (errno != EINTR) fail("wait LuaJIT");
    printf("@@NUPP_GUEST_EXIT@@ %d\n", WIFEXITED(status) ? WEXITSTATUS(status) : 128);
    for (;;) pause();
}
