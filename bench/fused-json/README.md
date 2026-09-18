# Fused JSON decoder throughput

Measures `nupp.codec.json.internal.decoder.fused`'s eager entry -- the vector
scan, the structural tape and the materialization into ordinary Lua values --
against the Lunajson decoder this repository already vendors, on five input
classes.

```sh
./run.sh        # fifteen paired samples
./run.sh 25     # more
```

`prepare.sh` copies the tree's own `fused.nupp` here under a second module
name before the build, so the benchmark measures whichever checkout it is run
from. A branch that rewrites the decoder needs no change here, which is what
makes two checkouts comparable.

It makes two mechanical signature edits, both explained in `prepare.sh`: the
module name, and `borrows source: string | Buffer` becomes `source: string`
(with the matching `paddedBytesU8` call becoming `paddedStringU8`). The second
is a workaround, not a preference -- the generated ahead-of-time wrapper for a
string-or-buffer parameter does not check today. `results/` says why.

## Proving what runs

A `kind = "modules"` project gives a *dependency* module no ahead-of-time
replacement, so the authored body runs interpreted and the benchmark reports a
number for something nobody meant to measure. `tests/bench.lua` refuses to
measure until three things hold: the artifact `require` loaded carries the
generated binding and no longer carries the authored scan, the
`__nuppAotCompiled` registry holds replacements, and the registered builders
are C functions out of the compiled object. It prints all three before the
first timing.

## Protocol

Implementations alternate inside every sample rather than one running all its
samples first, and which one leads rotates, so drift is shared. A full
collection runs before each timed batch and collection stays enabled during
it. Results are consumed. Each timed batch moves about 2 MB, which for the
30-byte payload is tens of thousands of calls. Medians are reported with the
sample range; a single run is not a result.
