# Batched regex lexer prototype

This experiment tests whether one compiled Rust regex, entered once from Lua,
can accelerate Nupp's lossless lexer. The native half returns a flat array of
classified byte spans; `benchmark.lua` materializes the same token, trivia,
position, and diagnostic tables as `nupp.compiler.lexer`.

The regex handles whitespace, line comments, names, short strings, and
operators. Small procedural scanners handle the language parts an ordinary
regular expression cannot represent: numerals with recovery, Lua long
brackets, and interpolated strings with nested brace depth.

From the repository root:

```sh
cargo build --release --manifest-path experiments/regex-lexer/Cargo.toml
./bin/nupp build
luajit experiments/regex-lexer/benchmark.lua
```

The benchmark first checks every token and diagnostic against the production
lexer over the repository's Nupp sources, malformed-input probes, and generated
ASCII and arbitrary-byte inputs. It refuses to print timings if they differ.

## Result

On Apple arm64 with LuaJIT 2.1.1785577137 and Rust 1.97.1, three warm runs over
2.285 MB in 145 files measured:

| implementation | throughput |
| --- | ---: |
| current LuaJIT lexer | 25.7–26.3 MB/s |
| native regex spans, before Lua allocation | 22.5–23.0 MB/s |
| native regex plus compatible Lua objects | 11.5–11.8 MB/s |

The native call crosses the FFI boundary once per source file. Even before
materializing Lua objects, the combined regex loses to the existing JIT-compiled
byte scanner. The compatible path is less than half as fast, so this prototype
does not justify replacing the production lexer.
