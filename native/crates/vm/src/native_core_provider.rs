//! Immutable address transport for the complete frozen native core ABI.
//! The image producer owns code, entry shims, arenas and runtime policy.
use std::cell::{Cell, UnsafeCell};
use std::sync::OnceLock;

pub const CORE_EXPORT_COUNT: usize = 105;
include!("native_core_symbols.rs");

struct Provider {
    addresses: [usize; CORE_EXPORT_COUNT],
    #[cfg(feature = "aot")]
    _image: Option<crate::native_raw::Image>,
}
static PROVIDER: OnceLock<Result<Provider, String>> = OnceLock::new();
thread_local! {
    static INITIALIZING: Cell<bool> = const { Cell::new(false) };
    static ARENA_SLOT: ThreadSlot = const { ThreadSlot { word: UnsafeCell::new(0), finalizer: Cell::new(0) } };
}

struct ThreadSlot {
    word: UnsafeCell<u64>,
    finalizer: Cell<usize>,
}
impl Drop for ThreadSlot {
    fn drop(&mut self) {
        let address = self.finalizer.replace(0);
        if address != 0 {
            let callback: unsafe extern "C" fn(u64) = unsafe { std::mem::transmute(address) };
            unsafe { callback(*self.word.get()) };
        }
        unsafe { *self.word.get() = 0 };
    }
}

/// Opaque per-thread storage for a Nupp-owned arena descriptor. The bridge
/// never dereferences, allocates, reclaims or interprets the stored word.
pub extern "C" fn nupp_raw_thread_slot() -> *mut u64 {
    ARENA_SLOT.with(|slot| slot.word.get())
}

/// Registers a thread-exit callback, or clears it when address is zero.
///
/// # Safety
/// The address must be an `extern "C" fn(u64)` valid until thread exit. It
/// receives the opaque stored word once and must not access these TLS helpers
/// or unwind. The generated callback owns all cleanup policy.
pub unsafe extern "C" fn nupp_raw_thread_finalizer(address: u64) {
    ARENA_SLOT.with(|slot| slot.finalizer.set(address as usize));
}

pub const fn export_index(name: &str) -> usize {
    let mut i = 0;
    while i < CORE_EXPORT_COUNT {
        let a = name.as_bytes();
        let b = CORE_EXPORT_NAMES[i].as_bytes();
        let mut same = a.len() == b.len();
        let mut j = 0;
        while same && j < a.len() {
            same = a[j] == b[j];
            j += 1;
        }
        if same {
            return i;
        }
        i += 1;
    }
    panic!("unknown frozen native core export")
}

impl Provider {
    fn configured() -> Result<Self, String> {
        let Some(path) = std::env::var_os("NUPP_RAW_CORE") else {
            return Ok(Self {
                addresses: linked_addresses(),
                #[cfg(feature = "aot")]
                _image: None,
            });
        };
        #[cfg(feature = "aot")]
        {
            let bundle = crate::native_raw_bundle::read_bundle(std::path::Path::new(&path))?;
            if bundle.output_words != CORE_EXPORT_COUNT {
                return Err("raw core setup must produce all 105 export addresses".into());
            }
            let image = bundle.seal()?;
            let mut words = [0u64; CORE_EXPORT_COUNT];
            unsafe { image.call(&[], &mut words) };
            let addresses = validate_addresses(&image, &words)?;
            Ok(Self {
                addresses,
                _image: Some(image),
            })
        }
        #[cfg(not(feature = "aot"))]
        {
            let _ = path;
            Err("raw core images require the aot loader feature".into())
        }
    }
}

#[cfg(feature = "aot")]
fn validate_addresses(
    image: &crate::native_raw::Image,
    words: &[u64; CORE_EXPORT_COUNT],
) -> Result<[usize; CORE_EXPORT_COUNT], String> {
    let mut addresses = [0; CORE_EXPORT_COUNT];
    for (index, word) in words.iter().enumerate() {
        let address =
            usize::try_from(*word).map_err(|_| "raw core address exceeds the host word")?;
        if !image.contains_entry(address) {
            return Err(format!(
                "raw core export {} is not an aligned address in its retained code image",
                CORE_EXPORT_NAMES[index]
            ));
        }
        addresses[index] = address;
    }
    Ok(addresses)
}

fn provider() -> Result<&'static Provider, String> {
    if INITIALIZING.with(Cell::get) {
        return Err("raw core setup reentered the native core before publication".into());
    }
    PROVIDER
        .get_or_init(|| {
            struct Reset;
            impl Drop for Reset {
                fn drop(&mut self) {
                    INITIALIZING.with(|flag| flag.set(false));
                }
            }
            INITIALIZING.with(|flag| flag.set(true));
            let _reset = Reset;
            Provider::configured()
        })
        .as_ref()
        .map_err(Clone::clone)
}

/// Selects the process's provider before any runtime state exists. Selection
/// is immutable; changing the environment afterward has no effect.
pub fn initialize() -> Result<(), String> {
    provider().map(|_| ())
}

#[doc(hidden)]
#[inline]
pub fn address(index: usize) -> usize {
    provider()
        .unwrap_or_else(|error| panic!("native core provider: {error}"))
        .addresses[index]
}

/// Preserve the exact existing call signature while routing linked and owned
/// backends through the same immutable address table.
#[macro_export]
macro_rules! native_core_api {
    ($($(#[$attribute:meta])* $visibility:vis fn $name:ident($($argument:ident: $kind:ty),* $(,)?) $(-> $result:ty)?;)*) => {
        $($(#[$attribute])* $visibility unsafe extern "C" fn $name($($argument: $kind),*) $(-> $result)? {
            const INDEX: usize = $crate::native_core_provider::export_index(stringify!($name));
            let address = $crate::native_core_provider::address(INDEX);
            let entry: unsafe extern "C" fn($($kind),*) $(-> $result)? = unsafe { std::mem::transmute(address) };
            unsafe { entry($($argument),*) }
        })*
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn thread_slot_is_opaque_and_thread_local() {
        let slot = nupp_raw_thread_slot();
        unsafe { *slot = 0xfedc_ba98_7654_3210 };
        let other = std::thread::spawn(|| {
            let slot = nupp_raw_thread_slot();
            assert_eq!(unsafe { *slot }, 0);
            unsafe { *slot = 17 };
            slot as usize
        })
        .join()
        .unwrap();
        assert_ne!(slot as usize, other);
        assert_eq!(unsafe { *slot }, 0xfedc_ba98_7654_3210);
        unsafe { *slot = 0 };
    }

    #[test]
    fn thread_exit_delivers_each_exact_opaque_word_once() {
        use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
        static FIRST: AtomicU64 = AtomicU64::new(0);
        static SECOND: AtomicU64 = AtomicU64::new(0);
        static CALLS: AtomicUsize = AtomicUsize::new(0);
        unsafe extern "C" fn first(word: u64) {
            FIRST.store(word, Ordering::SeqCst);
            CALLS.fetch_add(1, Ordering::SeqCst);
        }
        unsafe extern "C" fn second(word: u64) {
            SECOND.store(word, Ordering::SeqCst);
            CALLS.fetch_add(1, Ordering::SeqCst);
        }
        let threads: Vec<_> = [
            (first as *const () as u64, 0xfedc_ba98_7654_3210),
            (second as *const () as u64, 0x8765_4321_fedc_ba98),
        ]
        .into_iter()
        .map(|(callback, word)| {
            std::thread::spawn(move || unsafe {
                assert_eq!(*nupp_raw_thread_slot(), 0);
                *nupp_raw_thread_slot() = word;
                nupp_raw_thread_finalizer(callback);
                // Replacing the same registration still results in one delivery.
                nupp_raw_thread_finalizer(callback);
            })
        })
        .collect();
        for thread in threads {
            thread.join().unwrap();
        }
        assert_eq!(CALLS.load(Ordering::SeqCst), 2);
        assert_eq!(FIRST.load(Ordering::SeqCst), 0xfedc_ba98_7654_3210);
        assert_eq!(SECOND.load(Ordering::SeqCst), 0x8765_4321_fedc_ba98);
        std::thread::spawn(|| unsafe {
            nupp_raw_thread_finalizer(first as *const () as u64);
            nupp_raw_thread_finalizer(0);
        })
        .join()
        .unwrap();
        assert_eq!(CALLS.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn setup_reentry_is_refused_before_waiting_for_publication() {
        INITIALIZING.with(|flag| flag.set(true));
        let result = initialize();
        INITIALIZING.with(|flag| flag.set(false));
        assert!(result.unwrap_err().contains("reentered"));
    }

    #[test]
    #[cfg(all(feature = "aot", target_arch = "aarch64", target_endian = "little"))]
    fn every_export_must_be_aligned_inside_retained_code() {
        use crate::native_raw::{ImageSpec, PendingImage};
        let code = [0xc0, 0x03, 0x5f, 0xd6, 0xc0, 0x03, 0x5f, 0xd6];
        let pending = PendingImage::new(
            ImageSpec {
                architecture: "aarch64",
                layout_digest: [7; 32],
                entry: 0,
            },
            &[7; 32],
            &code,
            &[0; 8],
            &[],
        )
        .unwrap();
        let [base, data, _] = pending.bases();
        let image = pending.seal().unwrap();
        let mut words = [base as u64; CORE_EXPORT_COUNT];
        words[104] = (base + 4) as u64;
        assert_eq!(validate_addresses(&image, &words).unwrap()[104], base + 4);
        for invalid in [0, base - 4, base + 1, base + 8, data, usize::MAX] {
            words[104] = invalid as u64;
            let error = validate_addresses(&image, &words).unwrap_err();
            assert!(error.contains(CORE_EXPORT_NAMES[104]), "{error}");
        }
    }
}
