use crate::{Target256, WorkError};
use borsh::{BorshDeserialize, BorshSerialize};
use primitive_types::U512;

const ASERT_RADIX: i128 = 65_536;

/// Frozen target and timestamp parameters for Aura `PoW` Devnet v2.
pub const DEVNET_V2_DIFFICULTY_PARAMETERS: DifficultyParameters = DifficultyParameters {
    target_block_interval_seconds: 15,
    asert_half_life_seconds: 3_600,
    initial_target: Target256::from_be_bytes([
        0x0f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff,
    ]),
    pow_limit: Target256::from_be_bytes([
        0x0f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
        0xff, 0xff,
    ]),
    minimum_target: Target256::ONE,
    median_time_window: 11,
    maximum_future_drift_seconds: 120,
};

/// Consensus parameters for ASERT target calculation and timestamp checks.
#[derive(Clone, Copy, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct DifficultyParameters {
    /// Desired mean seconds between blocks.
    pub target_block_interval_seconds: u64,
    /// Schedule error that changes the target by a factor of two.
    pub asert_half_life_seconds: u64,
    /// Target at the fixed genesis schedule anchor.
    pub initial_target: Target256,
    /// Easiest permitted target.
    pub pow_limit: Target256,
    /// Hardest permitted target.
    pub minimum_target: Target256,
    /// Number of prior timestamps used by median-time-past.
    pub median_time_window: u8,
    /// Live-admission tolerance beyond local system time.
    pub maximum_future_drift_seconds: u64,
}

impl DifficultyParameters {
    /// Validates all deterministic bounds before target calculation.
    pub fn validate(self) -> Result<(), DifficultyError> {
        if self.target_block_interval_seconds == 0 {
            return Err(DifficultyError::InvalidParameters(
                "target block interval must be positive",
            ));
        }
        if self.asert_half_life_seconds == 0 {
            return Err(DifficultyError::InvalidParameters(
                "ASERT half-life must be positive",
            ));
        }
        if self.median_time_window == 0 {
            return Err(DifficultyError::InvalidParameters(
                "median-time window must be positive",
            ));
        }
        self.initial_target
            .validate_bounds(self.minimum_target, self.pow_limit)
            .map_err(DifficultyError::InvalidTarget)
    }
}

/// Deterministic target and timestamp validation errors.
#[derive(Clone, Copy, Debug, PartialEq, Eq, thiserror::Error)]
pub enum DifficultyError {
    /// A configured parameter is zero, reversed, or inconsistent.
    #[error("invalid difficulty parameters: {0}")]
    InvalidParameters(&'static str),
    /// Target bounds fail validation.
    #[error("invalid target configuration: {0}")]
    InvalidTarget(WorkError),
    /// Signed or fixed-width consensus arithmetic overflowed.
    #[error("difficulty arithmetic overflow")]
    ArithmeticOverflow,
    /// No prior block timestamp was supplied for MTP.
    #[error("median-time-past requires at least one previous timestamp")]
    EmptyTimestampHistory,
    /// A candidate did not strictly exceed median time past.
    #[error("candidate timestamp must be greater than median time past")]
    TimestampNotAfterMedian,
    /// A live candidate is beyond the configured future drift.
    #[error("candidate timestamp is too far in the future")]
    TimestampTooFarInFuture,
}

/// Calculates the target required for the child of the supplied parent.
pub fn calculate_asert_target(
    parent_height: u64,
    parent_timestamp_seconds: u64,
    genesis_timestamp_seconds: u64,
    parameters: DifficultyParameters,
) -> Result<Target256, DifficultyError> {
    parameters.validate()?;

    let elapsed = i128::from(parent_timestamp_seconds)
        .checked_sub(i128::from(genesis_timestamp_seconds))
        .ok_or(DifficultyError::ArithmeticOverflow)?;
    let scheduled = i128::from(parameters.target_block_interval_seconds)
        .checked_mul(i128::from(parent_height))
        .ok_or(DifficultyError::ArithmeticOverflow)?;
    let schedule_error = elapsed
        .checked_sub(scheduled)
        .ok_or(DifficultyError::ArithmeticOverflow)?;
    let scaled_error = schedule_error
        .checked_mul(ASERT_RADIX)
        .ok_or(DifficultyError::ArithmeticOverflow)?;
    // Rust signed division truncates toward zero, as required by ASERT.
    let exponent = scaled_error / i128::from(parameters.asert_half_life_seconds);
    target_from_exponent(exponent, parameters)
}

fn target_from_exponent(
    exponent: i128,
    parameters: DifficultyParameters,
) -> Result<Target256, DifficultyError> {
    let shifts = exponent.div_euclid(ASERT_RADIX);
    let fraction = exponent.rem_euclid(ASERT_RADIX);
    let fraction = u128::try_from(fraction).map_err(|_| DifficultyError::ArithmeticOverflow)?;

    let fraction_squared = fraction
        .checked_mul(fraction)
        .ok_or(DifficultyError::ArithmeticOverflow)?;
    let fraction_cubed = fraction_squared
        .checked_mul(fraction)
        .ok_or(DifficultyError::ArithmeticOverflow)?;
    let polynomial = 195_766_423_245_049_u128
        .checked_mul(fraction)
        .and_then(|value| {
            971_821_376_u128
                .checked_mul(fraction_squared)
                .and_then(|term| value.checked_add(term))
        })
        .and_then(|value| {
            5_127_u128
                .checked_mul(fraction_cubed)
                .and_then(|term| value.checked_add(term))
        })
        .and_then(|value| value.checked_add(1_u128 << 47))
        .ok_or(DifficultyError::ArithmeticOverflow)?;
    let factor = 65_536_u128
        .checked_add(polynomial >> 48)
        .ok_or(DifficultyError::ArithmeticOverflow)?;

    let initial = U512::from(parameters.initial_target.to_uint());
    let mut scaled = initial * U512::from(factor);
    let maximum_scaled = U512::from(parameters.pow_limit.to_uint()) << 16;

    if shifts >= 0 {
        let left = usize::try_from(shifts).map_err(|_| DifficultyError::ArithmeticOverflow)?;
        if left >= 512 || scaled > (maximum_scaled >> left) {
            return Ok(parameters.pow_limit);
        }
        scaled <<= left;
    } else {
        let right_i128 = shifts
            .checked_neg()
            .ok_or(DifficultyError::ArithmeticOverflow)?;
        let right = usize::try_from(right_i128).map_err(|_| DifficultyError::ArithmeticOverflow)?;
        if right >= 512 {
            return Ok(parameters.minimum_target);
        }
        scaled >>= right;
    }

    let result = scaled >> 16;
    let minimum = U512::from(parameters.minimum_target.to_uint());
    let maximum = U512::from(parameters.pow_limit.to_uint());
    if result < minimum {
        return Ok(parameters.minimum_target);
    }
    if result > maximum {
        return Ok(parameters.pow_limit);
    }
    Target256::try_from_wide(result).map_err(DifficultyError::InvalidTarget)
}

/// Returns the lower median of the final configured number of timestamps.
pub fn median_time_past(previous_timestamps: &[u64], window: u8) -> Result<u64, DifficultyError> {
    if previous_timestamps.is_empty() {
        return Err(DifficultyError::EmptyTimestampHistory);
    }
    if window == 0 {
        return Err(DifficultyError::InvalidParameters(
            "median-time window must be positive",
        ));
    }
    let count = previous_timestamps.len().min(usize::from(window));
    let mut timestamps = previous_timestamps[previous_timestamps.len() - count..].to_vec();
    timestamps.sort_unstable();
    Ok(timestamps[(timestamps.len() - 1) / 2])
}

/// Enforces the deterministic `candidate > median(previous)` timestamp rule.
pub fn validate_consensus_timestamp(
    candidate_timestamp_seconds: u64,
    previous_timestamps: &[u64],
    window: u8,
) -> Result<(), DifficultyError> {
    if candidate_timestamp_seconds <= median_time_past(previous_timestamps, window)? {
        return Err(DifficultyError::TimestampNotAfterMedian);
    }
    Ok(())
}

/// Enforces the live-admission wall-clock future bound.
pub fn validate_live_timestamp(
    candidate_timestamp_seconds: u64,
    local_time_seconds: u64,
    maximum_future_drift_seconds: u64,
) -> Result<(), DifficultyError> {
    let latest = local_time_seconds.saturating_add(maximum_future_drift_seconds);
    if candidate_timestamp_seconds > latest {
        return Err(DifficultyError::TimestampTooFarInFuture);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use primitive_types::U256;

    fn target_with_first_byte(byte: u8) -> Target256 {
        let mut bytes = [0_u8; 32];
        bytes[0] = byte;
        Target256::from_be_bytes(bytes)
    }

    fn parameters() -> DifficultyParameters {
        DifficultyParameters {
            target_block_interval_seconds: 15,
            asert_half_life_seconds: 3_600,
            initial_target: target_with_first_byte(4),
            pow_limit: target_with_first_byte(16),
            minimum_target: Target256::ONE,
            median_time_window: 11,
            maximum_future_drift_seconds: 120,
        }
    }

    #[test]
    fn devnet_parameters_match_the_frozen_specification() {
        DEVNET_V2_DIFFICULTY_PARAMETERS
            .validate()
            .expect("valid Devnet parameters");
        assert_eq!(
            DEVNET_V2_DIFFICULTY_PARAMETERS.initial_target.to_string(),
            "0fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
        );
    }

    #[test]
    fn on_schedule_target_is_unchanged() {
        let params = parameters();
        let target = calculate_asert_target(300, 5_500, 1_000, params).expect("target");
        assert_eq!(target, params.initial_target);
    }

    #[test]
    fn half_life_fast_and_slow_adjust_by_two() {
        let params = parameters();
        let fast = calculate_asert_target(300, 1_900, 1_000, params).expect("fast target");
        let slow = calculate_asert_target(300, 9_100, 1_000, params).expect("slow target");
        assert_eq!(fast, target_with_first_byte(2));
        assert_eq!(slow, target_with_first_byte(8));
    }

    #[test]
    fn negative_fraction_uses_truncation_and_euclidean_split() {
        let mut params = parameters();
        params.target_block_interval_seconds = 1;
        params.asert_half_life_seconds = 65_536;
        let elapsed = 0_i128;
        let scheduled = 1_i128;
        let exponent =
            ((elapsed - scheduled) * ASERT_RADIX) / i128::from(params.asert_half_life_seconds);
        assert_eq!(exponent, -1);
        assert_eq!(exponent.div_euclid(ASERT_RADIX), -1);
        assert_eq!(exponent.rem_euclid(ASERT_RADIX), 65_535);
        let target = calculate_asert_target(1, 1_000, 1_000, params).expect("fractional target");
        assert!(target < params.initial_target);
    }

    #[test]
    fn extreme_schedule_errors_saturate_to_bounds() {
        let params = parameters();
        let easiest = calculate_asert_target(1, u64::MAX, 0, params).expect("easy clamp");
        let hardest = calculate_asert_target(u64::MAX, 0, u64::MAX, params).expect("hard clamp");
        assert_eq!(easiest, params.pow_limit);
        assert_eq!(hardest, params.minimum_target);
    }

    #[test]
    fn invalid_parameters_and_arithmetic_fail_closed() {
        let mut params = parameters();
        params.asert_half_life_seconds = 0;
        assert!(matches!(
            calculate_asert_target(0, 0, 0, params),
            Err(DifficultyError::InvalidParameters(_))
        ));

        let params = DifficultyParameters {
            target_block_interval_seconds: u64::MAX,
            ..parameters()
        };
        assert_eq!(
            calculate_asert_target(u64::MAX, 0, 0, params),
            Err(DifficultyError::ArithmeticOverflow)
        );
    }

    #[test]
    fn median_and_timestamp_boundaries_are_exact() {
        let timestamps = [11, 1, 10, 2, 9, 3, 8, 4, 7, 5, 6, 100];
        // The final eleven values are 1..10 plus 100, whose median is 6.
        assert_eq!(median_time_past(&timestamps, 11).expect("median"), 6);
        assert_eq!(
            validate_consensus_timestamp(6, &timestamps, 11),
            Err(DifficultyError::TimestampNotAfterMedian)
        );
        validate_consensus_timestamp(7, &timestamps, 11).expect("MTP + 1");

        validate_live_timestamp(1_120, 1_000, 120).expect("future boundary");
        assert_eq!(
            validate_live_timestamp(1_121, 1_000, 120),
            Err(DifficultyError::TimestampTooFarInFuture)
        );
    }

    #[test]
    fn lower_median_is_frozen_during_bootstrap() {
        assert_eq!(median_time_past(&[40, 10], 11).expect("median"), 10);
    }

    fn target_from_compact(bits: u32) -> Target256 {
        let size = bits >> 24;
        let word = bits & 0x007f_ffff;
        let value = if size <= 3 {
            U256::from(word >> (8 * (3 - size)))
        } else {
            U256::from(word) << usize::try_from(8 * (size - 3)).expect("small compact shift")
        };
        Target256::from_uint(value)
    }

    fn target_to_compact(target: Target256, pow_limit: Target256) -> u32 {
        let value = target.to_uint().min(pow_limit.to_uint());
        let mut size = u32::try_from(value.bits().div_ceil(8)).expect("256-bit size");
        let mut compact = if size <= 3 {
            (value << usize::try_from(8 * (3 - size)).expect("small compact shift")).low_u32()
        } else {
            (value >> usize::try_from(8 * (size - 3)).expect("small compact shift")).low_u32()
        };
        if compact & 0x0080_0000 != 0 {
            compact >>= 8;
            size += 1;
        }
        (compact & 0x007f_ffff) | (size << 24)
    }

    fn assert_bchn_vectors(anchor_bits: u32, vectors: &[(u64, u64, u32)]) {
        let pow_limit = target_from_compact(0x1d00_ffff);
        let parameters = DifficultyParameters {
            target_block_interval_seconds: 600,
            asert_half_life_seconds: 172_800,
            initial_target: target_from_compact(anchor_bits),
            pow_limit,
            minimum_target: Target256::ONE,
            median_time_window: 11,
            maximum_future_drift_seconds: 120,
        };
        for (height, timestamp, expected_bits) in vectors {
            // BCHN's vectors anchor at block height 1 and its parent's time 0. Their
            // `height_diff + 1` coordinate is Aura's relative parent-height coordinate.
            let relative_parent_height = height.checked_sub(1).expect("height after anchor") + 1;
            let target = calculate_asert_target(relative_parent_height, *timestamp, 0, parameters)
                .expect("ASERT vector target");
            assert_eq!(
                target_to_compact(target, pow_limit),
                *expected_bits,
                "BCHN vector height {height}, timestamp {timestamp}"
            );
        }
    }

    #[test]
    fn bchn_aserti3_2d_reference_vectors_match_after_full_target_adaptation() {
        // Published BCHN qa-assets runs 04, 05, and 06. Aura keeps the full target internally;
        // compact conversion occurs here only to compare with the source vector corpus.
        assert_bchn_vectors(
            0x0101_0000,
            &[
                (2, 174_000, 0x0102_0000),
                (3, 347_400, 0x0104_0000),
                (7, 1_041_000, 0x0140_0000),
                (8, 1_214_400, 0x0200_8000),
                (13, 2_081_400, 0x0210_0000),
            ],
        );
        assert_bchn_vectors(
            0x1d00_ffff,
            &[
                (2, 0, 0x1d00_fec5),
                (290, 0, 0x1c7f_62c0),
                (866, 0, 0x1c1f_d8b0),
                (2_306, 0, 0x1c00_fec5),
                (3_170, 0, 0x1b1f_d8b0),
            ],
        );
        assert_bchn_vectors(
            0x1802_aee8,
            &[
                (2, 1_200, 0x1802_aee8),
                (3, 1_310, 0x1802_ad91),
                (4, 1_327, 0x1802_abf8),
                (8, 2_746, 0x1802_a94b),
                (9, 7_099, 0x1802_b39c),
                (13, 8_816, 0x1802_b1b7),
            ],
        );
    }
}
