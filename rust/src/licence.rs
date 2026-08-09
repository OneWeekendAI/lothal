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

#[derive(GodotClass)]
#[class(no_init, base=RefCounted)]
pub struct Licence;

#[godot_api]
impl Licence {
    /// RSA PKCS#1 v1.5 over SHA-256 of the EXACT payload bytes, against a PKCS#8 public key
    /// PEM. Returns false on every failure — bad key, bad signature, unreadable input — so the
    /// caller fails closed. The licence_check.gd test suite mutation-tests every path.
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
