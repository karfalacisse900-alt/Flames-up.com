use crate::{Error, Result, ATOMS_PER_AUR};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use std::fmt;

/// A non-negative quantity of atomic AUR units.
#[derive(
    Clone,
    Copy,
    Default,
    Debug,
    PartialEq,
    Eq,
    PartialOrd,
    Ord,
    Hash,
    borsh::BorshSerialize,
    borsh::BorshDeserialize,
)]
pub struct Amount(u64);

impl Amount {
    /// Zero AUR.
    pub const ZERO: Self = Self(0);

    /// Constructs an amount from atomic units.
    #[must_use]
    pub const fn from_atoms(atoms: u64) -> Self {
        Self(atoms)
    }

    /// Returns the quantity in atomic units.
    #[must_use]
    pub const fn atoms(self) -> u64 {
        self.0
    }

    /// Adds two amounts, rejecting overflow.
    pub fn checked_add(self, other: Self) -> Result<Self> {
        self.0
            .checked_add(other.0)
            .map(Self)
            .ok_or(Error::AmountOverflow)
    }

    /// Subtracts an amount, rejecting underflow.
    pub fn checked_sub(self, other: Self) -> Result<Self> {
        self.0
            .checked_sub(other.0)
            .map(Self)
            .ok_or(Error::AmountUnderflow)
    }
}

impl fmt::Display for Amount {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let whole = self.0 / ATOMS_PER_AUR;
        let fractional = self.0 % ATOMS_PER_AUR;
        write!(formatter, "{whole}.{fractional:08} AUR")
    }
}

// JSON uses decimal strings so genesis quantities cannot be rounded by parsers that represent
// all numbers as IEEE-754 doubles. Binary protocol encoding remains a fixed u64 through Borsh.
impl Serialize for Amount {
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str(&self.0.to_string())
    }
}

impl<'de> Deserialize<'de> for Amount {
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        let atoms = value.parse::<u64>().map_err(serde::de::Error::custom)?;
        Ok(Self(atoms))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn arithmetic_is_checked() {
        assert!(Amount::from_atoms(u64::MAX)
            .checked_add(Amount::from_atoms(1))
            .is_err());
        assert!(Amount::ZERO.checked_sub(Amount::from_atoms(1)).is_err());
    }
}
