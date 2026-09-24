//! The loader for a relocation-free image: map, copy, fill the import slots,
//! protect code and slots separately, flush, and -- for frames an unwinder
//! must cross -- register one FDE with the platform unwinder.

use crate::asm::Layout;
use crate::emit::Frame;
use gimli::write::{Address, CallFrameInstruction, CommonInformationEntry, EhFrame, EndianVec, FrameDescriptionEntry, FrameTable};
use gimli::{Encoding, Format, LittleEndian, Register};

pub struct Image {
    base: *mut u8,
    len: usize,
    /// The registered .eh_frame bytes; must outlive the registration.
    eh_frame: Option<Vec<u8>>,
    fde: *const u8,
}

unsafe extern "C" {
    fn sys_icache_invalidate(start: *mut libc::c_void, len: libc::size_t);
    fn __register_frame(fde: *const u8);
    fn __deregister_frame(fde: *const u8);
}

/// CIE + one FDE for the standard prologue, written by gimli.
fn eh_frame(base: u64, code_len: u32, frame: &Frame) -> (Vec<u8>, usize) {
    let encoding = Encoding { format: Format::Dwarf32, version: 1, address_size: 8 };
    let mut cie = CommonInformationEntry::new(encoding, 4, -8, Register(30));
    cie.add_instruction(CallFrameInstruction::Cfa(Register(31), 0));
    let mut table = FrameTable::default();
    let cie_id = table.add_cie(cie);
    let mut fde = FrameDescriptionEntry::new(Address::Constant(base), code_len);
    // After `stp x29, x30, [sp, #-16]!`.
    fde.add_instruction(4, CallFrameInstruction::CfaOffset(16));
    fde.add_instruction(4, CallFrameInstruction::Offset(Register(29), -16));
    fde.add_instruction(4, CallFrameInstruction::Offset(Register(30), -8));
    // After `mov x29, sp`.
    fde.add_instruction(8, CallFrameInstruction::CfaRegister(Register(29)));
    for (reg, off) in &frame.saved {
        fde.add_instruction(frame.prologue_end, CallFrameInstruction::Offset(Register(*reg), *off));
    }
    table.add_fde(cie_id, fde);
    let mut out = EhFrame(EndianVec::new(LittleEndian));
    table.write_eh_frame(&mut out).unwrap();
    let mut bytes = out.0.into_vec();
    let cie_len = u32::from_le_bytes(bytes[0..4].try_into().unwrap()) as usize + 4;
    bytes.extend_from_slice(&[0, 0, 0, 0]); // terminator
    (bytes, cie_len)
}

impl Image {
    pub fn load(code: &[u8]) -> Image {
        let layout = Layout { bytes: code.to_vec(), code_len: code.len(), slots_offset: code.len(), slots: 0 };
        Image::load_with(&layout, &[], None)
    }

    pub fn load_with(layout: &Layout, imports: &[usize], frame: Option<&Frame>) -> Image {
        assert_eq!(imports.len(), layout.slots);
        let len = (layout.bytes.len() + 16383) & !16383;
        unsafe {
            let base = libc::mmap(
                std::ptr::null_mut(),
                len,
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_PRIVATE | libc::MAP_ANON,
                -1,
                0,
            );
            assert!(base != libc::MAP_FAILED);
            let bytes = base as *mut u8;
            std::ptr::copy_nonoverlapping(layout.bytes.as_ptr(), bytes, layout.bytes.len());
            for (k, addr) in imports.iter().enumerate() {
                (bytes.add(layout.slots_offset + 8 * k) as *mut usize).write(*addr);
            }
            let code_pages = if layout.slots == 0 { len } else { layout.slots_offset };
            assert_eq!(libc::mprotect(base, code_pages, libc::PROT_READ | libc::PROT_EXEC), 0);
            if code_pages < len {
                let slots = bytes.add(code_pages) as *mut libc::c_void;
                assert_eq!(libc::mprotect(slots, len - code_pages, libc::PROT_READ), 0);
            }
            sys_icache_invalidate(base, layout.code_len);
            let mut image = Image { base: bytes, len, eh_frame: None, fde: std::ptr::null() };
            if let Some(frame) = frame {
                let (eh, fde_offset) = eh_frame(bytes as u64, layout.code_len as u32, frame);
                image.eh_frame = Some(eh);
                // Darwin's libunwind registers one FDE per call.
                image.fde = image.eh_frame.as_ref().unwrap().as_ptr().add(fde_offset);
                __register_frame(image.fde);
            }
            image
        }
    }

    pub fn entry(&self) -> *const u8 {
        self.base
    }
}

impl Drop for Image {
    fn drop(&mut self) {
        unsafe {
            if !self.fde.is_null() {
                __deregister_frame(self.fde);
            }
            libc::munmap(self.base as *mut libc::c_void, self.len);
        }
    }
}
