use crate::{hash_tagged, Hash256, Target256, WorkError};
use argon2::{Algorithm, Argon2, Params, Version};
use borsh::{BorshDeserialize, BorshSerialize};
use std::fmt;

/// Consensus algorithm identifier for RFC 9106 Argon2d version 0x13.
pub const POW_ALGORITHM_ARGON2D_V13: u16 = 1;

/// Frozen Argon2d parameters for Aura `PoW` Devnet v2.
pub const DEVNET_V2_POW_PARAMETERS: PowParameters = PowParameters {
    memory_cost_kib: 65_536,
    time_cost: 1,
    lanes: 1,
};

/// Consensus-fixed Argon2d resource parameters.
#[derive(Clone, Copy, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct PowParameters {
    /// Argon2 memory in kibibytes.
    pub memory_cost_kib: u32,
    /// Argon2 passes.
    pub time_cost: u32,
    /// Argon2 lanes per independent attempt.
    pub lanes: u32,
}

impl PowParameters {
    /// Constructs a parameter set. Call [`Self::validate`] before use.
    #[must_use]
    pub const fn new(memory_cost_kib: u32, time_cost: u32, lanes: u32) -> Self {
        Self {
            memory_cost_kib,
            time_cost,
            lanes,
        }
    }

    /// Validates these values through the pinned Argon2 implementation.
    pub fn validate(self) -> Result<(), PowError> {
        self.argon2_params().map(|_| ())
    }

    fn argon2_params(self) -> Result<Params, PowError> {
        Params::new(self.memory_cost_kib, self.time_cost, self.lanes, Some(32))
            .map_err(|error| PowError::InvalidParameters(error.to_string()))
    }
}

/// A computed Argon2d work result interpreted as a big-endian integer.
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
pub struct PowDigest([u8; 32]);

impl PowDigest {
    /// Constructs a work result from its big-endian bytes.
    #[must_use]
    pub const fn from_be_bytes(bytes: [u8; 32]) -> Self {
        Self(bytes)
    }

    /// Returns the exact big-endian work-result bytes.
    #[must_use]
    pub const fn as_be_bytes(&self) -> &[u8; 32] {
        &self.0
    }
}

impl fmt::Display for PowDigest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&hex::encode(self.0))
    }
}

/// Target inputs that must agree before an expensive `PoW` verification begins.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PowTargetRequirement {
    /// Target encoded in the candidate header.
    pub declared: Target256,
    /// Target deterministically required by the parent chain.
    pub required: Target256,
    /// Hardest target allowed by the network specification.
    pub minimum: Target256,
    /// Easiest target allowed by the network specification.
    pub pow_limit: Target256,
}

/// Proof-of-Work construction and validation errors.
#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
pub enum PowError {
    /// The pinned Argon2 implementation rejected consensus parameters.
    #[error("invalid Argon2d parameters: {0}")]
    InvalidParameters(String),
    /// Argon2 failed after parameters were accepted.
    #[error("Argon2d work calculation failed: {0}")]
    CalculationFailed(String),
    /// A candidate claims a target other than the deterministic required target.
    #[error("candidate target does not equal the required target")]
    TargetMismatch,
    /// Target bounds or the candidate target are invalid.
    #[error("invalid Proof-of-Work target: {0}")]
    InvalidTarget(WorkError),
    /// The calculated work integer is greater than the target.
    #[error("calculated work does not satisfy the target")]
    InsufficientWork,
}

/// Returns Aura's domain-separated SHA-256 digest of the canonical v2 header.
#[must_use]
pub fn pow_message_digest(canonical_header_bytes: &[u8]) -> Hash256 {
    hash_tagged("pow/message/v1", &[canonical_header_bytes])
}

/// Returns the parent-specific, non-miner-selectable 32-byte Argon2 salt.
#[must_use]
pub fn pow_salt(chain_id_hash: Hash256, parent_block_id: Hash256) -> Hash256 {
    hash_tagged(
        "pow/salt/v1",
        &[chain_id_hash.as_bytes(), parent_block_id.as_bytes()],
    )
}

/// Computes one genuine Argon2d version-0x13 work attempt.
pub fn calculate_argon2d_work(
    canonical_header_bytes: &[u8],
    chain_id_hash: Hash256,
    parent_block_id: Hash256,
    parameters: PowParameters,
) -> Result<PowDigest, PowError> {
    let params = parameters.argon2_params()?;
    let argon2 = Argon2::new(Algorithm::Argon2d, Version::V0x13, params);
    let message = pow_message_digest(canonical_header_bytes);
    let salt = pow_salt(chain_id_hash, parent_block_id);
    let mut output = [0_u8; 32];
    argon2
        .hash_password_into(message.as_bytes(), salt.as_bytes(), &mut output)
        .map_err(|error| PowError::CalculationFailed(error.to_string()))?;
    Ok(PowDigest(output))
}

/// Performs the cheap deterministic target checks for an already computed digest.
pub fn verify_pow_digest(
    digest: PowDigest,
    requirement: PowTargetRequirement,
) -> Result<(), PowError> {
    validate_target_requirement(requirement)?;
    if digest.as_be_bytes() > requirement.required.as_be_bytes() {
        return Err(PowError::InsufficientWork);
    }
    Ok(())
}

fn validate_target_requirement(requirement: PowTargetRequirement) -> Result<(), PowError> {
    if requirement.declared != requirement.required {
        return Err(PowError::TargetMismatch);
    }
    requirement
        .required
        .validate_bounds(requirement.minimum, requirement.pow_limit)
        .map_err(PowError::InvalidTarget)?;
    Ok(())
}

/// Checks target agreement and bounds, recomputes Argon2d, then verifies the result.
pub fn verify_argon2d_pow(
    canonical_header_bytes: &[u8],
    chain_id_hash: Hash256,
    parent_block_id: Hash256,
    requirement: PowTargetRequirement,
    parameters: PowParameters,
) -> Result<PowDigest, PowError> {
    // These inexpensive checks deliberately precede the memory-hard operation.
    validate_target_requirement(requirement)?;

    let digest = calculate_argon2d_work(
        canonical_header_bytes,
        chain_id_hash,
        parent_block_id,
        parameters,
    )?;
    verify_pow_digest(digest, requirement)?;
    Ok(digest)
}

#[cfg(test)]
mod tests {
    use super::*;
    use argon2::{AssociatedData, ParamsBuilder};

    const TEST_PARAMETERS: PowParameters = PowParameters::new(32, 1, 1);

    #[test]
    fn rfc_9106_argon2d_vector_matches() {
        let params = ParamsBuilder::new()
            .m_cost(32)
            .t_cost(3)
            .p_cost(4)
            .data(AssociatedData::new(&[0x04; 12]).expect("associated data"))
            .build()
            .expect("RFC parameters");
        let argon2 =
            Argon2::new_with_secret(&[0x03; 8], Algorithm::Argon2d, Version::V0x13, params)
                .expect("RFC secret");
        let mut output = [0_u8; 32];
        argon2
            .hash_password_into(&[0x01; 32], &[0x02; 16], &mut output)
            .expect("RFC vector");
        assert_eq!(
            hex::encode(output),
            "512b391b6f1162975371d30919734294f868e3be3984f3c1a13a4db9fabe4acb"
        );
    }

    #[test]
    fn aura_pow_vector_is_stable() {
        let digest = calculate_argon2d_work(
            b"Aura Devnet v2 work vector",
            Hash256::from_bytes([0x11; 32]),
            Hash256::from_bytes([0x22; 32]),
            TEST_PARAMETERS,
        )
        .expect("work");
        assert_eq!(
            digest.to_string(),
            "9f5478f33780f8cfa6ddc100eeeb2b19dbe94732b5985f2f33dbbb58718912a4"
        );
    }

    #[test]
    fn equality_is_valid_and_one_less_is_invalid() {
        let digest = calculate_argon2d_work(
            b"threshold boundary",
            Hash256::from_bytes([3; 32]),
            Hash256::from_bytes([4; 32]),
            TEST_PARAMETERS,
        )
        .expect("work");
        let exact = Target256::from_be_bytes(*digest.as_be_bytes());
        verify_pow_digest(
            digest,
            PowTargetRequirement {
                declared: exact,
                required: exact,
                minimum: Target256::ONE,
                pow_limit: Target256::MAX,
            },
        )
        .expect("equality must pass");

        let smaller = Target256::from_uint(exact.to_uint() - 1);
        assert_eq!(
            verify_pow_digest(
                digest,
                PowTargetRequirement {
                    declared: smaller,
                    required: smaller,
                    minimum: Target256::ONE,
                    pow_limit: Target256::MAX,
                },
            ),
            Err(PowError::InsufficientWork)
        );
    }

    #[test]
    fn fake_and_out_of_range_targets_fail_before_work() {
        let requirement = PowTargetRequirement {
            declared: Target256::MAX,
            required: Target256::ONE,
            minimum: Target256::ONE,
            pow_limit: Target256::MAX,
        };
        assert_eq!(
            verify_argon2d_pow(
                b"not evaluated",
                Hash256::ZERO,
                Hash256::ZERO,
                requirement,
                PowParameters::new(0, 0, 0),
            ),
            Err(PowError::TargetMismatch)
        );

        assert!(matches!(
            verify_pow_digest(
                PowDigest::default(),
                PowTargetRequirement {
                    declared: Target256::ZERO,
                    required: Target256::ZERO,
                    minimum: Target256::ONE,
                    pow_limit: Target256::MAX,
                }
            ),
            Err(PowError::InvalidTarget(_))
        ));
    }

    #[test]
    fn domains_and_parent_salt_change_work() {
        let chain = Hash256::from_bytes([7; 32]);
        let parent = Hash256::from_bytes([8; 32]);
        assert_ne!(pow_message_digest(b"a"), pow_message_digest(b"b"));
        assert_ne!(pow_salt(chain, parent), pow_salt(chain, Hash256::ZERO));

        let first = calculate_argon2d_work(b"a", chain, parent, TEST_PARAMETERS).expect("first");
        let second = calculate_argon2d_work(b"b", chain, parent, TEST_PARAMETERS).expect("second");
        assert_ne!(first, second);
    }
}
