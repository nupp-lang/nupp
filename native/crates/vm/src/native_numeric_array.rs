//! Borrowed numeric access to canonical Nupp-owned word backing.
use crate::native_value_array::ValueArray;
use crate::value::Value;
use std::ops::{Deref, DerefMut};

// Storage words are raw numeric bits, not managed Value edges. ValueArray only
// owns their allocation; the KIND_STORAGE object never traces those words.
#[repr(transparent)]
pub struct NumericArray(ValueArray);

impl NumericArray {
    pub fn capacity(&self) -> usize {
        self.0.capacity()
    }
}
impl Deref for NumericArray {
    type Target = [f64];
    fn deref(&self) -> &[f64] {
        let words: &[Value] = &self.0;
        unsafe { std::slice::from_raw_parts(words.as_ptr().cast(), words.len()) }
    }
}
impl DerefMut for NumericArray {
    fn deref_mut(&mut self) -> &mut [f64] {
        let words: &mut [Value] = &mut self.0;
        unsafe { std::slice::from_raw_parts_mut(words.as_mut_ptr().cast(), words.len()) }
    }
}
impl<'a> IntoIterator for &'a NumericArray {
    type Item = &'a f64;
    type IntoIter = std::slice::Iter<'a, f64>;
    fn into_iter(self) -> Self::IntoIter {
        self.iter()
    }
}
