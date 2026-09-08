---
order: 195
title: System information
---

# System information

`nupp.system` reports facts about the environment executing the Nupp ABI:

```nupp
local system = nupp.system
print(system.platform, system.architecture)
print(system.endianness, system.pointerBits)
print(system.availableParallelism())
```

Platform names include `macos`, `linux`, `windows` and `browser`.
Architecture uses names such as `x86_64`, `aarch64` and `wasm32`.
Endianness is `little` or `big`; pointer width is 32 or 64 bits.
Under emulation these describe the executing ABI, not the underlying hardware.

`availableParallelism()` returns an integer of at least one. Native hosts use
the operating-system estimate exposed by Rust's available_parallelism; browsers
use their hardwareConcurrency estimate, falling back to one. This is a sizing
hint, not a count of physical cores or a guarantee of future CPU availability.
It works without initializing the worker scheduler.

Browser hosts implement the `host.system` seam. These calls do not expose the
physical host's OS, CPU model, hostname, memory usage or core topology.
