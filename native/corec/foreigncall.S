// foreigncall.S: a guest's foreign call from the block that describes it,
// as s0 selects the generic call (select.nupp foreignCall, `all`): the
// function at word 0, x0-x7 at words 1-8, d0-d7 at 9-16, sixteen stack words
// at 17-32 and the indirect result address at 33. x0, x1 and d0-d3 come back
// into the block.
    .text
    .p2align 2
    .globl _nupp_foreign_call
_nupp_foreign_call:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #144
    str x0, [sp, #128]
    .irp word, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
    ldr x17, [x0, #(17 + \word) * 8]
    str x17, [sp, #\word * 8]
    .endr
    ldp d0, d1, [x0, #72]
    ldp d2, d3, [x0, #88]
    ldp d4, d5, [x0, #104]
    ldp d6, d7, [x0, #120]
    ldr x16, [x0]
    ldr x8, [x0, #264]
    ldp x6, x7, [x0, #56]
    ldp x4, x5, [x0, #40]
    ldp x2, x3, [x0, #24]
    ldr x1, [x0, #16]
    ldr x0, [x0, #8]
    blr x16
    ldr x17, [sp, #128]
    stp x0, x1, [x17, #8]
    stp d0, d1, [x17, #72]
    stp d2, d3, [x17, #88]
    add sp, sp, #144
    ldp x29, x30, [sp], #16
    ret
