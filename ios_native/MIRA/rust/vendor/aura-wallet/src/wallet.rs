use crate::{envelope, Error, KdfParams, Result};
use aura_core::{
    Address, Hash256, Network, SignedTransaction, SignedTransferV2, TransactionBody,
    TransactionBodyV2,
};
use ed25519_dalek::{Signer, SigningKey};
use rand_core::OsRng;
use std::{
    fs::{self, File},
    io::{Read, Write},
    path::Path,
};
use tempfile::Builder;
use zeroize::Zeroizing;

/// Maximum accepted password byte length.
pub const MAX_PASSWORD_BYTES: usize = 1_024;

/// A password buffer that is zeroized when dropped.
///
/// Construct it from an owned byte vector so the wallet does not need to retain
/// an additional immutable password copy. Callers remain responsible for any
/// copies they made before transferring ownership.
pub struct WalletPassword(Zeroizing<Vec<u8>>);

impl WalletPassword {
    /// Takes ownership of a nonempty bounded password.
    pub fn new(bytes: Vec<u8>) -> Result<Self> {
        let bytes = Zeroizing::new(bytes);
        if bytes.is_empty() || bytes.len() > MAX_PASSWORD_BYTES {
            return Err(Error::InvalidPasswordLength {
                maximum: MAX_PASSWORD_BYTES,
            });
        }
        Ok(Self(bytes))
    }

    pub(crate) fn as_bytes(&self) -> &[u8] {
        self.0.as_slice()
    }
}

/// Public, non-secret wallet identity.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct WalletIdentity {
    /// Aura network encoded into the address.
    pub network: Network,
    /// Aura address controlled by the wallet key.
    pub address: Address,
    /// Raw Ed25519 verifying key.
    pub public_key: [u8; 32],
}

/// Result of the platform's restrictive-permission attempt.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PermissionStatus {
    /// The resulting Unix file mode was restricted to owner read/write (`0600`).
    OwnerReadWrite,
    /// Restricting the Unix file mode failed; encryption still protects contents.
    RestrictionAttemptFailed,
    /// Windows ACLs were left at their inherited/platform defaults.
    PlatformDefaultAcl,
}

/// Result of an atomic wallet-file publication.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SaveReport {
    /// Whether an owner-only file permission was established where supported.
    pub permission_status: PermissionStatus,
    /// Size of the complete encrypted envelope.
    pub bytes_written: usize,
}

/// One local Ed25519 wallet key.
///
/// The private seed remains in a zeroizing buffer. This type deliberately has
/// no `Debug`, `Clone`, serialization, or raw-secret export implementation.
///
/// ```compile_fail
/// use aura_wallet::Wallet;
///
/// fn requires_debug<T: std::fmt::Debug>() {}
/// requires_debug::<Wallet>();
/// ```
pub struct Wallet {
    network: Network,
    secret_key: Zeroizing<[u8; 32]>,
}

impl Wallet {
    /// Generates a fresh Ed25519 key using the operating-system CSPRNG.
    pub fn generate(network: Network) -> Self {
        let signing_key = SigningKey::generate(&mut OsRng);
        Self {
            network,
            secret_key: Zeroizing::new(signing_key.to_bytes()),
        }
    }

    /// Constructs a wallet directly from a caller-supplied 32-byte Ed25519 seed.
    ///
    /// This does not add any new cryptography: `ed25519_dalek::SigningKey` already accepts any
    /// 32-byte value as a valid secret key, and [`Wallet::load`] already reconstructs a wallet
    /// this way from a decrypted envelope. This constructor exists so a caller that generates or
    /// derives the seed itself (for example, from a BIP39 mnemonic's raw entropy) can hand it to
    /// the same wallet type used everywhere else, instead of that caller re-deriving the address
    /// and signing logic independently. The caller remains responsible for zeroizing its own
    /// copy of `seed` once this returns.
    #[must_use]
    pub fn from_seed_bytes(network: Network, seed: [u8; 32]) -> Self {
        Self {
            network,
            secret_key: Zeroizing::new(seed),
        }
    }

    /// Returns the wallet's non-secret identity.
    #[must_use]
    pub fn identity(&self) -> WalletIdentity {
        let public_key = self.signing_key().verifying_key().to_bytes();
        WalletIdentity {
            network: self.network,
            address: Address::from_public_key(self.network, &public_key),
            public_key,
        }
    }

    /// Signs an already domain-separated 256-bit digest.
    #[must_use]
    pub fn sign_digest(&self, digest: &Hash256) -> [u8; 64] {
        self.signing_key().sign(digest.as_bytes()).to_bytes()
    }

    /// Signs the currently exposed `aura_core::TransactionBody` as a temporary
    /// bridge until the v2 transaction implementation replaces that type.
    pub fn sign_transaction_body(&self, body: TransactionBody) -> Result<SignedTransaction> {
        let identity = self.identity();
        if body.network != identity.network {
            return Err(Error::TransactionNetworkMismatch);
        }
        if body.sender != identity.address {
            return Err(Error::TransactionSenderMismatch);
        }
        Ok(SignedTransaction::sign(body, &self.signing_key())?)
    }

    /// Signs a canonical Aura `PoW` Devnet v2 transfer body.
    ///
    /// The public key is derived from this wallet's decrypted private seed.
    /// Aura core remains the single implementation of the frozen v2 signing
    /// payload and Ed25519 witness construction.
    pub fn sign_transaction_body_v2(&self, body: TransactionBodyV2) -> Result<SignedTransferV2> {
        let identity = self.identity();
        if body.network != identity.network {
            return Err(Error::TransactionNetworkMismatch);
        }
        if body.sender != identity.address {
            return Err(Error::TransactionSenderMismatch);
        }
        Ok(SignedTransferV2::sign(body, &self.signing_key())?)
    }

    /// Encrypts and atomically saves the wallet using default Argon2id parameters.
    pub fn save(&self, path: impl AsRef<Path>, password: &WalletPassword) -> Result<SaveReport> {
        self.save_with_params(path, password, KdfParams::default())
    }

    /// Encrypts and atomically saves the wallet using explicitly stored,
    /// safety-bounded Argon2id parameters.
    pub fn save_with_params(
        &self,
        path: impl AsRef<Path>,
        password: &WalletPassword,
        kdf: KdfParams,
    ) -> Result<SaveReport> {
        let bytes = envelope::seal(self.network, &self.secret_key, password, kdf)?;
        atomic_write(path.as_ref(), &bytes)
    }

    /// Loads and authenticates a bounded encrypted wallet file.
    pub fn load(path: impl AsRef<Path>, password: &WalletPassword) -> Result<Self> {
        let bytes = read_bounded(path.as_ref())?;
        let opened = envelope::open(&bytes, password)?;
        Ok(Self {
            network: opened.network,
            secret_key: opened.secret_key,
        })
    }

    fn signing_key(&self) -> SigningKey {
        SigningKey::from_bytes(&self.secret_key)
    }
}

fn read_bounded(path: &Path) -> Result<Vec<u8>> {
    let file = File::open(path)?;
    let metadata = file.metadata()?;
    if !metadata.is_file() {
        return Err(Error::Io(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "wallet path is not a regular file",
        )));
    }
    if metadata.len() > envelope::MAX_ENVELOPE_BYTES as u64 {
        return Err(Error::EnvelopeTooLarge {
            maximum: envelope::MAX_ENVELOPE_BYTES,
        });
    }

    let mut bytes =
        Vec::with_capacity(usize::try_from(metadata.len()).unwrap_or(envelope::MAX_ENVELOPE_BYTES));
    file.take((envelope::MAX_ENVELOPE_BYTES + 1) as u64)
        .read_to_end(&mut bytes)?;
    if bytes.len() > envelope::MAX_ENVELOPE_BYTES {
        return Err(Error::EnvelopeTooLarge {
            maximum: envelope::MAX_ENVELOPE_BYTES,
        });
    }
    Ok(bytes)
}

fn atomic_write(path: &Path, bytes: &[u8]) -> Result<SaveReport> {
    let parent = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(parent)?;

    let mut temporary = Builder::new().prefix(".aura-wallet-").tempfile_in(parent)?;
    temporary.write_all(bytes)?;
    temporary.flush()?;
    let permission_status = restrict_permissions(temporary.as_file());
    temporary.as_file().sync_all()?;

    // `tempfile::persist` uses the platform's atomic replacement primitive and
    // replaces an existing destination rather than exposing a partial file.
    let published = temporary
        .persist(path)
        .map_err(|error| Error::Io(error.error))?;
    published.sync_all()?;
    sync_parent_best_effort(parent);

    Ok(SaveReport {
        permission_status,
        bytes_written: bytes.len(),
    })
}

#[cfg(unix)]
fn restrict_permissions(file: &File) -> PermissionStatus {
    use std::os::unix::fs::PermissionsExt;

    match file.set_permissions(fs::Permissions::from_mode(0o600)) {
        Ok(()) => PermissionStatus::OwnerReadWrite,
        Err(_) => PermissionStatus::RestrictionAttemptFailed,
    }
}

#[cfg(windows)]
fn restrict_permissions(_file: &File) -> PermissionStatus {
    // Rust's standard library does not provide a portable user-only NTFS ACL
    // API. Installers must establish and test the intended ACL separately.
    PermissionStatus::PlatformDefaultAcl
}

#[cfg(not(any(unix, windows)))]
fn restrict_permissions(_file: &File) -> PermissionStatus {
    PermissionStatus::RestrictionAttemptFailed
}

#[cfg(unix)]
fn sync_parent_best_effort(parent: &Path) {
    if let Ok(directory) = File::open(parent) {
        let _ = directory.sync_all();
    }
}

#[cfg(not(unix))]
fn sync_parent_best_effort(_parent: &Path) {}

#[cfg(test)]
mod tests {
    use super::*;
    use aura_core::{
        hash_tagged, Amount, Error as CoreError, TRANSACTION_VERSION, TRANSACTION_VERSION_V2,
    };
    use ed25519_dalek::{Signature, VerifyingKey};
    use tempfile::tempdir;

    fn password(value: &str) -> WalletPassword {
        WalletPassword::new(value.as_bytes().to_vec()).expect("valid test password")
    }

    fn test_kdf() -> KdfParams {
        KdfParams::new(crate::MIN_MEMORY_KIB, 1, 1).expect("bounded test KDF")
    }

    #[test]
    fn encrypted_round_trip_preserves_only_public_identity() {
        let directory = tempdir().expect("temporary directory");
        let path = directory.path().join("wallet.aura");
        let wallet = Wallet::generate(Network::Devnet);
        let expected = wallet.identity();
        wallet
            .save_with_params(&path, &password("round-trip"), test_kdf())
            .expect("save wallet");

        let loaded = Wallet::load(&path, &password("round-trip")).expect("load wallet");
        assert_eq!(loaded.identity(), expected);
    }

    #[test]
    fn generated_wallets_use_unique_os_entropy() {
        let first = Wallet::generate(Network::Devnet).identity();
        let second = Wallet::generate(Network::Devnet).identity();
        assert_ne!(first.public_key, second.public_key);
        assert_ne!(first.address, second.address);
    }

    #[test]
    fn from_seed_bytes_is_deterministic_and_matches_the_signing_key_it_wraps() {
        let seed = [0x11_u8; 32];
        let first = Wallet::from_seed_bytes(Network::Devnet, seed).identity();
        let second = Wallet::from_seed_bytes(Network::Devnet, seed).identity();
        assert_eq!(first, second);

        let expected_public_key = SigningKey::from_bytes(&seed).verifying_key().to_bytes();
        assert_eq!(first.public_key, expected_public_key);
        assert_eq!(
            first.address,
            Address::from_public_key(Network::Devnet, &expected_public_key)
        );
    }

    #[test]
    fn atomic_replacement_publishes_the_complete_new_wallet() {
        let directory = tempdir().expect("temporary directory");
        let path = directory.path().join("wallet.aura");
        let first = Wallet::generate(Network::Devnet);
        let second = Wallet::generate(Network::Devnet);
        let password = password("replacement");

        first
            .save_with_params(&path, &password, test_kdf())
            .expect("save first wallet");
        second
            .save_with_params(&path, &password, test_kdf())
            .expect("replace wallet");
        let loaded = Wallet::load(&path, &password).expect("load replacement");
        assert_eq!(loaded.identity(), second.identity());
        assert_ne!(loaded.identity(), first.identity());
        assert_eq!(
            fs::read_dir(directory.path())
                .expect("read wallet directory")
                .count(),
            1
        );
    }

    #[test]
    fn digest_and_transaction_bridge_signatures_verify() {
        let wallet = Wallet::generate(Network::Devnet);
        let identity = wallet.identity();
        let digest = hash_tagged("wallet/test-digest/v1", &[b"digest"]);
        let signature = Signature::from_bytes(&wallet.sign_digest(&digest));
        VerifyingKey::from_bytes(&identity.public_key)
            .expect("valid public key")
            .verify_strict(digest.as_bytes(), &signature)
            .expect("valid digest signature");

        let body = TransactionBody {
            version: TRANSACTION_VERSION,
            network: Network::Devnet,
            chain_id_hash: hash_tagged("chain-id/v1", &[b"aura-devnet-wallet-test"]),
            sender: identity.address,
            recipient: Address::from_public_key(Network::Devnet, &[42; 32]),
            amount: Amount::from_atoms(10),
            fee: Amount::from_atoms(1),
            nonce: 1,
            valid_until_height: 10,
        };
        let signed = wallet
            .sign_transaction_body(body)
            .expect("sign transaction body");
        signed
            .verify(
                Network::Devnet,
                signed.body.chain_id_hash,
                Amount::from_atoms(1),
                1,
                2_048,
            )
            .expect("valid bridged transaction");
    }

    #[test]
    fn decrypted_wallet_signs_the_exact_v2_core_authorization_payload() {
        let directory = tempdir().expect("temporary directory");
        let path = directory.path().join("wallet.aura");
        let wallet = Wallet::generate(Network::Devnet);
        let identity = wallet.identity();
        let password = password("v2-signing-bridge");
        wallet
            .save_with_params(&path, &password, test_kdf())
            .expect("save wallet");
        drop(wallet);

        let wallet = Wallet::load(&path, &password).expect("decrypt wallet");
        let chain_id_hash = hash_tagged("chain-id/v2", &[b"aura-devnet-pow-v2"]);
        let body = TransactionBodyV2 {
            version: TRANSACTION_VERSION_V2,
            network: Network::Devnet,
            chain_id_hash,
            sender: identity.address,
            recipient: Address::from_public_key(Network::Devnet, &[42; 32]),
            amount: Amount::from_atoms(10),
            fee: Amount::from_atoms(1),
            nonce: 1,
            valid_until_height: 10,
        };
        let expected_signing_hash = body.signing_hash().expect("canonical signing hash");
        let signed = wallet.sign_transaction_body_v2(body).expect("sign v2 body");

        assert_eq!(signed.public_key, identity.public_key);
        let signature = Signature::from_bytes(&signed.signature);
        VerifyingKey::from_bytes(&signed.public_key)
            .expect("valid wallet public key")
            .verify_strict(expected_signing_hash.as_bytes(), &signature)
            .expect("signature covers the exact core authorization payload");
        signed
            .verify(
                Network::Devnet,
                chain_id_hash,
                Amount::from_atoms(1),
                1,
                2_048,
            )
            .expect("core accepts wallet signature");
    }

    #[test]
    fn v2_bridge_signature_rejects_body_tampering() {
        let wallet = Wallet::generate(Network::Devnet);
        let identity = wallet.identity();
        let chain_id_hash = hash_tagged("chain-id/v2", &[b"aura-devnet-pow-v2"]);
        let mut signed = wallet
            .sign_transaction_body_v2(TransactionBodyV2 {
                version: TRANSACTION_VERSION_V2,
                network: Network::Devnet,
                chain_id_hash,
                sender: identity.address,
                recipient: Address::from_public_key(Network::Devnet, &[42; 32]),
                amount: Amount::from_atoms(10),
                fee: Amount::from_atoms(1),
                nonce: 1,
                valid_until_height: 10,
            })
            .expect("sign v2 body");

        signed.body.amount = Amount::from_atoms(11);
        assert!(matches!(
            signed.verify(
                Network::Devnet,
                chain_id_hash,
                Amount::from_atoms(1),
                1,
                2_048,
            ),
            Err(CoreError::InvalidSignature)
        ));
    }

    #[test]
    fn v2_bridge_errors_and_public_outputs_do_not_format_private_seed() {
        let wallet = Wallet {
            network: Network::Devnet,
            secret_key: Zeroizing::new([0xa5; 32]),
        };
        let identity = wallet.identity();
        let secret_hex = "a5".repeat(32);
        let secret_debug = format!("{:?}", [0xa5_u8; 32]);
        let chain_id_hash = hash_tagged("chain-id/v2", &[b"aura-devnet-pow-v2"]);
        let wrong_sender = Address::from_public_key(Network::Devnet, &[7; 32]);
        assert_ne!(wrong_sender, identity.address);
        let error = wallet
            .sign_transaction_body_v2(TransactionBodyV2 {
                version: TRANSACTION_VERSION_V2,
                network: Network::Devnet,
                chain_id_hash,
                sender: wrong_sender,
                recipient: Address::from_public_key(Network::Devnet, &[42; 32]),
                amount: Amount::from_atoms(10),
                fee: Amount::from_atoms(1),
                nonce: 1,
                valid_until_height: 10,
            })
            .expect_err("wallet must reject an uncontrolled sender");

        assert!(!format!("{error:?}").contains(&secret_hex));
        assert!(!format!("{error:?}").contains(&secret_debug));
        assert!(!error.to_string().contains(&secret_hex));
        assert!(!error.to_string().contains(&secret_debug));

        let signed = wallet
            .sign_transaction_body_v2(TransactionBodyV2 {
                version: TRANSACTION_VERSION_V2,
                network: Network::Devnet,
                chain_id_hash,
                sender: identity.address,
                recipient: Address::from_public_key(Network::Devnet, &[42; 32]),
                amount: Amount::from_atoms(10),
                fee: Amount::from_atoms(1),
                nonce: 1,
                valid_until_height: 10,
            })
            .expect("sign v2 body");
        assert!(!format!("{signed:?}").contains(&secret_hex));
        assert!(!format!("{signed:?}").contains(&secret_debug));
    }
}
