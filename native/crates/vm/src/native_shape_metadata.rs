//! Borrowed text and decoded hints for canonical Nupp-owned shape metadata.
use crate::heap::SlotTy;
use crate::native_byte_array::ByteArray;
use crate::native_value_array::ValueArray;
use crate::value::Value;
use std::ffi::c_void;
use std::ops::Deref;

// Only valid Rust text can construct this immutable view. No external byte
// pointer can enter the safe API or mutate the bytes after construction.
#[repr(transparent)]
pub struct ShapeName(ByteArray);
impl ShapeName {
    pub(crate) unsafe fn new(owner: *mut c_void, name: &str) -> Self {
        let mut bytes = unsafe { ByteArray::new(owner, 0, name.len()) };
        bytes.extend_from_slice(name.as_bytes());
        Self(bytes)
    }
    pub fn as_str(&self) -> &str {
        // The private backing is initialized only from &str and never mutated.
        unsafe { std::str::from_utf8_unchecked(&self.0) }
    }
}
impl Deref for ShapeName {
    type Target = str;
    fn deref(&self) -> &str {
        self.as_str()
    }
}
impl AsRef<str> for ShapeName {
    fn as_ref(&self) -> &str {
        self.as_str()
    }
}
impl<T: AsRef<str>> PartialEq<T> for ShapeName {
    fn eq(&self, other: &T) -> bool {
        self.as_str() == other.as_ref()
    }
}
impl std::fmt::Display for ShapeName {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.as_str().fmt(f)
    }
}
impl std::fmt::Debug for ShapeName {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        std::fmt::Debug::fmt(self.as_str(), f)
    }
}

#[repr(transparent)]
pub struct ShapeTypes(ValueArray);
const _: () = {
    assert!(std::mem::size_of::<ShapeName>() == 32);
    assert!(std::mem::size_of::<ShapeTypes>() == 32);
    assert!(std::mem::align_of::<ShapeTypes>() == 8);
};
#[cfg(feature = "native-runtime")]
unsafe extern "C" {
    pub(crate) fn nupp_shape_types_replace(
        types: *mut ShapeTypes,
        source: *const Value,
        count: u64,
    ) -> u64;
    fn nupp_shape_types_set(types: *mut ShapeTypes, index: u64, word: u64) -> u64;
}
macro_rules! native {
    ($name:ident($($argument:expr),* $(,)?)) => {{
        #[cfg(feature = "native-runtime")]
        { unsafe { $name($($argument),*) } }
        #[cfg(not(feature = "native-runtime"))]
        { panic!("shape metadata requires a linked Nupp core") }
    }};
}
fn encode(ty: SlotTy) -> Value {
    Value(match ty {
        SlotTy::Any => 0,
        SlotTy::Num => 1,
        SlotTy::Str => 2,
        SlotTy::Bool => 3,
        SlotTy::Record(id) => (4u64 << 32) | id as u64,
    })
}
fn decode(word: &Value) -> SlotTy {
    match word.0 {
        0 => SlotTy::Any,
        1 => SlotTy::Num,
        2 => SlotTy::Str,
        3 => SlotTy::Bool,
        n if n >> 32 == 4 => SlotTy::Record(n as u32),
        _ => unreachable!("invalid canonical slot type"),
    }
}
type TypesIter<'a> = std::iter::Map<std::slice::Iter<'a, Value>, fn(&Value) -> SlotTy>;
impl ShapeTypes {
    pub(crate) unsafe fn new(owner: *mut c_void, types: &[SlotTy]) -> Self {
        let mut result = Self(unsafe { ValueArray::new(owner, 0) });
        result.replace(types);
        result
    }
    #[cfg(test)]
    pub(crate) fn words(&self) -> &[Value] {
        &self.0
    }
    pub fn len(&self) -> usize {
        self.0.len()
    }
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
    pub fn at(&self, index: usize) -> SlotTy {
        decode(&self.0[index])
    }
    pub fn iter(&self) -> TypesIter<'_> {
        self.0.iter().map(decode)
    }
    pub fn replace(&mut self, types: &[SlotTy]) {
        // Temporary ABI transport only; canonical storage and replacement
        // policy belong to Nupp, independent of the Rust enum representation.
        let words: Vec<Value> = types.iter().copied().map(encode).collect();
        let status: u64 = native!(nupp_shape_types_replace(
            self,
            words.as_ptr(),
            words.len() as u64
        ));
        assert_eq!(status, 0, "shape type backing refused");
    }
    pub fn set(&mut self, index: usize, ty: SlotTy) {
        let status: u64 = native!(nupp_shape_types_set(self, index as u64, encode(ty).0));
        assert_eq!(status, 0, "invalid shape type index");
    }
}
impl<'a> IntoIterator for &'a ShapeTypes {
    type Item = SlotTy;
    type IntoIter = TypesIter<'a>;
    fn into_iter(self) -> Self::IntoIter {
        self.iter()
    }
}

#[cfg(all(test, feature = "native-runtime"))]
mod tests {
    use super::*;
    use crate::native_allocator::NativeAllocator;

    #[test]
    fn shape_metadata_preserves_text_and_complete_type_words() {
        let owner = NativeAllocator::new();
        let types = [
            SlotTy::Any,
            SlotTy::Num,
            SlotTy::Str,
            SlotTy::Bool,
            SlotTy::Record(0),
            SlotTy::Record(65536),
            SlotTy::Record(u32::MAX),
        ];
        for text in [
            String::new(),
            "x".into(),
            "struct:東京\0🦀".into(),
            "é".repeat(32769),
        ] {
            let (name, hints) = owner.shape_metadata(&text, &types);
            assert_eq!(name.as_bytes(), text.as_bytes());
            assert_eq!(hints.iter().collect::<Vec<_>>(), types);
            assert_eq!(
                hints.0.iter().map(|v| v.0).collect::<Vec<_>>(),
                [0, 1, 2, 3, 0x400000000, 0x400010000, 0x4ffffffff]
            );
        }
        let many = vec![SlotTy::Record(0xffff8001); 8193];
        let (_, mut mapped) = owner.shape_metadata("mapped-types", &many);
        assert_eq!(mapped.iter().collect::<Vec<_>>(), many);
        mapped.replace(&[SlotTy::Bool]);
        assert_eq!(mapped.at(0), SlotTy::Bool);
        let (_, empty) = owner.shape_metadata("", &[]);
        assert!(empty.is_empty());
    }

    #[test]
    fn shape_types_replace_refuses_atomically_and_copies_aliased_source() {
        let owner = NativeAllocator::new();
        let (_, mut hints) =
            owner.shape_metadata("types", &[SlotTy::Any, SlotTy::Record(u32::MAX)]);
        let pointer = hints.0.as_ptr();
        let before = hints.iter().collect::<Vec<_>>();
        for word in [4, 1 << 32, 5 << 32, u64::MAX, Value::NIL.0] {
            let source = [Value(1), Value(word)];
            assert_eq!(
                unsafe { nupp_shape_types_replace(&mut hints, source.as_ptr(), 2) },
                1
            );
            assert_eq!(hints.0.as_ptr(), pointer);
            assert_eq!(hints.iter().collect::<Vec<_>>(), before);
        }
        for (source, count) in [(std::ptr::null(), 1), (pointer, u64::MAX)] {
            assert_eq!(
                unsafe { nupp_shape_types_replace(&mut hints, source, count) },
                1
            );
            assert_eq!(hints.0.as_ptr(), pointer);
        }
        assert_eq!(unsafe { nupp_shape_types_set(&mut hints, 2, 0) }, 1);
        assert_eq!(unsafe { nupp_shape_types_set(&mut hints, 0, 4) }, 1);
        assert_eq!(hints.iter().collect::<Vec<_>>(), before);
        assert_eq!(
            unsafe { nupp_shape_types_replace(&mut hints, pointer, 2) },
            0
        );
        assert_eq!(hints.iter().collect::<Vec<_>>(), before);
        hints.set(0, SlotTy::Bool);
        assert_eq!(hints.at(0), SlotTy::Bool);
        hints.replace(&[]);
        assert!(hints.is_empty());
    }
}
