//! Encrypted local wallet storage for Aura.
//!
//! Wallet files use a strict versioned binary envelope, RFC 9106 Argon2id
//! version 0x13 for password derivation, and XChaCha20-Poly1305 authenticated
//! encryption. Private keys, password buffers, decrypted payloads, and derived
//! keys are held in zeroizing containers and are never formatted or logged.
//!
//! This crate is wallet infrastructure, not evidence that node networking,
//! mining, transaction propagation, or a public Aura network exists.

#![forbid(unsafe_code)]

mod envelope;
mod error;
mod wallet;

pub use error::{Error, Result};
pub use wallet::{
    PermissionStatus, SaveReport, Wallet, WalletIdentity, WalletPassword, MAX_PASSWORD_BYTES,
};

/// Minimum accepted Argon2id memory cost in KiB.
pub const MIN_MEMORY_KIB: u32 = 8 * 1024;
/// Maximum accepted Argon2id memory cost in KiB.
pub const MAX_MEMORY_KIB: u32 = 256 * 1024;
/// Maximum accepted Argon2id time cost.
pub const MAX_TIME_COST: u32 = 10;
/// Maximum accepted Argon2id lane count.
pub const MAX_PARALLELISM: u32 = 8;

/// Explicit Argon2id v0x13 password-derivation parameters stored in each file.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct KdfParams {
    memory_kib: u32,
    time_cost: u32,
    parallelism: u32,
}

impl KdfParams {
    /// Creates parameters after enforcing hard resource bounds.
    pub fn new(memory_kib: u32, time_cost: u32, parallelism: u32) -> Result<Self> {
        let value = Self {
            memory_kib,
            time_cost,
            parallelism,
        };
        value.validate()?;
        Ok(value)
    }

    /// Argon2 memory cost in KiB.
    #[must_use]
    pub const fn memory_kib(self) -> u32 {
        self.memory_kib
    }

    /// Argon2 iteration/time cost.
    #[must_use]
    pub const fn time_cost(self) -> u32 {
        self.time_cost
    }

    /// Argon2 lane count.
    #[must_use]
    pub const fn parallelism(self) -> u32 {
        self.parallelism
    }

    pub(crate) fn validate(self) -> Result<()> {
        let minimum_for_lanes = self.parallelism.checked_mul(8);
        if !(MIN_MEMORY_KIB..=MAX_MEMORY_KIB).contains(&self.memory_kib)
            || !(1..=MAX_TIME_COST).contains(&self.time_cost)
            || !(1..=MAX_PARALLELISM).contains(&self.parallelism)
            || minimum_for_lanes.is_none_or(|minimum| self.memory_kib < minimum)
        {
            return Err(Error::UnsafeKdfParameters);
        }
        Ok(())
    }
}

impl Default for KdfParams {
    fn default() -> Self {
        Self {
            memory_kib: 64 * 1024,
            time_cost: 3,
            parallelism: 1,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kdf_bounds_are_enforced() {
        assert!(KdfParams::new(MIN_MEMORY_KIB, 1, 1).is_ok());
        assert!(KdfParams::new(MIN_MEMORY_KIB - 1, 1, 1).is_err());
        assert!(KdfParams::new(MAX_MEMORY_KIB + 1, 1, 1).is_err());
        assert!(KdfParams::new(MIN_MEMORY_KIB, 0, 1).is_err());
        assert!(KdfParams::new(MIN_MEMORY_KIB, MAX_TIME_COST + 1, 1).is_err());
        assert!(KdfParams::new(MIN_MEMORY_KIB, 1, 0).is_err());
        assert!(KdfParams::new(MIN_MEMORY_KIB, 1, MAX_PARALLELISM + 1).is_err());
    }

    #[test]
    fn invalid_password_buffers_are_zeroized_on_rejection_path() {
        assert!(WalletPassword::new(Vec::new()).is_err());
        assert!(WalletPassword::new(vec![b'x'; MAX_PASSWORD_BYTES + 1]).is_err());
    }
}
