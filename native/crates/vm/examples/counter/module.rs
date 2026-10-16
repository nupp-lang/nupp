// The `demo.counter` module in Rust, against `tests/extension/counter.d.nupp`.
// `embed_host` registers it in process, `counter_extension` exports it from a
// shared library, and the embedding tests include it.
use nupp_extension::{Error, Module, Retained, Value};
use std::sync::{Arc, Mutex};

/// The native state behind a counter resource.
pub struct Counter {
    value: i64,
}

pub fn counter() -> Module {
    let mut module = Module::new("demo.counter");
    let kind = module.saved_resource::<Counter>(
        "Counter",
        |c| c.value.to_le_bytes().to_vec(),
        |bytes| {
            let bytes: [u8; 8] = bytes.try_into().map_err(|_| "a saved counter is eight bytes".to_string())?;
            Ok(Counter { value: i64::from_le_bytes(bytes) })
        },
    );
    module.function("add", "function(a: integer, b: integer): integer", |call| {
        let sum = call.integer(0)?.checked_add(call.integer(1)?).ok_or("the sum overflows")?;
        Ok(vec![sum.into()])
    });
    module.function("new", "function(start: integer): any", move |call| {
        let start = call.integer(0)?;
        Ok(vec![call.new_resource(kind, Counter { value: start })?.into()])
    });
    module.function("bump", "function(counter: any, n: integer): integer", move |call| {
        let (handle, n) = (call.handle(0)?, call.integer(1)?);
        let counter = call.resource(kind, handle)?;
        counter.value += n;
        Ok(vec![counter.value.into()])
    });
    module.function("close", "function(counter: any)", move |call| {
        let handle = call.handle(0)?;
        call.close_resource(kind, handle)?;
        Ok(vec![])
    });
    module.function("apply", "function(f: function(integer): integer, x: integer): integer", |call| {
        let (f, x) = (call.handle(0)?, call.integer(1)?);
        let out = call.invoke(f, &[x.into()], 1)?;
        let y = out[0].as_integer().ok_or("the function did not answer an integer")?;
        Ok(vec![(y + 1).into()])
    });
    // One kept function per process: enough for one VM at a time.
    let kept: Arc<Mutex<Option<Retained>>> = Arc::default();
    let keep = kept.clone();
    module.function("keep", "function(f: function(integer): integer)", move |call| {
        let retained = call.retain(call.handle(0)?)?;
        let old = keep.lock().unwrap().replace(retained);
        if let Some(old) = old {
            call.release(old);
        }
        Ok(vec![])
    });
    let keep = kept.clone();
    module.function("callKept", "function(x: integer): integer", move |call| {
        let f = keep.lock().unwrap().as_ref().map(Retained::handle).ok_or("nothing is kept")?;
        let out = call.invoke(f, &[call.integer(0)?.into()], 1)?;
        Ok(vec![out[0].as_integer().ok_or("the kept function did not answer an integer")?.into()])
    });
    module.function("forget", "function()", move |call| {
        let old = kept.lock().unwrap().take();
        if let Some(old) = old {
            call.release(old);
        }
        Ok(vec![])
    });
    module.function("later", "function(text: string, ms: integer): string", |call| {
        let reversed: String = call.str(0)?.chars().rev().collect();
        let ms = call.integer(1)?;
        let request = call.suspend()?;
        std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_millis(ms.max(0) as u64));
            if ms < 0 {
                request.fail("a negative delay");
            } else {
                request.complete(vec![Value::from(reversed)]);
            }
        });
        Ok(vec![])
    });
    module.function("fail", "function(message: string)", |call| Err(Error::Message(call.str(0)?.to_string())));
    module
}
