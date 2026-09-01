//! Immutable bytes shared between isolated worker lanes.
//!
//! A region is one reference-counted allocation with cheap, checked extents.
//! Lua states receive only opaque handles to regions; bytes never borrow from a
//! Lua heap and the final reference may be released on any worker thread.

use std::fmt;
use std::ops::Range;
use std::sync::Arc;

#[derive(Clone, Default)]
pub struct SharedBytes {
    storage: Arc<[u8]>,
    extent: Range<usize>,
}

impl SharedBytes {
    pub fn new(bytes: impl Into<Vec<u8>>) -> Self {
        let storage: Arc<[u8]> = bytes.into().into();
        let length = storage.len();
        Self {
            storage,
            extent: 0..length,
        }
    }

    pub fn from_arc(storage: Arc<[u8]>) -> Self {
        let length = storage.len();
        Self {
            storage,
            extent: 0..length,
        }
    }

    pub fn len(&self) -> usize {
        self.extent.len()
    }

    pub fn is_empty(&self) -> bool {
        self.extent.is_empty()
    }

    pub fn as_slice(&self) -> &[u8] {
        &self.storage[self.extent.clone()]
    }

    pub fn slice(&self, extent: Range<usize>) -> Option<Self> {
        if extent.start > extent.end || extent.end > self.len() {
            return None;
        }
        Some(Self {
            storage: Arc::clone(&self.storage),
            extent: self.extent.start + extent.start..self.extent.start + extent.end,
        })
    }

    pub fn allocation_len(&self) -> usize {
        self.storage.len()
    }

    pub fn allocation_id(&self) -> *const u8 {
        self.storage.as_ptr()
    }
}

impl AsRef<[u8]> for SharedBytes {
    fn as_ref(&self) -> &[u8] {
        self.as_slice()
    }
}

impl PartialEq for SharedBytes {
    fn eq(&self, other: &Self) -> bool {
        self.as_slice() == other.as_slice()
    }
}

impl Eq for SharedBytes {}

impl fmt::Debug for SharedBytes {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        out.debug_struct("SharedBytes")
            .field("length", &self.len())
            .field("allocation_length", &self.allocation_len())
            .finish_non_exhaustive()
    }
}

#[derive(Default)]
pub struct SharedBytesBuilder {
    bytes: Vec<u8>,
    reserved: Option<Range<usize>>,
}

impl SharedBytesBuilder {
    pub fn append(&mut self, bytes: &[u8]) -> Result<(), BuilderError> {
        if self.reserved.is_some() {
            return Err(BuilderError::ReservationOpen);
        }
        self.bytes.extend_from_slice(bytes);
        Ok(())
    }

    pub fn reserve(&mut self, count: usize) -> Result<&mut [u8], BuilderError> {
        if self.reserved.is_some() {
            return Err(BuilderError::ReservationOpen);
        }
        let start = self.bytes.len();
        let end = start.checked_add(count).ok_or(BuilderError::TooLarge)?;
        self.bytes.resize(end, 0);
        self.reserved = Some(start..end);
        Ok(&mut self.bytes[start..end])
    }

    pub fn commit(&mut self, written: usize) -> Result<(), BuilderError> {
        let reserved = self.reserved.take().ok_or(BuilderError::NoReservation)?;
        if written > reserved.len() {
            self.reserved = Some(reserved);
            return Err(BuilderError::BeyondReservation);
        }
        self.bytes.truncate(reserved.start + written);
        Ok(())
    }

    pub fn freeze(self) -> Result<SharedBytes, BuilderError> {
        if self.reserved.is_some() {
            return Err(BuilderError::ReservationOpen);
        }
        Ok(SharedBytes::new(self.bytes))
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BuilderError {
    ReservationOpen,
    NoReservation,
    BeyondReservation,
    TooLarge,
}

impl fmt::Display for BuilderError {
    fn fmt(&self, out: &mut fmt::Formatter<'_>) -> fmt::Result {
        let message = match self {
            Self::ReservationOpen => "a shared-byte reservation is already open",
            Self::NoReservation => "no shared-byte reservation is open",
            Self::BeyondReservation => "the commit exceeds the shared-byte reservation",
            Self::TooLarge => "the shared-byte reservation is too large",
        };
        out.write_str(message)
    }
}

impl std::error::Error for BuilderError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn views_share_one_immutable_allocation() {
        let bytes = SharedBytes::new(b"worker payload".to_vec());
        let view = bytes.slice(7..14).unwrap();
        assert_eq!(view.as_slice(), b"payload");
        assert_eq!(view.allocation_id(), bytes.allocation_id());
        assert_eq!(view.allocation_len(), bytes.len());
    }

    #[test]
    fn builder_reservation_commits_only_written_bytes() {
        let mut builder = SharedBytesBuilder::default();
        builder.append(b"one").unwrap();
        builder.reserve(8).unwrap()[..3].copy_from_slice(b"two");
        builder.commit(3).unwrap();
        assert_eq!(builder.freeze().unwrap().as_slice(), b"onetwo");
    }

    #[test]
    fn an_open_reservation_prevents_mutation_and_freeze() {
        let mut builder = SharedBytesBuilder::default();
        builder.reserve(2).unwrap();
        assert_eq!(builder.append(b"x"), Err(BuilderError::ReservationOpen));
        assert_eq!(builder.freeze(), Err(BuilderError::ReservationOpen));
    }
}
