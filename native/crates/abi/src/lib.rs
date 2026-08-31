//! Versioned primitives shared by the Rust host and native providers.

#![forbid(unsafe_op_in_unsafe_fn)]

use std::cell::RefCell;
use std::ffi::{CStr, CString, c_char};
use std::fmt;

pub const ABI_VERSION: u32 = 2;

#[repr(i32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Status {
    Ok = 0,
    InvalidArgument = 1,
    Capacity = 2,
    StaleHandle = 3,
    Closed = 4,
    Internal = 5,
}

impl Status {
    pub const fn code(self) -> i32 {
        self as i32
    }
}

thread_local! {
    static LAST_ERROR: RefCell<CString> = RefCell::new(c"no error".to_owned());
}

pub fn set_last_error(message: impl fmt::Display) {
    let mut bytes = message.to_string().into_bytes();
    for byte in &mut bytes {
        if *byte == 0 {
            *byte = b'?';
        }
    }
    let value = CString::new(bytes).expect("interior NUL bytes were replaced");
    LAST_ERROR.with(|slot| *slot.borrow_mut() = value);
}

pub fn with_last_error<T>(read: impl FnOnce(&CStr) -> T) -> T {
    LAST_ERROR.with(|slot| read(slot.borrow().as_c_str()))
}

pub fn last_error_ptr() -> *const c_char {
    with_last_error(CStr::as_ptr)
}

#[repr(transparent)]
#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
pub struct Handle(u64);

impl Handle {
    pub const INVALID: Self = Self(0);

    pub const fn from_raw(raw: u64) -> Self {
        Self(raw)
    }

    pub const fn raw(self) -> u64 {
        self.0
    }

    pub const fn is_valid(self) -> bool {
        let index = (self.0 & u32::MAX as u64) as u32;
        let generation = (self.0 >> 32) as u32;
        index != 0 && generation != 0
    }

    fn new(index: usize, generation: u32) -> Self {
        debug_assert!(index < u32::MAX as usize);
        Self((u64::from(generation) << 32) | (index as u64 + 1))
    }

    fn parts(self) -> Option<(usize, u32)> {
        let index = (self.0 & u64::from(u32::MAX)) as u32;
        let generation = (self.0 >> 32) as u32;
        if index == 0 || generation == 0 {
            None
        } else {
            Some(((index - 1) as usize, generation))
        }
    }
}

struct Slot<T> {
    generation: u32,
    value: Option<T>,
}

/// An arena whose public identities cannot alias a reused slot.
pub struct Arena<T> {
    slots: Vec<Slot<T>>,
    free: Vec<usize>,
    len: usize,
}

impl<T> Arena<T> {
    pub const fn new() -> Self {
        Self {
            slots: Vec::new(),
            free: Vec::new(),
            len: 0,
        }
    }

    pub fn len(&self) -> usize {
        self.len
    }

    pub fn is_empty(&self) -> bool {
        self.len == 0
    }

    pub fn insert(&mut self, value: T) -> Result<Handle, Status> {
        let index = if let Some(index) = self.free.pop() {
            index
        } else {
            if self.slots.len() == u32::MAX as usize {
                return Err(Status::Capacity);
            }
            self.slots.push(Slot {
                generation: 1,
                value: None,
            });
            self.slots.len() - 1
        };
        let slot = &mut self.slots[index];
        debug_assert!(slot.value.is_none());
        slot.value = Some(value);
        self.len += 1;
        Ok(Handle::new(index, slot.generation))
    }

    pub fn get(&self, handle: Handle) -> Result<&T, Status> {
        let (index, generation) = handle.parts().ok_or(Status::StaleHandle)?;
        let slot = self.slots.get(index).ok_or(Status::StaleHandle)?;
        if slot.generation != generation {
            return Err(Status::StaleHandle);
        }
        slot.value.as_ref().ok_or(Status::StaleHandle)
    }

    pub fn get_mut(&mut self, handle: Handle) -> Result<&mut T, Status> {
        let (index, generation) = handle.parts().ok_or(Status::StaleHandle)?;
        let slot = self.slots.get_mut(index).ok_or(Status::StaleHandle)?;
        if slot.generation != generation {
            return Err(Status::StaleHandle);
        }
        slot.value.as_mut().ok_or(Status::StaleHandle)
    }

    pub fn remove(&mut self, handle: Handle) -> Result<T, Status> {
        let (index, generation) = handle.parts().ok_or(Status::StaleHandle)?;
        let slot = self.slots.get_mut(index).ok_or(Status::StaleHandle)?;
        if slot.generation != generation {
            return Err(Status::StaleHandle);
        }
        let value = slot.value.take().ok_or(Status::StaleHandle)?;
        if slot.generation != u32::MAX {
            slot.generation += 1;
            self.free.push(index);
        }
        self.len -= 1;
        Ok(value)
    }
}

impl<T> Default for Arena<T> {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_reused_slot_never_revives_the_old_handle() {
        let mut arena = Arena::new();
        let first = arena.insert("first").unwrap();
        assert_eq!(arena.remove(first), Ok("first"));
        let second = arena.insert("second").unwrap();
        assert_ne!(first, second);
        assert_eq!(arena.get(first), Err(Status::StaleHandle));
        assert_eq!(arena.get(second), Ok(&"second"));
    }

    #[test]
    fn zero_and_double_release_are_stale() {
        let mut arena = Arena::new();
        assert_eq!(arena.get(Handle::INVALID), Err(Status::StaleHandle));
        let handle = arena.insert(42).unwrap();
        assert_eq!(arena.remove(handle), Ok(42));
        assert_eq!(arena.remove(handle), Err(Status::StaleHandle));
    }

    #[test]
    fn error_text_replaces_interior_nuls() {
        set_last_error("bad\0message");
        with_last_error(|value| assert_eq!(value.to_bytes(), b"bad?message"));
    }
}
