//! Mobile-facing wallet FFI surface for Aura Mobile.
//!
//! This module is a thin C ABI wrapper around `aura_wallet`/`aura_core`. It does not implement,
//! derive, or approximate any cryptography of its own: key generation, address derivation, and
//! transaction signing are all delegated to those crates exactly as Aura Desktop uses them.
//!
//! Private key material never crosses this boundary. Callers receive an opaque wallet handle
//! (a raw pointer Swift must treat as unintelligible) and only ever get back public data:
//! addresses, public keys, and signed-transaction bytes/hashes. There is no function anywhere in
//! this module that returns a raw private key or seed once a wallet has been created -- the only
//! place the seed is ever exposed in plaintext is the one-time mnemonic backup returned at
//! creation/restoration time, which the caller is expected to show the user once and then not
//! persist outside the platform's own secure storage.
//!
//! Recovery phrases are standard 24-word BIP39 mnemonics (well-established word list and
//! checksum, via the `bip39` crate). Aura wallets are currently single-key (no HD derivation
//! paths), so the phrase's raw 256-bit entropy is used directly as the Ed25519 seed -- there is
//! no SLIP-10/BIP32 child-key derivation layered on top. This keeps the derivation exactly as
//! auditable as the wallet itself, but it does mean this phrase is Aura-specific: it will not
//! import into a generic multi-coin BIP39/BIP32 wallet and produce the same key.

use aura_core::{Address, Hash256, Network, TransactionBodyV2, TransactionV2};
use aura_wallet::{PermissionStatus, Wallet, WalletPassword};
use bip39::Mnemonic;
use serde::{Deserialize, Serialize};
use std::ffi::{c_void, CStr, CString};
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::str::FromStr;
use zeroize::Zeroizing;

const MNEMONIC_ENTROPY_BYTES: usize = 32;

// ---------------------------------------------------------------------------------------------
// C-string / JSON plumbing
// ---------------------------------------------------------------------------------------------

fn read_c_str(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    // Safety: caller-supplied pointers are only ever read as a NUL-terminated string here, never
    // written through or retained past this call.
    let bytes = unsafe { CStr::from_ptr(ptr) }.to_bytes();
    std::str::from_utf8(bytes).ok().map(str::to_owned)
}

fn read_c_bytes(ptr: *const c_char) -> Option<Vec<u8>> {
    if ptr.is_null() {
        return None;
    }
    // Safety: caller-supplied pointers are read only for the duration of this call. Password
    // bytes are copied directly into an owned buffer that is immediately transferred to
    // `WalletPassword`, whose storage is zeroized on drop.
    Some(unsafe { CStr::from_ptr(ptr) }.to_bytes().to_vec())
}

fn c_string_out(value: String) -> *mut c_char {
    match CString::new(value) {
        Ok(owned) => owned.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

fn write_out_string(out: *mut *mut c_char, value: String) {
    if out.is_null() {
        return;
    }
    // Safety: `out` is a caller-supplied out-parameter slot; it is only ever written once here.
    unsafe {
        *out = c_string_out(value);
    }
}

#[derive(Serialize)]
struct JsonEnvelope<T: Serialize> {
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    data: Option<T>,
}

fn json_ok<T: Serialize>(data: T) -> *mut c_char {
    let envelope = JsonEnvelope {
        ok: true,
        error: None,
        data: Some(data),
    };
    c_string_out(
        serde_json::to_string(&envelope).unwrap_or_else(|_| {
            "{\"ok\":false,\"error\":\"failed to encode response\"}".to_owned()
        }),
    )
}

fn json_err(message: impl Into<String>) -> *mut c_char {
    let envelope = JsonEnvelope::<()> {
        ok: false,
        error: Some(message.into()),
        data: None,
    };
    c_string_out(serde_json::to_string(&envelope).unwrap_or_else(|_| {
        "{\"ok\":false,\"error\":\"failed to encode error response\"}".to_owned()
    }))
}

const FFI_PANIC_MESSAGE: &str = "Rust wallet operation failed safely";

fn catch_ffi_json(operation: impl FnOnce() -> *mut c_char) -> *mut c_char {
    match catch_unwind(AssertUnwindSafe(operation)) {
        Ok(value) => value,
        Err(_) => json_err(FFI_PANIC_MESSAGE),
    }
}

fn catch_ffi_handle(
    out_error: *mut *mut c_char,
    operation: impl FnOnce() -> *mut c_void,
) -> *mut c_void {
    match catch_unwind(AssertUnwindSafe(operation)) {
        Ok(value) => value,
        Err(_) => {
            write_out_string(out_error, FFI_PANIC_MESSAGE.to_owned());
            std::ptr::null_mut()
        }
    }
}

fn catch_ffi_i32(operation: impl FnOnce() -> i32) -> i32 {
    catch_unwind(AssertUnwindSafe(operation)).unwrap_or(0)
}

fn catch_ffi_void(operation: impl FnOnce()) {
    let _ = catch_unwind(AssertUnwindSafe(operation));
}

/// Frees a string returned by any `mira_wallet_*`/`mira_aura_*` function, including the
/// mnemonic and error out-parameters. Passing null is safe and does nothing.
///
/// # Safety
/// `ptr` must be null or a pointer this module previously returned that has not already been
/// freed.
#[no_mangle]
pub unsafe extern "C" fn mira_free_string(ptr: *mut c_char) {
    catch_ffi_void(|| {
        if ptr.is_null() {
            return;
        }
        // Safety: only ever called with a pointer this module itself produced via `CString::into_raw`.
        unsafe {
            drop(CString::from_raw(ptr));
        }
    });
}

// ---------------------------------------------------------------------------------------------
// Network encoding
// ---------------------------------------------------------------------------------------------

fn network_from_u8(value: u8) -> Result<Network, String> {
    match value {
        0 => Ok(Network::Mainnet),
        1 => Ok(Network::Testnet),
        2 => Ok(Network::Devnet),
        other => Err(format!(
            "unknown network code {other}; expected 0 (mainnet), 1 (testnet), or 2 (devnet)"
        )),
    }
}

fn network_name(network: Network) -> &'static str {
    match network {
        Network::Mainnet => "mainnet",
        Network::Testnet => "testnet",
        Network::Devnet => "devnet",
    }
}

// ---------------------------------------------------------------------------------------------
// Wallet lifecycle
// ---------------------------------------------------------------------------------------------

/// Generates a brand-new Aura wallet and its one-time BIP39 backup phrase.
///
/// On success, returns a non-null opaque wallet handle (release it with `mira_wallet_free`) and
/// writes a freshly generated 24-word mnemonic into `*out_mnemonic` (release it with
/// `mira_free_string`). On failure, returns null and writes an error message into
/// `*out_mnemonic` instead -- callers should check for a null handle, not for a null message.
///
/// `network` is 0 (mainnet), 1 (testnet), or 2 (devnet).
///
/// # Safety
/// `out_mnemonic` must be null or point to a valid, writable `*mut c_char` slot.
#[no_mangle]
pub unsafe extern "C" fn mira_wallet_create(
    network: u8,
    out_mnemonic: *mut *mut c_char,
) -> *mut c_void {
    catch_ffi_handle(out_mnemonic, || {
        let network = match network_from_u8(network) {
            Ok(network) => network,
            Err(message) => {
                write_out_string(out_mnemonic, message);
                return std::ptr::null_mut();
            }
        };

        let mut seed = Zeroizing::new([0_u8; MNEMONIC_ENTROPY_BYTES]);
        if let Err(error) = getrandom_fill(&mut seed) {
            write_out_string(
                out_mnemonic,
                format!("could not generate wallet entropy: {error}"),
            );
            return std::ptr::null_mut();
        }

        let mnemonic = match Mnemonic::from_entropy(seed.as_slice()) {
            Ok(mnemonic) => mnemonic,
            Err(error) => {
                write_out_string(
                    out_mnemonic,
                    format!("could not encode recovery phrase: {error}"),
                );
                return std::ptr::null_mut();
            }
        };

        let wallet = Wallet::from_seed_bytes(network, *seed);
        write_out_string(out_mnemonic, mnemonic.to_string());
        Box::into_raw(Box::new(wallet)) as *mut c_void
    })
}

/// Restores a wallet from its 24-word BIP39 recovery phrase.
///
/// On success, returns a non-null opaque wallet handle and leaves `*out_error` untouched.
/// On failure (invalid phrase, wrong word count, bad checksum, or an unknown network code),
/// returns null and writes an error message into `*out_error` (release it with
/// `mira_free_string`).
///
/// # Safety
/// `mnemonic` must be null or a valid, NUL-terminated C string. `out_error` must be null or
/// point to a valid, writable `*mut c_char` slot.
#[no_mangle]
pub unsafe extern "C" fn mira_wallet_restore_from_mnemonic(
    mnemonic: *const c_char,
    network: u8,
    out_error: *mut *mut c_char,
) -> *mut c_void {
    catch_ffi_handle(out_error, || {
        let network = match network_from_u8(network) {
            Ok(network) => network,
            Err(message) => {
                write_out_string(out_error, message);
                return std::ptr::null_mut();
            }
        };

        let Some(phrase) = read_c_str(mnemonic) else {
            write_out_string(
                out_error,
                "recovery phrase must be valid UTF-8 text".to_owned(),
            );
            return std::ptr::null_mut();
        };
        let phrase = Zeroizing::new(phrase);

        let mnemonic = match Mnemonic::parse_normalized(phrase.trim()) {
            Ok(mnemonic) => mnemonic,
            Err(error) => {
                write_out_string(out_error, format!("recovery phrase is invalid: {error}"));
                return std::ptr::null_mut();
            }
        };

        let entropy = mnemonic.to_entropy();
        let Ok(seed): Result<[u8; MNEMONIC_ENTROPY_BYTES], _> = entropy.try_into() else {
            write_out_string(
                out_error,
                "recovery phrase must be the 24-word Aura format (256 bits of entropy)".to_owned(),
            );
            return std::ptr::null_mut();
        };
        let seed = Zeroizing::new(seed);

        let wallet = Wallet::from_seed_bytes(network, *seed);
        Box::into_raw(Box::new(wallet)) as *mut c_void
    })
}

/// Releases a wallet handle, zeroizing its private key material.
///
/// Safe to call with a null handle. Calling this twice on the same handle, or using the handle
/// again afterward, is undefined behavior -- exactly as with any other C ABI resource handle.
///
/// # Safety
/// `handle` must be null or a live handle from `mira_wallet_create`/`mira_wallet_restore_from_mnemonic`
/// that has not already been freed.
#[no_mangle]
pub unsafe extern "C" fn mira_wallet_free(handle: *mut c_void) {
    catch_ffi_void(|| {
        if handle.is_null() {
            return;
        }
        // Safety: only ever called with a pointer this module produced via `Box::into_raw`, and the
        // caller contract above forbids reuse or double-free.
        unsafe {
            drop(Box::from_raw(handle as *mut Wallet));
        }
    });
}

fn wallet_ref<'a>(handle: *mut c_void) -> Option<&'a Wallet> {
    if handle.is_null() {
        return None;
    }
    // Safety: only ever called with a live handle produced by `mira_wallet_create` or
    // `mira_wallet_restore_from_mnemonic` and not yet freed, per this module's documented
    // handle-lifetime contract.
    Some(unsafe { &*(handle as *const Wallet) })
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct WalletIdentityJson {
    network: &'static str,
    address: String,
    public_key_hex: String,
}

/// Returns this wallet's public identity (network, receiving address, raw public key) as JSON.
/// Never includes any private key material. Returns null if `handle` is null.
///
/// # Safety
/// `handle` must be null or a live handle from `mira_wallet_create`/`mira_wallet_restore_from_mnemonic`.
#[no_mangle]
pub unsafe extern "C" fn mira_wallet_identity_json(handle: *mut c_void) -> *mut c_char {
    catch_ffi_json(|| {
        let Some(wallet) = wallet_ref(handle) else {
            return json_err("wallet handle is null");
        };
        let identity = wallet.identity();
        json_ok(WalletIdentityJson {
            network: network_name(identity.network),
            address: identity.address.to_string(),
            public_key_hex: hex::encode(identity.public_key),
        })
    })
}

#[derive(Serialize)]
#[cfg_attr(test, derive(Deserialize))]
#[serde(rename_all = "camelCase")]
struct WalletSaveJson {
    bytes_written: usize,
    permission_status: String,
}

fn wallet_password(ptr: *const c_char) -> Result<WalletPassword, String> {
    let bytes = read_c_bytes(ptr).ok_or_else(|| "wallet password is missing".to_owned())?;
    WalletPassword::new(bytes).map_err(|error| format!("wallet password is invalid: {error}"))
}

/// Encrypts and atomically saves a wallet using `aura-wallet`'s versioned Argon2id +
/// XChaCha20-Poly1305 envelope. The password is consumed into zeroizing Rust storage and is
/// never retained by the wallet handle.
///
/// # Safety
/// `handle` must be a live wallet handle. `path` and `password` must be valid NUL-terminated
/// strings for the duration of this call.
#[no_mangle]
pub unsafe extern "C" fn mira_wallet_save_json(
    handle: *mut c_void,
    path: *const c_char,
    password: *const c_char,
) -> *mut c_char {
    catch_ffi_json(|| {
        let Some(wallet) = wallet_ref(handle) else {
            return json_err("wallet handle is null");
        };
        let Some(path) = read_c_str(path) else {
            return json_err("wallet path must be valid UTF-8 text");
        };
        let password = match wallet_password(password) {
            Ok(password) => password,
            Err(message) => return json_err(message),
        };
        let report = match wallet.save(path, &password) {
            Ok(report) => report,
            Err(error) => return json_err(format!("could not save encrypted wallet: {error}")),
        };
        let permission_status = match report.permission_status {
            PermissionStatus::OwnerReadWrite => "ownerReadWrite",
            PermissionStatus::RestrictionAttemptFailed => "restrictionAttemptFailed",
            PermissionStatus::PlatformDefaultAcl => "platformDefaultAcl",
        };
        json_ok(WalletSaveJson {
            bytes_written: report.bytes_written,
            permission_status: permission_status.to_owned(),
        })
    })
}

/// Loads and authenticates an encrypted Aura wallet file. A wrong password or malformed file
/// returns a null handle and an error message; no partially decoded wallet escapes.
///
/// # Safety
/// `path` and `password` must be valid NUL-terminated strings for the duration of this call.
/// `out_error` must be null or point to a writable string-pointer slot.
#[no_mangle]
pub unsafe extern "C" fn mira_wallet_load(
    path: *const c_char,
    password: *const c_char,
    out_error: *mut *mut c_char,
) -> *mut c_void {
    catch_ffi_handle(out_error, || {
        let Some(path) = read_c_str(path) else {
            write_out_string(out_error, "wallet path must be valid UTF-8 text".to_owned());
            return std::ptr::null_mut();
        };
        let password = match wallet_password(password) {
            Ok(password) => password,
            Err(message) => {
                write_out_string(out_error, message);
                return std::ptr::null_mut();
            }
        };
        match Wallet::load(path, &password) {
            Ok(wallet) => Box::into_raw(Box::new(wallet)) as *mut c_void,
            Err(error) => {
                write_out_string(
                    out_error,
                    format!("could not unlock encrypted wallet: {error}"),
                );
                std::ptr::null_mut()
            }
        }
    })
}

// ---------------------------------------------------------------------------------------------
// Address validation
// ---------------------------------------------------------------------------------------------

/// Validates an Aura Bech32m address string. Returns 1 if valid, 0 if not (including for a
/// null or non-UTF-8 input).
///
/// # Safety
/// `address` must be null or a valid, NUL-terminated C string.
#[no_mangle]
pub unsafe extern "C" fn mira_aura_validate_address(address: *const c_char) -> i32 {
    catch_ffi_i32(|| match read_c_str(address) {
        Some(value) => i32::from(Address::from_str(&value).is_ok()),
        None => 0,
    })
}

// ---------------------------------------------------------------------------------------------
// Unsigned transaction construction
// ---------------------------------------------------------------------------------------------

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct UnsignedTransferParams {
    network: u8,
    chain_id_hash_hex: String,
    sender_address: String,
    recipient_address: String,
    /// Decimal atomic-unit string, matching `aura_core::Amount`'s own JSON convention (kept as a
    /// string so large values are never rounded through an IEEE-754 JSON number).
    amount_atoms: String,
    fee_atoms: String,
    nonce: String,
    valid_until_height: String,
}

#[derive(Serialize)]
#[cfg_attr(test, derive(Deserialize))]
#[serde(rename_all = "camelCase")]
struct UnsignedTransferResult {
    unsigned_body_hex: String,
    signing_hash_hex: String,
}

fn parse_u64_field(name: &str, value: &str) -> Result<u64, String> {
    value
        .trim()
        .parse::<u64>()
        .map_err(|_| format!("{name} must be a decimal integer string"))
}

/// Builds an unsigned Aura `PoW` Devnet v2 transfer body from the given JSON parameters and
/// returns its canonical encoded bytes (hex) plus the exact digest a signature must cover.
/// This performs no signing and touches no wallet handle -- it is pure, stateless data
/// construction using `aura_core`'s own encoding.
///
/// # Safety
/// `params_json` must be null or a valid, NUL-terminated C string.
#[no_mangle]
pub unsafe extern "C" fn mira_aura_build_unsigned_transfer_v2_json(
    params_json: *const c_char,
) -> *mut c_char {
    catch_ffi_json(|| {
        let Some(raw) = read_c_str(params_json) else {
            return json_err("parameters must be valid UTF-8 JSON text");
        };
        let params: UnsignedTransferParams = match serde_json::from_str(&raw) {
            Ok(params) => params,
            Err(error) => return json_err(format!("could not parse parameters: {error}")),
        };

        let network = match network_from_u8(params.network) {
            Ok(network) => network,
            Err(message) => return json_err(message),
        };
        let chain_id_hash = match Hash256::from_str(params.chain_id_hash_hex.trim()) {
            Ok(hash) => hash,
            Err(error) => return json_err(format!("chainIdHashHex is invalid: {error}")),
        };
        let sender = match Address::from_str(params.sender_address.trim()) {
            Ok(address) => address,
            Err(error) => return json_err(format!("senderAddress is invalid: {error}")),
        };
        let recipient = match Address::from_str(params.recipient_address.trim()) {
            Ok(address) => address,
            Err(error) => return json_err(format!("recipientAddress is invalid: {error}")),
        };
        let amount = match parse_u64_field("amountAtoms", &params.amount_atoms) {
            Ok(value) => aura_core::Amount::from_atoms(value),
            Err(message) => return json_err(message),
        };
        let fee = match parse_u64_field("feeAtoms", &params.fee_atoms) {
            Ok(value) => aura_core::Amount::from_atoms(value),
            Err(message) => return json_err(message),
        };
        let nonce = match parse_u64_field("nonce", &params.nonce) {
            Ok(value) => value,
            Err(message) => return json_err(message),
        };
        let valid_until_height =
            match parse_u64_field("validUntilHeight", &params.valid_until_height) {
                Ok(value) => value,
                Err(message) => return json_err(message),
            };

        let body = TransactionBodyV2 {
            version: aura_core::TRANSACTION_VERSION_V2,
            network,
            chain_id_hash,
            sender,
            recipient,
            amount,
            fee,
            nonce,
            valid_until_height,
        };

        let encoded = match body.encode() {
            Ok(bytes) => bytes,
            Err(error) => return json_err(format!("could not encode transaction body: {error}")),
        };
        let signing_hash = match body.signing_hash() {
            Ok(hash) => hash,
            Err(error) => return json_err(format!("could not compute signing hash: {error}")),
        };

        json_ok(UnsignedTransferResult {
            unsigned_body_hex: hex::encode(encoded),
            signing_hash_hex: signing_hash.to_string(),
        })
    })
}

// ---------------------------------------------------------------------------------------------
// Local signing
// ---------------------------------------------------------------------------------------------

#[derive(Serialize)]
#[cfg_attr(test, derive(Deserialize))]
#[serde(rename_all = "camelCase")]
struct SignedTransferResult {
    signed_transfer_hex: String,
    witness_id_hex: String,
    intent_id_hex: String,
}

/// Signs an unsigned v2 transfer body (as produced by
/// `mira_aura_build_unsigned_transfer_v2_json`) with the given wallet's private key, entirely
/// inside this process -- the private key never leaves the Rust wallet layer. Returns the
/// complete canonical transaction bytes (including the transfer discriminant) and its
/// witness/intent hashes. These bytes can be submitted directly to Aura RPC v2.
///
/// # Safety
/// `handle` must be null or a live handle from `mira_wallet_create`/`mira_wallet_restore_from_mnemonic`.
/// `unsigned_body_hex` must be null or a valid, NUL-terminated C string.
#[no_mangle]
pub unsafe extern "C" fn mira_wallet_sign_transfer_v2_json(
    handle: *mut c_void,
    unsigned_body_hex: *const c_char,
) -> *mut c_char {
    catch_ffi_json(|| {
        let Some(wallet) = wallet_ref(handle) else {
            return json_err("wallet handle is null");
        };
        let Some(hex_body) = read_c_str(unsigned_body_hex) else {
            return json_err("unsigned body must be valid UTF-8 hex text");
        };
        let bytes = match hex::decode(hex_body.trim()) {
            Ok(bytes) => bytes,
            Err(error) => return json_err(format!("unsigned body is not valid hex: {error}")),
        };
        let body = match TransactionBodyV2::decode(&bytes) {
            Ok(body) => body,
            Err(error) => return json_err(format!("unsigned body is invalid: {error}")),
        };

        let signed = match wallet.sign_transaction_body_v2(body) {
            Ok(signed) => signed,
            Err(error) => return json_err(format!("could not sign transaction: {error}")),
        };
        let encoded = match TransactionV2::Transfer(signed.clone()).encode() {
            Ok(bytes) => bytes,
            Err(error) => {
                return json_err(format!("could not encode canonical transaction: {error}"));
            }
        };
        let witness_id = match signed.witness_id() {
            Ok(hash) => hash,
            Err(error) => return json_err(format!("could not compute witness id: {error}")),
        };
        let intent_id = match signed.intent_id() {
            Ok(hash) => hash,
            Err(error) => return json_err(format!("could not compute intent id: {error}")),
        };

        json_ok(SignedTransferResult {
            signed_transfer_hex: hex::encode(encoded),
            witness_id_hex: witness_id.to_string(),
            intent_id_hex: intent_id.to_string(),
        })
    })
}

/// Fills `seed` with operating-system randomness, using the exact same `rand_core`/`OsRng`
/// entropy source `aura_wallet::Wallet::generate` itself relies on.
fn getrandom_fill(seed: &mut [u8; MNEMONIC_ENTROPY_BYTES]) -> Result<(), String> {
    use rand_core::{OsRng, RngCore};
    OsRng
        .try_fill_bytes(seed)
        .map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use aura_core::{hash_tagged, Amount};

    const DEVNET: u8 = 2;

    /// Exercises the FFI exactly as Swift would: build a C string, call the `extern "C"`
    /// function, read the result back through the same pointer-based API a caller has to use.
    fn call_create(network: u8) -> (*mut c_void, Option<String>) {
        let mut out_mnemonic: *mut c_char = std::ptr::null_mut();
        // Safety: `out_mnemonic` is a valid, writable local slot, exactly what the function
        // requires.
        let handle = unsafe { mira_wallet_create(network, &mut out_mnemonic) };
        let mnemonic = read_and_free(out_mnemonic);
        (handle, mnemonic)
    }

    fn call_restore(mnemonic: &str, network: u8) -> (*mut c_void, Option<String>) {
        let mnemonic_c = CString::new(mnemonic).expect("test mnemonic has no interior NUL");
        let mut out_error: *mut c_char = std::ptr::null_mut();
        // Safety: `mnemonic_c` is a valid NUL-terminated string and `out_error` is a valid,
        // writable local slot.
        let handle = unsafe {
            mira_wallet_restore_from_mnemonic(mnemonic_c.as_ptr(), network, &mut out_error)
        };
        let error = read_and_free(out_error);
        (handle, error)
    }

    fn call_identity(handle: *mut c_void) -> WalletIdentityJson {
        // Safety: `handle` is a live handle from `call_create`/`call_restore`, per this test
        // helper's contract.
        let json =
            read_and_free(unsafe { mira_wallet_identity_json(handle) }).expect("identity JSON");
        let envelope: JsonEnvelopeOwned<WalletIdentityJson> =
            serde_json::from_str(&json).expect("valid identity envelope");
        assert!(envelope.ok, "expected ok identity response, got {json}");
        envelope
            .data
            .expect("identity payload present on ok response")
    }

    fn read_and_free(ptr: *mut c_char) -> Option<String> {
        if ptr.is_null() {
            return None;
        }
        // Safety: `ptr` was produced by this module's own `c_string_out`, exactly as a real
        // FFI caller would receive it, and is freed exactly once here.
        let value = unsafe {
            let value = CStr::from_ptr(ptr).to_string_lossy().into_owned();
            mira_free_string(ptr);
            value
        };
        Some(value)
    }

    fn call_free(handle: *mut c_void) {
        // Safety: every call site below passes a handle from `call_create`/`call_restore` that
        // has not already been freed.
        unsafe { mira_wallet_free(handle) };
    }

    fn call_validate_address(ptr: *const c_char) -> i32 {
        // Safety: every call site below passes either null or a valid NUL-terminated string.
        unsafe { mira_aura_validate_address(ptr) }
    }

    fn call_build_unsigned(params_json: &CString) -> Option<String> {
        // Safety: `params_json` is a valid NUL-terminated string.
        read_and_free(unsafe { mira_aura_build_unsigned_transfer_v2_json(params_json.as_ptr()) })
    }

    fn call_sign(handle: *mut c_void, unsigned_body_hex: &CString) -> Option<String> {
        // Safety: `handle` is a live handle and `unsigned_body_hex` is a valid NUL-terminated
        // string, per this test helper's contract.
        read_and_free(unsafe {
            mira_wallet_sign_transfer_v2_json(handle, unsigned_body_hex.as_ptr())
        })
    }

    // Local mirrors of the private JSON envelope/identity shapes so tests can deserialize what
    // the FFI functions actually emit, without changing their visibility for production code.
    #[derive(serde::Deserialize)]
    struct JsonEnvelopeOwned<T> {
        ok: bool,
        error: Option<String>,
        data: Option<T>,
    }

    #[test]
    fn wallet_ffi_panic_boundary_returns_a_bounded_error() {
        let json = read_and_free(catch_ffi_json(|| {
            panic!("test-only wallet FFI panic");
        }))
        .expect("panic boundary JSON");
        let envelope: JsonEnvelopeOwned<serde_json::Value> =
            serde_json::from_str(&json).expect("valid panic boundary envelope");

        assert!(!envelope.ok);
        assert_eq!(envelope.error.as_deref(), Some(FFI_PANIC_MESSAGE));
        assert!(envelope.data.is_none());
    }

    impl<'de> serde::Deserialize<'de> for WalletIdentityJson {
        fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
        where
            D: serde::Deserializer<'de>,
        {
            #[derive(serde::Deserialize)]
            #[serde(rename_all = "camelCase")]
            struct Raw {
                network: String,
                address: String,
                public_key_hex: String,
            }
            let raw = Raw::deserialize(deserializer)?;
            Ok(WalletIdentityJson {
                network: match raw.network.as_str() {
                    "mainnet" => "mainnet",
                    "testnet" => "testnet",
                    "devnet" => "devnet",
                    other => {
                        return Err(serde::de::Error::custom(format!("unknown network {other}")))
                    }
                },
                address: raw.address,
                public_key_hex: raw.public_key_hex,
            })
        }
    }

    #[test]
    fn create_wallet_returns_a_handle_and_a_24_word_mnemonic() {
        let (handle, mnemonic) = call_create(DEVNET);
        assert!(!handle.is_null());
        let mnemonic = mnemonic.expect("mnemonic present on success");
        assert_eq!(mnemonic.split_whitespace().count(), 24);

        let identity = call_identity(handle);
        assert_eq!(identity.network, "devnet");
        assert!(identity.address.starts_with("daura1"));
        assert_eq!(identity.public_key_hex.len(), 64);

        call_free(handle);
    }

    #[test]
    fn create_rejects_an_unknown_network_code_and_returns_a_null_handle() {
        let (handle, message) = call_create(99);
        assert!(handle.is_null());
        assert!(message
            .expect("error message")
            .contains("unknown network code"));
    }

    #[test]
    fn restore_from_the_created_mnemonic_reproduces_the_exact_same_identity() {
        let (created_handle, mnemonic) = call_create(DEVNET);
        let mnemonic = mnemonic.expect("mnemonic present");
        let created_identity = call_identity(created_handle);
        call_free(created_handle);

        let (restored_handle, error) = call_restore(&mnemonic, DEVNET);
        assert!(error.is_none(), "unexpected restore error: {error:?}");
        assert!(!restored_handle.is_null());
        let restored_identity = call_identity(restored_handle);
        call_free(restored_handle);

        assert_eq!(created_identity.address, restored_identity.address);
        assert_eq!(
            created_identity.public_key_hex,
            restored_identity.public_key_hex
        );
    }

    #[test]
    fn restore_rejects_a_garbage_phrase_with_a_null_handle_and_an_error_message() {
        let (handle, error) = call_restore("not a real recovery phrase at all", DEVNET);
        assert!(handle.is_null());
        assert!(error.is_some());
    }

    #[test]
    fn restore_rejects_a_wrong_word_count_phrase() {
        // A syntactically valid-looking but short (12-word) BIP39 phrase should still be
        // rejected, since Aura wallets require the 24-word / 256-bit-entropy format.
        let short_phrase =
            "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
        let (handle, error) = call_restore(short_phrase, DEVNET);
        assert!(handle.is_null());
        assert!(error.is_some());
    }

    #[test]
    fn address_validation_accepts_a_real_address_and_rejects_a_corrupted_one() {
        let (handle, _mnemonic) = call_create(DEVNET);
        let identity = call_identity(handle);
        call_free(handle);

        let valid = CString::new(identity.address.clone()).unwrap();
        assert_eq!(call_validate_address(valid.as_ptr()), 1);

        let mut corrupted = identity.address;
        corrupted.pop();
        corrupted.push(if corrupted.ends_with('q') { 'p' } else { 'q' });
        let corrupted_c = CString::new(corrupted).unwrap();
        assert_eq!(call_validate_address(corrupted_c.as_ptr()), 0);

        assert_eq!(call_validate_address(std::ptr::null()), 0);
    }

    #[test]
    fn build_sign_and_independently_verify_a_full_transfer() {
        let (sender_handle, _) = call_create(DEVNET);
        let sender_identity = call_identity(sender_handle);
        let (recipient_handle, _) = call_create(DEVNET);
        let recipient_identity = call_identity(recipient_handle);
        call_free(recipient_handle);

        let chain_id_hash = hash_tagged("chain-id/v2", &[b"mira-core-test-chain"]);
        let params = format!(
            "{{\"network\":{DEVNET},\"chainIdHashHex\":\"{}\",\"senderAddress\":\"{}\",\"recipientAddress\":\"{}\",\"amountAtoms\":\"1000\",\"feeAtoms\":\"10\",\"nonce\":\"1\",\"validUntilHeight\":\"500\"}}",
            chain_id_hash, sender_identity.address, recipient_identity.address,
        );
        let params_c = CString::new(params).unwrap();
        let unsigned_json = call_build_unsigned(&params_c).expect("unsigned json");
        let unsigned: JsonEnvelopeOwned<UnsignedTransferResult> =
            serde_json::from_str(&unsigned_json).expect("valid unsigned envelope");
        assert!(unsigned.ok, "unexpected build failure: {unsigned_json}");
        let unsigned_body_hex = unsigned.data.expect("unsigned payload").unsigned_body_hex;

        let unsigned_hex_c = CString::new(unsigned_body_hex).unwrap();
        let signed_json = call_sign(sender_handle, &unsigned_hex_c).expect("signed json");
        call_free(sender_handle);
        let signed: JsonEnvelopeOwned<SignedTransferResult> =
            serde_json::from_str(&signed_json).expect("valid signed envelope");
        assert!(signed.ok, "unexpected sign failure: {signed_json}");
        let signed_data = signed.data.expect("signed payload");

        // Independently decode and verify with aura-core directly, bypassing this module's own
        // FFI functions entirely, to prove the bytes it produced are a genuine, valid Aura v2
        // transfer and not merely bytes that happen to round-trip through this same code.
        let signed_bytes = hex::decode(&signed_data.signed_transfer_hex).expect("valid hex");
        let transaction = TransactionV2::decode(&signed_bytes, 4096)
            .expect("decodes as a complete canonical v2 transaction");
        let TransactionV2::Transfer(signed_transfer) = transaction else {
            panic!("mobile signing must return the transfer transaction variant");
        };
        signed_transfer
            .verify(
                Network::Devnet,
                chain_id_hash,
                Amount::from_atoms(1),
                1,
                4096,
            )
            .expect("aura-core accepts the FFI-produced signature");
        assert_eq!(
            signed_transfer.witness_id().unwrap().to_string(),
            signed_data.witness_id_hex
        );
        assert_eq!(
            signed_transfer.intent_id().unwrap().to_string(),
            signed_data.intent_id_hex
        );
    }

    #[test]
    fn signing_a_body_addressed_from_a_different_wallet_is_rejected() {
        let (signer_handle, _) = call_create(DEVNET);
        let (other_handle, _) = call_create(DEVNET);
        let other_identity = call_identity(other_handle);
        call_free(other_handle);

        let chain_id_hash = hash_tagged("chain-id/v2", &[b"mira-core-test-chain"]);
        // Sender is `other_identity`'s address, but we will try to sign with `signer_handle`,
        // whose key does not control that address.
        let params = format!(
            "{{\"network\":{DEVNET},\"chainIdHashHex\":\"{}\",\"senderAddress\":\"{}\",\"recipientAddress\":\"{}\",\"amountAtoms\":\"1\",\"feeAtoms\":\"1\",\"nonce\":\"1\",\"validUntilHeight\":\"0\"}}",
            chain_id_hash, other_identity.address, other_identity.address,
        );
        let params_c = CString::new(params).unwrap();
        let unsigned_json = call_build_unsigned(&params_c).expect("unsigned json");
        let unsigned: JsonEnvelopeOwned<UnsignedTransferResult> =
            serde_json::from_str(&unsigned_json).expect("valid unsigned envelope");
        let unsigned_body_hex = unsigned.data.expect("unsigned payload").unsigned_body_hex;

        let unsigned_hex_c = CString::new(unsigned_body_hex).unwrap();
        let signed_json = call_sign(signer_handle, &unsigned_hex_c).expect("signed json");
        call_free(signer_handle);
        let signed: JsonEnvelopeOwned<SignedTransferResult> =
            serde_json::from_str(&signed_json).expect("valid envelope even on failure");
        assert!(!signed.ok, "signing an uncontrolled sender must fail");
    }

    #[test]
    fn encrypted_wallet_save_and_load_preserve_identity() {
        let directory = tempfile::tempdir().expect("temporary wallet directory");
        let path = directory.path().join("mobile-wallet.aura");
        let path_c = CString::new(path.to_string_lossy().as_bytes()).unwrap();
        let password_c = CString::new("correct horse battery staple").unwrap();

        let (handle, _) = call_create(DEVNET);
        let original = call_identity(handle);
        let save_json = read_and_free(unsafe {
            mira_wallet_save_json(handle, path_c.as_ptr(), password_c.as_ptr())
        })
        .expect("save response");
        let save: JsonEnvelopeOwned<WalletSaveJson> =
            serde_json::from_str(&save_json).expect("valid save envelope");
        assert!(save.ok, "unexpected save failure: {save_json}");
        assert!(save.data.expect("save payload").bytes_written > 0);
        call_free(handle);

        let mut out_error: *mut c_char = std::ptr::null_mut();
        let loaded =
            unsafe { mira_wallet_load(path_c.as_ptr(), password_c.as_ptr(), &mut out_error) };
        assert!(
            !loaded.is_null(),
            "unlock failed: {:?}",
            read_and_free(out_error)
        );
        let reopened = call_identity(loaded);
        call_free(loaded);
        assert_eq!(original.address, reopened.address);
        assert_eq!(original.public_key_hex, reopened.public_key_hex);
        assert_eq!(original.network, reopened.network);
    }

    #[test]
    fn encrypted_wallet_load_rejects_wrong_password() {
        let directory = tempfile::tempdir().expect("temporary wallet directory");
        let path = directory.path().join("mobile-wallet.aura");
        let path_c = CString::new(path.to_string_lossy().as_bytes()).unwrap();
        let password_c = CString::new("right password").unwrap();
        let wrong_password_c = CString::new("wrong password").unwrap();

        let (handle, _) = call_create(DEVNET);
        let save_json = read_and_free(unsafe {
            mira_wallet_save_json(handle, path_c.as_ptr(), password_c.as_ptr())
        })
        .expect("save response");
        call_free(handle);
        let save: JsonEnvelopeOwned<WalletSaveJson> =
            serde_json::from_str(&save_json).expect("valid save envelope");
        assert!(save.ok, "unexpected save failure: {save_json}");

        let mut out_error: *mut c_char = std::ptr::null_mut();
        let loaded =
            unsafe { mira_wallet_load(path_c.as_ptr(), wrong_password_c.as_ptr(), &mut out_error) };
        assert!(loaded.is_null());
        let error = read_and_free(out_error).expect("wrong-password error");
        assert!(error.contains("unlock"));
    }

    #[test]
    fn free_functions_tolerate_null_without_crashing() {
        call_free(std::ptr::null_mut());
        // Safety: null is explicitly documented as safe to pass here.
        unsafe { mira_free_string(std::ptr::null_mut()) };
    }
}
