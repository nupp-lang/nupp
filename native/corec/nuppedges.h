/* nuppedges.h: what the emitted runtime reaches outside Nupp. The OS edges
   the bridge supplies through the entry packet's import table, the routines
   s0 generates in their place (atomics, a guest's foreign call, the foreign
   walk's collector), and a literal raise. Every emitted source includes it
   last, after the headers that declare the scope. */
#ifndef NUPPEDGES_H
#define NUPPEDGES_H

#include "servicescope.h"

/* The bridge's OS import table (the entry packet's seventh word). */
extern uint64_t *nupp_os_imports;

enum {
    OS_POOL_START,
    OS_POOL_SUBMIT,
    OS_POOL_TAKE,
    OS_POOL_FINISH,
    OS_POOL_CANCEL,
    OS_POOL_SETTLE,
    OS_DLOPEN,
    OS_DLSYM,
    OS_DLCLOSE,
    OS_FOREIGN_TABLE
};

#define NUPP_OS(slot, type) ((type)(uintptr_t)nupp_os_imports[slot])

static inline int64_t os_poolStart(uint64_t threads) {
    return NUPP_OS(OS_POOL_START, int64_t (*)(uint64_t))(threads);
}

static inline int64_t os_poolSubmit(uint64_t kind, uint64_t id, void *data, uint64_t bytes) {
    return NUPP_OS(OS_POOL_SUBMIT, int64_t (*)(uint64_t, uint64_t, void *, uint64_t))(kind, id, data, bytes);
}

static inline int64_t os_poolTake(void) {
    return NUPP_OS(OS_POOL_TAKE, int64_t (*)(void))();
}

static inline int64_t os_poolFinish(uint64_t id, void *data, uint64_t bytes) {
    return NUPP_OS(OS_POOL_FINISH, int64_t (*)(uint64_t, void *, uint64_t))(id, data, bytes);
}

static inline int64_t os_poolCancel(uint64_t id) {
    return NUPP_OS(OS_POOL_CANCEL, int64_t (*)(uint64_t))(id);
}

static inline int64_t os_poolsettle(uint64_t id) {
    return NUPP_OS(OS_POOL_SETTLE, int64_t (*)(uint64_t))(id);
}

static inline void *os_dlopen(void *path, int64_t mode) {
    return NUPP_OS(OS_DLOPEN, void *(*)(void *, int64_t))(path, mode);
}

/* The foreign calls' symbol cells: the bridge's table. */
static inline void *os_foreignCells(void) {
    return (void *)(uintptr_t)nupp_os_imports[OS_FOREIGN_TABLE];
}

/* A guest's foreign call, from the block that describes it (foreigncall.S). */
uint64_t nupp_foreign_call(void *block);

static inline uint64_t os_foreignCall(void *block) {
    return nupp_foreign_call(block);
}

/* The visitor a foreign walk calls back (a libffi closure), in edges.c. */
void nupp_collector(void *cif, void *ret, void **args, void *userdata);

static inline void *os_foreignCollector(void) {
    return (void *)nupp_collector;
}

static inline uint64_t os_atomicload64(void *base, int64_t offset) {
    return __atomic_load_n((uint64_t *)NUPP_AT(base, offset), __ATOMIC_SEQ_CST);
}

static inline uint64_t os_atomiccas64(void *base, int64_t offset, uint64_t expected, uint64_t replacement) {
    __atomic_compare_exchange_n((uint64_t *)NUPP_AT(base, offset), &expected, replacement, false,
                                __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
    return expected;
}

/* error("message") in the runtime: the scope's first error, which the guest
   reports with the message the bundle's catalog keeps for this owner (the
   raising function) and site (the raise within it). */
#define NUPP_RAISE_CODE 1
#define NUPP_RAISE(scope, owner, site, message) servicescope_fail((scope), NUPP_RAISE_CODE, (owner), (site))

#endif
