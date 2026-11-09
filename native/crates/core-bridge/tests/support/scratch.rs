//! Test-only guard pages and an opaque producer-supplied high-water canary.
use super::platform;
use std::ffi::c_void;

unsafe extern "C" {
    fn mprotect(address: *mut c_void, length: usize, protection: i32) -> i32;
}

pub(super) struct Mapping {
    pub address: *mut u8,
    base: u64,
    total: u64,
    rounded: usize,
    high_water: usize,
}

impl Mapping {
    pub fn new(bytes: usize) -> Result<Self, String> {
        // Zero-sized refusal fixtures need no mapping and no canary.
        if bytes == 0 {
            return Self::with_high_water(0, None);
        }
        let high_water = std::env::var("CORE_TEST_HIGH_WATER")
            .ok()
            .map(|text| {
                text.parse::<usize>()
                    .map_err(|_| "invalid CORE_TEST_HIGH_WATER".to_string())
            })
            .transpose()?;
        Self::with_high_water(bytes, high_water)
    }

    fn with_high_water(bytes: usize, high_water: Option<usize>) -> Result<Self, String> {
        let high_water = high_water.unwrap_or(bytes);
        if high_water > bytes {
            return Err("test high-water exceeds scratch extent".into());
        }
        if bytes == 0 {
            return Ok(Self {
                address: std::ptr::null_mut(),
                base: 0,
                total: 0,
                rounded: 0,
                high_water: 0,
            });
        }
        let page = platform::page_size() as usize;
        let rounded = bytes.checked_add(page - 1).ok_or("guard extent overflow")? & !(page - 1);
        let total = rounded
            .checked_add(page * 2)
            .ok_or("guard extent overflow")? as u64;
        let base = platform::map_pages(total);
        if base == 0 {
            return Err("test guarded mapping failed".into());
        }
        let result = Self {
            address: (base as usize + page) as *mut u8,
            base,
            total,
            rounded,
            high_water,
        };
        for address in [base as usize, base as usize + page + rounded] {
            if unsafe { mprotect(address as *mut c_void, page, 0) } != 0 {
                return Err(format!(
                    "test guard protection failed: {}",
                    std::io::Error::last_os_error()
                ));
            }
        }
        // No interpretation of Nupp context/frame/window fields: the producer
        // supplies one byte extent, and every later byte must remain untouched.
        unsafe {
            std::ptr::write_bytes(result.address.add(high_water), 0xa5, rounded - high_water);
        }
        Ok(result)
    }

    pub fn verify(&self) -> Result<(), String> {
        if self.rounded == 0 {
            return Ok(());
        }
        let canary = unsafe {
            std::slice::from_raw_parts(
                self.address.add(self.high_water),
                self.rounded - self.high_water,
            )
        };
        if let Some(offset) = canary.iter().position(|byte| *byte != 0xa5) {
            return Err(format!(
                "scratch high-water canary changed at byte {}",
                self.high_water + offset
            ));
        }
        Ok(())
    }
}

impl Drop for Mapping {
    fn drop(&mut self) {
        if self.total != 0 {
            unsafe {
                platform::unmap_pages(self.base, self.total);
            }
        }
    }
}

#[test]
fn guarded_scratch_preserves_zeroed_usable_bytes_and_canary() {
    let region = Mapping::with_high_water(65536, Some(8480)).unwrap();
    assert_eq!(region.address as usize % platform::page_size() as usize, 0);
    assert!(
        unsafe { std::slice::from_raw_parts(region.address, 8480) }
            .iter()
            .all(|byte| *byte == 0)
    );
    region.verify().unwrap();
    unsafe {
        *region.address.add(8480) = 0;
    }
    assert_eq!(
        region.verify().unwrap_err(),
        "scratch high-water canary changed at byte 8480"
    );
}

#[test]
fn scratch_page_padding_is_also_canaried() {
    let region = Mapping::with_high_water(1, None).unwrap();
    unsafe {
        *region.address = 7;
    }
    region.verify().unwrap();
    unsafe {
        *region.address.add(1) = 0;
    }
    assert_eq!(
        region.verify().unwrap_err(),
        "scratch high-water canary changed at byte 1"
    );
    assert!(Mapping::with_high_water(31, Some(32)).is_err());
    Mapping::with_high_water(0, None).unwrap().verify().unwrap();
}
