// A tail-call-threaded dispatch core for the untyped opcodes fib uses, on
// the same one-stack frame layout as the Rust interpreter: four header
// words then the value window. Each handler finishes by tail-calling the
// next instruction's handler, so dispatch is one indirect branch per
// instruction with its own predictor slot, and the state stays in the
// argument registers. Built by build.rs; `threaded_fib` is the entry.
#include <stdint.h>
#include <string.h>
#include <math.h>

typedef uint64_t Value;
typedef struct { uint8_t op, a, b, c; int32_t imm; int64_t k; } Ins;

enum { OP_K, OP_MOVE, OP_ADD, OP_SUB, OP_LT, OP_JMPIFNOT, OP_JMP, OP_CALL, OP_RET, OP_COUNT };

#define QNAN 0x7ff8000000000000ull
#define TAG_SHIFT 48
#define T_NIL (QNAN | (1ull << TAG_SHIFT))
#define T_FALSE (QNAN | (2ull << TAG_SHIFT))
#define T_TRUE (QNAN | (3ull << TAG_SHIFT))
#define HDR 4
#define NONE 0xffffffffu

typedef struct {
    const Ins* code;      // one function: fib
    const Value* consts;
    uint64_t* stack;      // words
    size_t cap;
    uint32_t frame_words; // HDR + nregs
    Value result;
} Ctx;

static inline int is_num(Value v) { return (v & QNAN) != QNAN || v == QNAN; }
static inline double as_num(Value v) { double d; memcpy(&d, &v, 8); return d; }
static inline Value num(double d) { Value v; memcpy(&v, &d, 8); if ((v & QNAN) == QNAN) v = QNAN; return v; }
static inline int truthy(Value v) { return v != T_NIL && v != T_FALSE; }

typedef Value (*Handler)(const Ins* pc, Value* regs, Ctx* ctx, uint64_t* frame);
static const Handler dispatch[OP_COUNT];
#define NEXT(pc, regs, ctx, frame) __attribute__((musttail)) return dispatch[(pc)->op]((pc), (regs), (ctx), (frame))

static Value h_k(const Ins* pc, Value* regs, Ctx* ctx, uint64_t* frame) { regs[pc->a] = ctx->consts[pc->b]; pc++; NEXT(pc, regs, ctx, frame); }
static Value h_move(const Ins* pc, Value* regs, Ctx* ctx, uint64_t* frame) { regs[pc->a] = regs[pc->b]; pc++; NEXT(pc, regs, ctx, frame); }
static Value h_add(const Ins* pc, Value* regs, Ctx* ctx, uint64_t* frame) {
    Value x = regs[pc->b], y = regs[pc->c];
    if (__builtin_expect(is_num(x) && is_num(y), 1)) regs[pc->a] = num(as_num(x) + as_num(y)); else __builtin_trap();
    pc++; NEXT(pc, regs, ctx, frame);
}
static Value h_sub(const Ins* pc, Value* regs, Ctx* ctx, uint64_t* frame) {
    Value x = regs[pc->b], y = regs[pc->c];
    if (__builtin_expect(is_num(x) && is_num(y), 1)) regs[pc->a] = num(as_num(x) - as_num(y)); else __builtin_trap();
    pc++; NEXT(pc, regs, ctx, frame);
}
static Value h_lt(const Ins* pc, Value* regs, Ctx* ctx, uint64_t* frame) {
    Value x = regs[pc->b], y = regs[pc->c];
    if (__builtin_expect(is_num(x) && is_num(y), 1)) regs[pc->a] = as_num(x) < as_num(y) ? T_TRUE : T_FALSE; else __builtin_trap();
    pc++; NEXT(pc, regs, ctx, frame);
}
static Value h_jmpifnot(const Ins* pc, Value* regs, Ctx* ctx, uint64_t* frame) { int32_t off = pc->imm; pc++; if (!truthy(regs[pc[-1].a])) pc += off; NEXT(pc, regs, ctx, frame); }
static Value h_jmp(const Ins* pc, Value* regs, Ctx* ctx, uint64_t* frame) { pc = pc + 1 + pc->imm; NEXT(pc, regs, ctx, frame); }
// Call: the callee's frame follows the caller's; header saves the return pc
// (as an index) and the caller's frame; one value argument is copied.
static Value h_call(const Ins* pc, Value* regs, Ctx* ctx, uint64_t* frame) {
    uint64_t* callee = frame + ctx->frame_words;
    if (__builtin_expect((size_t)(callee + ctx->frame_words - ctx->stack) > ctx->cap, 0)) __builtin_trap();
    callee[0] = (uint64_t)(pc + 1 - ctx->code);       // return pc index
    callee[1] = (uint64_t)(frame - ctx->stack);       // caller frame
    callee[2] = (uint64_t)(pc->b);                    // result register in the caller
    Value* cregs = (Value*)(callee + HDR);
    for (unsigned i = 0; i < pc->c; i++) cregs[1 + i] = regs[pc->b + 1 + i];
    NEXT(ctx->code, cregs, ctx, callee);
}
static Value h_ret(const Ins* pc, Value* regs, Ctx* ctx, uint64_t* frame) {
    Value v = regs[pc->a];
    if (frame[1] == NONE) { ctx->result = v; return v; }
    uint64_t* caller = ctx->stack + frame[1];
    Value* cregs = (Value*)(caller + HDR);
    cregs[frame[2]] = v;
    const Ins* rpc = ctx->code + frame[0];
    NEXT(rpc, cregs, ctx, caller);
}
static const Handler dispatch[OP_COUNT] = { h_k, h_move, h_add, h_sub, h_lt, h_jmpifnot, h_jmp, h_call, h_ret };

// Runs `code` (one function, entry at 0) with one number argument.
double threaded_run(const Ins* code, const Value* consts, uint32_t nregs, uint64_t* stack, size_t cap, double arg) {
    Ctx ctx = { code, consts, stack, cap, HDR + nregs + 1, 0 };
    stack[0] = 0; stack[1] = NONE; stack[2] = 0; stack[3] = 0;
    Value* regs = (Value*)(stack + HDR);
    regs[1] = num(arg);
    Value r = dispatch[code->op](code, regs, &ctx, stack);
    return as_num(r);
}
