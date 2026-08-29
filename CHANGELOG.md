# Changelog

## Unreleased

- A binary that carries some of what the compiler carries no longer reports that
  it carries none of the rest. `bundledlist.list` read the presence of an
  embedded resource table as proof that it was the only place to look, so the
  test binary -- which embeds the modules and not the templates -- answered that
  there are no built-in templates, and `nupp test templatetest` failed ten cases
  on a machine where `nupp init` worked. It falls through to the directory the
  way `bundled.source` always has.

- A declaration that carries a runtime value is refused beside `export =`, as
  `NUPP2143`, rather than compiling to a module that raises when it is first
  required. `export record`, `export function` and `export const` were writing
  into the export table before the assignment established it, and the checker
  meanwhile said the name was reachable through the module, which it was never
  going to be: with `export =` the named value is the module and the compiler
  builds no table of its own. An `export interface` or `export type` is erased
  and stays legal beside one, which is how seven modules in this compiler are
  written.

- `@derive` works on a portable target. Both bundled recipes render by appending
  into a `string.buffer`, which is LuaJIT's module, and that was the only thing
  in the derive runtime or in `nupp.data.serde` a `lua51` target could not answer
  -- neither reaches `cstorage` for anything, whatever the classification used to
  say. A new `text.buffer` seam supplies the buffer, `nupp.runtime.provider.tablebuffer`
  is the carried provider, and the browser backend selects it, so a page derives
  `Debug` and `JSON` with nothing further to configure. The Chromium acceptance
  covers the round trip, and the seam's conformance suite is run against LuaJIT's
  own buffer as well as against the provider, so the contract describes the thing
  rather than the stand-in.

  A provider implements the declared module rather than replacing it, which is
  what `implementationModules` already meant for the build and now means at
  install too: signatures keep naming `string.buffer.Buffer` on either target.
  Substituting the interface as well gave the same buffer two names, and a
  `Buffer` from one was not a `Buffer` to the other.

- Every compiler-provided runtime is now either compiled for the target that
  needs it or refused there. `nupp.compiler.runtime.reflect`, `nupp.suspension`,
  `nupp.tasks` and `nupp.data.digest` join `nupp.compiler.runtime.math` in saying
  their runtime is portable, so a `lua51` payload carries a `lua51` lowering of
  each rather than the compiler's own `luajit` build of it. A suite holds the
  whole feature table to the rule, so the next one added has to answer it.

- `@derive` says why it does not work on a portable target, on the line that
  asked for it. The derive runtime renders through `nupp.data.serde`, which needs
  `cstorage`, and the classification said otherwise -- so a `lua51` program that
  wrote `@derive(nupp.derive.Debug)` got four errors inside compiler-carried
  source and nothing pointing back at its own annotation. Resolving a recipe now
  asks whether the target can reach the module before checking it.

- `nupp.tasks` runs on a browser page. `tasks.run`, `tasks.runFor`,
  `scope:spawn`, `tasks.checkpoint()` and `tasks.Scope:workers()` all work there,
  so a page gets the fail-fast form of a worker scope: a scope deadline reaches a
  lane and the checkpoint is where it lands. The browser acceptance covers it.

  It hung because the scope driver parked and its children never woke it. The
  handler a child installs is keyed by the coroutine it was installed on, and on
  stock Lua 5.1 a cleanup region runs its body on a coroutine of its own -- so a
  child that installed a handler and then awaited was, as far as the lookup was
  concerned, running somewhere else with no handler at all. The browser
  provider's `install` is no longer affine, which is what gave its block that
  region; it was made affine to quiet a lint that used to discard the module, and
  the lint no longer does.

- `nupp.math` works on a portable target. Its run-time half named three things
  only LuaJIT has -- the `bit` table, an `ffi` union for every `binary32`
  conversion, and the two-argument arc tangent -- so a `lua51` program that read
  `nupp.math` as a value rather than through a lowered intrinsic got a payload
  that could not even load. Bit operations now come from whatever answers
  `numeric.bitops` on the target, and the conversions are arithmetic that agrees
  with the union bit for bit. This is what the `scalar` Wasm AOT case in Chromium
  was failing on, and it is the last of the eleven browser cases to pass.

- A module the compiler carries is compiled for the target that needs it rather
  than staged from the compiler's own build, wherever the two are not the same
  target. A `lua51` payload was being handed `luajit` artifacts, which still
  spell `const` where the portable dialect writes `local`, and so did not parse.
  `nupp.tasks` reached a browser page that way, and `nupp.compiler.runtime.math`
  reaches an AOT one -- the latter only by a require that code generation emits,
  which no dependency walk sees, so a feature now says whether its runtime is
  portable and a portable target compiles the ones that are.

- A selected runtime provider is installed before the standard facilities that
  are built on it, rather than after. Nothing depended on the order until the
  run-time half of `nupp.math` started reading the `numeric.bitops` provider,
  which on a portable target was still unbound when it ran.

- Worker tasks run on a browser page. Everything the concept page describes was
  written and checked before anything had executed one; running the Chromium
  acceptance is what found the four faults between there and working, all of them
  about stock Lua 5.1 refusing to yield where LuaJIT allows it.

  The entry module ran inside `require`, which is a C function, so a browser
  application that reached workers could not suspend at all -- no sleep, no
  request, no awaited task. It is called where the payload runs now.

  A protected call is the same barrier, and a cleanup region runs its terminals
  inside one, which is how a scope drains. A portable target that can suspend now
  gets `pcall` and `xpcall` that run the body on a coroutine and pass through what
  it yields. Without it there was no way to observe a worker failure at all, which
  is half of what the structured-scope contract offers.

  The turn budget a task scope spends is answered by the browser suspension
  provider rather than missing from it.

- `nupp.tasks` on a browser page was reported as working when it had only been
  checked and built. It hangs: `tasks.run` parks on the host and never finds its
  children ready. `tasks.Scope:workers()` goes with it. The workers page says so
  now, and the backlog carries what is left.

- `nupp aot --emit asm` shows the instructions an `@aot` body compiled to. The
  generated C is compiled with the flags a build compiles that tier's
  translation unit with and stopped one step before the assembler encodes it, so
  the answer carries no addresses and needs no disassembler installed. Each
  symbol is headed by what it is -- the compiled body, the forced-scalar oracle
  it is differentially tested against, a Lua wrapper or registrar, a layout
  reporter, or a helper the C compiler declined to inline -- and by a count of
  the listing under it: total, vector, loads, stores, branches, calls, and
  instructions whose memory operand is the frame.

  `--function` names one body, and with `--features` that is a repeatable
  command for one function at one tier. The total is exact; the categories are a
  stated rule per architecture over the mnemonic and the operand shape, and
  scalar floating point is not counted as vector on either, since a loop that
  fell back to one element at a time is what a vector count is usually read to
  detect. There are rules for aarch64 and x86-64; another architecture is
  refused rather than reported with empty counts. `--json` carries the compiler
  that answered and the flags it was given, which is what says whether two runs
  are comparable.

- `nupp.tasks` works in a browser application. `tasks.run`, `tasks.runFor`,
  `scope:spawn`, `tasks.checkpoint()` and `tasks.Scope:workers()` are written
  there the way they are natively, so a page gets the fail-fast form of a worker
  scope: a deadline reaches a lane, and a running lane observes cancellation at
  its checkpoint. That was the last thing [](docs/concepts/workers.md) had to
  describe as absent.

- A record an exact provider module declares is one nominal wherever it is named.
  Naming it as a type resolved through the seam, and constructing one did not, so
  `new suspension.Handler(...)` reported that a `Handler` is not a `Handler` and
  `nupp.io.http`'s `Request` could not be named at all. Both readers now ask the
  same question: which module does the artifact actually require here.

- A warning against a declaration the compiler carries no longer discards it. The
  module became `unknown` at every use with nothing said, which is the failure the
  code's own note about strictness describes and only half escaped -- and is why
  `nupp.tasks` looked absent rather than lint-worthy.

- The browser suspension provider's `Installed` carries the affine terminal the
  native one does, so an installed handler stops being in force where its block
  ends. It is what `nupp.tasks` relies on to restore the previous handler when a
  child's body finishes, and without it the binding read as unused.
- `nupp.workers` runs in a browser application. The browser backend supplies
  `host.workers`, so `workers.scope()`, `scope:spawn`, `Task:await`, structured
  scope cleanup, cancellation, and the copy rule are all written the same way
  they are natively. A lane is a module Web Worker holding its own Lua 5.1 Wasm
  state, booted from the same verified package the page loaded and including its
  AOT side modules, so a compiled kernel runs on a lane as it does on the page.
  Work and results cross as copies through the ordinary browser effect framing.

  No Wasm threads and no `SharedArrayBuffer`, which is the point: a page serving
  the packaged assets needs no cross-origin isolation headers to get parallel CPU
  work. The packaging step ships the lane entry point beside the
  content-addressed runtime, and only where the application reached workers.

  Three observable differences follow from a browser giving two Workers no
  synchronous channel, and are why this is a second provider rather than a second
  transport under the native scheduler: a reply reaches the calling state when it
  next waits, a queued cancellation settles at the next wait rather than inside
  `Task:cancel`, and a lane reads a cancellation request at the cost of one turn
  of its event loop. [](docs/concepts/workers.md) says which.

- A module carried as runtime support no longer drags in the native
  implementation of a module a seam replaces. Linking propagated dependencies
  without the rule that the seam list already applies, so a project module that
  required both a seam-backed module and something else -- two levels down from
  the entry, which is why no single-file browser test had shown it -- compiled
  `nupp.time` or `nupp.workers` for a target that cannot run either.

- Subtyping terminates on a recursive type reached through two tables for one
  declaration. A scope whose `spawn` takes that scope asks the same subtype
  question inside its own answer; the pair under way is now assumed to hold,
  which is what makes an equirecursive comparison finish. Before, the compiler
  exhausted its stack.

- The `host.workers` seam names the module it replaces, so selecting a provider
  for it substitutes `nupp.workers` the way the other module seams substitute
  theirs. Its runtime check no longer asks for `ScopeToken`, which is an affine
  interface and has no runtime value for any provider to supply.

- `nupp.mem.sharedbytes` is classified as needing the storage capability rather
  than the `host.workers` seam. It shares the native host feature, but a `lua51`
  target reaching it needs engine-backed storage rather than whichever module
  implements worker lanes there.

- `nupp.data.json.isArray(value)` reports whether a value has JSON array
  shape, including a decoded empty array. Callers no longer have to compare a
  decoded table's metatable with the private marker carried by `EMPTY_ARRAY`.
  The `data.json` runtime seam is contract version 2.

- `nupp.data.valuebuilder.newFixedByteScratch(n)` is a byte buffer whose length
  is its capacity from creation: every byte readable and writable in any order,
  zero until written, no append protocol. The byte counterpart of
  `newFixedWordScratch`, and it buys one thing more. A word buffer small enough
  was already inline; a byte buffer's storage was `lua_newuserdata` on every
  call. `@aot` requires `n` to be a literal, so the storage becomes a C array at
  the call site and each access compares against that literal instead of loading
  a length.

  `nupp.data.digest` uses it for both of its buffers and its compiled entry now
  allocates nothing at all. A 32-byte digest goes from 291ns to 179ns against a
  control taking 178 -- 0.715x to 0.957x on the benchmark -- which is parity,
  and which closes the gap that two rounds of notes had blamed on the cost of
  entering compiled code. It was never that. Both costs are what an appending
  buffer is for: storage sized at run time has to be allocated, and a bound that
  moves has to be loaded. Neither was true of these buffers.

  Resetting a fixed buffer is refused on both routes, since a buffer with no
  fill state has none to discard. The IR version is 14.

- `nupp.data.sha256` assembles its own final block. `digest.sha256` used to
  build the remainder, the terminating bit, the padding and the length in bits
  as a Lua string and pass it to the compiled entry beside the message; the
  entry builds it in a byte buffer now and takes the message alone. That was
  five interned string allocations for every call and 60ns of a 320ns digest,
  and a 32-byte digest goes from 0.638x the hand-written C it replaced to
  0.738x. Longer messages are unchanged, which is what should happen.

  Two things came out of measuring it. The Lua/C boundary was not the cost: the
  same entry, with the same argument checks and the same result, returns in 17ns
  when the body does no hashing. And a fixed word buffer whose capacity is a
  literal now stands on the C stack rather than in userdata the registry keys
  and the Lua stack roots -- a buffer that cannot escape the entry has nothing
  for Lua to own.

- `bench/sha256` hashes different bytes on every call. It hashed one payload
  over and over, which makes everything an implementation derives from its
  argument loop-invariant, and LuaJIT hoisted the caller-side padding out of the
  timing loop entirely. The 32-byte row read 249ns where the same code hashing
  varying bytes took 312 -- a quarter fast, and blind to the largest single cost
  in the short call. The harness cycles through distinct payloads now, bounded
  to four megabytes of them.

- `unused-binding` answers for the file as written when an `@aot` policy links.
  A linking policy replaces each `@aot` declaration with the wrapper that calls
  the compiled code -- body and all -- and the module build checks that text, so
  every binding the removed body was the only reader of looked unread. A
  `bench/sha256` build reported twelve of them, `nupp.data.digest`'s round
  constants and all ten of its helpers among them, each pointing at a line still
  plainly using the name.

  The policy already checks the source as written, to lower it. That check's
  verdict on unread bindings is now carried to the module build and reported in
  place of the rewritten source's, so a binding nothing reads is still reported
  and one only the compiled body reads is not. An AOT build and `nupp check` now
  say the same thing about the same file.

- `nupp.data.valuebuilder.newFixedWordScratch(n)` is a word buffer whose length
  is its capacity from creation: every word readable, zero until written, no
  fill loop and no append protocol. Ordinary Lua sees the same buffer it always
  did. `@aot` requires `n` to be a literal, and emits each access with that
  bound as an immediate rather than as a load of the buffer's length.

  That is worth eleven points on `nupp.data.digest`, whose compiled entry goes
  from 0.849x the hand-written C it replaced to 0.963x -- 0.999x on a megabyte.
  The mechanism is not the one the earlier ablation implied. Deleting the
  bounds checks outright measured 0.919x and keeping them with a constant bound
  measured 0.940x, so the check was never the cost: the bound was, because a
  write through the buffer may alias the length field as far as the C compiler
  can tell, and it reloaded the bound after every store. Handed a constant, it
  discharges the comparison where it can follow the index and emits the branch
  where it cannot. The refusal is unchanged on both routes, and no range
  analysis was added to the Nupp compiler.

  The IR version is 13, since the bound reaches the emitter on each access.

- A `const` bound to a string literal is a byte table an `@aot` body can read,
  and the emitter places it in static C data. A table an author keeps in a
  packed string used to arrive as a Lua string the backend knew nothing about
  and reached with a `memcpy` from a pointer it could not align; it is a
  `static const unsigned char[]` now, whose contents and alignment the C
  compiler has. `nupp.data.digest`'s round constants are one, which took its
  compiled entry from about 0.80x the C it replaced to 0.849x.

  A read spells a constant table exactly as it spells a rooted argument, which
  is why nothing between the source and the emitted load had to learn about
  them. The IR version is 12, since the tables reach the emitter on the program.

- There is no SHA-256 in C any more. The playground's Wasm host carried one for
  a single call -- checking the compiler bundle it fetches against a digest
  compiled into itself -- and that check is now `crypto.subtle` in
  `src/wasm-runtime.js`, where the bytes already are. It is no weaker for
  moving: the caller is what decides which bytes reach the host at all. Nothing
  else was left. `nupp.data.sha256` is Nupp, the stamped binary's trailer is
  XXH64, and the implementation that used to be `nupp.data.sha256` is now a
  frozen control in `bench/sha256`, beside the Lua one it also replaced.

- A stamped binary's trailer digest is XXH64. That check runs on every
  invocation over the whole payload, and the compiler's own binary carries
  about ten megabytes of one, so a cryptographic digest was twenty-five
  milliseconds added to every command against a tool whose design goal is that
  an unchanged project answers in about the time it takes to start. It is now
  under one. Nothing is given up: the file is unsigned and only eight bytes are
  recorded, so anyone who can rewrite the payload can rewrite the trailer
  beside it, and the reference has always said the field is a corruption check
  rather than a security boundary.

- SHA-256 is Nupp. `nupp.data.sha256` was a call into the native provider's C;
  it is now [`nupp.data.digest`](src/nupp/data/digest.nupp), an `@aot` entry
  that a target with a `require` policy compiles ahead of time and that runs on
  LuaJIT where a target does not. The build's own trailer digest is the same
  module rather than a second implementation beside it, and the playground's
  Wasm host no longer carries a third, vendored one. What remains in C is
  `runtime/native/c/sha256.c`, which exists for the two payload checks that run
  before the payload they are checking can be trusted to run: a stamped binary's
  trailer, and the playground's compiler bundle. Neither can call into the
  program it has not yet decided to admit. `sha256` is therefore no longer a
  forceable native feature name; the effect it records keeps its identifier,
  because that is what stamped artifacts already carry. `bench/sha256` measures
  the compiled entry at about four fifths of the C it replaced across payloads
  from a kilobyte to a megabyte, holds four implementations against each other
  on every length to two hundred bytes and on every padding boundary, and
  records what the uncompiled route still costs.

- A bitwise operator keeps the width its operands carried. `a & b` on two
  `int32` used to come back as an unestablished `integer`, so every use had to
  launder it through `nupp.math.i32.wrap` -- which takes a binary64, so the
  emitted C promoted a thirty-two bit pattern out to `double` and cast it back,
  and a value at or above 2^31 did not survive the return trip. The operators
  are BitOp's and their results are thirty-two bit patterns; the AOT backend
  already typed its IR node that way, so the fact was going missing rather than
  being unavailable. Answered only where both operands already carry a width,
  which is the condition the backend puts on them. Two lowering rules follow:
  an exact literal in range reaches a fixed-width parameter as a constant of
  that width, and a comparison narrows a constant to the other side's width, so
  a counted loop stops converting its cursor to floating point once an
  iteration to compare two integers.

- The fixed-width members lower to inline BitOp rather than to a call through
  the installed `nupp.math`. LuaJIT records a `bit` primitive as one IR
  instruction where it has to record a Lua call as the whole inlined body, so a
  body built out of hundreds of them -- a digest, a checksum, a bit-twiddling
  parser -- could exceed what the trace recorder will unroll and run
  interpreted whatever its policy. `nupp.data.digest` was two orders of
  magnitude off its own compiled entry for that reason and is now a fifth of
  it, which is also 6.3x the implementation it replaced. Portable and
  compatibility dialects keep the call, since their `numeric.bitops` seam is
  what supplies the primitives.

- The unsigned 32-bit normalisation is `% 2^32` rather than a comparison
  against zero. It is the same function -- Lua's `%` is floor-modulo -- without
  the branch, which cost about six times as much wherever a value's sign varied
  and so the predictor had nothing to go on, which is every bit-twiddling loop.
  Reading its subject once is also what lets code generation inline the
  unsigned members at all.

- `@aot` wraps modulo 2^32, as `i32.wrap` and `u32.wrap` are defined to. Both
  lowered to a plain C cast from `double`, which is undefined outside the
  destination's range and saturates on arm64, so every value at or above 2^31
  came back as INT32_MAX and a compiled body disagreed with the same source on
  the interpreter over exactly the values a wrap exists for.

- `@aot` admits `nupp.math.i32.fromU32` and `nupp.math.u32.toI32`, the two
  reinterpretations between the signed and unsigned views of one thirty-two bit
  pattern. Reaching them through `wrap` instead converts out to binary64 and
  back for bits that never left thirty-two.

- `nupp.io.net` is the fourth byte transport, beside the filesystem, a child's
  streams and an HTTP response body. A listener, the connections it accepts, and
  connections a program opens itself, all reading and writing through the
  `Reader` and `Writer` contracts every other byte source already uses, so a
  parser reads a socket without knowing it has one. A read answers bytes, parks
  while none have arrived, or answers empty because the peer closed its sending
  half; empty is only ever the end, which is what keeps a quiet connection from
  ending a parser on the first lull between segments. `shutdownWrite` is the
  half-close a graceful drain is built from, the send queue has an authored
  maximum the transport enforces rather than an option a caller may forget, and
  `net.asReader` and `net.asWriter` hand out borrowed direction views whose close
  ends a direction rather than the connection. The reactor is one per lane, which
  is what `uv_accept` requires and what keeps a listener off another lane's loop.
  Datagrams are the other half: a receive is one message into storage the caller
  named, answering how many bytes landed, which peer sent them, and whether the
  datagram was larger than the storage offered. Truncation is reported rather
  than dropped quietly, because a protocol that parses the first part of a
  message nobody sent has a security bug and not a lost packet, and an empty
  datagram is a message rather than an absence, because several protocols use
  them as keepalives. A connect carries a deadline, thirty seconds by default
  and not disableable, since a connect that waits forever is a hang somebody
  eventually reports as a bug. Unix domain sockets are the same transport under a
  filesystem name: `listen` and `connect` take a `path` instead of a host and
  port, and naming both is refused where it is written. A connection answers
  `peerAddress` and `localAddress`, which is what a server needs to log, rate
  limit or refuse anybody and cannot infer from a listener. `setNoDelay` turns
  Nagle off, since the kernel's default holds a small reply for tens of
  milliseconds waiting for more to send, and `setKeepAlive` asks it to notice a
  peer that vanished without closing. A datagram socket takes the multicast
  options a discovery protocol needs: `setBroadcast`, `setMulticastTTL`,
  `setMulticastLoop`, and joining or leaving a group on a named interface.

- `nupp.io.newLines` takes a reader apart into lines, over anything that reads
  bytes rather than over sockets in particular. Both `\n` and `\r\n` end one and
  neither is part of it, bytes left after the last terminator are still a line,
  and a line longer than an authored limit is refused rather than buffered,
  because a line that never ends is how a peer takes the process down. It takes
  its source rather than borrowing one: reading a line means reading past its
  end, so two readers over the same source would each see half of it.

- A connection stops asking the platform for more once a mebibyte is received
  and unread, and asks again once it has been taken. Without that bound a peer
  that sends faster than the program reads chooses how much of this process's
  memory to spend; with it, the kernel's own window closes behind the pause and
  the backpressure reaches the sender. `flush` waits until nothing accepted is
  still held here, because closing cancels queued writes and a caller that
  writes, flushes and closes would otherwise lose them, and it reports a write
  that failed after being accepted rather than reading an empty queue as
  success. A borrowed writer flushes the same queue, and both `shutdownWrite`
  and closing a writing view wait for the direction to end rather than only
  submitting it. A connect that resolves
  to several addresses tries the next when one fails, so a host whose first
  answer is unreachable still connects, and a name that resolves after its
  deadline has passed is not connected to at all.

- `nupp.io.tls` encrypts a connection `nupp.io.net` already opened. A session
  borrows the connection rather than owning it, so one socket stays under one
  cleanup obligation, and reads and writes through the same `Reader` and
  `Writer` contracts a plain connection does. Verification is on unless a caller
  turns it off, and a verifying client must name the peer, because a certificate
  checked against no name is a certificate belonging to anybody and the failure
  is silent. A session ends with `close_notify` and a connection ends with a
  half-close, kept apart so a stream cut off in transit cannot be mistaken for
  one that finished. It is a module beside the socket one rather than a flag
  inside it, so a program that opens sockets and does not encrypt them carries
  no mbedTLS. Both sides may name application protocols and `protocol` answers
  what was agreed: the server picks, so a client naming `h2` first still gets
  `http/1.1` from a server that prefers it, and a server sharing none of the
  client's refuses the handshake rather than serving something the client
  cannot read.

- Remove the redundant `nupp.extensions` and `nupp.managed` compatibility
  modules. Their complete surfaces already live at `nupp.reflect.ExtensionKey`,
  `nupp.reflect.extensionKey`, `nupp.ManagedGroup`, and `nupp.managedGroup`.
  File the two stock backend descriptors with the other backends as
  `nupp.runtime.backend.portable` and `nupp.runtime.backend.wasm`.

- A type function takes a pack: `F(C...)` beside the `Q<C...>` a generic
  application already took. A comptime function may be declared to take a
  `typepack` and had no way to be given a binder, so the sequence a caller had
  in hand could not reach the algorithm meant to read it. With `elements` and
  `arguments` this is enough to derive one side of a call from the other:
  components named as values, and the function given them checked against what
  they hold.

- `nupp.types` reads back what it can already build. `elements` takes a pack
  apart as it does a composite type, giving its fixed head, and `arguments`
  answers with whatever a generic declaration was applied to. A comptime
  function could construct a pack and pass one along, but not look inside one it
  was handed, so a type algorithm over a sequence had nowhere to start.

- A computed parameter tail types the callback it is written on. `...: unpackof
  F(T)` expanded where a value was passed to it and nowhere else, so a callback
  parameter carrying one read as an untyped vararg: an argument written without
  types took `any`, and a function with the wrong parameters, or five of them,
  satisfied the slot silently. It now expands wherever the signature is read,
  which is what the same parameter list written out already meant.

- Scaffold a library with `nupp init lib` rather than `nupp rock init`. That
  command was `nupp rock`'s own copy of the layout from before templates
  existed, and has been scaffolding the built-in `lib` template since they
  arrived; what goes is the second spelling of one thing, and with it the
  `absent` destination policy `nupp.compiler.template` carried for the sake of
  a published refusal `nupp init` never made. `nupp rock` is `pack` and `test`,
  the two things LuaRocks needs a Nupp-aware step for, and `rock init` says
  where scaffolding went rather than reporting an unknown operation.

- Restore the path parity suite. `nupp.io.path`'s recorded answers lived in the
  provider crate's own tests, and went with the crate; `tests/pathtest.lua` is
  that table, reached the way a program reaches the module. It pins the
  distinction the facility rests on: a path that is rebuilt is normalized, and
  one that is sliced keeps the spelling the caller wrote.

- Parse URIs with [ada](https://github.com/ada-url/ada) rather than by hand. It
  is the WHATWG parser Node.js uses and the model `nupp.io.uri` documents, and
  checked against the table recorded from the implementation it replaces it
  agrees on every one of seventeen URIs and eleven components each, refuses the
  same six malformed inputs, and answers identically to every derivation,
  resolution and rerooting. 1123 lines of hand-written parsing leave the tree.
  Why a URI is invalid is still answered here, because ada reports only that one
  is. Ada needs C++20, so the documented C++ floor moves from C++17.

- Reimplement the binary host in C, and remove Cargo from the tree. Locating and
  verifying the payload, starting LuaJIT, the component and handle lifecycle,
  the embedding ABI in `host/include/nupp.h`, worker states and bounded byte
  channels are `host/c`; `scripts/toolchain` builds them, feature by feature,
  and builds the native provider the same way. `runtime/native/Cargo.toml`,
  `host/Cargo.toml` and both crates are gone, and with them the transitional
  Rust names the C entry points forwarded through.

  A checkout now asks for a C and a C++ compiler and nothing else. LuaJIT, LPeg,
  luautf8, simdjson, libcurl and mbedTLS are fetched from pinned sources,
  verified against a digest, and built by the same driver. This completes
  [NEP 17](docs/neps/0017-c-only-toolchain.md).

- Reimplement the HTTP transport on libcurl. Tokio, reqwest and rustls are
  replaced by a pinned libcurl over a pinned mbedTLS, both built by
  `scripts/toolchain` from sources verified against a digest. One client owns one
  multi handle and one thread to drive it, so two runtimes embedded in one host
  do not share each other's limits, proxy or cancellation. That thread is the
  only one that speaks to libcurl: pausing, resuming and cancelling are notes
  left under a lock and read by the reactor, because `curl_easy_pause` on a
  handle another thread is inside is not a call to make. `runtime/native` now
  has no Rust dependencies at all.

- Serialize spawning where the platform has no `pipe2`. Between `pipe` and the
  `fcntl` that marks its ends close-on-exec, the descriptors are inheritable,
  and a fork in that instant hands them to a child that did not ask for them --
  after which the reader of that pipe never sees end of stream. What it looks
  like is a command that finished and never returned.

- Install the development native library by renaming rather than by writing over
  it. `bin/nupp` copied it into place, which leaves a window in which the file
  is half a shared library -- and the loader does not report that as a bad file:
  on macOS the kernel refuses the image and kills the process, some way from the
  cause. Rebuilding it whenever its sources change made that window reachable in
  ordinary use.

- Reimplement child processes in C. Spawning, the nonblocking pipes to and from
  a child, the readiness wait and the exit accounting move to
  `runtime/native/c/process.c` and the two platform files under it. The POSIX
  half keeps what the Rust one had got right and says so in the same places: the
  `SIGPIPE` block-inspect-write-consume-restore sequence, close-on-exec on both
  ends of every pipe, and stderr joined to stdout as one pipe handed to the
  child twice rather than two streams merged afterwards. The Windows half uses
  uniquely named overlapped pipes, because an anonymous pipe cannot be read
  without blocking and has nothing a readiness wait can wait on. `libc` and
  `windows-sys` leave the dependency list.

- Reimplement URI parsing in C. A URI is held as one normalized serialization
  plus the offsets of its parts, so reading a component slices storage the
  handle already owns; deriving one takes the parts apart, replaces the one that
  changed, writes the result out and parses it again, so one grammar decides
  what is valid. `tests/uritest.lua` records the answers -- every component of
  seventeen URIs, six malformed ones and their reasons, and every derivation,
  concatenation, resolution and rerooting -- against the implementation this
  replaces. The `url` crate leaves the dependency list for everything but the
  HTTP transport, which still parses the handle's own text until it too is
  ported.

- Reimplement paths, SHA-256 and the UUID generators in C. `nupp.io.path` reads
  a path as components rather than by string arithmetic, and answers what it
  answered before down to the spelling: a path rebuilt is normalised, one sliced
  keeps the `.` the caller wrote. The digest is FIPS 180-4 directly and the two
  identifier versions are the same random bytes with different stamps. Five more
  crates -- `camino`, `path-clean`, `pathdiff`, `sha2` and `uuid` -- leave the
  dependency list.

- Rebuild the development native library when its sources change. `bin/nupp`
  built it once and then never again, so an edit to a provider was picked up by
  whoever next deleted the library by hand and every command in between ran
  against the one before it.

- Reimplement the file provider in C. `nupp.io.files` stands on
  `runtime/native/c` rather than on the Rust crate: metadata, listing, globbing,
  the open-file handles and the off-thread transfer lane, with the platform
  halves in `platform_posix.c` and `platform_windows.c` rather than one file
  with the differences threaded through it. The ABI is unchanged, so nothing
  above it moved. This is the first facility ported under
  [NEP 17](docs/neps/0017-c-only-toolchain.md); the rest of the provider and the
  binary host are still Rust.

- Provision LuaJIT, LPeg, luautf8 and simdjson from pinned sources rather than
  expecting them installed. `scripts/toolchain` fetches each by revision,
  refuses any archive whose SHA-256 is not the one written down, builds it with
  `NUPP_CC` and `NUPP_CXX`, and caches the result beside the repository so every
  worktree shares one build. `bin/nupp` uses the interpreter on `PATH` when it
  clears the syntax floor and builds the pinned one when it does not, putting it
  on `PATH` so the comptime workers, the LSP relay and the test runner all reach
  the same one; the JSON runtime links what pkg-config reports and falls back to
  the staged simdjson where it reports nothing. A checkout's requirement is now
  a C and a C++ compiler, plus a Rust toolchain until the native providers and
  the binary host are ported.

- Add schema-driven serde for records, fixed-layout structs, and run-time
  dynamic values. `@derive(nupp.derive.Serde)` produces one format-neutral
  schema and binding; prepared JSON profiles cache encoded keys and raw-byte
  lookup, traverse flat scalar structures in one native call, and reuse
  per-thread encoder and decoder scratch. Dynamic bindings resolve names once
  into checked dense slots, and typed extensions now provide the shared lazy
  cache boundary for reflection descriptors, schemas, and bindings. Prepared
  writes reserve caller-owned buffer storage and avoid allocating and copying a
  complete intermediate Lua string.

- Publish the documentation site by convention rather than by inventory. A page
  entry names a `glob`, and every Markdown file it matches is published at the
  route its path gives, under the title its heading gives; what a path cannot
  say -- where the page sits in the navigation, the name navigation should use
  instead, the routes it used to answer at -- the page says in its own front
  matter. The manifest had listed all 71 pages as a route, a title, and a source
  that were the same fact written three times, which the tree already held and
  which failed silently the first time a page was written and not listed. The
  home page's hero and feature showcase move the same way, from three hundred
  lines of Lua tables holding Markdown into the Markdown page itself, between
  comment markers. `nupp.lua` is a third of its former size.

- Move the standard library's documentation into the modules themselves. Twelve
  pages under `docs/modules/` said what a module is, next to none of the source
  that says what it does, so a change to one had to remember the other. Each is
  now that module's blurb: `nupp.data.json` in `src/nupp/data/json.nupp`,
  `nupp.math` and `nupp.peg` in the prelude declarations that describe them. A
  blurb renders as a module page's own prose, its headings join the page
  outline, and a reference to a module may carry an anchor into it, as
  `[](nupp.mem.span#writable-spans)`.

- Add the explicit `nupp.Closeable` lifecycle, inherent affine construction, and
  `managed(T)` cells with checked copyable `alias(T)` references. Replace the
  compiler-privileged `nupp.owners` Set/Store protocol with ordinary
  `nupp.ManagedGroup` library code, permanent cell tombstones, and managed
  policy checks during hot reload. HTTP clients now use the same `nupp.Closeable`
  lifecycle.

- Write incremental and derived JSON through one checked, buffer-backed writer.
  `EncodedValue` and the interned `EncodedString` retain bytes encoded or
  verified once, letting `write` and `key` append them without another walk,
  validation, escape pass, or intermediate string. Derived schemas lazily cache
  encoded field names and literals; `encodeAs` and `encodeRecord` remain
  explicit allocating conveniences. The Writer is `nupp.Closeable`, batches commits,
  names container endings explicitly, and pools only native backing state after
  its consuming `close()`.

- Let a loop compile around an owned binding whose protected body reads or
  writes an enclosing local. A capture stable for one function call keeps one
  guarded region closure in that invocation; a local recreated by an enclosing
  loop travels through a frame passed to the module-cached closure, with writes
  copied back before cleanup and structured-exit dispatch. Recursive calls keep
  independent upvalues, and per-iteration resources remain per-iteration.

- Put the design rationale where the question occurs. A `::: rationale` block
  renders collapsed, holds two to four sentences on why the construct on that
  page is shaped the way it is, and links to the proposal holding the full
  record. Fifteen pages had no signal that a design record existed at all. It
  carries the current design only: a rejected alternative, a superseded
  spelling, or a withdrawn attempt has no page to sit on and is rewritten away
  when behaviour changes, which is why proposals are separate files.

- Cut the enhancement proposals to eleven architecture documents. The port
  produced one proposal per decision, which is one per sub-feature: forty-three
  documents, several of them re-documenting the type system, the standard
  library, or the command-line tools that already have pages of their own. A proposal is now a broad
  architectural slice -- ownership, suspension, comptime, modules, C interop,
  ahead-of-time compilation -- and each shows the syntax, a usage example, and
  what the construct lowers to, rather than describing it. More granular ones
  can arrive when contributors write them.

- Publish the design record on the site as Nupp Enhancement Proposals. `plans/`
  held 71 dated files outside the documentation, and their statuses had stopped
  being true: two described `Owned<T, cleanup>` and `@drop` as implemented after
  both were removed, two disagreed with each other about whether a pluck is
  written with parentheses or braces, and one carried two status lines. They are
  now 42 numbered proposals under `docs/neps/`, ordered so each builds on the
  ones before it, and a proposal records why a design was chosen rather than what
  the compiler does -- reasoning about a decision made on a date stays true after
  the code moves, which is the property that made the old files worth keeping and
  the descriptions in them worth deleting. Three that never built anything are
  kept as the alternatives sections of the designs that replaced them, because
  the module design looks arbitrary without the four attempts before it. The
  backlog that was living in there is `TODO.md`, and the four diagnostic anchors
  that pointed into `plans/` now point at proposals, so `nupp explain` renders
  them as links rather than as repository paths.

- Publish a directory of markdown as one documentation section. A page entry in
  the manifest may name a `directory` instead of a `source`, and then stands for
  every document under it plus an index generated at its own route from their
  frontmatter. Listing each document instead fails silently -- the file is
  written, the site shows one fewer than the repository holds, and nothing
  reports a problem.

- Let a reader take the part of the reference they need. `nupp reference` had
  three slices -- `language`, `cli`, `performance` -- and the first is over
  thirteen thousand words, so a question about one construct cost the whole
  chapter. `--section NAME` prints one section, a few hundred words, named by
  its heading or by any `docs` pointer at it, so the anchor every diagnostic
  already carries is a thing that can be followed rather than only cited.
  `--for CODE` goes the other way and prints whichever sections explain a
  diagnostic, which is what a reader holding one actually has. Bare `nupp
  reference` now lists every section, because the alternative to naming the
  slices is guessing at them: agents in the evaluation harness ran `nupp
  reference types`, `nupp reference syntax` and `nupp reference
  docs/modules.md`, all of which failed, and then loaded the whole chapter
  instead. `types` and `modules` are real names now.

- Say whether `nupp check --json` actually checked anything. An empty
  `diagnostics` meant two different things -- a project with nothing wrong,
  and a run that never reached a file because it could not use the manifest --
  and nothing in the payload told them apart, so a reader consuming the JSON
  and not the exit status read a configuration failure as a clean bill of
  health. `ok` is now beside `diagnostics`, false in both failing cases, which
  is what `nupp build --json` has always reported for the same reason. Found by
  the agent evaluation harness, whose first task workspace was misconfigured
  in exactly that way and reported clean.

- Give `nupp explain` a worked example for every diagnostic code the compiler
  can actually emit that one is reachable for. 60 of the 149 codes used to
  fall back to their family's generic paragraph -- summary, rule and all --
  which reads as an answer without being one; `NUPP2105`, an unknown-variable
  typo, was one of them. Each new entry's `wrong` example is compiled for
  real and asserted to report the code it is filed under, the same as every
  existing entry; two lint codes and two codegen codes are demonstrated too,
  by triggering the underlying checker/generator gap rather than inventing a
  program that only looks like it should. A handful of codes -- a reserved
  annotation nothing currently reserves, a formatter safety net with no known
  input that trips it, hot reload's own restart notice, and two whole-project
  name collisions no single file can exhibit -- keep the family's rule text
  under their own summary but carry no example, since a wrong example that
  cannot be verified is worse than the fallback it would replace.

- Report `nupp check --json`'s cache accounting the same way `nupp build
  --json` already does. AGENTS.md has long said a slow check is worth reading
  rather than waiting out, but nothing in `check`'s own output said what a
  given run actually redid -- the accounting was already computed for every
  check, `nupp build --json`'s `timing` object having published it for a
  build all along, and `check` silently discarded it before it reached
  `--json`. `compiledModules = 0` is now the answer to trust that a slow
  check redid nothing; `slowest` ranks modules by wall-clock time spent
  either way, since confirming a cache entry is still valid costs time too,
  just less of it.

- Remind the next worktree about the last one. `scripts/worktree` now lists
  any other registered worktree whose branch already merged into `HEAD`,
  right after creating the one just asked for. AGENTS.md has always asked
  that a finished worktree be removed, but nothing noticed when it was not;
  two accumulated silently in this checkout before this was written. The
  check is best effort and never fails the worktree it is only polishing.

- Hold hot reload to the strict floor. `src/nupp/hotreload.g.nupp` and
  `src/nupp/compiler/hot_session.g.nupp` were the only two files under `src` that
  opted out of it, which put the machinery deciding whether an edit may reach a
  running program outside the checking every other part of the compiler gets.
  Both are `.nupp` now. `nupp.HotReload.poll` answers `nupp.HotReloadPoll`
  instead of `any`, and its docblock says which of the four `kind` values carries
  which fields, so a host branches on a documented answer. The compiler side
  gains the `Prepared | Rejected | Restart | Unchanged` result it was specified
  to have, plus the `Session`, `InitialBuild` and watched-input types. The slot
  vectors, the loaded patch chunk and the module manifests stay `any`, which is
  what they are: generated code writes them, generated code reads them, and their
  shape is not this module's to claim.

- Replace lua-cjson with Nupp's simdjson-backed JSON runtime. The public
  `nupp.data.json` surface now has eager `decode`, On-Demand `pull`, strict
  `encode`/`serialize`, and an incremental writer. Null is dropped by default
  or preserved with a caller-provided value; `NULL`, `EMPTY_ARRAY`, and
  `EMPTY_OBJECT` cover the values plain Lua cannot distinguish, while
  `asArray` and `asObject` make container intent explicit. The compiler,
  sidecar builds, and self-contained host all use the same codec and policy.
- Check every entry of a table constructor, not only the ones before its first
  computed key. A `[k] = v` entry settles what the constructor's type is -- a
  generic table -- and the checker answered with that type as soon as it saw
  one, which left every entry past it unvisited. So a mistake in one went
  unreported, and a `new R(field = value)` standing after one reached the
  generator with nothing resolved: a construction lowers from the fields the
  checker bound rather than from the arguments as written, so it was written
  out as the call it was spelled as, and `{["a"] = new R(f = 1), ["b"] = new
  R(f = 2)}` failed to compile with NUPP3005. Positional construction past a
  computed key had the quieter version of the same fault -- it generated Lua
  that parsed and called the record's own table at run time.
- Create a project from a template with `nupp init`. A template is a directory
  tree with one `template.lua` at its root, and the same format serves a
  built-in, a directory named with `--from`, and a repository spelled
  `owner/repo`, optionally with a path within it and `@rev`. `${name}` is
  replaced in file contents and in path components, so `src/${moduleName}.nupp`
  becomes a file named for the project. The built-in `app` and `lib` travel
  inside the compiler, so `nupp init` answers with no network and no checkout,
  and `nupp rock init` now scaffolds `lib` rather than carrying its own copy of
  the same five files.
- Run nothing a fetched template supplied. `template.lua` is read in a sandbox
  with no `io`, `os`, `require` or `load` in it, and a repository template's
  post-init steps are reduced to `git init`, because `check`, `build` and
  `test` all load the scaffolded `nupp.lua` and a manifest is ordinary
  unrestricted Lua. A repository template also names the commit it resolved to
  and is confirmed before anything is written; a run with nothing at the
  terminal to answer is refused rather than assumed.
- Let a loop compile around an owned binding whose body calls something. The
  cached region function is written where it stands and only its instance is
  kept for the module, so a name the chunk's outermost block declares -- which
  is every module-level function -- can be captured and reused. Only a name
  belonging to an enclosing function, block, or loop, including a chunk-level
  loop variable, still costs the region a function per entry.
- Spread an argument list one argument per line whenever it stops fitting on
  one, whether by width, by a comment inside it, or by an argument whose own
  body is a block. A call's trailing function or table still hugs the line that
  opens the call while what precedes its body fits there, and a table
  constructor spreads on the same terms.
- Keep a shape type of one field on the line that names it, so
  `headers: {string: string}?` stays as written and breaks only on width. A
  shape of several fields is still a list of them, one per line however short.
- Keep the space in `borrows (p)` and a closure's `takes (a, b)`, leave a bare
  `;` on the line of the statement it terminates, indent a comment that is the
  whole of an `if` arm inside that arm, and stop a docblock's trailing
  annotation from taking the blank line owed to the declaration below it.
- Say when a closure that reads its iteration costs a loop its trace. The new
  `jit-loop-closure` lint (`NUPP2515`) is off until a project asks for it,
  since the code it reports is correct and has no mechanical fix, but a
  function annotated `@jit` promised that it compiles and reports the same
  hazard as `NUPP2707` whatever level the lint is at.
- Read each workspace folder under its own `nupp.lua`, so a file is checked the
  same way whichever window opened it. Every folder gets its own incremental
  graph, built when something first asks that folder a question and reading the
  editor's open buffers along with the rest; `$/nupp/inspect` and
  `workspace/symbol` say which folder answered.
- Stop language-server work when the request it belongs to is cancelled, at
  every module and file header on the way to the answer, and answer
  `ContentModified` rather than sending positions the client has already typed
  past. Published diagnostics name the document version they were found in.
- Say what a build is doing while it runs, and where its wall-clock time went
  and which modules cost the most when it ends. Reported to a terminal only;
  `--progress`, `-q` and `NUPP_PROGRESS` say otherwise, and `build --json`
  carries the same numbers in a `timing` object.
- Type `ffi.C` from a C function this process had already declared, which an
  ordering accident between the compiler's own code and the file it is
  checking could previously empty.
- Add deterministic target-aware C header export and typed ordinary-struct
  pointer interoperation through `nupp export-c`.
- Add explicit allocation-free `nupp.math.i32`, `u32`, and IEEE-754 binary32
  scalar operations.
- Add affine writable span slices, allocation-free checked common ranges, and
  ownership-qualified typed variadic parameters.
- Add `noalloc do` and `noraise do` regions with observed cross-module
  guarantees and cleanup-aware effect inference.
- Increase the single isolated comptime-worker deadline to 10 seconds so
  bounded evaluation includes compiler startup under parallel build load.
