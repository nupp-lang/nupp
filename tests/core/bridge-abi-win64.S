// Test-only Win64 C ABI probe. Report rbx/rbp/rdi/rsi/r12-r15 in bits 0-7
// and all 128 bits of xmm6-xmm15 in bits 8-17.

.macro save_gpr reg, offset
    movq %\reg, \offset(%rsp)
    .seh_savereg %\reg, \offset
.endm

.macro save_xmm reg, offset
    movdqa %xmm\reg, \offset(%rsp)
    .seh_savexmm %xmm\reg, \offset
.endm

.macro seed_xmm reg, seed
    movl $\seed, %eax
    movd %eax, %xmm\reg
    pshufd $0, %xmm\reg, %xmm\reg
.endm

.macro check_gpr reg, seed, bit
    cmpq $\seed, %\reg
    je 1f
    orq $(1 << \bit), %r10
1:
.endm

.macro check_xmm reg, seed, bit
    seed_xmm 0, \seed
    pcmpeqb %xmm\reg, %xmm0
    pmovmskb %xmm0, %eax
    cmpl $65535, %eax
    je 1f
    orq $(1 << \bit), %r10
1:
.endm

.text
.p2align 4
.globl nupp_core_test_abi
.seh_proc nupp_core_test_abi
nupp_core_test_abi:

    // Shadow space at 0-31, report and result at 32-47. Save the caller's
    // registers above that and align rsp for the entry call.
    subq $280, %rsp
    .seh_stackalloc 280
    save_gpr rbx, 48
    save_gpr rbp, 56
    save_gpr rdi, 64
    save_gpr rsi, 72
    save_gpr r12, 80
    save_gpr r13, 88
    save_gpr r14, 96
    save_gpr r15, 104
    save_xmm 6, 112
    save_xmm 7, 128
    save_xmm 8, 144
    save_xmm 9, 160
    save_xmm 10, 176
    save_xmm 11, 192
    save_xmm 12, 208
    save_xmm 13, 224
    save_xmm 14, 240
    save_xmm 15, 256
    .seh_endprologue

    movq %r9, 32(%rsp)
    movq %rcx, %r11
    movq %rdx, %rcx
    movq %r8, %rdx
    movq $6419, %rbx
    movq $6420, %rbp
    movq $6421, %rdi
    movq $6422, %rsi
    movq $6423, %r12
    movq $6424, %r13
    movq $6425, %r14
    movq $6426, %r15
    seed_xmm 6, 55306
    seed_xmm 7, 55307
    seed_xmm 8, 55308
    seed_xmm 9, 55309
    seed_xmm 10, 55310
    seed_xmm 11, 55311
    seed_xmm 12, 55312
    seed_xmm 13, 55313
    seed_xmm 14, 55314
    seed_xmm 15, 55315
    call *%r11
    movq %rax, 40(%rsp)

    xorq %r10, %r10
    check_gpr rbx, 6419, 0
    check_gpr rbp, 6420, 1
    check_gpr rdi, 6421, 2
    check_gpr rsi, 6422, 3
    check_gpr r12, 6423, 4
    check_gpr r13, 6424, 5
    check_gpr r14, 6425, 6
    check_gpr r15, 6426, 7
    check_xmm 6, 55306, 8
    check_xmm 7, 55307, 9
    check_xmm 8, 55308, 10
    check_xmm 9, 55309, 11
    check_xmm 10, 55310, 12
    check_xmm 11, 55311, 13
    check_xmm 12, 55312, 14
    check_xmm 13, 55313, 15
    check_xmm 14, 55314, 16
    check_xmm 15, 55315, 17
    movq 32(%rsp), %r11
    movq 40(%rsp), %rax
    movq %rax, (%r11)
    movq %r10, 8(%r11)

    movq 48(%rsp), %rbx
    movq 56(%rsp), %rbp
    movq 64(%rsp), %rdi
    movq 72(%rsp), %rsi
    movq 80(%rsp), %r12
    movq 88(%rsp), %r13
    movq 96(%rsp), %r14
    movq 104(%rsp), %r15
    movdqa 112(%rsp), %xmm6
    movdqa 128(%rsp), %xmm7
    movdqa 144(%rsp), %xmm8
    movdqa 160(%rsp), %xmm9
    movdqa 176(%rsp), %xmm10
    movdqa 192(%rsp), %xmm11
    movdqa 208(%rsp), %xmm12
    movdqa 224(%rsp), %xmm13
    movdqa 240(%rsp), %xmm14
    movdqa 256(%rsp), %xmm15
    addq $280, %rsp
    ret
.seh_endproc

// Calibration deliberately changes rbx and the high half of xmm6.
.p2align 4
.globl nupp_core_test_abi_clobber
nupp_core_test_abi_clobber:
    xorq %rbx, %rbx
    movq %xmm6, %rax
    movq %rax, %xmm6
    movl $7, %eax
    ret
