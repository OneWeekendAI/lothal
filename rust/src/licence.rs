//! The activation gate's signature verification, fused into the crate (design §5(a)).
//!
//! GDScript (src/app/licence_check.gd) keeps the envelope/payload parsing, the key_id map,
//! the email plausibility check, the Result object and store()/clear(). What moved here is the
//! one piece that must not ship as plain text: the RSA verification itself. Ripping out the
//! gate means reimplementing this, which is the point.
//!
//! The offline-verification property survives: this is arithmetic over bytes on disk, no
//! network, and the issuing backend is a one-time service the app never speaks to.

use godot::prelude::*;

use rsa::pkcs1v15::{Signature, VerifyingKey};
use rsa::pkcs8::DecodePublicKey;
use rsa::signature::Verifier;
use rsa::RsaPublicKey;
use sha2::Sha256;

/// The activation trust anchor, embedded at COMPILE TIME.
///
/// It used to be read from `res://keys/activation_public.pem` inside the pck and handed to this
/// module as a parameter. That made the gate's trust anchor a file in an archive: repacking the
/// pck with a different PEM took over verification outright, with no decompiler, no Rust, and no
/// code modification at all — a cheaper attack than the one this whole port exists to raise the
/// cost of. `include_str!` reads the same file the issuing service uses, so there is still
/// exactly one key on disk and no copy to drift; what changes is that the shipped artifact
/// carries it as immutable bytes inside a signed Mach-O rather than as a replaceable resource.
///
/// `key_id` -> PEM. Ids absent from this table are refused. A second entry appears the day the
/// first key is rotated, and the ORDER matters: ship the build containing the new public key
/// first, wait for adoption, and only then issue licences against it. Reversing that strands
/// everyone whose install predates the new key.
const ACTIVATION_PUBLIC_KEYS: &[(i64, &str)] =
    &[(1, include_str!("../../keys/activation_public.pem"))];

fn key_pem_for_id(key_id: i64) -> Option<&'static str> {
    ACTIVATION_PUBLIC_KEYS
        .iter()
        .find(|(id, _)| *id == key_id)
        .map(|(_, pem)| *pem)
}

#[derive(GodotClass)]
#[class(no_init, base=RefCounted)]
pub struct Licence;

#[godot_api]
impl Licence {
    /// Verification against the BAKED-IN key that `key_id` names — the only path production
    /// takes. An unknown id returns false rather than falling back to any key, so a forged
    /// envelope naming key 99 is refused by the same branch that refuses a bad signature.
    #[func]
    fn verify(payload: String, signature_b64: String, key_id: i64) -> bool {
        match key_pem_for_id(key_id) {
            Some(pem) => Self::verify_signature(payload, signature_b64, pem.to_string()),
            None => false,
        }
    }

    /// Whether `key_id` names a key this build carries. GDScript asks rather than keeping its
    /// own copy of the id list, so there is one table and it is the compiled one.
    #[func]
    fn knows_key_id(key_id: i64) -> bool {
        key_pem_for_id(key_id).is_some()
    }

    /// RSA PKCS#1 v1.5 over SHA-256 of the EXACT payload bytes, against a caller-supplied
    /// PKCS#8 public key PEM. Returns false on every failure — bad key, bad signature,
    /// unreadable input — so the caller fails closed.
    ///
    /// PRODUCTION MUST NOT CALL THIS. It exists so the test suite can sign fixtures with a
    /// throwaway pair; `verify()` above is the real entry point and reaches the baked-in key
    /// that no caller can substitute. Passing your own PEM here means verifying against a key
    /// whose private half you hold, which is not verification — the honest name for this
    /// parameter is "which key do you want to be convinced by".
    ///
    /// The signed unit is the payload STRING exactly as it sits in the envelope, never a
    /// re-serialisation of its dictionary — the load-bearing rule from update_check.gd and
    /// licence_check.gd. PKCS#1 v1.5, never RSA-PSS: PSS passes every unit test and rejects
    /// every licence ever issued.
    #[func]
    fn verify_signature(payload: String, signature_b64: String, key_pem: String) -> bool {
        let public_key = match RsaPublicKey::from_public_key_pem(&key_pem) {
            Ok(k) => k,
            Err(_) => return false,
        };
        let mut verifying_key = VerifyingKey::<Sha256>::new(public_key);

        let mut marshalls = godot::classes::Marshalls::singleton();
        let sig_bytes = marshalls.base64_to_raw(&signature_b64);
        if sig_bytes.is_empty() {
            return false;
        }
        let signature = match Signature::try_from(sig_bytes.to_vec().as_slice()) {
            Ok(s) => s,
            Err(_) => return false,
        };

        verifying_key
            .verify(payload.as_bytes(), &signature)
            .is_ok()
    }
}
