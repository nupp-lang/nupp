/* Holds nearby virtual address space for LuaJIT states created later.
 *
 * LuaJIT's arm64 traces must be branch-reachable from the interpreter. A host
 * that loads enough code before creating a worker can leave `luaL_newstate`
 * unable to place any machine-code area, while `jit.status()` still reports
 * that the JIT is enabled -- so the program runs, correctly, and slowly, with
 * nothing said. Reserve early, then give it back immediately before the first
 * worker state is created, so later mappings cannot consume the window.
 */

#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

#include "nupp_host.h"

#if NUPP_FEATURE_WORKERS

#if defined(_WIN32)

/* Windows places JIT areas by its own rules and has no equivalent hazard here,
 * so both halves are nothing. */
void nupp_host_mcode_reserve(void) {}
void nupp_host_mcode_release(void) {}

#else

#include <dlfcn.h>
#include <pthread.h>
#include <stddef.h>
#include <sys/mman.h>

#define ARENA_BYTES (24u << 20)
#define ARENA_MIN (4u << 20)
/* What an arm64 branch can reach, less a margin for the interpreter's own
 * code. */
#define MCODE_RANGE (((size_t)1 << 26) - ((size_t)1 << 21))
#define ATTEMPTS 64
#define STEP ((size_t)1 << 20)

static pthread_mutex_t arenaGuard = PTHREAD_MUTEX_INITIALIZER;
static void *arenaAddress;
static size_t arenaSize;

/* Where the interpreter itself was loaded, rounded down: the reservation only
 * helps if it lands within branch range of that. */
static size_t interpreter_anchor(void) {
    Dl_info info;
    if (dladdr((const void *)(size_t)&luaL_newstate, &info) == 0) {
        return 0;
    }
    if (info.dli_fbase == NULL) {
        return 0;
    }
    return (size_t)info.dli_fbase & ~(size_t)0xffff;
}

/* Walks upward from `low` asking for `size` bytes until one lands inside the
 * window. `PROT_NONE`, because nothing is stored here: what is wanted is the
 * addresses, held so that nothing else takes them. */
static void *reserve_within(size_t size, size_t low, size_t high) {
    size_t hint = low;
    int attempt;
    for (attempt = 0; attempt < ATTEMPTS; attempt++) {
        void *address = mmap(
            (void *)hint, size, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
        size_t got;
        if (address == MAP_FAILED) {
            return NULL;
        }
        got = (size_t)address;
        if (got >= low && got + size <= high) {
            return address;
        }
        munmap(address, size);
        hint = (got > hint ? got : hint) + STEP;
        if (hint >= high) {
            return NULL;
        }
    }
    return NULL;
}

void nupp_host_mcode_reserve(void) {
    size_t anchor, low, high, size;
    pthread_mutex_lock(&arenaGuard);
    if (arenaAddress != NULL) {
        pthread_mutex_unlock(&arenaGuard);
        return;
    }
    anchor = interpreter_anchor();
    if (anchor == 0) {
        pthread_mutex_unlock(&arenaGuard);
        return;
    }
    low = anchor > MCODE_RANGE ? anchor - MCODE_RANGE : 0;
    high = anchor + MCODE_RANGE;
    /* Halving rather than failing: a smaller arena still holds a window, and
     * none at all is what this exists to avoid. */
    for (size = ARENA_BYTES; size >= ARENA_MIN; size /= 2) {
        void *address = reserve_within(size, low, high);
        if (address != NULL) {
            arenaAddress = address;
            arenaSize = size;
            break;
        }
    }
    pthread_mutex_unlock(&arenaGuard);
}

void nupp_host_mcode_release(void) {
    pthread_mutex_lock(&arenaGuard);
    if (arenaAddress != NULL) {
        munmap(arenaAddress, arenaSize);
        arenaAddress = NULL;
        arenaSize = 0;
    }
    pthread_mutex_unlock(&arenaGuard);
}

#endif /* _WIN32 */

#endif /* NUPP_FEATURE_WORKERS */
