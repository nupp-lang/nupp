#![cfg(all(feature = "compiled-runtime", target_pointer_width = "64"))]

use nupp_vm::compiled::{
    AOT_ABI, LINKED_TABLE_ENTRIES, LINKED_TABLE_MAPS, LINKED_TABLE_PCS, LINKED_TABLE_SIZE,
    LinkedTable,
};

fn table(entries: &[u64], maps: &[u8]) -> LinkedTable {
    LinkedTable {
        abi: AOT_ABI as u64,
        hash: [37; 32],
        count: (entries.len() / 3) as u64,
        entries: entries.as_ptr(),
        maps_len: maps.len() as u64,
        maps: maps.as_ptr(),
        pcs_len: 0,
        pcs: std::ptr::null(),
    }
}
fn bytes(words: &[u32]) -> Vec<u8> {
    words.iter().flat_map(|n| n.to_le_bytes()).collect()
}
fn valid_words() -> Vec<u32> {
    vec![2, 7, 96, 1, 24, 32, 2, 0, 8, 12, 48, 0]
}
const ENTRIES: [u64; 6] = [7, 0x1000, 96, 12, 0x2000, 48];

#[test]
fn linked_program_table_matches_the_emitter_and_c_entry_layout() {
    assert_eq!(std::mem::size_of::<LinkedTable>(), LINKED_TABLE_SIZE);
    assert_eq!(LINKED_TABLE_SIZE, 88);
    assert_eq!(std::mem::align_of::<LinkedTable>(), 8);
    assert_eq!(std::mem::offset_of!(LinkedTable, abi), 0);
    assert_eq!(std::mem::offset_of!(LinkedTable, hash), 8);
    assert_eq!(std::mem::offset_of!(LinkedTable, count), 40);
    assert_eq!(
        std::mem::offset_of!(LinkedTable, entries),
        LINKED_TABLE_ENTRIES
    );
    assert_eq!(std::mem::offset_of!(LinkedTable, maps_len), 56);
    assert_eq!(std::mem::offset_of!(LinkedTable, maps), LINKED_TABLE_MAPS);
    assert_eq!(std::mem::offset_of!(LinkedTable, pcs_len), 72);
    assert_eq!(std::mem::offset_of!(LinkedTable, pcs), LINKED_TABLE_PCS);
}

#[test]
fn linked_program_table_preserves_sparse_ids_hash_and_gc_zero_offsets() {
    let maps = bytes(&valid_words());
    let decoded = unsafe { table(&ENTRIES, &maps).read() }.unwrap();
    assert_eq!(decoded.hash, [37; 32]);
    assert_eq!(decoded.entries, vec![(7, 0x1000), (12, 0x2000)]);
    assert_eq!(
        decoded.maps,
        vec![
            (0x1000, 96, vec![(24, 32, vec![0, 8])]),
            (0x2000, 48, vec![])
        ]
    );
}

#[test]
fn empty_weak_program_table_never_dereferences_null_storage() {
    let header = LinkedTable {
        abi: 0,
        hash: [0; 32],
        count: 0,
        entries: std::ptr::null(),
        maps_len: 0,
        maps: std::ptr::null(),
        pcs_len: 0,
        pcs: std::ptr::null(),
    };
    let decoded = unsafe { header.read() }.unwrap();
    assert!(decoded.entries.is_empty());
    assert!(decoded.maps.is_empty());
}

#[test]
fn linked_program_table_checks_abi_even_with_no_entries() {
    let maps = bytes(&[0]);
    let mut header = table(&[], &maps);
    header.abi = 3;
    assert!(
        unsafe { header.read() }
            .err()
            .unwrap()
            .contains("ABI mismatch")
    );
    header.abi = AOT_ABI as u64;
    assert!(unsafe { header.read() }.is_ok());
}

#[test]
fn linked_program_table_rejects_counts_and_pointers_before_dereference() {
    let maps = bytes(&valid_words());
    let mut header = table(&ENTRIES, &maps);
    header.count = u64::MAX;
    assert!(unsafe { header.read() }.is_err());
    header.count = 2;
    header.entries = std::ptr::null();
    assert!(unsafe { header.read() }.is_err());
    header.entries = 1usize as *const u64;
    assert!(unsafe { header.read() }.is_err());
    header.entries = ENTRIES.as_ptr();
    header.maps_len = u64::MAX;
    assert!(unsafe { header.read() }.is_err());
    header.maps_len = maps.len() as u64;
    header.maps = std::ptr::null();
    assert!(unsafe { header.read() }.is_err());
}

#[test]
fn linked_program_table_rejects_duplicate_ids_addresses_and_bad_ranges() {
    let maps = bytes(&valid_words());
    for entries in [
        [7, 0x1000, 96, 7, 0x2000, 48],
        [7, 0x1000, 96, 12, 0x1000, 48],
        [7, 0, 96, 12, 0x2000, 48],
        [7, 0x1000, 0, 12, 0x2000, 48],
        [7, u64::MAX - 4, 96, 12, 0x2000, 48],
    ] {
        assert!(unsafe { table(&entries, &maps).read() }.is_err());
    }
}

#[test]
fn linked_program_table_rejects_truncated_trailing_and_inconsistent_maps() {
    let maps = bytes(&valid_words());
    for end in 0..maps.len() {
        assert!(unsafe { table(&ENTRIES, &maps[..end]).read() }.is_err());
    }
    let mut trailing = maps.clone();
    trailing.push(0);
    assert!(unsafe { table(&ENTRIES, &trailing).read() }.is_err());
    for (at, value) in [
        (0, 1),
        (1, 99),
        (2, 95),
        (3, u32::MAX),
        (4, 96),
        (5, 0),
        (6, u32::MAX),
        (7, 32),
        (8, 3),
        (9, 7),
    ] {
        let mut words = valid_words();
        words[at] = value;
        assert!(
            unsafe { table(&ENTRIES, &bytes(&words)).read() }.is_err(),
            "accepted word{at}={value}"
        );
    }
}

#[test]
fn linked_program_table_reserves_empty_source_pc_metadata() {
    let maps = bytes(&valid_words());
    let pcs = [0u8; 4];
    let mut header = table(&ENTRIES, &maps);
    header.pcs_len = 4;
    header.pcs = pcs.as_ptr();
    assert!(
        unsafe { header.read() }
            .err()
            .unwrap()
            .contains("source-PC")
    );
}
