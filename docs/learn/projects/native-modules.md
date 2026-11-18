---
order: 555
title: Native modules
redirects: learn/projects/embedding
---

# Native modules

A native module is a typed Nupp module whose functions are C, or any language
that can export a C ABI. It is a shared library that reaches a program one of
two ways, and the program cannot tell which:

- An application that embeds the VM registers the module in process.
- A program run by `nupp` loads the module when it first requires it.

Either way the module arrives through one versioned C ABI,
`native/include/nupp_extension.h`, and either way it is checked against the
module's `.d.nupp` declaration before any of its code runs. The declaration is
what typed callers were checked against, so a library that registers another
signature is refused, not called.

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

## Writing it in C

An extension includes `nupp_extension.h` and nothing else of Nupp's, and links
nothing of Nupp's. It describes the module in static data: the module name, the
target it was built for, its functions under their declared Nupp types, and its
resource types. One exported entry point answers that description:

```c
#include "nupp_extension.h"

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
an opaque `nupp_handle`. The arguments are already checked against the declared
parameter types when the function runs, and its `nresults` result slots start
as nil. A function answers `NUPP_OK` with its results, `NUPP_ERROR` after
`host->raise`, which raises the message at the Nupp call site, or
`NUPP_SUSPENDED` after `host->suspend`. Nothing may unwind through the VM.

The `nupp_host` table the VM passes to every call is the rest of the API:

- **Handles.** A table, record or function argument arrives as a handle, valid
  for the call. `retain` makes one that outlives the call, until `release`.
  `invoke` calls a Nupp function on the VM's thread, inside the call; when it
  answers `NUPP_ERROR`, returning `NUPP_ERROR` raises that error to the caller
  with its original value.
- **Suspension.** `suspend` parks the calling task and hands back a request,
  which any thread completes once with plain values (`complete`) or fails with a
  message (`fail`). The task resumes at the call with those values, or raises
  the message there. Only a call from a task can park; where the call cannot,
  `suspend` answers null with the refusal raised, naming the function.
- **Resources.** A `nupp_resource_type` is a kind of native object the VM owns
  and the extension keeps the data of. `new_resource` makes one owning a
  pointer, `resource` answers that pointer for a live object of the type, and
  `close_resource` drops it now. Its type's `drop` hook runs when the object is
  closed or its VM ends, and its `save` and `restore` hooks carry it through a
  checkpoint.
- **Instances.** The optional `init` hook runs once per VM after every check
  passed and may set an instance pointer that every call receives; `shutdown`
  runs when the VM ends, after its resources were dropped. Every entry that
  takes a `nupp_call` runs on the VM's thread, inside that call.

A host table only grows: a later ABI appends entries and reports its size.

```c
typedef struct {
    const nupp_host *host;
    nupp_request *request;
    char *text;
    size_t length;
} job;

static void *finish(void *arg) {
    job *j = arg;
    nupp_slot result = {.kind = NUPP_STRING};
    result.as.string.bytes = j->text;
    result.as.string.length = j->length;
    j->host->complete(j->request, &result, 1);
    free(j->text);
    free(j);
    return NULL;
}

/* function(text: string): string, answered from another thread. */
static nupp_status later(const nupp_host *host, nupp_call *call, void *instance, void *data,
                         const nupp_slot *args, size_t nargs, nupp_slot *results, size_t nresults) {
    job *j = calloc(1, sizeof *j);
    j->host = host;
    j->length = args[0].as.string.length;
    j->text = malloc(j->length);
    memcpy(j->text, args[0].as.string.bytes, j->length);
    j->request = host->suspend(call);
    if (!j->request) {
        free(j->text);
        free(j);
        return NUPP_ERROR;
    }
    pthread_t thread;
    pthread_create(&thread, NULL, finish, j);
    pthread_detach(thread);
    return NUPP_SUSPENDED;
}
```

`native/crates/vm/tests/extension/counter.c` is the whole `demo.counter`
module: resources saved through a checkpoint, retained callbacks and parked
calls completed from its own threads.

## Building and loading it

Build the module as a shared library with any C compiler; it needs only the
header:

```sh
cc -std=c11 -shared -fPIC -pthread -Inative/include counter.c -o libcounter.so
```

On macOS use `-dynamiclib` and name it `libcounter.dylib`. When a program
first requires `demo.counter`, the runtime finds the library its declaration
names, by the rules `foreign.load` uses: a path is opened as written, a bare
name gains the platform's prefix and extension and is searched for, and an `@`
name is looked for at or above the requiring module's directory, then at or
above the executable's.

Before any of the library's code runs but its entry point, the runtime refuses
it when its ABI version is not the runtime's, it was built for another target,
it provides another module, or any declared function is missing or registered
under another type. Only then does it call the library's `init`. The library
stays loaded while the VM that loaded it lives; each VM loads a module once.

## Embedding the VM

`nupp_vm::embed::Vm` is one isolated runtime for a Rust application. Load the
images a project compiles to, register native modules with their
declarations, and call the program's exports:

```rust
use nupp_vm::embed::{Arg, Module, Vm};

let mut vm = Vm::new();
vm.load_image(&image)?;
vm.register(Module::load("libcounter.so".as_ref())?, include_str!("demo/counter.d.nupp"))?;

let sum = vm.export("demo.main", "sum")?;
let out = vm.call(&sum, &[Arg::Integer(2), Arg::Integer(3)])?;
```

`Module::load` opens a library and reads its entry point; an application that
links the description in itself passes it to `Module::from_descriptor` with
whatever keeps it valid. Registration is refused, naming the function and both
types, when a declared function is missing or registered under another type:

```text
demo.counter.add is declared function(number, number): number, but the extension registers function(int64, int64): int64
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

The `embed_host` example in the VM crate does all of this with
`counter.c`, then saves the VM and restores it into a second one.

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
