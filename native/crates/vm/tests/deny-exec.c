// Host-native no-JIT gate. Interpose executable mappings/protection changes;
// exit rather than allowing an allocator to hide a denial with a fallback.
// This tests the current macOS host, not a console SDK or its loader policy.
#include <sys/mman.h>
#include <unistd.h>

static void reject_exec(void) {
    static const char message[] = "no-JIT gate: executable memory requested\n";
    write(STDERR_FILENO, message, sizeof(message) - 1);
    _exit(86);
}

static void *deny_exec_mmap(void *addr, size_t len, int prot, int flags,
                           int fd, off_t offset) {
    if ((prot & PROT_EXEC) || (flags & MAP_JIT)) reject_exec();
    return mmap(addr, len, prot, flags, fd, offset);
}

static int deny_exec_mprotect(void *addr, size_t len, int prot) {
    if (prot & PROT_EXEC) reject_exec();
    return mprotect(addr, len, prot);
}

__attribute__((used, section("__DATA,__interpose")))
static const struct { const void *replacement; const void *original; } hooks[] = {
    { (const void *)deny_exec_mmap, (const void *)mmap },
    { (const void *)deny_exec_mprotect, (const void *)mprotect },
};
