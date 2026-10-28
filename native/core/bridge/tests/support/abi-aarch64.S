// Test-only AAPCS64 preservation probe. No guest operations or frame policy.
.text
.p2align 2
.globl _nupp_core_test_abi
.globl nupp_core_test_abi
_nupp_core_test_abi:
nupp_core_test_abi:
    sub sp, sp, #192
    stp x19, x20, [sp, #0]
    stp x21, x22, [sp, #16]
    stp x23, x24, [sp, #32]
    stp x25, x26, [sp, #48]
    stp x27, x28, [sp, #64]
    stp x29, x30, [sp, #80]
    stp d8, d9, [sp, #96]
    stp d10, d11, [sp, #112]
    stp d12, d13, [sp, #128]
    stp d14, d15, [sp, #144]
    str x3, [sp, #160]
    mov x16, x0
    mov x0, x1
    mov x1, x2
    mov x19, #6419
    mov x20, #6420
    mov x21, #6421
    mov x22, #6422
    mov x23, #6423
    mov x24, #6424
    mov x25, #6425
    mov x26, #6426
    mov x27, #6427
    mov x28, #6428
    mov x29, #6429
    mov x17, #55304
    fmov d8, x17
    mov x17, #55305
    fmov d9, x17
    mov x17, #55306
    fmov d10, x17
    mov x17, #55307
    fmov d11, x17
    mov x17, #55308
    fmov d12, x17
    mov x17, #55309
    fmov d13, x17
    mov x17, #55310
    fmov d14, x17
    mov x17, #55311
    fmov d15, x17
    blr x16
    str x0, [sp, #168]
    mov x15, #0
    mov x16, #6419
    cmp x19, x16
    cset x17, ne
    orr x15, x15, x17, lsl #0
    mov x16, #6420
    cmp x20, x16
    cset x17, ne
    orr x15, x15, x17, lsl #1
    mov x16, #6421
    cmp x21, x16
    cset x17, ne
    orr x15, x15, x17, lsl #2
    mov x16, #6422
    cmp x22, x16
    cset x17, ne
    orr x15, x15, x17, lsl #3
    mov x16, #6423
    cmp x23, x16
    cset x17, ne
    orr x15, x15, x17, lsl #4
    mov x16, #6424
    cmp x24, x16
    cset x17, ne
    orr x15, x15, x17, lsl #5
    mov x16, #6425
    cmp x25, x16
    cset x17, ne
    orr x15, x15, x17, lsl #6
    mov x16, #6426
    cmp x26, x16
    cset x17, ne
    orr x15, x15, x17, lsl #7
    mov x16, #6427
    cmp x27, x16
    cset x17, ne
    orr x15, x15, x17, lsl #8
    mov x16, #6428
    cmp x28, x16
    cset x17, ne
    orr x15, x15, x17, lsl #9
    mov x16, #6429
    cmp x29, x16
    cset x17, ne
    orr x15, x15, x17, lsl #10
    fmov x16, d8
    mov x17, #55304
    cmp x16, x17
    cset x17, ne
    orr x15, x15, x17, lsl #11
    fmov x16, d9
    mov x17, #55305
    cmp x16, x17
    cset x17, ne
    orr x15, x15, x17, lsl #12
    fmov x16, d10
    mov x17, #55306
    cmp x16, x17
    cset x17, ne
    orr x15, x15, x17, lsl #13
    fmov x16, d11
    mov x17, #55307
    cmp x16, x17
    cset x17, ne
    orr x15, x15, x17, lsl #14
    fmov x16, d12
    mov x17, #55308
    cmp x16, x17
    cset x17, ne
    orr x15, x15, x17, lsl #15
    fmov x16, d13
    mov x17, #55309
    cmp x16, x17
    cset x17, ne
    orr x15, x15, x17, lsl #16
    fmov x16, d14
    mov x17, #55310
    cmp x16, x17
    cset x17, ne
    orr x15, x15, x17, lsl #17
    fmov x16, d15
    mov x17, #55311
    cmp x16, x17
    cset x17, ne
    orr x15, x15, x17, lsl #18
    ldr x16, [sp, #160]
    ldr x17, [sp, #168]
    stp x17, x15, [x16]
    ldp d8, d9, [sp, #96]
    ldp d10, d11, [sp, #112]
    ldp d12, d13, [sp, #128]
    ldp d14, d15, [sp, #144]
    ldp x19, x20, [sp, #0]
    ldp x21, x22, [sp, #16]
    ldp x23, x24, [sp, #32]
    ldp x25, x26, [sp, #48]
    ldp x27, x28, [sp, #64]
    ldp x29, x30, [sp, #80]
    add sp, sp, #192
    ret

// Calibration deliberately violates exactly x19 and low64 d8.
.p2align 2
.globl _nupp_core_test_abi_clobber
.globl nupp_core_test_abi_clobber
_nupp_core_test_abi_clobber:
nupp_core_test_abi_clobber:
    mov x19, #0
    fmov d8, xzr
    mov x0, #7
    ret
