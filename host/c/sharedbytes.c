/* Engine-owned immutable byte regions.
 *
 * A block is engine memory holding an atomic reference count and bytes; it is
 * immutable once a region handle exists over it, so any number of Lua states
 * may read it concurrently. Each state's handle is a full userdata whose
 * finalizer releases one reference, and whichever thread drops the last
 * reference frees the block. Lua owns extents and views; this file owns bytes
 * and lifetime. See NEP 22.
 */

#include "nupp_host.h"

#if NUPP_FEATURE_WORKERS

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#   include <windows.h>
#   define REGION_ATOMIC_INCREMENT(p) InterlockedIncrement((volatile LONG *)(p))
#   define REGION_ATOMIC_DECREMENT(p) InterlockedDecrement((volatile LONG *)(p))
typedef LONG RegionCount;
#else
#   define REGION_ATOMIC_INCREMENT(p) __atomic_add_fetch((p), 1, __ATOMIC_RELAXED)
#   define REGION_ATOMIC_DECREMENT(p) __atomic_sub_fetch((p), 1, __ATOMIC_ACQ_REL)
typedef long RegionCount;
#endif

typedef struct {
    RegionCount refs;
    size_t length;
    uint8_t bytes[1];
} RegionBlock;

static RegionBlock *block_new(size_t length) {
    RegionBlock *block = malloc(sizeof *block + length);
    if (block != NULL) {
        block->refs = 1;
        block->length = length;
    }
    return block;
}

void nupp_host_region_retain(void *raw) {
    if (raw != NULL) {
        REGION_ATOMIC_INCREMENT(&((RegionBlock *)raw)->refs);
    }
}

void nupp_host_region_release(void *raw) {
    if (raw != NULL && REGION_ATOMIC_DECREMENT(&((RegionBlock *)raw)->refs) == 0) {
        free(raw);
    }
}

/* --- per-state accounting ------------------------------------------------- */

/* The unit of account is the block, once per state: the first live handle a
 * state holds over a block charges its full size, and the last one's finalizer
 * discharges it, however many handles and slices name it in between. Charges
 * accrue as collection debt paid down with ordinary collector steps, exactly
 * as the state's own heap allocation paces its collector; discharge credits
 * the account. Only the debt-to-step ratio is tuning. See NEP 22.
 *
 * Accounting is pressure feedback and never load-bearing: an allocation
 * failure inside it skips the charge, not the handle. */

#define ACCOUNT_REGISTRY "nupp.mem.sharedbytes.account"
#define ACCOUNT_STEP_BYTES ((size_t)1 << 20)

typedef struct {
    void **blocks;
    size_t *counts;
    size_t capacity; /* power of two; zero until first use and after close */
    size_t used;
    size_t charged; /* bytes currently charged to this state */
    size_t debt;    /* charged bytes not yet paid down with step work */
} RegionAccount;

static int account_gc(lua_State *state) {
    RegionAccount *account = lua_touserdata(state, 1);
    if (account != NULL) {
        free(account->blocks);
        free(account->counts);
        account->blocks = NULL;
        account->counts = NULL;
        account->capacity = 0;
    }
    return 0;
}

static RegionAccount *account_find(lua_State *state) {
    RegionAccount *account;
    lua_getfield(state, LUA_REGISTRYINDEX, ACCOUNT_REGISTRY);
    account = lua_touserdata(state, -1);
    lua_pop(state, 1);
    return account;
}

static RegionAccount *account_get(lua_State *state) {
    RegionAccount *account = account_find(state);
    if (account != NULL) {
        return account;
    }
    account = lua_newuserdata(state, sizeof *account);
    memset(account, 0, sizeof *account);
    lua_createtable(state, 0, 1);
    lua_pushcclosure(state, account_gc, 0);
    lua_setfield(state, -2, "__gc");
    lua_setmetatable(state, -2);
    lua_setfield(state, LUA_REGISTRYINDEX, ACCOUNT_REGISTRY);
    return account;
}

static size_t account_slot(void **blocks, size_t capacity, void *block) {
    size_t index = (((size_t)block >> 4) * 2654435761u) & (capacity - 1);
    while (blocks[index] != NULL && blocks[index] != block) {
        index = (index + 1) & (capacity - 1);
    }
    return index;
}

static int account_grow(RegionAccount *account) {
    size_t capacity = account->capacity == 0 ? 64 : account->capacity * 2;
    void **blocks = calloc(capacity, sizeof *blocks);
    size_t *counts = calloc(capacity, sizeof *counts);
    size_t index;
    if (blocks == NULL || counts == NULL) {
        free(blocks);
        free(counts);
        return 0;
    }
    for (index = 0; index < account->capacity; index++) {
        if (account->blocks[index] != NULL) {
            size_t slot = account_slot(blocks, capacity, account->blocks[index]);
            blocks[slot] = account->blocks[index];
            counts[slot] = account->counts[index];
        }
    }
    free(account->blocks);
    free(account->counts);
    account->blocks = blocks;
    account->counts = counts;
    account->capacity = capacity;
    return 1;
}

static void account_charge(lua_State *state, RegionBlock *block) {
    RegionAccount *account = account_get(state);
    size_t slot;
    if ((account->used + 1) * 4 >= account->capacity * 3 && !account_grow(account)) {
        return;
    }
    slot = account_slot(account->blocks, account->capacity, (void *)block);
    if (account->blocks[slot] != NULL) {
        account->counts[slot]++;
        return;
    }
    account->blocks[slot] = (void *)block;
    account->counts[slot] = 1;
    account->used++;
    account->charged += block->length;
    account->debt += block->length;
    if (account->debt >= ACCOUNT_STEP_BYTES) {
        size_t debt = account->debt;
        account->debt = 0;
        /* One step's worth of work per kilobyte charged, as if the state had
         * allocated the bytes on its own heap. Finalizers may run here and
         * discharge other blocks; this block's entry is already complete. */
        lua_gc(state, LUA_GCSTEP, (int)(debt >> 10));
    }
}

static void account_discharge(lua_State *state, RegionBlock *block) {
    RegionAccount *account = account_find(state);
    size_t slot;
    size_t hole;
    size_t next;
    if (account == NULL || account->capacity == 0) {
        return;
    }
    slot = account_slot(account->blocks, account->capacity, (void *)block);
    if (account->blocks[slot] == NULL) {
        return;
    }
    if (--account->counts[slot] != 0) {
        return;
    }
    account->used--;
    account->charged -= block->length <= account->charged ? block->length : account->charged;
    account->debt -= block->length <= account->debt ? block->length : account->debt;
    /* Backward-shift deletion keeps later probes correct without tombstones. */
    hole = slot;
    next = (hole + 1) & (account->capacity - 1);
    while (account->blocks[next] != NULL) {
        size_t home =
            (((size_t)account->blocks[next] >> 4) * 2654435761u) & (account->capacity - 1);
        if (((next - home) & (account->capacity - 1)) >= ((next - hole) & (account->capacity - 1))) {
            account->blocks[hole] = account->blocks[next];
            account->counts[hole] = account->counts[next];
            hole = next;
        }
        next = (next + 1) & (account->capacity - 1);
    }
    account->blocks[hole] = NULL;
    account->counts[hole] = 0;
}

static int region_accounted(lua_State *state) {
    RegionAccount *account = account_find(state);
    lua_pushinteger(state, (lua_Integer)(account != NULL ? account->charged : 0));
    return 1;
}

/* --- handles ------------------------------------------------------------- */

typedef struct {
    RegionBlock *block;
} RegionHandle;

#define REGION_METATABLE "nupp.mem.sharedbytes.region"

static int region_handle_gc(lua_State *state) {
    RegionHandle *handle = lua_touserdata(state, 1);
    if (handle != NULL && handle->block != NULL) {
        account_discharge(state, handle->block);
        nupp_host_region_release(handle->block);
        handle->block = NULL;
    }
    return 0;
}

/* Pushes a handle owning one reference to `block`; the reference transfers to
 * the handle rather than being retained again. */
void nupp_host_region_push_handle(lua_State *state, void *block) {
    RegionHandle *handle = lua_newuserdata(state, sizeof *handle);
    handle->block = block;
    lua_getfield(state, LUA_REGISTRYINDEX, REGION_METATABLE);
    if (lua_isnil(state, -1)) {
        lua_pop(state, 1);
        lua_createtable(state, 0, 1);
        lua_pushcclosure(state, region_handle_gc, 0);
        lua_setfield(state, -2, "__gc");
        lua_pushvalue(state, -1);
        lua_setfield(state, LUA_REGISTRYINDEX, REGION_METATABLE);
    }
    lua_setmetatable(state, -2);
    /* Charge after the finalizer is armed; the handle itself sits anchored on
     * the stack through any collector step the charge pays. */
    account_charge(state, (RegionBlock *)block);
}

/* The block a stack slot's region handle holds, or NULL when the slot is not
 * a live region handle. Checked by metatable identity, so an arbitrary
 * userdata cannot be misread as a block pointer. */
void *nupp_host_region_block(lua_State *state, int index) {
    RegionHandle *handle = lua_touserdata(state, index);
    void *block = NULL;
    if (handle == NULL || !lua_getmetatable(state, index)) {
        return NULL;
    }
    lua_getfield(state, LUA_REGISTRYINDEX, REGION_METATABLE);
    if (lua_rawequal(state, -1, -2)) {
        block = handle->block;
    }
    lua_pop(state, 2);
    return block;
}

/* --- the Lua surface ----------------------------------------------------- */

static int region_from_string(lua_State *state) {
    size_t length = 0;
    const char *text = lua_tolstring(state, 1, &length);
    RegionBlock *block;
    if (text == NULL) {
        lua_pushnil(state);
        lua_pushnil(state);
        return 2;
    }
    block = block_new(length);
    if (block == NULL) {
        lua_pushnil(state);
        lua_pushnil(state);
        return 2;
    }
    if (length != 0) {
        memcpy(block->bytes, text, length);
    }
    nupp_host_region_push_handle(state, block);
    lua_pushinteger(state, (lua_Integer)length);
    return 2;
}

/* Reads a whole file directly into engine storage, so no intermediate Lua
 * string is created for the payload. */
static int region_read_file(lua_State *state) {
    const char *path = lua_tostring(state, 1);
    FILE *file;
    long size;
    RegionBlock *block;
    if (path == NULL) {
        lua_pushnil(state);
        lua_pushstring(state, "a file path is required");
        return 2;
    }
    file = fopen(path, "rb");
    if (file == NULL) {
        lua_pushnil(state);
        lua_pushfstring(state, "cannot open %s", path);
        return 2;
    }
    if (fseek(file, 0, SEEK_END) != 0 || (size = ftell(file)) < 0
        || fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        lua_pushnil(state);
        lua_pushfstring(state, "cannot size %s", path);
        return 2;
    }
    block = block_new((size_t)size);
    if (block == NULL) {
        fclose(file);
        lua_pushnil(state);
        lua_pushstring(state, "cannot allocate region storage");
        return 2;
    }
    if (size != 0 && fread(block->bytes, 1, (size_t)size, file) != (size_t)size) {
        fclose(file);
        free(block);
        lua_pushnil(state);
        lua_pushfstring(state, "cannot read %s", path);
        return 2;
    }
    fclose(file);
    nupp_host_region_push_handle(state, block);
    lua_pushinteger(state, (lua_Integer)size);
    return 2;
}

/* Interns bytes [first, last] of the block, 1-based inclusive, as the one
 * explicit copy a region ever makes into a Lua state. */
static int region_text(lua_State *state) {
    RegionBlock *block = nupp_host_region_block(state, 1);
    lua_Integer first = lua_tointeger(state, 2);
    lua_Integer last = lua_tointeger(state, 3);
    if (block == NULL || first < 1 || last > (lua_Integer)block->length
        || first > last + 1) {
        lua_pushnil(state);
        return 1;
    }
    lua_pushlstring(state, (const char *)block->bytes + (first - 1),
        (size_t)(last - first + 1));
    return 1;
}

static int region_pointer(lua_State *state) {
    RegionBlock *block = nupp_host_region_block(state, 1);
    if (block == NULL) {
        lua_pushnil(state);
        return 1;
    }
    lua_pushlightuserdata(state, block->bytes);
    return 1;
}

static int region_length(lua_State *state) {
    RegionBlock *block = nupp_host_region_block(state, 1);
    if (block == NULL) {
        lua_pushnil(state);
        return 1;
    }
    lua_pushinteger(state, (lua_Integer)block->length);
    return 1;
}

/* --- builders ------------------------------------------------------------ */

/* A builder grows a private allocation shaped like a block, so freeze is a
 * transfer rather than a copy. Only the builder references it before freeze,
 * which is what makes realloc growth safe. A reservation is capacity lent out
 * for a producer to write into directly: all growth happens when it is taken,
 * so the lent pointer stays put, and it stays open until one commit closes it
 * with the count that actually arrived. See NEP 22. */
typedef struct {
    RegionBlock *block;
    size_t capacity;
    size_t reserved;
    int reservationOpen;
} RegionBuilder;

static int builder_ensure(RegionBuilder *builder, size_t extra) {
    size_t used = builder->block->length;
    if (used + extra > builder->capacity) {
        size_t grown = builder->capacity == 0 ? 4096 : builder->capacity * 2;
        RegionBlock *moved;
        while (grown < used + extra) {
            grown *= 2;
        }
        moved = realloc(builder->block, sizeof *moved + grown);
        if (moved == NULL) {
            return 0;
        }
        builder->block = moved;
        builder->capacity = grown;
    }
    return 1;
}

#define BUILDER_METATABLE "nupp.mem.sharedbytes.builder"

static int builder_gc(lua_State *state) {
    RegionBuilder *builder = lua_touserdata(state, 1);
    if (builder != NULL && builder->block != NULL) {
        free(builder->block);
        builder->block = NULL;
    }
    return 0;
}

static int builder_new(lua_State *state) {
    RegionBuilder *builder = lua_newuserdata(state, sizeof *builder);
    builder->block = block_new(0);
    builder->capacity = 0;
    builder->reserved = 0;
    builder->reservationOpen = 0;
    if (builder->block == NULL) {
        lua_pushnil(state);
        return 1;
    }
    lua_getfield(state, LUA_REGISTRYINDEX, BUILDER_METATABLE);
    if (lua_isnil(state, -1)) {
        lua_pop(state, 1);
        lua_createtable(state, 0, 1);
        lua_pushcclosure(state, builder_gc, 0);
        lua_setfield(state, -2, "__gc");
        lua_pushvalue(state, -1);
        lua_setfield(state, LUA_REGISTRYINDEX, BUILDER_METATABLE);
    }
    lua_setmetatable(state, -2);
    return 1;
}

static int builder_append(lua_State *state) {
    RegionBuilder *builder = lua_touserdata(state, 1);
    size_t length = 0;
    const char *chunk = lua_tolstring(state, 2, &length);
    if (builder == NULL || builder->block == NULL || chunk == NULL) {
        lua_pushboolean(state, 0);
        return 1;
    }
    if (builder->reservationOpen) {
        lua_pushboolean(state, 0);
        lua_pushstring(state, "open");
        return 2;
    }
    if (!builder_ensure(builder, length)) {
        lua_pushboolean(state, 0);
        return 1;
    }
    if (length != 0) {
        memcpy(builder->block->bytes + builder->block->length, chunk, length);
    }
    builder->block->length += length;
    lua_pushboolean(state, 1);
    return 1;
}

/* Grows the storage and lends a pointer over `count` uninitialized bytes past
 * what is committed. Growth happens here, before the writer exists, so the
 * lent pointer is stable until the reservation is closed. */
static int builder_reserve(lua_State *state) {
    RegionBuilder *builder = lua_touserdata(state, 1);
    lua_Integer count = lua_tointeger(state, 2);
    if (builder == NULL || builder->block == NULL || count < 0) {
        lua_pushnil(state);
        return 1;
    }
    if (builder->reservationOpen) {
        lua_pushnil(state);
        lua_pushstring(state, "open");
        return 2;
    }
    if (!builder_ensure(builder, (size_t)count)) {
        lua_pushnil(state);
        return 1;
    }
    builder->reserved = (size_t)count;
    builder->reservationOpen = 1;
    lua_pushlightuserdata(state, builder->block->bytes + builder->block->length);
    return 1;
}

static int builder_commit(lua_State *state) {
    RegionBuilder *builder = lua_touserdata(state, 1);
    lua_Integer written = lua_tointeger(state, 2);
    int accepted = builder != NULL
        && builder->block != NULL
        && builder->reservationOpen
        && written >= 0
        && (size_t)written <= builder->reserved;
    if (accepted) {
        builder->block->length += (size_t)written;
        builder->reserved = 0;
        builder->reservationOpen = 0;
    }
    lua_pushboolean(state, accepted);
    return 1;
}

static int builder_freeze(lua_State *state) {
    RegionBuilder *builder = lua_touserdata(state, 1);
    RegionBlock *block;
    if (builder == NULL || builder->block == NULL) {
        lua_pushnil(state);
        lua_pushnil(state);
        return 2;
    }
    if (builder->reservationOpen) {
        lua_pushnil(state);
        lua_pushstring(state, "open");
        return 2;
    }
    block = builder->block;
    builder->block = NULL;
    nupp_host_region_push_handle(state, block);
    lua_pushinteger(state, (lua_Integer)block->length);
    return 2;
}

static void field(lua_State *state, const char *name, lua_CFunction function) {
    lua_pushcclosure(state, function, 0);
    lua_setfield(state, -2, name);
}

int nupp_host_sharedbytes_open(lua_State *state) {
    lua_createtable(state, 0, 11);
    field(state, "fromString", region_from_string);
    field(state, "readFile", region_read_file);
    field(state, "text", region_text);
    field(state, "pointer", region_pointer);
    field(state, "length", region_length);
    field(state, "builderNew", builder_new);
    field(state, "builderAppend", builder_append);
    field(state, "builderReserve", builder_reserve);
    field(state, "builderCommit", builder_commit);
    field(state, "builderFreeze", builder_freeze);
    field(state, "accounted", region_accounted);
    return 1;
}

#endif /* NUPP_FEATURE_WORKERS */
