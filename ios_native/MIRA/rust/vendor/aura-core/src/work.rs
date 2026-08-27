use borsh::{BorshDeserialize, BorshSerialize};
use primitive_types::{U256, U512};
use std::fmt;

/// A consensus target encoded as exactly 32 big-endian bytes.
#[derive(
    Clone,
    Copy,
    Default,
    PartialEq,
    Eq,
    PartialOrd,
    Ord,
    Hash,
    Debug,
    BorshSerialize,
    BorshDeserialize,
)]
pub struct Target256([u8; 32]);

impl Target256 {
    /// The invalid zero target, useful only as the genesis marker.
    pub const ZERO: Self = Self([0; 32]);
    /// The hardest nonzero target.
    pub const ONE: Self = Self([
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 1,
    ]);
    /// The largest representable target.
    pub const MAX: Self = Self([0xff; 32]);

    /// Constructs a target from its consensus big-endian bytes.
    #[must_use]
    pub const fn from_be_bytes(bytes: [u8; 32]) -> Self {
        Self(bytes)
    }

    /// Returns the exact consensus big-endian bytes.
    #[must_use]
    pub const fn as_be_bytes(&self) -> &[u8; 32] {
        &self.0
    }

    /// Returns true for the invalid non-genesis zero target.
    #[must_use]
    pub fn is_zero(self) -> bool {
        self == Self::ZERO
    }

    /// Checks this target against the configured inclusive consensus bounds.
    pub fn validate_bounds(self, minimum: Self, pow_limit: Self) -> Result<(), WorkError> {
        if minimum.is_zero() || minimum > pow_limit {
            return Err(WorkError::InvalidTargetBounds);
        }
        if self < minimum || self > pow_limit {
            return Err(WorkError::TargetOutOfRange);
        }
        Ok(())
    }

    pub(crate) fn to_uint(self) -> U256 {
        U256::from_big_endian(&self.0)
    }

    pub(crate) fn from_uint(value: U256) -> Self {
        Self(value.to_big_endian())
    }

    pub(crate) fn try_from_wide(value: U512) -> Result<Self, WorkError> {
        let narrowed = U256::try_from(value).map_err(|_| WorkError::IntegerConversionOverflow)?;
        Ok(Self::from_uint(narrowed))
    }
}

impl fmt::Display for Target256 {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&hex::encode(self.0))
    }
}

/// The exact expected-work contribution of one target.
#[derive(
    Clone,
    Copy,
    Default,
    PartialEq,
    Eq,
    PartialOrd,
    Ord,
    Hash,
    Debug,
    BorshSerialize,
    BorshDeserialize,
)]
pub struct BlockWork256([u8; 32]);

impl BlockWork256 {
    /// Zero work, which no non-genesis block may contribute.
    pub const ZERO: Self = Self([0; 32]);

    /// Constructs a work value from its consensus big-endian bytes.
    #[must_use]
    pub const fn from_be_bytes(bytes: [u8; 32]) -> Self {
        Self(bytes)
    }

    /// Returns the exact consensus big-endian bytes.
    #[must_use]
    pub const fn as_be_bytes(&self) -> &[u8; 32] {
        &self.0
    }

    fn from_uint(value: U256) -> Self {
        Self(value.to_big_endian())
    }

    fn to_wide(self) -> U512 {
        U512::from(U256::from_big_endian(&self.0))
    }
}

impl fmt::Display for BlockWork256 {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&hex::encode(self.0))
    }
}

/// Checked accumulated work, encoded as exactly 64 big-endian bytes.
#[derive(
    Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Debug, BorshSerialize, BorshDeserialize,
)]
pub struct CumulativeWork512([u8; 64]);

impl Default for CumulativeWork512 {
    fn default() -> Self {
        Self::ZERO
    }
}

impl CumulativeWork512 {
    /// The cumulative work assigned to genesis.
    pub const ZERO: Self = Self([0; 64]);
    /// The largest representable cumulative work value.
    pub const MAX: Self = Self([0xff; 64]);

    /// Constructs cumulative work from its consensus big-endian bytes.
    #[must_use]
    pub const fn from_be_bytes(bytes: [u8; 64]) -> Self {
        Self(bytes)
    }

    /// Returns the exact consensus big-endian bytes.
    #[must_use]
    pub const fn as_be_bytes(&self) -> &[u8; 64] {
        &self.0
    }

    /// Adds one block's work and rejects overflow rather than wrapping.
    pub fn checked_add_block(self, block_work: BlockWork256) -> Result<Self, WorkError> {
        let current = U512::from_big_endian(&self.0);
        let (sum, overflowed) = current.overflowing_add(block_work.to_wide());
        if overflowed {
            return Err(WorkError::CumulativeWorkOverflow);
        }
        Ok(Self(sum.to_big_endian()))
    }
}

impl fmt::Display for CumulativeWork512 {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&hex::encode(self.0))
    }
}

/// Errors from target and work arithmetic.
#[derive(Clone, Copy, Debug, PartialEq, Eq, thiserror::Error)]
pub enum WorkError {
    /// Configured bounds are zero or reversed.
    #[error("invalid target bounds")]
    InvalidTargetBounds,
    /// A block target is outside its inclusive consensus bounds.
    #[error("target is outside the configured consensus bounds")]
    TargetOutOfRange,
    /// A fixed-width conversion would discard significant bits.
    #[error("fixed-width integer conversion overflow")]
    IntegerConversionOverflow,
    /// Accumulated work cannot be represented in 512 bits.
    #[error("cumulative work overflow")]
    CumulativeWorkOverflow,
}

/// Calculates `floor((2^256 - 1) / (target + 1)) + 1` exactly.
pub fn calculate_block_work(target: Target256) -> Result<BlockWork256, WorkError> {
    if target.is_zero() {
        return Err(WorkError::TargetOutOfRange);
    }

    let one = U512::one();
    let numerator = (one << 256) - one;
    let denominator = U512::from(target.to_uint()) + one;
    let work = (numerator / denominator) + one;
    let narrowed = U256::try_from(work).map_err(|_| WorkError::IntegerConversionOverflow)?;
    Ok(BlockWork256::from_uint(narrowed))
}

/// Calculates the exact work contribution for a validated nonzero target.
pub fn block_work(target: Target256) -> Result<BlockWork256, WorkError> {
    calculate_block_work(target)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn target_borsh_is_exactly_big_endian_bytes() {
        let mut bytes = [0_u8; 32];
        bytes[0] = 0x12;
        bytes[31] = 0x34;
        let target = Target256::from_be_bytes(bytes);
        let encoded = borsh::to_vec(&target).expect("encode target");
        assert_eq!(encoded, bytes);
        assert_eq!(Target256::try_from_slice(&encoded).expect("decode"), target);
    }

    #[test]
    fn big_endian_order_matches_numeric_order() {
        let one = Target256::ONE;
        let mut two_bytes = [0_u8; 32];
        two_bytes[31] = 2;
        let two = Target256::from_be_bytes(two_bytes);
        let mut two_fifty_six_bytes = [0_u8; 32];
        two_fifty_six_bytes[30] = 1;
        let two_fifty_six = Target256::from_be_bytes(two_fifty_six_bytes);
        assert!(one < two);
        assert!(two < two_fifty_six);
    }

    #[test]
    fn block_work_matches_exact_boundary_vectors() {
        let easiest = calculate_block_work(Target256::MAX).expect("maximum target");
        assert_eq!(easiest.as_be_bytes(), Target256::ONE.as_be_bytes());

        let mut half_minus_one = [0xff_u8; 32];
        half_minus_one[0] = 0x7f;
        let work = calculate_block_work(Target256::from_be_bytes(half_minus_one))
            .expect("half-space target");
        let mut expected_two = [0_u8; 32];
        expected_two[31] = 2;
        assert_eq!(work.as_be_bytes(), &expected_two);

        let hardest = calculate_block_work(Target256::ONE).expect("hardest target");
        let mut expected_hardest = [0_u8; 32];
        expected_hardest[0] = 0x80;
        assert_eq!(hardest.as_be_bytes(), &expected_hardest);
    }

    #[test]
    fn cumulative_work_is_checked_and_big_endian() {
        let work = calculate_block_work(Target256::MAX).expect("work");
        let accumulated = CumulativeWork512::ZERO
            .checked_add_block(work)
            .expect("sum");
        assert_eq!(accumulated.as_be_bytes()[63], 1);
        assert_eq!(borsh::to_vec(&accumulated).expect("encode").len(), 64);
        assert_eq!(
            CumulativeWork512::MAX.checked_add_block(work),
            Err(WorkError::CumulativeWorkOverflow)
        );
    }

    #[test]
    fn target_bounds_fail_closed() {
        assert_eq!(
            Target256::ONE.validate_bounds(Target256::ZERO, Target256::MAX),
            Err(WorkError::InvalidTargetBounds)
        );
        assert_eq!(
            Target256::ZERO.validate_bounds(Target256::ONE, Target256::MAX),
            Err(WorkError::TargetOutOfRange)
        );
    }
}
