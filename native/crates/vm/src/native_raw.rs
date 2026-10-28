//! Memory-only transport for the S0 native backend experiment.
//! Nupp supplies code, data, entry shims and every relocation. This module
//! neither reads machine instructions nor compiles or patches them.
use cranelift_jit::{BranchProtection, JITMemoryKind, JITMemoryProvider, SystemMemoryProvider};

/// The only architecture accepted by the first native backend experiment.
pub const ARCHITECTURE: &str = "aarch64";
/// The fixed call packet version, independent of the runtime object ABI.
pub const CALL_ABI: u64 = 1;

/// Metadata supplied independently of the opaque machine-code bytes.
pub struct ImageSpec<'a> {
    pub architecture: &'a str,
    pub layout_digest: [u8; 32],
    pub entry: usize,
}

struct Memory(SystemMemoryProvider);
impl Drop for Memory {
    fn drop(&mut self) {
        unsafe { self.0.free_memory() }
    }
}

/// Writable storage, not yet callable. Relocations and import slots belong
/// to the Nupp producer, which may fill these slices before publication.
pub struct PendingImage {
    memory: Memory,
    code: *mut u8,
    code_len: usize,
    data: *mut u8,
    data_len: usize,
    imports: *mut usize,
    imports_len: usize,
    entry: usize,
}

fn validate(
    spec: &ImageSpec<'_>,
    expected: &[u8; 32],
    code: usize,
    data: usize,
    imports: usize,
) -> Result<(), String> {
    if spec.architecture != ARCHITECTURE
        || std::env::consts::ARCH != ARCHITECTURE
        || !cfg!(target_endian = "little")
    {
        return Err("raw image requires a little-endian aarch64 host and image".into());
    }
    if &spec.layout_digest != expected {
        return Err("raw image layout digest differs from the host".into());
    }
    if code == 0 || code % 4 != 0 || spec.entry % 4 != 0 || spec.entry >= code {
        return Err("raw image code and entry require complete aligned ARM64 instructions".into());
    }
    // Leave room for the provider's page rounding, and reject pointer-sized
    // arithmetic overflow before asking it to allocate anything.
    let limit = isize::MAX as usize / 2;
    if code > limit || data > limit || imports.checked_mul(8).is_none_or(|n| n > limit) {
        return Err("raw image extent exceeds addressable storage".into());
    }
    Ok(())
}

impl PendingImage {
    pub fn new(
        spec: ImageSpec<'_>,
        expected_layout: &[u8; 32],
        code: &[u8],
        data: &[u8],
        imports: &[usize],
    ) -> Result<Self, String> {
        validate(
            &spec,
            expected_layout,
            code.len(),
            data.len(),
            imports.len(),
        )?;
        let mut memory = Memory(SystemMemoryProvider::new());
        let mut allocate =
            |size, kind| memory.0.allocate(size, 16, kind).map_err(|e| e.to_string());
        let code_ptr = allocate(code.len(), JITMemoryKind::Executable)?;
        let data_ptr = allocate(data.len().max(1), JITMemoryKind::ReadOnly)?;
        let imports_ptr = allocate(
            std::mem::size_of_val(imports).max(1),
            JITMemoryKind::ReadOnly,
        )?
        .cast::<usize>();
        unsafe {
            std::ptr::copy_nonoverlapping(code.as_ptr(), code_ptr, code.len());
            std::ptr::copy_nonoverlapping(data.as_ptr(), data_ptr, data.len());
            std::ptr::copy_nonoverlapping(imports.as_ptr(), imports_ptr, imports.len());
        }
        Ok(Self {
            memory,
            code: code_ptr,
            code_len: code.len(),
            data: data_ptr,
            data_len: data.len(),
            imports: imports_ptr,
            imports_len: imports.len(),
            entry: spec.entry,
        })
    }

    pub fn code_mut(&mut self) -> &mut [u8] {
        unsafe { std::slice::from_raw_parts_mut(self.code, self.code_len) }
    }
    pub fn data_mut(&mut self) -> &mut [u8] {
        unsafe { std::slice::from_raw_parts_mut(self.data, self.data_len) }
    }
    /// Addresses for the producer's own relocation calculations. These are
    /// opaque integers; dereferencing them remains the producer's obligation.
    pub fn bases(&self) -> [usize; 3] {
        [
            self.code as usize,
            self.data as usize,
            self.imports as usize,
        ]
    }

    /// Publish code as RX and data/imports as read-only, including the memory
    /// provider's instruction-cache and cross-thread pipeline flushes.
    pub fn seal(mut self) -> Result<Image, String> {
        self.memory
            .0
            .finalize(BranchProtection::None)
            .map_err(|e| e.to_string())?;
        Ok(Image { pending: self })
    }
}

/// Published immutable code and data. Dropping it unmaps all three regions;
/// callers must retain it while any generated address can still be used.
pub struct Image {
    pending: PendingImage,
}

// Publication makes all storage immutable. Executing an entry is unsafe and
// still requires the caller to uphold its imports' threading contracts.
unsafe impl Send for Image {}
unsafe impl Sync for Image {}

impl Image {
    pub(crate) fn contains_entry(&self, address: usize) -> bool {
        address % 4 == 0
            && address
                .checked_sub(self.pending.code as usize)
                .is_some_and(|offset| offset < self.pending.code_len)
    }
    /// Invoke the Nupp-produced C entry shim. Its first argument points to ten
    /// u64 words: call ABI, code base/length, data base/length, import table
    /// base/count, input base/count and output count. Its second argument is
    /// the output buffer. No scalar signature or relocation is interpreted.
    ///
    /// # Safety
    /// Code must implement that C ABI and respect all supplied extents. It
    /// must not unwind, retain call-local pointers, or outlive this image.
    /// Imported addresses and any pointers in input words must remain valid.
    /// The entry shim owns all register saves, arena frames and native calls.
    pub unsafe fn call(&self, words: &[u64], out: &mut [u64]) {
        let image = &self.pending;
        let packet = [
            CALL_ABI,
            image.code as u64,
            image.code_len as u64,
            image.data as u64,
            image.data_len as u64,
            image.imports as u64,
            image.imports_len as u64,
            words.as_ptr() as u64,
            words.len() as u64,
            out.len() as u64,
        ];
        let entry: unsafe extern "C" fn(*const u64, *mut u64) =
            unsafe { std::mem::transmute(image.code.add(image.entry)) };
        unsafe { entry(packet.as_ptr(), out.as_mut_ptr()) }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn raw_image_rejects_foreign_architecture_before_allocation() {
        let spec = ImageSpec {
            architecture: "x86_64",
            layout_digest: [0; 32],
            entry: 0,
        };
        assert!(
            validate(&spec, &[0; 32], 4, 0, 0)
                .unwrap_err()
                .contains("aarch64")
        );
    }

    #[test]
    #[cfg(all(target_arch = "aarch64", target_endian = "little"))]
    fn raw_image_rejects_layout_alignment_and_extent_mismatches() {
        let mut spec = ImageSpec {
            architecture: ARCHITECTURE,
            layout_digest: [1; 32],
            entry: 0,
        };
        assert!(
            validate(&spec, &[0; 32], 4, 0, 0)
                .unwrap_err()
                .contains("digest")
        );
        spec.layout_digest = [0; 32];
        for (code, entry) in [(0, 0), (3, 0), (4, 1), (4, 4), (4, usize::MAX)] {
            spec.entry = entry;
            assert!(validate(&spec, &[0; 32], code, 0, 0).is_err());
        }
        spec.entry = 0;
        assert!(validate(&spec, &[0; 32], 4, usize::MAX, 0).is_err());
        assert!(validate(&spec, &[0; 32], 4, 0, usize::MAX).is_err());
        assert!(validate(&spec, &[0; 32], 4, 0, 0).is_ok());
    }
}
