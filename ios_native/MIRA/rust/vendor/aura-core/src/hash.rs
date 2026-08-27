use crate::{Error, Result};
use borsh::BorshSerialize;
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use sha2::{Digest, Sha256};
use std::{fmt, str::FromStr};

/// A 256-bit protocol hash.
#[derive(
    Clone,
    Copy,
    Default,
    PartialEq,
    Eq,
    PartialOrd,
    Ord,
    Hash,
    borsh::BorshSerialize,
    borsh::BorshDeserialize,
)]
pub struct Hash256([u8; 32]);

impl Hash256 {
    /// All-zero sentinel used only where the protocol explicitly allows it.
    pub const ZERO: Self = Self([0; 32]);

    /// Constructs a hash from its bytes.
    #[must_use]
    pub const fn from_bytes(bytes: [u8; 32]) -> Self {
        Self(bytes)
    }

    /// Returns the raw hash bytes.
    #[must_use]
    pub const fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }
}

impl fmt::Display for Hash256 {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&hex::encode(self.0))
    }
}

impl fmt::Debug for Hash256 {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "Hash256({self})")
    }
}

impl FromStr for Hash256 {
    type Err = Error;

    fn from_str(value: &str) -> Result<Self> {
        let bytes = hex::decode(value)
            .map_err(|error| Error::Serialization(format!("invalid hash hex: {error}")))?;
        let bytes: [u8; 32] = bytes
            .try_into()
            .map_err(|_| Error::Serialization("hash must contain exactly 32 bytes".into()))?;
        Ok(Self(bytes))
    }
}

impl Serialize for Hash256 {
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str(&self.to_string())
    }
}

impl<'de> Deserialize<'de> for Hash256 {
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        value.parse().map_err(serde::de::Error::custom)
    }
}

/// Domain-separated SHA-256 over length-prefixed byte slices.
#[must_use]
pub fn hash_tagged(tag: &str, parts: &[&[u8]]) -> Hash256 {
    let mut hasher = Sha256::new();
    hasher.update(b"AURA\0");
    hasher.update((tag.len() as u64).to_le_bytes());
    hasher.update(tag.as_bytes());
    for part in parts {
        hasher.update((part.len() as u64).to_le_bytes());
        hasher.update(part);
    }
    Hash256::from_bytes(hasher.finalize().into())
}

/// Hashes a value after deterministic Borsh encoding.
pub fn hash_borsh<T: BorshSerialize>(tag: &str, value: &T) -> Result<Hash256> {
    let encoded = borsh::to_vec(value)
        .map_err(|error| Error::Serialization(format!("Borsh encoding failed: {error}")))?;
    Ok(hash_tagged(tag, &[&encoded]))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn domains_are_distinct_and_stable() {
        let first = hash_tagged("a", &[b"bc"]);
        let second = hash_tagged("ab", &[b"c"]);
        let repeated = hash_tagged("a", &[b"bc"]);
        assert_ne!(first, second);
        assert_eq!(first, repeated);
        assert_eq!(first.to_string().len(), 64);
    }
}
