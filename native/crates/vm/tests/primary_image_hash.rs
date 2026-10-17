use nupp_vm::{
    image,
    interp::Interp,
    persist::{self, Policies, ResourceCodecs},
};
use sha2::{Digest, Sha256};

const IMAGE: &str = "function answer 0 0 4 1 :v\nconst 0 num 42\nK 1 0\nRet 1\nend\nentry 0\n";

#[test]
fn primary_image_hash_requires_an_image_before_globals() {
    let mut vm = Interp::new();
    let expected = "linked code requires an image loaded before runtime globals";
    assert_eq!(persist::primary_image_hash(&vm).unwrap_err(), expected);
    vm.install_globals();
    image::load(&mut vm, IMAGE).unwrap();
    assert_eq!(persist::primary_image_hash(&vm).unwrap_err(), expected);
}

#[test]
fn primary_image_identity_is_raw_and_survives_append_and_checkpoint() {
    let source = IMAGE
        .replace("answer", "answerλ🦀\0é")
        .replace('\n', "\r\n");
    let expected: [u8; 32] = Sha256::digest(source.as_bytes()).into();
    let mut vm = Interp::new();
    image::load(&mut vm, &source).unwrap();
    assert_eq!(persist::primary_image_hash(&vm).unwrap(), expected);
    vm.install_globals();
    image::load(&mut vm, IMAGE).unwrap();
    assert_eq!(persist::primary_image_hash(&vm).unwrap(), expected);
    let bytes =
        persist::save_vm(&mut vm, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    let mut restored =
        persist::load_vm(&bytes, &Policies::default(), &mut ResourceCodecs::new()).unwrap();
    assert_eq!(persist::primary_image_hash(&restored).unwrap(), expected);
    restored.full_cycle();
    restored.check_oracle();
}

// The correctness driver pins the authoritative image and manifest digest.
// The fixture remains external instead of committing a compiler image.
#[test]
#[ignore = "requires pinned NUPP_PRIMARY_HASH_IMAGE and NUPP_PRIMARY_HASH_EXPECTED"]
fn current_compiler_image_matches_its_linked_raw_digest() {
    let path = std::env::var_os("NUPP_PRIMARY_HASH_IMAGE").expect("pinned image path");
    let expected_hex = std::env::var("NUPP_PRIMARY_HASH_EXPECTED").expect("pinned raw digest");
    assert_eq!(expected_hex.len(), 64);
    let source = std::fs::read_to_string(path).unwrap();
    let expected: [u8; 32] = Sha256::digest(source.as_bytes()).into();
    let hex: String = expected.iter().map(|byte| format!("{byte:02x}")).collect();
    assert_eq!(
        hex, expected_hex,
        "actual fixture must match its pinned manifest"
    );
    let mut vm = Interp::new();
    image::load(&mut vm, &source).unwrap();
    assert_eq!(persist::primary_image_hash(&vm).unwrap(), expected);
}
