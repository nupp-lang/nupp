/**
 * @file
 * @brief Provides the i386 guest's local stack-check failure trampoline.
 */

/* GCC's i386 PIC stack protector calls a hidden, executable-local trampoline.
 * musl exports the failure handler; glibc supplies this through libc_nonshared.
 */
extern void __stack_chk_fail(void) __attribute__((noreturn));
/** Forwards the guest executable's stack-check failure to musl. */
__attribute__((visibility("hidden"), noreturn)) void __stack_chk_fail_local(void) {
    __stack_chk_fail();
}
