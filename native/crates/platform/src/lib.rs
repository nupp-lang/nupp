//! Native facilities that require no asynchronous executor.

use std::sync::OnceLock;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
#[cfg(feature = "uuid")]
use uuid::Uuid;

const P1: u64 = 0x9E37_79B1_85EB_CA87;
const P2: u64 = 0xC2B2_AE3D_27D4_EB4F;
const P3: u64 = 0x1656_67B1_9E37_79F9;
const P4: u64 = 0x85EB_CA77_C2B2_AE63;
const P5: u64 = 0x27D4_EB2F_1656_67C5;
const SECOND_SEED: u64 = 0x9E37_79B9_7F4A_7C15;

pub fn monotonic_ns() -> u64 {
    static START: OnceLock<Instant> = OnceLock::new();
    let elapsed = START.get_or_init(Instant::now).elapsed().as_nanos();
    elapsed.min(u128::from(u64::MAX)) as u64
}

pub fn wall_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or(Duration::ZERO)
        .as_millis()
        .min(u128::from(u64::MAX)) as u64
}

pub fn sleep_ms(milliseconds: u64) {
    std::thread::sleep(Duration::from_millis(milliseconds));
}

#[cfg(feature = "uuid")]
pub fn uuid4() -> String {
    Uuid::new_v4().hyphenated().to_string()
}

#[cfg(feature = "uuid")]
pub fn uuid7() -> String {
    Uuid::now_v7().hyphenated().to_string()
}

pub fn xxh64(bytes: &[u8], seed: u64) -> u64 {
    let mut at = 0;
    let mut hash = if bytes.len() >= 32 {
        let mut v1 = seed.wrapping_add(P1).wrapping_add(P2);
        let mut v2 = seed.wrapping_add(P2);
        let mut v3 = seed;
        let mut v4 = seed.wrapping_sub(P1);
        while at <= bytes.len() - 32 {
            v1 = round(v1, read64(&bytes[at..]));
            v2 = round(v2, read64(&bytes[at + 8..]));
            v3 = round(v3, read64(&bytes[at + 16..]));
            v4 = round(v4, read64(&bytes[at + 24..]));
            at += 32;
        }
        let mut value = v1
            .rotate_left(1)
            .wrapping_add(v2.rotate_left(7))
            .wrapping_add(v3.rotate_left(12))
            .wrapping_add(v4.rotate_left(18));
        value = merge(value, v1);
        value = merge(value, v2);
        value = merge(value, v3);
        merge(value, v4)
    } else {
        seed.wrapping_add(P5)
    };
    hash = hash.wrapping_add(bytes.len() as u64);
    while at + 8 <= bytes.len() {
        hash ^= round(0, read64(&bytes[at..]));
        hash = hash.rotate_left(27).wrapping_mul(P1).wrapping_add(P4);
        at += 8;
    }
    if at + 4 <= bytes.len() {
        hash ^= u64::from(read32(&bytes[at..])).wrapping_mul(P1);
        hash = hash.rotate_left(23).wrapping_mul(P2).wrapping_add(P3);
        at += 4;
    }
    while at < bytes.len() {
        hash ^= u64::from(bytes[at]).wrapping_mul(P5);
        hash = hash.rotate_left(11).wrapping_mul(P1);
        at += 1;
    }
    hash ^= hash >> 33;
    hash = hash.wrapping_mul(P2);
    hash ^= hash >> 29;
    hash = hash.wrapping_mul(P3);
    hash ^ (hash >> 32)
}

pub fn cache_digest(bytes: &[u8]) -> [u8; 32] {
    let mut output = [0; 32];
    write_hex(&mut output[..16], xxh64(bytes, 0));
    write_hex(&mut output[16..], xxh64(bytes, SECOND_SEED));
    output
}

pub fn trailer_digest(bytes: &[u8]) -> [u8; 8] {
    xxh64(bytes, 0).to_le_bytes()
}

fn round(lane: u64, input: u64) -> u64 {
    lane.wrapping_add(input.wrapping_mul(P2))
        .rotate_left(31)
        .wrapping_mul(P1)
}

fn merge(hash: u64, lane: u64) -> u64 {
    (hash ^ round(0, lane)).wrapping_mul(P1).wrapping_add(P4)
}

fn read64(bytes: &[u8]) -> u64 {
    u64::from_le_bytes(bytes[..8].try_into().expect("eight-byte slice"))
}

fn read32(bytes: &[u8]) -> u32 {
    u32::from_le_bytes(bytes[..4].try_into().expect("four-byte slice"))
}

fn write_hex(output: &mut [u8], mut value: u64) {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    for byte in output.iter_mut().rev() {
        *byte = DIGITS[(value & 0xf) as usize];
        value >>= 4;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn xxh64_matches_published_vectors() {
        assert_eq!(xxh64(b"", 0), 0xef46_db37_51d8_e999);
        assert_eq!(xxh64(b"abc", 0), 0x44bc_2cf5_ad77_0999);
        assert_eq!(&cache_digest(b"")[..16], b"ef46db3751d8e999");
        assert_eq!(trailer_digest(b""), 0xef46_db37_51d8_e999_u64.to_le_bytes());
    }

    #[test]
    #[cfg(feature = "uuid")]
    fn uuids_have_the_selected_versions_and_variant() {
        let four = Uuid::parse_str(&uuid4()).unwrap();
        let seven = Uuid::parse_str(&uuid7()).unwrap();
        assert_eq!(four.get_version_num(), 4);
        assert_eq!(seven.get_version_num(), 7);
        assert_eq!(four.as_bytes()[8] & 0xc0, 0x80);
        assert_eq!(seven.as_bytes()[8] & 0xc0, 0x80);
    }

    #[test]
    fn clocks_have_explicit_units() {
        let before = monotonic_ns();
        sleep_ms(1);
        assert!(monotonic_ns() >= before);
        assert!(wall_ms() > 1_500_000_000_000);
    }
}
