// The tail-call-threaded dispatch core (contracts 5.2). Every handler ends by
// tail-calling the next instruction's handler through one table, so dispatch
// is one indirect branch per instruction with its own predictor slot and the
// activation's state (pc, the three windows, the frame, the context) stays in
// the argument registers. The frame layout is the Rust interpreter's (5.1):
// four header words, then the value, integer, float and vector windows. The
// hot opcodes are here; anything else, and every fast path that fails its
// guard, hands the instruction to the Rust interpreter through `rt_exec_op`,
// which executes exactly that one opcode and says where to continue.
//
// Built by build.rs with the C compiler cc finds; `musttail` needs clang (or a
// gcc that knows the attribute), and without it the crate runs the Rust loop.
#include <stdint.h>
#include <string.h>
#include <math.h>

typedef uint64_t Value;
typedef struct { uint8_t op, a, b, c; int32_t imm; int64_t k; } Ins;

typedef struct {
    const Ins* code;
    const Value* consts;
    uint32_t frame_words, nregs, nparams, off_i, off_f, vararg, ncode, pad;
} FuncInfo;

typedef struct {
    void* interp;
    uint64_t tid;
    uint64_t* stack;
    uint64_t cap;
    uint64_t cur;
    const FuncInfo* funcs;
    uint64_t nfuncs;
    uint32_t status;
    uint32_t pc;
    uint64_t result;
    uint64_t last_nres;
    const struct { const Value* names; uint64_t n; }* shapes;
    uint64_t nshapes;
    const uint8_t* marking;
} Ctx;

// Rust helpers.
extern uint32_t rt_exec_op(Ctx* ctx, uint32_t pc);
extern void rt_grow(Ctx* ctx, uint64_t needed);
extern uint32_t rt_eq_slow(Ctx* ctx, Value x, Value y);
extern Value rt_get_field(Ctx* ctx, Value obj, Value name);
extern Value rt_get_index_num(Ctx* ctx, Value obj, int64_t i);
extern void rt_set_index_num(Ctx* ctx, Value obj, int64_t i, Value v);
extern void rt_barrier(Ctx* ctx, Value parent, Value child);
extern void rt_call_builtin(Ctx* ctx, uint32_t id, uint64_t base, uint32_t nargs);
extern void rt_call_iter(Ctx* ctx, Value iter, uint64_t base);
extern Value rt_new_record(Ctx* ctx, uint32_t shape);
extern uint64_t rt_len(Ctx* ctx, Value v);
extern Value rt_get_index(Ctx* ctx, Value obj, Value key);

// Opcode numbers, matched by `threaded.rs`.
enum {
    OP_SLOW = 0, OP_MOVE, OP_K, OP_NIL, OP_ADD, OP_SUB, OP_MUL, OP_LT, OP_LE, OP_EQ, OP_NE, OP_NOT, OP_NEG,
    OP_JMP, OP_JMPIF, OP_JMPIFNOT, OP_JMPIFIZERO,
    OP_IK, OP_IADD, OP_ISUB, OP_IAND, OP_IOR, OP_ISHL, OP_ISHRU, OP_ICMPSLT, OP_ICMPSLE, OP_ICMPEQ, OP_ICMPNE, OP_ICMPLT, OP_ICMPLE,
    OP_IMOV, OP_IADDK, OP_IMASKU32, OP_IUNBOX, OP_ITOF, OP_FTOI, OP_TRUTHY, OP_BOOLFROMI,
    OP_FK, OP_FMOV, OP_FADD, OP_FSUB, OP_FMUL, OP_FDIV, OP_FMOD, OP_FNEG, OP_FUNBOX, OP_FBOX, OP_FCMPEQ, OP_FCMPNE, OP_FCMPLE, OP_FCMPLT,
    OP_GETUPVAL, OP_GETCELL, OP_GETSLOT, OP_GETSLOTF, OP_SETSLOTF, OP_LEN, OP_LENF, OP_STRBYTE,
    OP_CALL, OP_CALLK, OP_CALLDYN, OP_RET, OP_RETNIL, OP_RETN,
    OP_GETFIELD, OP_GETIDXI, OP_SETIDXI, OP_SETCELL, OP_SETSLOT, OP_TAGCHECKNUM, OP_NEWRECORD, OP_GETIDX,
    OP_COUNT
};

// Statuses `rt_exec_op` answers with, beyond a next pc.
#define ST_REENTER 0xffffffffu
#define ST_DONE 0xfffffffeu
#define ST_PARKED 0xfffffffdu

#define QNAN 0x7ff8000000000000ull
#define TAG_SHIFT 48
#define TAG_MASK (0x7ull << TAG_SHIFT)
#define PAYLOAD ((1ull << 48) - 1)
#define T_NIL (QNAN | (1ull << TAG_SHIFT))
#define T_FALSE (QNAN | (2ull << TAG_SHIFT))
#define T_TRUE (QNAN | (3ull << TAG_SHIFT))
#define T_FUNC (QNAN | (4ull << TAG_SHIFT))
#define T_OBJ (QNAN | (5ull << TAG_SHIFT))
#define HDR 4
#define NONE 0xffffffffull

// The object header (heap.rs): kind at 0, aux at 12, aux_ptr at 16, aux_len at 24.
#define KIND_STR 1
#define KIND_TABLE 2
#define KIND_RECORD 3
#define KIND_CLOSURE 5
#define KIND_CELL 6
#define KIND_ITER 8
#define KIND_SLICE 9
#define HOST_BASE 1000u
static inline uint8_t obj_kind(Value v) { return *(const uint8_t*)(uintptr_t)(v & PAYLOAD); }
static inline uint32_t obj_aux(Value v) { return *(const uint32_t*)((uintptr_t)(v & PAYLOAD) + 12); }
static inline uint8_t* obj_ptr(Value v) { return *(uint8_t**)((uintptr_t)(v & PAYLOAD) + 16); }
static inline uint64_t obj_len(Value v) { return *(const uint64_t*)((uintptr_t)(v & PAYLOAD) + 24); }
static inline uint8_t obj_flags(Value v) { return *(const uint8_t*)((uintptr_t)(v & PAYLOAD) + 3); }

static inline int is_num(Value v) { return (v & QNAN) != QNAN || v == QNAN; }
static inline int is_obj(Value v) { return !is_num(v) && (v & TAG_MASK) == (5ull << TAG_SHIFT); }
static inline int is_func(Value v) { return !is_num(v) && (v & TAG_MASK) == (4ull << TAG_SHIFT); }
static inline double as_num(Value v) { double d; memcpy(&d, &v, 8); return d; }
static inline Value num(double d) { Value v; memcpy(&v, &d, 8); if ((v & QNAN) == QNAN) v = QNAN; return v; }
static inline int truthy(Value v) { return v != T_NIL && v != T_FALSE; }
static inline Value boolean(int b) { return b ? T_TRUE : T_FALSE; }
#define F_INTERNED 1
// Equal words are equal; two interned strings with different words are not;
// other object pairs may be equal by content (slices, long strings).
static inline int values_equal(Ctx* ctx, Value x, Value y) {
    if (x == y) return 1;
    if (!is_obj(x) || !is_obj(y)) return 0;
    if ((obj_flags(x) & F_INTERNED) && (obj_flags(y) & F_INTERNED)) return 0;
    return (int)rt_eq_slow(ctx, x, y);
}
static inline uint64_t header3(uint64_t words, uint64_t nvar) { return (words << 33) | (nvar << 49); }
static inline uint64_t frame_words_of(uint64_t h3) { return (h3 >> 33) & 0xffff; }

typedef Value (*Handler)(const Ins* pc, Value* regs, int64_t* iregs, double* fregs, Ctx* ctx, uint64_t* frame);
static const Handler dispatch[OP_COUNT];
#define ARGS const Ins* pc, Value* regs, int64_t* iregs, double* fregs, Ctx* ctx, uint64_t* frame
#define NEXT __attribute__((musttail)) return dispatch[pc->op](pc, regs, iregs, fregs, ctx, frame)
#define FUNC_OF(frame) (&ctx->funcs[(uint32_t)(frame)[0]])

// Re-derives the windows from the context after a frame change, then
// continues. Every function a handler tail-calls shares the handler
// signature, as `musttail` requires; unused parameters are just that.
static Value reenter(ARGS) {
    frame = ctx->stack + ctx->cur;
    const FuncInfo* fi = FUNC_OF(frame);
    uint32_t pcx = (uint32_t)(frame[0] >> 32);
    pc = fi->code + pcx;
    regs = (Value*)(frame + HDR);
    iregs = (int64_t*)(frame + fi->off_i);
    fregs = (double*)(frame + fi->off_f);
    NEXT;
}
#define REENTER __attribute__((musttail)) return reenter(pc, regs, iregs, fregs, ctx, frame)

// Hands one instruction to the Rust interpreter.
static Value slow(ARGS) {
    const FuncInfo* fi = FUNC_OF(frame);
    uint32_t r = rt_exec_op(ctx, (uint32_t)(pc - fi->code));
    if (r == ST_DONE || r == ST_PARKED) { ctx->status = r; return 0; }
    if (r == ST_REENTER) { REENTER; }
    // The stack may have moved under an allocation or a push inside the helper.
    frame = ctx->stack + ctx->cur;
    regs = (Value*)(frame + HDR);
    iregs = (int64_t*)(frame + fi->off_i);
    fregs = (double*)(frame + fi->off_f);
    pc = fi->code + r;
    NEXT;
}
#define SLOW __attribute__((musttail)) return slow(pc, regs, iregs, fregs, ctx, frame)

static Value h_move(ARGS) { regs[pc->a] = regs[pc->b]; pc++; NEXT; }
static Value h_k(ARGS) { regs[pc->a] = FUNC_OF(frame)->consts[pc->imm]; pc++; NEXT; }
static Value h_nil(ARGS) { regs[pc->a] = T_NIL; pc++; NEXT; }
#define ARITH(name, expr) static Value name(ARGS) { Value x = regs[pc->b], y = regs[pc->c]; if (__builtin_expect(is_num(x) && is_num(y), 1)) { double p = as_num(x), q = as_num(y); regs[pc->a] = (expr); pc++; NEXT; } SLOW; }
ARITH(h_add, num(p + q))
ARITH(h_sub, num(p - q))
ARITH(h_mul, num(p * q))
ARITH(h_lt, boolean(p < q))
ARITH(h_le, boolean(p <= q))
static Value h_eq(ARGS) {
    regs[pc->a] = boolean(values_equal(ctx, regs[pc->b], regs[pc->c])); pc++; NEXT;
}
static Value h_ne(ARGS) {
    regs[pc->a] = boolean(!values_equal(ctx, regs[pc->b], regs[pc->c])); pc++; NEXT;
}
static Value h_not(ARGS) { regs[pc->a] = boolean(!truthy(regs[pc->b])); pc++; NEXT; }
static Value h_neg(ARGS) { Value x = regs[pc->b]; if (__builtin_expect(is_num(x), 1)) { regs[pc->a] = num(-as_num(x)); pc++; NEXT; } SLOW; }
static Value h_jmp(ARGS) { pc = pc + 1 + pc->imm; NEXT; }
static Value h_jmpif(ARGS) { int32_t off = pc->imm; Value c = regs[pc->a]; pc++; if (truthy(c)) pc += off; NEXT; }
static Value h_jmpifnot(ARGS) { int32_t off = pc->imm; Value c = regs[pc->a]; pc++; if (!truthy(c)) pc += off; NEXT; }
static Value h_jmpifizero(ARGS) { int32_t off = pc->imm; int64_t c = iregs[pc->a]; pc++; if (c == 0) pc += off; NEXT; }

static Value h_ik(ARGS) { iregs[pc->a] = pc->k; pc++; NEXT; }
#define IBIN(name, expr) static Value name(ARGS) { int64_t p = iregs[pc->b], q = iregs[pc->c]; iregs[pc->a] = (expr); pc++; NEXT; }
IBIN(h_iadd, (int64_t)((uint64_t)p + (uint64_t)q))
IBIN(h_isub, (int64_t)((uint64_t)p - (uint64_t)q))
IBIN(h_iand, p & q)
IBIN(h_ior, p | q)
IBIN(h_ishl, (int64_t)((uint64_t)p << ((uint64_t)q & 63)))
IBIN(h_ishru, (int64_t)((uint64_t)p >> ((uint64_t)q & 63)))
IBIN(h_icmpslt, p < q)
IBIN(h_icmpsle, p <= q)
IBIN(h_icmpeq, p == q)
IBIN(h_icmpne, p != q)
IBIN(h_icmplt, (uint64_t)p < (uint64_t)q)
IBIN(h_icmple, (uint64_t)p <= (uint64_t)q)
static Value h_imov(ARGS) { iregs[pc->a] = iregs[pc->b]; pc++; NEXT; }
static Value h_iaddk(ARGS) { iregs[pc->a] = (int64_t)((uint64_t)iregs[pc->b] + (uint64_t)pc->k); pc++; NEXT; }
static Value h_imasku32(ARGS) { iregs[pc->a] = iregs[pc->b] & 0xffffffffll; pc++; NEXT; }
static Value h_iunbox(ARGS) { iregs[pc->a] = (int64_t)as_num(regs[pc->b]); pc++; NEXT; }
static Value h_itof(ARGS) { fregs[pc->a] = (double)iregs[pc->b]; pc++; NEXT; }
// Rust's `as i64`: NaN is 0 and out-of-range values saturate.
static inline int64_t f2i(double d) { if (d != d) return 0; if (d >= 9223372036854775807.0) return INT64_MAX; if (d <= -9223372036854775808.0) return INT64_MIN; return (int64_t)d; }
static Value h_ftoi(ARGS) { iregs[pc->a] = f2i(fregs[pc->b]); pc++; NEXT; }
static Value h_truthy(ARGS) { iregs[pc->a] = truthy(regs[pc->b]); pc++; NEXT; }
static Value h_boolfromi(ARGS) { regs[pc->a] = boolean(iregs[pc->b] != 0); pc++; NEXT; }

static Value h_fk(ARGS) { memcpy(&fregs[pc->a], &pc->k, 8); pc++; NEXT; }
static Value h_fmov(ARGS) { fregs[pc->a] = fregs[pc->b]; pc++; NEXT; }
#define FBIN(name, expr) static Value name(ARGS) { double p = fregs[pc->b], q = fregs[pc->c]; fregs[pc->a] = (expr); pc++; NEXT; }
FBIN(h_fadd, p + q)
FBIN(h_fsub, p - q)
FBIN(h_fmul, p * q)
FBIN(h_fdiv, p / q)
FBIN(h_fmod, p - floor(p / q) * q)
static Value h_fneg(ARGS) { fregs[pc->a] = -fregs[pc->b]; pc++; NEXT; }
static Value h_funbox(ARGS) { Value v = regs[pc->b]; if (__builtin_expect(is_num(v), 1)) { fregs[pc->a] = as_num(v); pc++; NEXT; } SLOW; }
static Value h_fbox(ARGS) { regs[pc->a] = num(fregs[pc->b]); pc++; NEXT; }
#define FCMP(name, expr) static Value name(ARGS) { double p = fregs[pc->b], q = fregs[pc->c]; iregs[pc->a] = (expr); pc++; NEXT; }
FCMP(h_fcmpeq, p == q)
FCMP(h_fcmpne, p != q)
FCMP(h_fcmple, p <= q)
FCMP(h_fcmplt, p < q)

static Value h_getupval(ARGS) { Value clo = frame[2]; if (__builtin_expect(is_obj(clo), 1)) { regs[pc->a] = ((Value*)obj_ptr(clo))[pc->b]; pc++; NEXT; } SLOW; }
static Value h_getcell(ARGS) { Value c = regs[pc->b]; if (__builtin_expect(is_obj(c) && obj_kind(c) == KIND_CELL, 1)) { regs[pc->a] = ((Value*)obj_ptr(c))[0]; pc++; NEXT; } SLOW; }
static Value h_getslot(ARGS) { Value r = regs[pc->b]; if (__builtin_expect(is_obj(r) && obj_kind(r) == KIND_RECORD, 1)) { regs[pc->a] = ((Value*)obj_ptr(r))[pc->c]; pc++; NEXT; } SLOW; }
static Value h_getslotf(ARGS) { Value r = regs[pc->b]; if (__builtin_expect(is_obj(r) && obj_kind(r) == KIND_RECORD, 1)) { fregs[pc->a] = as_num(((Value*)obj_ptr(r))[pc->c]); pc++; NEXT; } SLOW; }
// A number stored into a slot needs no barrier: it is not a reference.
static Value h_setslotf(ARGS) { Value r = regs[pc->a]; if (__builtin_expect(is_obj(r) && obj_kind(r) == KIND_RECORD, 1)) { ((Value*)obj_ptr(r))[pc->b] = num(fregs[pc->c]); pc++; NEXT; } SLOW; }
static Value h_len(ARGS) { Value v = regs[pc->b]; if (__builtin_expect(is_obj(v), 1)) { uint8_t k = obj_kind(v); if (k == KIND_TABLE || k == KIND_STR || k == KIND_SLICE) { regs[pc->a] = num((double)obj_len(v)); pc++; NEXT; } if (k == KIND_RECORD) { regs[pc->a] = num((double)rt_len(ctx, v)); pc++; NEXT; } } SLOW; }
static Value h_lenf(ARGS) { Value v = regs[pc->b]; if (__builtin_expect(is_obj(v), 1)) { uint8_t k = obj_kind(v); if (k == KIND_TABLE || k == KIND_STR || k == KIND_SLICE) { fregs[pc->a] = (double)obj_len(v); pc++; NEXT; } if (k == KIND_RECORD) { fregs[pc->a] = (double)rt_len(ctx, v); pc++; NEXT; } } SLOW; }
static Value h_strbyte(ARGS) {
    Value s = regs[pc->b];
    if (__builtin_expect(is_obj(s), 1)) {
        uint8_t k = obj_kind(s);
        if (k == KIND_STR || k == KIND_SLICE) {
            int64_t i = iregs[pc->c]; uint64_t n = obj_len(s);
            regs[pc->a] = (i >= 1 && (uint64_t)i <= n) ? num((double)obj_ptr(s)[i - 1]) : T_NIL;
            pc++; NEXT;
        }
    }
    SLOW;
}

// The call: the callee's frame after the caller's whole frame, the value
// arguments copied, missing parameters nil, exactly as `push_frame` does.
static inline void push(Ctx* ctx, uint64_t* frame, uint32_t fid, uint32_t args_at, uint32_t nargs, uint32_t pcx, Value closure) {
    const FuncInfo* fi = &ctx->funcs[fid];
    uint64_t s = ctx->cur;
    frame[0] = (frame[0] & 0xffffffffull) | ((uint64_t)pcx << 32);
    uint64_t ns = s + frame_words_of(frame[3]);
    uint64_t words = fi->frame_words;
    if (ns + words > ctx->cap) { rt_grow(ctx, ns + words); }
    uint64_t* st = ctx->stack;
    uint64_t* nf = st + ns;
    nf[0] = fid;
    nf[1] = s | ((uint64_t)args_at << 32);
    nf[2] = closure;
    nf[3] = header3(words, 0);
    uint32_t np = fi->nparams;
    for (uint32_t i = 0; i < nargs; i++) nf[HDR + 1 + i] = st[args_at + 1 + i];
    for (uint32_t i = nargs; i < np; i++) nf[HDR + 1 + i] = T_NIL;
    ctx->cur = ns;
}
// Enters the frame `push` just placed at ctx->cur.
static Value enter(ARGS) {
    frame = ctx->stack + ctx->cur;
    const FuncInfo* fi = FUNC_OF(frame);
    pc = fi->code;
    regs = (Value*)(frame + HDR);
    iregs = (int64_t*)(frame + fi->off_i);
    fregs = (double*)(frame + fi->off_f);
    NEXT;
}
#define ENTER __attribute__((musttail)) return enter(pc, regs, iregs, fregs, ctx, frame)
// A direct call to an image function (`Call`), or through a value (`CallK`,
// `CallDyn`): a function handle of the main image or a closure object. A
// builtin, a host service, an iterator, a vararg callee or a spread go to Rust.
static Value h_call(ARGS) {
    const FuncInfo* fi = FUNC_OF(frame);
    uint32_t fid = (uint32_t)pc->k;
    if (ctx->funcs[fid].vararg) SLOW;
    push(ctx, frame, fid, (uint32_t)(ctx->cur + HDR + pc->a), pc->b, (uint32_t)(pc - fi->code) + 1, T_NIL);
    ENTER;
}
static Value h_calldyn(ARGS) {
    const FuncInfo* fi = FUNC_OF(frame);
    Value callee = regs[pc->a];
    uint32_t nargs = pc->c;
    if (nargs >= 128) SLOW;
    uint32_t fid; Value closure;
    if (is_obj(callee) && obj_kind(callee) == KIND_CLOSURE) { fid = obj_aux(callee); closure = callee; }
    else if (is_func(callee) && ((callee >> 32) & 0xffff) == 0) { fid = (uint32_t)callee; closure = T_NIL; }
    else if (is_func(callee) && ((callee >> 32) & 0xffff) == 0xffff) {
        // A builtin; a host service may park, so it goes to Rust whole.
        uint32_t id = (uint32_t)callee;
        if (id >= HOST_BASE) SLOW;
        rt_call_builtin(ctx, id, ctx->cur + HDR + pc->b, nargs);
        frame = ctx->stack + ctx->cur; regs = (Value*)(frame + HDR); iregs = (int64_t*)(frame + fi->off_i); fregs = (double*)(frame + fi->off_f);
        pc++; NEXT;
    }
    else if (is_obj(callee) && obj_kind(callee) == KIND_ITER) {
        rt_call_iter(ctx, callee, ctx->cur + HDR + pc->b);
        frame = ctx->stack + ctx->cur; regs = (Value*)(frame + HDR); iregs = (int64_t*)(frame + fi->off_i); fregs = (double*)(frame + fi->off_f);
        pc++; NEXT;
    }
    else SLOW;
    if (fid >= ctx->nfuncs || ctx->funcs[fid].vararg) SLOW;
    uint32_t np = ctx->funcs[fid].nparams;
    if (nargs > np) nargs = np;
    push(ctx, frame, fid, (uint32_t)(ctx->cur + HDR + pc->b), nargs, (uint32_t)(pc - fi->code) + 1, closure);
    ENTER;
}
// The return: the caller's result slot from the header, the task done when
// there is no caller.
// The value to return rides in ctx->result on the way in.
static Value pop(ARGS) {
    Value v = ctx->result;
    uint64_t h1 = frame[1];
    uint32_t caller = (uint32_t)h1;
    if (caller == NONE) { ctx->result = v; ctx->status = ST_DONE; ctx->last_nres = 1; return 0; }
    uint64_t h3 = frame[3];
    if ((h3 >> 32) & 1) { double d = as_num(v); memcpy(&ctx->stack[h3 & 0xffffffffull], &d, 8); }
    else ctx->stack[h1 >> 32] = v;
    ctx->cur = caller;
    ctx->last_nres = 1;
    REENTER;
}
static Value h_ret(ARGS) { ctx->result = regs[pc->a]; __attribute__((musttail)) return pop(pc, regs, iregs, fregs, ctx, frame); }
static Value h_retnil(ARGS) { ctx->result = T_NIL; __attribute__((musttail)) return pop(pc, regs, iregs, fregs, ctx, frame); }
static Value h_retn(ARGS) {
    uint32_t n = pc->b;
    if (n >= 128) SLOW;
    uint64_t h1 = frame[1];
    uint32_t caller = (uint32_t)h1;
    if (caller == NONE) SLOW; // the entry frame's several results are the task's, which Rust records
    uint64_t ret = h1 >> 32;
    Value* from = &regs[pc->a];
    for (uint32_t i = 0; i < n && i < 8; i++) ctx->stack[ret + i] = from[i];
    if (n == 0) ctx->stack[ret] = T_NIL;
    ctx->cur = caller;
    ctx->last_nres = n > 8 ? 8 : n;
    REENTER;
}

// A field read by name (constant imm): a record's shape is scanned for the
// interned name, a miss or a table goes to the helper.
static Value h_getfield(ARGS) {
    Value t = regs[pc->b];
    Value name = FUNC_OF(frame)->consts[pc->imm];
    if (__builtin_expect(is_obj(t), 1)) {
        if (obj_kind(t) == KIND_RECORD) {
            uint32_t shape = obj_aux(t);
            const Value* names = ctx->shapes[shape].names; uint64_t n = ctx->shapes[shape].n;
            for (uint64_t i = 0; i < n; i++) if (names[i] == name) { regs[pc->a] = ((Value*)obj_ptr(t))[i]; pc++; NEXT; }
        }
        regs[pc->a] = rt_get_field(ctx, t, name);
        frame = ctx->stack + ctx->cur; regs = (Value*)(frame + HDR);
        pc++; NEXT;
    }
    SLOW;
}
// Table reads and writes by integer index: the array part in place, the
// rest (growth, hash part, records) through helpers.
static Value h_getidxi(ARGS) {
    Value t = regs[pc->b]; int64_t i = iregs[pc->c];
    if (__builtin_expect(is_obj(t) && obj_kind(t) == KIND_TABLE, 1)) {
        uint64_t n = obj_len(t);
        if (i >= 1 && (uint64_t)i <= n) { regs[pc->a] = ((Value*)obj_ptr(t))[i - 1]; pc++; NEXT; }
    }
    if (is_obj(t)) { regs[pc->a] = rt_get_index_num(ctx, t, i); pc++; NEXT; }
    SLOW;
}
static Value h_setidxi(ARGS) {
    Value t = regs[pc->a]; int64_t i = iregs[pc->b]; Value v = regs[pc->c];
    if (__builtin_expect(is_obj(t) && obj_kind(t) == KIND_TABLE, 1)) {
        uint64_t n = obj_len(t);
        if (i >= 1 && (uint64_t)i <= n) { if (*ctx->marking) rt_barrier(ctx, t, v); ((Value*)obj_ptr(t))[i - 1] = v; pc++; NEXT; }
    }
    if (is_obj(t)) { rt_set_index_num(ctx, t, i, v); frame = ctx->stack + ctx->cur; regs = (Value*)(frame + HDR); pc++; NEXT; }
    SLOW;
}
// Stores of references: the barrier's slow path only while marking (3.6).
static Value h_setcell(ARGS) {
    Value c = regs[pc->a]; Value v = regs[pc->b];
    if (__builtin_expect(is_obj(c) && obj_kind(c) == KIND_CELL, 1)) { if (*ctx->marking) rt_barrier(ctx, c, v); ((Value*)obj_ptr(c))[0] = v; pc++; NEXT; }
    SLOW;
}
static Value h_setslot(ARGS) {
    Value r = regs[pc->a]; Value v = regs[pc->c];
    if (__builtin_expect(is_obj(r) && obj_kind(r) == KIND_RECORD, 1)) { if (*ctx->marking) rt_barrier(ctx, r, v); ((Value*)obj_ptr(r))[pc->b] = v; pc++; NEXT; }
    SLOW;
}
// A read by a value key: an integral number within a table's array part in
// place, anything else (hash part, records, slices as keys) through the helper.
static Value h_getidx(ARGS) {
    Value t = regs[pc->b]; Value key = regs[pc->c];
    if (__builtin_expect(is_obj(t), 1)) {
        if (obj_kind(t) == KIND_TABLE && is_num(key)) {
            double d = as_num(key); uint64_t n = obj_len(t);
            if (d >= 1.0 && d <= (double)n && d == (double)(uint64_t)d) { regs[pc->a] = ((Value*)obj_ptr(t))[(uint64_t)d - 1]; pc++; NEXT; }
        }
        regs[pc->a] = rt_get_index(ctx, t, key);
        frame = ctx->stack + ctx->cur; regs = (Value*)(frame + HDR);
        pc++; NEXT;
    }
    SLOW;
}
static Value h_tagchecknum(ARGS) { Value v = regs[pc->b]; if (__builtin_expect(is_num(v), 1)) { regs[pc->a] = v; pc++; NEXT; } SLOW; }
static Value h_newrecord(ARGS) {
    Value v = rt_new_record(ctx, (uint32_t)pc->k);
    frame = ctx->stack + ctx->cur; regs = (Value*)(frame + HDR);
    regs[pc->a] = v; pc++; NEXT;
}

static const Handler dispatch[OP_COUNT] = {
    [OP_SLOW] = slow, [OP_MOVE] = h_move, [OP_K] = h_k, [OP_NIL] = h_nil, [OP_ADD] = h_add, [OP_SUB] = h_sub, [OP_MUL] = h_mul, [OP_LT] = h_lt, [OP_LE] = h_le, [OP_EQ] = h_eq, [OP_NE] = h_ne, [OP_NOT] = h_not, [OP_NEG] = h_neg,
    [OP_JMP] = h_jmp, [OP_JMPIF] = h_jmpif, [OP_JMPIFNOT] = h_jmpifnot, [OP_JMPIFIZERO] = h_jmpifizero,
    [OP_IK] = h_ik, [OP_IADD] = h_iadd, [OP_ISUB] = h_isub, [OP_IAND] = h_iand, [OP_IOR] = h_ior, [OP_ISHL] = h_ishl, [OP_ISHRU] = h_ishru, [OP_ICMPSLT] = h_icmpslt, [OP_ICMPSLE] = h_icmpsle, [OP_ICMPEQ] = h_icmpeq, [OP_ICMPNE] = h_icmpne, [OP_ICMPLT] = h_icmplt, [OP_ICMPLE] = h_icmple,
    [OP_IMOV] = h_imov, [OP_IADDK] = h_iaddk, [OP_IMASKU32] = h_imasku32, [OP_IUNBOX] = h_iunbox, [OP_ITOF] = h_itof, [OP_FTOI] = h_ftoi, [OP_TRUTHY] = h_truthy, [OP_BOOLFROMI] = h_boolfromi,
    [OP_FK] = h_fk, [OP_FMOV] = h_fmov, [OP_FADD] = h_fadd, [OP_FSUB] = h_fsub, [OP_FMUL] = h_fmul, [OP_FDIV] = h_fdiv, [OP_FMOD] = h_fmod, [OP_FNEG] = h_fneg, [OP_FUNBOX] = h_funbox, [OP_FBOX] = h_fbox, [OP_FCMPEQ] = h_fcmpeq, [OP_FCMPNE] = h_fcmpne, [OP_FCMPLE] = h_fcmple, [OP_FCMPLT] = h_fcmplt,
    [OP_GETUPVAL] = h_getupval, [OP_GETCELL] = h_getcell, [OP_GETSLOT] = h_getslot, [OP_GETSLOTF] = h_getslotf, [OP_SETSLOTF] = h_setslotf, [OP_LEN] = h_len, [OP_LENF] = h_lenf, [OP_STRBYTE] = h_strbyte,
    [OP_CALL] = h_call, [OP_CALLK] = h_calldyn, [OP_CALLDYN] = h_calldyn, [OP_RET] = h_ret, [OP_RETNIL] = h_retnil, [OP_RETN] = h_retn,
    [OP_GETFIELD] = h_getfield, [OP_GETIDXI] = h_getidxi, [OP_SETIDXI] = h_setidxi, [OP_SETCELL] = h_setcell, [OP_SETSLOT] = h_setslot, [OP_TAGCHECKNUM] = h_tagchecknum, [OP_NEWRECORD] = h_newrecord, [OP_GETIDX] = h_getidx,
};

// Runs the context's task from its top frame until it finishes or parks;
// the status says which, and `result` carries the value or the park key.
uint32_t vm_run(Ctx* ctx) {
    ctx->status = 0;
    reenter(0, 0, 0, 0, ctx, 0);
    return ctx->status;
}
