/*
** The core's hot opcode handlers written in C with the same logic and the
** same layouts as src/nupp/runtime/core/guesthandlers.nupp: a measuring
** oracle for the s0 backend. clang -O2's code for each fast path is what s0
** is held to (build/codegen/compare.md). Never built into anything shipped.
**
**   sh bench/codegen-oracle/measure.sh
*/

#include <stdint.h>

/* Context words (runtime/core/context.nupp). */
#define CTX_REMAINING 0
#define CTX_CANCELLED 1
#define CTX_STATUS 2
#define CTX_DISPATCH 5
#define CTX_STATE 6
#define CTX_CATALOG 7
#define CTX_FAILURE 15
#define UNLIMITED UINT64_MAX

/* Value words (runtime/vm/values.nupp). */
#define NIL 0x7ff9000000000000ULL
#define FALSE 0x7ffa000000000000ULL
#define INSTRUCTION_BYTES 16
#define INSTRUCTION_SHIFT 4
#define INVALID 4
#define TAG_MASK 0x7fff000000000000ULL
#define TAG_OBJ 0x7ffd000000000000ULL
#define PAYLOAD 0x0000ffffffffffffULL
#define CONSTANT_MASK 0xffff000000000000ULL
#define STRING_CONSTANT 0x7ffe000000000000ULL
#define INTEGER_CONSTANT 0x7ffc000000000000ULL
#define KIND_CLOSURE 5

typedef struct Frame {
  uint64_t pad0[3];
  uint64_t functionId;
  uint64_t bodyOwner;
  uint64_t code;
  uint64_t instructionCount;
  uint64_t pad1;
  uint64_t closureRoot;
  uint64_t pad2;
  uint64_t valueCount;
} Frame;

typedef struct Function {
  uint64_t pad[8];
  uint64_t constants;
  uint64_t constantCount;
} Function;

typedef struct Header {
  uint8_t kind;
  uint8_t pad[15];
  uint64_t auxPtr;
  uint64_t auxLen;
} Header;

typedef struct State {
  uint64_t active;
} State;

typedef uint64_t (*Handler)(const uint8_t *pc, uint64_t *regs, uint64_t *ints,
                            double *floats, uint64_t *ctx, Frame *frame);

extern void fail (uint64_t *ctx, Frame *frame, const uint8_t *pc, uint64_t code,
                  uint64_t failure);
extern uint64_t stringConstant (uint64_t *ctx, uint64_t owner, uint64_t value);
extern uint64_t integerConstant (uint64_t *ctx, uint64_t owner, uint64_t value);
extern uint64_t charge (uint64_t *ctx, Frame *frame, const uint8_t *pc);

static uint64_t failed (uint64_t *ctx, Frame *frame, const uint8_t *pc) {
  fail(ctx, frame, pc, INVALID, ctx[CTX_FAILURE]);

  return 0;
}

#define DISPATCH(next)                                                         \
  do {                                                                         \
    Handler handler = ((Handler *)ctx[CTX_DISPATCH])[*(next)];                 \
    __attribute__((musttail)) return handler(next, regs, ints, floats, ctx,    \
                                             frame);                           \
  } while (0)

static int running (uint64_t *ctx, Frame *frame) {
  return ((State *)ctx[CTX_STATE])->active == (uint64_t)frame;
}

static int inCode (Frame *frame, const uint8_t *next) {
  uint64_t end = frame->code + (frame->instructionCount << INSTRUCTION_SHIFT);

  return (uint64_t)next >= frame->code && (uint64_t)next < end;
}

uint64_t Move (const uint8_t *pc, uint64_t *regs, uint64_t *ints,
               double *floats, uint64_t *ctx, Frame *frame) {
  if (!running(ctx, frame)) {
    return failed(ctx, frame, pc);
  }

  uint64_t dst = pc[1], src = pc[2];

  if (dst >= frame->valueCount || src >= frame->valueCount) {
    return failed(ctx, frame, pc);
  }

  regs[dst] = regs[src];
  const uint8_t *next = pc + INSTRUCTION_BYTES;

  if ((uint64_t)next >=
      frame->code + (frame->instructionCount << INSTRUCTION_SHIFT)) {
    return failed(ctx, frame, pc);
  }

  DISPATCH(next);
}

static uint64_t backEdge (const uint8_t *pc, uint64_t *ctx, Frame *frame) {
  uint64_t remaining = ctx[CTX_REMAINING];

  if (ctx[CTX_STATUS] != 0 || ctx[CTX_CANCELLED] != 0 || remaining == 0) {
    return charge(ctx, frame, pc) == 1;
  }

  if (remaining != UNLIMITED) {
    ctx[CTX_REMAINING] = remaining - 1;
  }

  return 1;
}

uint64_t Jmp (const uint8_t *pc, uint64_t *regs, uint64_t *ints, double *floats,
              uint64_t *ctx, Frame *frame) {
  if (!running(ctx, frame)) {
    return failed(ctx, frame, pc);
  }

  int32_t displacement = *(const int32_t *)(pc + 4);

  if (displacement < 0 && !backEdge(pc, ctx, frame)) {
    return 0;
  }

  const uint8_t *target =
      pc + INSTRUCTION_BYTES + ((int64_t)displacement << INSTRUCTION_SHIFT);

  if (!inCode(frame, target)) {
    return failed(ctx, frame, pc);
  }

  DISPATCH(target);
}

uint64_t JmpIf (const uint8_t *pc, uint64_t *regs, uint64_t *ints,
                double *floats, uint64_t *ctx, Frame *frame) {
  if (!running(ctx, frame)) {
    return failed(ctx, frame, pc);
  }

  uint64_t src = pc[1];

  if (src >= frame->valueCount) {
    return failed(ctx, frame, pc);
  }

  uint64_t value = regs[src];

  if (value == FALSE || value == NIL) {
    const uint8_t *next = pc + INSTRUCTION_BYTES;

    if ((uint64_t)next >=
        frame->code + (frame->instructionCount << INSTRUCTION_SHIFT)) {
      return failed(ctx, frame, pc);
    }

    DISPATCH(next);
  }

  int32_t displacement = *(const int32_t *)(pc + 4);

  if (displacement < 0 && !backEdge(pc, ctx, frame)) {
    return 0;
  }

  const uint8_t *target =
      pc + INSTRUCTION_BYTES + ((int64_t)displacement << INSTRUCTION_SHIFT);

  if (!inCode(frame, target)) {
    return failed(ctx, frame, pc);
  }

  DISPATCH(target);
}

uint64_t K (const uint8_t *pc, uint64_t *regs, uint64_t *ints, double *floats,
            uint64_t *ctx, Frame *frame) {
  if (!running(ctx, frame)) {
    return failed(ctx, frame, pc);
  }

  uint64_t dst = pc[1];
  int32_t index = *(const int32_t *)(pc + 4);

  if (dst >= frame->valueCount || index < 0) {
    return failed(ctx, frame, pc);
  }

  Function *fn = (Function *)frame->bodyOwner;

  if ((uint64_t)index >= fn->constantCount) {
    return failed(ctx, frame, pc);
  }

  const uint8_t *data = *(const uint8_t **)ctx[CTX_CATALOG];
  uint64_t value =
      *(const uint64_t *)(data + fn->constants + (uint64_t)index * 8);

  if ((value & CONSTANT_MASK) == STRING_CONSTANT) {
    value = TAG_OBJ | stringConstant(ctx, frame->functionId, value);
  }

  if ((value & CONSTANT_MASK) == INTEGER_CONSTANT) {
    value = integerConstant(ctx, frame->functionId, value);
  }

  regs[dst] = value;
  const uint8_t *next = pc + INSTRUCTION_BYTES;

  if ((uint64_t)next >=
      frame->code + (frame->instructionCount << INSTRUCTION_SHIFT)) {
    return failed(ctx, frame, pc);
  }

  DISPATCH(next);
}

uint64_t GetUpval (const uint8_t *pc, uint64_t *regs, uint64_t *ints,
                   double *floats, uint64_t *ctx, Frame *frame) {
  if (!running(ctx, frame)) {
    return failed(ctx, frame, pc);
  }

  uint64_t dst = pc[1];
  int32_t index = *(const int32_t *)(pc + 4);

  if (dst >= frame->valueCount || index < 0) {
    return failed(ctx, frame, pc);
  }

  uint64_t closure = frame->closureRoot;

  if ((closure & TAG_MASK) != TAG_OBJ) {
    return failed(ctx, frame, pc);
  }

  Header *header = (Header *)(closure & PAYLOAD);

  if (header->kind != KIND_CLOSURE || (uint64_t)index + 1 >= header->auxLen) {
    return failed(ctx, frame, pc);
  }

  regs[dst] = ((const uint64_t *)header->auxPtr)[(uint64_t)index + 1];
  const uint8_t *next = pc + INSTRUCTION_BYTES;

  if ((uint64_t)next >=
      frame->code + (frame->instructionCount << INSTRUCTION_SHIFT)) {
    return failed(ctx, frame, pc);
  }

  DISPATCH(next);
}
