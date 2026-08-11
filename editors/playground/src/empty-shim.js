// fengari's package statically requires a handful of Node built-ins (fs,
// path, os, child_process, crypto) plus two CLI-only helper packages
// (readline-sync, tmp) for code paths this playground never runs: real
// filesystem I/O, dynamic library loading, stdin prompts, and os.tmpname.
// io.open/io.popen are shimmed out in host-runtime.lua before any of that
// runs, so none of it executes — but esbuild still needs *something*
// resolvable to bundle for the browser. This is that something.
export default {};
