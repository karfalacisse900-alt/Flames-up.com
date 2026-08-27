use thiserror::Error;

/// Failures at the local Aura wallet boundary.
///
/// Error messages never contain passwords, derived keys, private keys, salts,
/// nonces, plaintext key material, or encrypted wallet contents.
#[derive(Debug, Error)]
pub enum Error {
    #[error("wallet password must contain between 1 and {maximum} bytes")]
    InvalidPasswordLength { maximum: usize },
    #[error("wallet Argon2id parameters are outside the accepted safety bounds")]
    UnsafeKdfParameters,
    #[error("wallet envelope exceeds the {maximum}-byte limit")]
    EnvelopeTooLarge { maximum: usize },
    #[error("wallet envelope is truncated")]
    TruncatedEnvelope,
    #[error("wallet envelope contains trailing bytes")]
    TrailingBytes,
    #[error("wallet envelope magic is invalid")]
    InvalidMagic,
    #[error("wallet envelope version {0} is unsupported")]
    UnsupportedEnvelopeVersion(u16),
    #[error("wallet KDF identifier {0} is unsupported")]
    UnsupportedKdf(u8),
    #[error("wallet Argon2 version {0:#04x} is unsupported")]
    UnsupportedArgon2Version(u8),
    #[error("wallet network identifier {0:#010x} is unsupported")]
    UnsupportedNetwork(u32),
    #[error("wallet ciphertext length is invalid")]
    InvalidCiphertextLength,
    #[error("wallet password or encrypted payload authentication failed")]
    AuthenticationFailed,
    #[error("decrypted wallet payload is malformed")]
    MalformedPayload,
    #[error("wallet cryptographic operation failed")]
    CryptographicFailure,
    #[error("wallet and transaction networks differ")]
    TransactionNetworkMismatch,
    #[error("wallet does not control the transaction sender")]
    TransactionSenderMismatch,
    #[error("wallet file operation failed: {0}")]
    Io(#[source] std::io::Error),
    #[error("Aura transaction signing failed: {0}")]
    Core(#[from] aura_core::Error),
}

impl From<std::io::Error> for Error {
    fn from(error: std::io::Error) -> Self {
        Self::Io(error)
    }
}

/// Aura wallet result type.
pub type Result<T> = std::result::Result<T, Error>;
