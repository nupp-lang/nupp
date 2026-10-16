---
order: 555
title: Native modules
---

# Native modules

A native module is a typed Nupp module whose functions are Rust or C. It reaches
a program one of two ways, and the program cannot tell which:

- An application that embeds the VM registers the module in process.
- A program run by `nupp` loads the module from a shared library built apart
  from it, when it first requires the module.

Either way the module arrives through one versioned C ABI, and either way it is
checked against the module's `.d.nupp` declaration before any of its code runs.
The declaration is what typed callers were checked against, so a library that
registers another signature is refused, not called.

::: info
Native modules run on the Nupp VM. The LuaJIT embedding described in
[Embedding Nupp](embedding.md) is a separate, older surface.
:::

## Declaring the module

Declare the module the way any module without a Nupp body is declared: a
`.d.nupp` file that returns a record of functions. An `@extension` line names
the library that provides it, the way a `cdef ... from` declaration names one:

```nupp:fragment [src/demo/counter.d.nupp]
--- @extension counter
local record Counter
    --- `a + b`, computed natively.
    add: function(a: integer, b: integer): integer

    --- A counter resource starting at `start`.
    new: function(start: integer): any

    --- Adds `n` to `counter` and answers its value.
    bump: function(counter: any, n: integer): integer

    --- Calls `f(x)` and answers its result plus one.
    apply: function(f: function(integer): integer, x: integer): integer

    --- `text` reversed, answered from another thread after `ms` milliseconds.
    later: function(text: string, ms: integer): string
end

return Counter
```

Callers use it like any module:

```nupp:fragment
local counter = require("demo.counter")

assert(counter.add(19, 23) == 42)
assert(counter.apply(function(x: integer): integer
    return x * 2
end, 20) == 41)
```

When a program is compiled for the VM, its image carries the declaration of
every native module it requires. The runtime compares the library with that
declaration, not with whatever declaration the library brought along.

Values cross the boundary as these types. Arguments are checked against the
declared parameter types before the native function runs, and results against
the declared result types after it returns, so typed code never receives a
value its type does not describe.

| Declared type | Native side |
| --- | --- |
| `nil`, `boolean`, `number`, `string` | the value |
| `integer`, `int32`, `uint32`, `int64` | a 64-bit integer, range-checked both ways |
| `T?` | nil, or `T` |
| `any`, a function type, a table type | a handle |

A result declared as a named record type or a union is refused when the module
registers, because the boundary cannot check it. Declare it `any` instead.
Variadic and generic host functions are refused, too.

## Writing it in Rust

The `nupp-extension` crate is the Rust SDK. A `Module` is a name, functions
under their declared Nupp types, and resource types:

```rust
use nupp_extension::{Module, Value};

pub fn module() -> Module {
    let mut module = Module::new("demo.counter");
    module.function("add", "function(a: integer, b: integer): integer", |call| {
        let sum = call.integer(0)?.checked_add(call.integer(1)?).ok_or("the sum overflows")?;
        Ok(vec![sum.into()])
    });
    module.function("apply", "function(f: function(integer): integer, x: integer): integer", |call| {
        let (f, x) = (call.handle(0)?, call.integer(1)?);
        let out = call.invoke(f, &[x.into()], 1)?;
        Ok(vec![(out[0].as_integer().ok_or("not an integer")? + 1).into()])
    });
    module
}
```

A function answers its results or an error. An `Err` raises at the Nupp call
site with its message, and a panic raises the same way rather than unwinding
into the VM.

- **Handles.** A table, record or function argument arrives as a `Handle`,
  valid for the call. `call.retain(handle)` makes one that outlives the call,
  until `call.release`. `call.invoke(f, args, n)` calls a Nupp function on the
  VM's thread, inside the call.
- **Suspension.** `call.suspend()` parks the calling task and hands back a
  `Request`, which any thread completes with plain values or fails with a
  message. The task resumes at the call with those values, or raises the
  message there. Only a call from a task can park; a call that cannot is
  refused with the function named.
- **Resources.** `module.saved_resource::<T>(name, save, restore)` makes a type
  of native object the VM owns and the module keeps a `T` for.
  `call.new_resource`, `call.resource` and `call.close_resource` make one,
  reach its `T` and drop it.

```rust
module.function("later", "function(text: string, ms: integer): string", |call| {
    let reversed: String = call.str(0)?.chars().rev().collect();
    let ms = call.integer(1)?;
    let request = call.suspend()?;
    std::thread::spawn(move || {
        std::thread::sleep(std::time::Duration::from_millis(ms as u64));
        request.complete(vec![Value::from(reversed)]);
    });
    Ok(vec![])
});
```

## Embedding the VM

`nupp_vm::embed::Vm` is one isolated runtime. Load the images a project
compiles to, register native modules with their declarations, and call the
program's exports:

```rust
use nupp_vm::embed::{Arg, Vm};

let mut vm = Vm::new();
vm.load_image(&image)?;
vm.register(counter::module(), include_str!("demo/counter.d.nupp"))?;

let sum = vm.export("demo.main", "sum")?;
let out = vm.call(&sum, &[Arg::Integer(2), Arg::Integer(3)])?;
```

Registration is refused, naming the function and both types, when a declared
function is missing or registered under another type:

```text
demo.counter.add is declared function(number, number): number, but the extension registers function(integer, integer): integer
```

`Vm::call` runs a function to its end on the caller's stack, so nothing it
calls may park. A task can: `Vm::spawn` starts one, `Vm::run_ready` runs what is
ready, and `Vm::run` drives the scheduler until a given task ends, sleeping
until the next timer and blocking for host completions when nothing else can
move.

```rust
let fetch = vm.export("demo.main", "fetch")?;
let task = vm.spawn(&fetch, &[Arg::from("olleh")])?;
let results = vm.run(task)?; // "hello", completed from another thread
```

Values come out as `Out`: scalars and strings by value, anything else as a
`Root`. A root keeps its value alive across calls and collections until
`Vm::release`; `Vm::read` reads it and `Arg::Root` passes it back in.

The `embed_host` example in the VM crate does all of this, then saves the VM
and restores it into a second one.

## Loading it as an extension

The same module becomes an extension when a shared library exports it:

```rust
nupp_extension::export!(module);
```

```toml
[lib]
name = "counter"
crate-type = ["cdylib"]
```

The library depends on `nupp-extension` alone, never on the VM, and is built
by itself. When a program first requires `demo.counter`, the runtime finds the
library its declaration names, by the rules `foreign.load` uses: a path is
opened as written, a bare name gains the platform's prefix and extension and is
searched for, and an `@` name is looked for at or above the requiring module's
directory, then at or above the executable's.

Before any of the library's code runs but its entry point, the runtime refuses
it when its ABI version is not the runtime's, it was built for another target,
it provides another module, or any declared function is missing or registered
under another type. Only then does it call the library's `init`. The library
stays loaded while the VM that loaded it lives; each VM loads a module once.

## The C ABI

`native/crates/vm/include/nupp_extension.h` is the ABI. A C extension includes
it and nothing else of Nupp's:

```c
static nupp_status add(const nupp_host *host, nupp_call *call, void *instance, void *data,
                       const nupp_slot *args, size_t nargs, nupp_slot *results, size_t nresults) {
    int64_t sum;
    if (__builtin_add_overflow(args[0].as.integer, args[1].as.integer, &sum)) {
        return host->raise(call, "the sum overflows", 17);
    }
    results[0].kind = NUPP_INTEGER;
    results[0].as.integer = sum;
    return NUPP_OK;
}

static const nupp_function_entry functions[] = {
    {"add", "function(a: integer, b: integer): integer", add, NULL, 0, 0},
};

static const nupp_extension extension = {
    NUPP_EXTENSION_ABI_VERSION, sizeof(nupp_extension), "demo.counter", NUPP_EXTENSION_TARGET,
    functions, 1, NULL, 0, NULL, NULL,
};

const nupp_extension *NUPP_EXTENSION_ENTRY(void) { return &extension; }
```

Values cross as `nupp_slot`s: scalars and strings by value, everything else as
an opaque `nupp_handle`. The `nupp_host` table the VM passes to every call
raises errors, retains and releases handles, invokes Nupp functions, suspends
calls and completes them from any thread, and makes and drops resources. Every
entry that takes a `nupp_call` runs on the VM's thread, inside that call, and
nothing may unwind through the table. A host table only grows: a later ABI
appends entries and reports its size.

## Checkpoints

A checkpoint saves a module's resources through their types' `save` hooks and
names the type of any resource that has none:

```text
checkpoint cannot save resource Scratch of demo.unsaved: the type has no save hook
```

Restoring binds each module before its resources: an extension's library is
loaded and checked again, and an embedder passes its modules to
`Vm::restore`. A module's own state outside resources is not saved, so keep
what a program would miss in resources. Roots and retained handles end with
the VM that made them, and a pending host request blocks a checkpoint until it
completes.
