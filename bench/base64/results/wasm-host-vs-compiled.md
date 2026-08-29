# Encoding base64 from inside WebAssembly

`nupp.runtime.browser.base64` is the encoder the browser providers use, and the
question this answers is whether a compiled entry should replace it or whether
the host's own base64 should. The answer is the host's, and by enough that it
is not close.

Node 26 on Apple silicon, three consecutive runs agreeing to within a few
percent. Nanoseconds per input byte; lower is better. The bytes start in
WebAssembly memory, which is where a Lua-in-Wasm caller has them.

| bytes | compiled, in Wasm | `btoa` + marshalling | `btoa` alone | marshalling alone | `toBase64` |
| --- | --- | --- | --- | --- | --- |
| 1,024 | 0.611 | 1.282 | 0.348 | 0.241 | 0.334 |
| 65,536 | 0.75 | 0.43 | 0.22 | 0.062 | 0.139 |
| 1,048,576 | 0.71 | 0.38 | 0.156 | 0.049 | 0.111 |

`compiled, in Wasm` is `bench/base64`'s scalar C control built with
`emcc -O2`, called with its input already in Wasm memory. It stands in for what
an `@aot` entry would reach there and, if anything, flatters it: it pays none of
the Lua boundary, the scratch, or the publish that a real entry does.

**`Uint8Array.prototype.toBase64` is about six times that, and copies nothing
on the way in.** `subarray` is a view into Wasm memory rather than a copy, so
the host reads the bytes where they already are. The older `btoa` route needs a
binary string first, and that marshalling is most of what it costs.

## What the columns do not say

The `toBase64` column excludes writing the result back into Wasm memory, and
the `btoa` column includes it. That asymmetry is deliberate rather than an
oversight: the browser providers encode in order to hand the text *to*
JavaScript -- a worker payload, an HTTP body -- so the result does not come
back. Decoding runs the other way and `Uint8Array.fromBase64` is its
counterpart.

Marshalling here uses Node's `Buffer.prototype.toString("latin1")`, which a
browser does not have. With the technique a browser would use -- chunked
`String.fromCharCode` -- the same `btoa` route measured 2.3 ns per byte, or
eight times the compiled entry. So `btoa` is only competitive given a fast
byte-to-binary-string primitive, while `toBase64` needs none at all.

`toBase64` and `fromBase64` are recent. Somewhere that lacks them, the compiled
entry beats the `btoa` route on the marshalling a browser can actually do, so
the fallback should be the compiled entry rather than `btoa`.
