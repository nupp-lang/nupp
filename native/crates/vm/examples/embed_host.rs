//! An application that embeds the Nupp VM and registers a native module.
//!
//! It loads a program image, registers `demo.counter` (the C extension in
//! `tests/extension/counter.c`, a shared library written against
//! `native/include/nuppextension.h`) checked against its `.d.nupp`
//! declaration, calls an export, drives a task that parks on a request the
//! module completes from another thread, and carries a native resource through
//! a checkpoint into a second VM.
//!
//! The image here is a small hand-written one the tests share; an application
//! ships the image its project compiles to:
//!
//! ```sh
//! nupp-vm run COMPILER.image nupp.tools.vm.project emit PROJECT MODULE
//! ```
//!
//! Build the module, then run the example with its path:
//!
//! ```sh
//! cc -shared -fPIC -pthread -Inative/include native/crates/vm/tests/extension/counter.c -o libcounter.so
//! cargo run --release -p nupp-vm --example embed_host -- ./libcounter.so
//! ```
use nupp_vm::embed::{Arg, Module, Out, Vm};
use std::path::PathBuf;

const PROGRAM: &str = include_str!("../tests/extension/main.bytecode");
const DECLARATION: &str = include_str!("../tests/extension/counter.d.nupp");

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let library: PathBuf = std::env::args_os().nth(1).ok_or("usage: embed_host LIBRARY")?.into();
    let mut vm = Vm::new();
    vm.load_image(PROGRAM)?;
    // Refused, with the function and both types named, if any declared
    // function is missing or registered under another type.
    vm.register(Module::load(&library)?, DECLARATION)?;

    // A call that runs to its end on this thread.
    let sum = vm.export("demo.main", "sum")?;
    let out = vm.call(&sum, &[Arg::Integer(2), Arg::Integer(3)])?;
    println!("add(add(2, 3), 3) = {}", out[0].as_integer().unwrap_or_default());

    // Tasks park on `later`, which completes from the module's own thread;
    // `run` drives the scheduler until the task ends.
    let fetch = vm.export("demo.main", "fetch")?;
    let first = vm.spawn(&fetch, &[Arg::from("olleh")])?;
    let second = vm.spawn(&fetch, &[Arg::from("dlrow")])?;
    let hello = vm.run(first)?;
    let world = vm.run(second)?;
    println!("{} {}", hello[0].as_str().unwrap_or("?"), world[0].as_str().unwrap_or("?"));

    // A resource the module owns the data of, saved through its hooks.
    let use_counter = vm.export("demo.main", "use_counter")?;
    let remember = vm.export("demo.main", "remember")?;
    let out = vm.call(&use_counter, &[Arg::Integer(10)])?;
    let Out::Root(counter) = &out[0] else { return Err("a counter is a resource".into()) };
    vm.call(&remember, &[Arg::Root(counter)])?;
    let checkpoint = vm.checkpoint()?;
    println!("checkpoint: {} bytes", checkpoint.len());

    // A second VM from the checkpoint, the module registered again first.
    let mut restored = Vm::restore(&checkpoint, vec![(Module::load(&library)?, DECLARATION.to_string())])?;
    let recall = restored.export("demo.main", "recall")?;
    let bump = restored.export("demo.main", "bump")?;
    let counter = restored.call(&recall, &[])?.remove(0);
    let Out::Root(counter) = counter else { return Err("the counter did not survive".into()) };
    let value = restored.call(&bump, &[Arg::Root(&counter), Arg::Integer(1)])?;
    println!("restored counter = {}", value[0].as_integer().unwrap_or_default());
    Ok(())
}
