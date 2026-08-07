# Distribution: stubs and payloads

How a Nupp program becomes one file somebody can run.

A distributed program is a **stub** with a **payload** appended to it. The stub
is an ordinary executable — a host that embeds LuaJIT and knows how to find and
run a payload. The payload is one Lua chunk carrying everything the program
needs. Making a binary is copying a stub, appending a payload, and writing a
trailer that says where the payload starts.

Nothing about that is specific to Nupp's own compiler, and that is the point.
Nupp is the first stub, not the only one: an engine or framework can publish its
own host — one that opens a window, or owns an event loop — and Nupp will stamp
programs into it without knowing what it is.

## Why the contract is written before the code

Everything else here can be revised. This cannot: once somebody publishes a stub
built against it, the format is load-bearing in a repository nobody here
controls. So it is specified first, and the first two consumers are both ours —
the trivial test host and Nupp itself — before any third party is invited.

## The container

The payload is **appended to the end of the stub file**, followed by a fixed
trailer. Not a platform section: an ELF section, a Mach-O segment and a PE
resource are three formats and three writers, and appending is one that works on
all of them and on a platform nobody has thought of yet.

What appending costs is code signatures. Adding bytes to a signed Mach-O
invalidates it, and macOS on arm64 refuses to run an executable whose signature
does not verify, so the emitter re-signs after appending. That is a real step,
not an afterthought — see "Signing" below.

    ┌──────────────────────┐
    │ stub executable      │  an ordinary ELF / Mach-O / PE
    ├──────────────────────┤
    │ payload              │  one Lua chunk, see below
    ├──────────────────────┤
    │ trailer (48 bytes)   │  fixed size, at the very end of the file
    └──────────────────────┘

### The trailer

48 bytes, little-endian, at the end of the file. A stub reads the last 48 bytes,
checks the magic, and knows the rest without searching.

     offset  size  field
     ──────  ────  ─────────────────────────────────────────────────────
     0       8     magic, the ASCII bytes "NUPPLOAD"
     8       4     format version, currently 1
     12      4     reserved, zero
     16      8     payload offset from the start of the file
     24      8     payload length in bytes
     32      8     first 8 bytes of the payload's SHA-256
     40      8     trailer length, currently 48

The magic is last-resort identification, not a search key: a stub that finds no
magic has no payload and says so, and one that finds a version it does not know
refuses rather than guessing. The truncated digest is a corruption check, not a
security boundary — a stub that wanted integrity guarantees would need a
signature over the payload, and appending one is a version-2 question.

Reserved bytes are zero and are checked to be zero, so a later version can use
them and an older stub will refuse rather than misread.

## The payload

One Lua chunk, exactly as `nupp build` with a `bundle` target produces it. It is
plain Lua and runs under a plain `luajit` with no stub at all, which is what
makes it testable on its own.

"Plain" has a floor. Generated Nupp is written in the LuaJIT 3.0 syntax that
2.1 backported — `?.`, `??`, `?:`, the bit operators, compound assignment —
rather than in a lowering of it, so a payload needs LuaJIT 2.1.1784535649 or
newer. A stub is therefore not free to embed whichever LuaJIT its build system
had lying around: `host/build.rs` pins one by revision and digest, and the pin
is a requirement rather than a preference.

Its shape:

```lua
package.preload["some.module"] = function(...) --[[ compiled module ]] end
-- ...one per module in the program...
package.preload["nupp.embedded"] = function()
    return {["/some/resource.txt"] = [==[ ... ]==]}
end
-- the entry module's code, last, as the chunk's own body
```

Resources ride in `package.preload["nupp.embedded"]` as a table of path to
content. That is the same mechanism the compiler uses to carry its own standard
library declarations, so a program's resources and the compiler's behave
identically and are read through one lookup.

The payload is **deterministic**: modules and resources are emitted in sorted
order, and nothing records a timestamp, a path from the building machine, or a
build counter. Two builds of one tree produce byte-identical payloads. This is
not tidiness — the packaging fixpoint below depends on it.

## What a stub must do

1. Locate its own executable. Not `arg[0]`, which is whatever the caller typed:
   `/proc/self/exe`, `_NSGetExecutablePath`, `GetModuleFileNameW`.
2. Read the last 48 bytes. No magic, or a version it does not know: report that
   plainly and exit non-zero. Do not fall back to guessing.
3. Verify the payload's length and truncated digest.
4. Load the payload as a Lua chunk, named so tracebacks are readable.
5. Set `arg` from the command line, dropping nothing the program should see.
6. Run it. The program's exit status is the process's.

A stub with **no** payload is a plain interpreter: it runs the file named as its
first argument. That is what makes a stub testable before anything is stamped
into it, and what makes `nupp` itself usable during development.

Everything else a stub does is its own business. A game engine's stub may open a
window and own an event loop before step 6; Nupp's own does none of that.

## Signing, and what macOS does about it

**The signature is not touched, and on macOS that is the whole trick.**

A stub arrives ad-hoc signed from its linker, and the signature covers the image
up to a recorded *code limit*. Bytes appended past that limit are simply outside
what was signed, and the kernel loads the image regardless. This was measured,
along with both of the things that do not work:

     What the emitter does           Result on macOS arm64
     ──────────────────────────────  ─────────────────────────────────────
     append, leave the signature     runs
     strip signature, append         Killed: 9 before main runs
     append, then re-sign            codesign: main executable failed
                                     strict validation
     strip, append, then sign        the same refusal

Apple's `codesign` will not accept a Mach-O with anything after its signature —
its parser rejects bytes past everything the load commands describe. And unsigned
is not a fallback, because arm64 kills an unsigned executable outright. Doing
nothing is what works.

     Platform  State
     ────────  ─────────────────────────────────────────────────────────
     macOS     works; the stub's own signature is left alone
     Linux     works; nothing to sign
     Windows   expected to work; Authenticode only if distributing

### What this costs

`codesign --verify` reports strict validation failure on the result, and with it
notarization. That is fine for a binary you run, and not fine for one handed to
somebody else's Mac, where Gatekeeper will refuse it. Distributing to other
people needs a signer that signs *over* the payload rather than around it:
nothing in the format requires the code limit to stop where the load commands
do, and a third-party implementation can set it to cover everything. Apple's
tool will not.

That signer is the same component cross-building needs, which is worth noticing.
Linking a Mach-O off-platform is impossible — the Apple SDK is not
redistributable — but *appending to one already linked* needs no SDK at all.
Once signing is ours rather than Apple's, a Linux machine can produce a runnable,
distributable macOS binary. Fetching a prebuilt stub is what turns
cross-compilation from a licensing problem into a download.

## The packaging fixpoint

The compiler proves it can compile itself, byte for byte, on every change. The
packager proves the same thing about itself: a Nupp binary, run, stamps out a
Nupp binary identical to itself.

That is the acceptance test for everything above. It fails if the payload is not
deterministic, if the trailer does not round-trip, if the emitter's idea of where
a payload starts disagrees with the stub's, or if signing is not reproducible. It
is deliberately the last gate before a third party is allowed to publish a stub,
because after that the format cannot move.

**It passes**, and it is a command rather than a story: `nupp fixpoint --binary`
stamps the target named by `selfHost.binary`, then has the binary that came out
stamp another, and compares them. Stage one is kept beside the output so stage
two writes where stage one did, and the comparison is of two files made the same
way rather than of one file and a memory of another.

Two things it caught on the way, both of which would otherwise have been found by
somebody else:

- A bundle was carrying every `.lua` under the output directory, which is also
  where native dependencies build. lua-cjson ships example scripts, one of them
  opening with a hashbang, which is a syntax error the moment a preload wraps it
  in a function. A bundle now carries what the build compiled and nothing else.
- The stub could not find `cjson` at all until it was vendored and registered in
  `package.preload`, because the compiler requires it before it does anything.

## What this does not do

- **It does not replace the bootstrap.** `bootstrap/nupp.lua` exists so a source
  checkout can build a compiler; a distributed binary is what comes out the other
  end. Different problems that are easy to conflate.
- **It does not absorb arbitrary native dependencies.** Self-contained means the
  program needs no LuaJIT and no engine installed. A project with its own C or
  Rust library still ships that library beside the binary, unless it is linked
  into a stub built for the purpose.
- **It does not make Nupp a Rust project.** The host is a component, built by the
  same machinery that already builds a project's other native dependencies.
