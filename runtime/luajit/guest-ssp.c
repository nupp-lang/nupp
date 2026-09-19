/* GCC's i386 PIC stack protector calls a hidden, executable-local trampoline.
 * musl exports the failure handler; glibc supplies this through libc_nonshared.
 */
extern void __stack_chk_fail(void) __attribute__((noreturn));
__attribute__((visibility("hidden"), noreturn)) void __stack_chk_fail_local(void) {
    __stack_chk_fail();
}
