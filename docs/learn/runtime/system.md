# System services

The `os` table provides system facts, clocks, and UUIDs. `os.info()` returns
facts about the ABI executing the program.

```nupp
local facts: os.Info = os.info()
print(facts.platform, facts.arch, facts.pointerbits)
print(facts.endianness, facts.parallelism)
```

Platform names include `macos`, `linux`, `windows`, and `browser`.
Architecture uses names such as `x86_64`, `aarch64`, `x86`, and `wasm32`.
Endianness is `little` or `big`; pointer width is 32 or 64 bits.
Under emulation these describe the executing ABI, not the underlying hardware.
The browser ABI is 32-bit and little-endian.

`platform` and `arch` name the operating system and instruction set.
`endianness` is `"little"` or `"big"`, and `pointerbits` is 32 or 64.
`parallelism` estimates how many execution units the process may use, including
host restrictions, and is at least one. Each call queries parallelism again.

## Clocks

`os.monotonic()` returns milliseconds from an unspecified origin. Subtract two
readings to measure an interval:

```nupp
local started = os.monotonic()
print(os.monotonic() - started)
```

`os.walltime()` returns milliseconds since the Unix epoch. Clock corrections
can move it backward, so use the monotonic clock for elapsed time and deadlines.

## UUIDs

`os.uuid(4)` returns a random version 4 UUID. `os.uuid(7)` returns a version 7
UUID ordered by its millisecond timestamp; identifiers made in the same
millisecond can compare in either order.

```nupp
print(os.uuid(4))
print(os.uuid(7))
```

Both return lowercase, hyphenated strings and raise when the selected host
service fails or returns a malformed identifier.
