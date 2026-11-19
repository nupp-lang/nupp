/**
 * @file
 * @brief Sanitizer defaults for core bridge and native contract tests.
 *
 * The sanitizers' defaults for the bridge, the guard and the contracts,
 * which scripts/core-bridge links in only when it builds them sanitized.
 * Compiled into the program, they hold for every harness that runs it,
 * whatever its environment says; ASAN_OPTIONS and UBSAN_OPTIONS still add
 * to them.
 *
 * A segmentation fault or bus error is left to kill the process by its
 * signal: the contracts and the guard provoke them on purpose and check how
 * the process died, and the sanitizer's handler would abort instead. Leak
 * detection is off: the bridge hands the guest memory that lives until
 * exit. Undefined behavior stops the process at once, with its stack.
 */

/* The names are the sanitizer runtimes' own, which they look up when they
 * start. NOLINTBEGIN(bugprone-reserved-identifier,cert-dcl37-c) */
const char *__asan_default_options (void);
const char *__ubsan_default_options (void);

const char *__asan_default_options (void) {
  return "handle_segv=0:handle_sigbus=0:detect_leaks=0";
}

const char *__ubsan_default_options (void) {
  return "halt_on_error=1:print_stacktrace=1";
}

/* NOLINTEND(bugprone-reserved-identifier,cert-dcl37-c) */
