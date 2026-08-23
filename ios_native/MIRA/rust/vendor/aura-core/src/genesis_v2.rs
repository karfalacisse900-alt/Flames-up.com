use crate::{hash_tagged, Address, Amount, Error, Hash256, Network, Result, Target256};
use borsh::{BorshDeserialize, BorshSerialize};

/// Canonical protocol version for Aura's first Proof-of-Work development chain.
pub const POW_PROTOCOL_VERSION: u16 = 2;
/// Argon2d-v0x13 consensus algorithm identifier.
pub const ARGON2D_POW_ALGORITHM_ID: u16 = 1;
/// Built-in `PoW` Devnet chain identity. It is deliberately distinct from Phase 1.
pub const POW_DEVNET_CHAIN_ID: &str = "aura-devnet-pow-v2";
/// Built-in `PoW` Devnet genesis time: 2026-08-22T00:00:00Z.
pub const POW_DEVNET_GENESIS_TIME_SECONDS: u64 = 1_787_356_800;
/// Operational bound for the canonical v2 genesis-configuration encoding.
pub const MAX_GENESIS_CONFIG_V2_BYTES: usize = 64 * 1024;

const MAXIMUM_BLOCK_BYTES_LIMIT: u32 = 16 * 1024 * 1024;
const MINIMUM_TRANSACTION_BYTES_LIMIT: u32 = 256;
const MAXIMUM_TRANSACTION_BYTES_LIMIT: u32 = 1024 * 1024;
const MAXIMUM_TRANSACTIONS_LIMIT: u32 = 50_000;
const MAXIMUM_ARGON_MEMORY_KIB: u32 = 1024 * 1024;

/// Resource and transaction limits committed by the v2 genesis specification.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct ConsensusLimitsV2 {
    pub maximum_block_bytes: u32,
    pub maximum_transaction_bytes: u32,
    /// Includes the mandatory coinbase on non-genesis blocks.
    pub maximum_transactions_per_block: u32,
    pub minimum_fee: Amount,
}

/// Explicit Devnet issuance rules. These are not Mainnet economics.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct EconomicParametersV2 {
    pub atoms_per_aur: u64,
    pub block_subsidy: Amount,
    pub maximum_supply: Amount,
    /// Zero means maturity is not adopted and a canonical reward is immediately spendable.
    pub coinbase_maturity_blocks: u32,
}

/// Argon2d, target, ASERT, and timestamp parameters committed at genesis.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct PowParametersV2 {
    pub algorithm_id: u16,
    pub argon_memory_kib: u32,
    pub argon_time_cost: u32,
    pub argon_lanes: u32,
    pub argon_output_bytes: u32,
    pub target_block_interval_seconds: u64,
    pub asert_half_life_seconds: u64,
    pub initial_target: Target256,
    pub pow_limit: Target256,
    pub minimum_target: Target256,
    pub median_time_window: u16,
    pub maximum_future_drift_seconds: u64,
}

/// A transparent genesis allocation committed to a v2 genesis hash.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct GenesisAllocationV2 {
    pub address: Address,
    pub available: Amount,
    pub locked: Amount,
    pub purpose: String,
}

/// Complete, canonical identity of an Aura `PoW` v2 chain.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct PowGenesisConfigV2 {
    pub protocol_version: u16,
    pub chain_name: String,
    pub chain_id: String,
    pub network: Network,
    pub genesis_time_seconds: u64,
    pub limits: ConsensusLimitsV2,
    pub economics: EconomicParametersV2,
    pub pow: PowParametersV2,
    pub allocations: Vec<GenesisAllocationV2>,
}

impl PowGenesisConfigV2 {
    /// Returns the built-in, zero-allocation Argon2d development chain.
    ///
    /// Its easy initial target and economics are local development parameters, not a public
    /// launch promise or production security level.
    #[must_use]
    pub fn builtin_devnet() -> Self {
        let mut easiest = [0xff_u8; 32];
        easiest[0] = 0x0f;
        let mut minimum = [0_u8; 32];
        minimum[31] = 1;
        Self {
            protocol_version: POW_PROTOCOL_VERSION,
            chain_name: "Aura PoW Devnet v2".into(),
            chain_id: POW_DEVNET_CHAIN_ID.into(),
            network: Network::Devnet,
            genesis_time_seconds: POW_DEVNET_GENESIS_TIME_SECONDS,
            limits: ConsensusLimitsV2 {
                maximum_block_bytes: 2 * 1024 * 1024,
                maximum_transaction_bytes: 2 * 1024,
                maximum_transactions_per_block: 10_000,
                minimum_fee: Amount::from_atoms(1_000),
            },
            economics: EconomicParametersV2 {
                atoms_per_aur: crate::ATOMS_PER_AUR,
                block_subsidy: Amount::from_atoms(8 * crate::ATOMS_PER_AUR),
                maximum_supply: Amount::from_atoms(1_000_000_000_u64 * crate::ATOMS_PER_AUR),
                coinbase_maturity_blocks: 0,
            },
            pow: PowParametersV2 {
                algorithm_id: ARGON2D_POW_ALGORITHM_ID,
                argon_memory_kib: 65_536,
                argon_time_cost: 1,
                argon_lanes: 1,
                argon_output_bytes: 32,
                target_block_interval_seconds: 15,
                asert_half_life_seconds: 3_600,
                initial_target: Target256::from_be_bytes(easiest),
                pow_limit: Target256::from_be_bytes(easiest),
                minimum_target: Target256::from_be_bytes(minimum),
                median_time_window: 11,
                maximum_future_drift_seconds: 120,
            },
            allocations: Vec::new(),
        }
    }

    /// A separate, explicitly non-interoperable profile for fast automated tests.
    ///
    /// It cannot be mistaken for the built-in `PoW` Devnet because its chain ID, parameters,
    /// configuration hash, and genesis block are different.
    #[must_use]
    pub fn local_regtest() -> Self {
        let mut config = Self::builtin_devnet();
        config.chain_name = "Aura local PoW regtest v2".into();
        config.chain_id = "aura-devnet-pow-regtest-v2".into();
        config.genesis_time_seconds = 0;
        config.pow.argon_memory_kib = 1_024;
        config.pow.target_block_interval_seconds = 1;
        config.pow.asert_half_life_seconds = 60;
        config.pow.initial_target = Target256::from_be_bytes([0xff; 32]);
        config.pow.pow_limit = Target256::from_be_bytes([0xff; 32]);
        config
    }

    /// Validates every bounded field and rejects public-network activation.
    pub fn validate(&self) -> Result<()> {
        if self.protocol_version != POW_PROTOCOL_VERSION {
            return Err(Error::InvalidGenesis(format!(
                "PoW v2 requires protocol_version {POW_PROTOCOL_VERSION}"
            )));
        }
        if self.network != Network::Devnet {
            return Err(Error::ConsensusUnavailable);
        }
        validate_text(&self.chain_name, 1, 64, "chain_name")?;
        validate_chain_id(&self.chain_id)?;
        self.validate_limits()?;
        self.validate_economics()?;
        self.validate_pow()?;
        self.validate_allocations()?;
        Ok(())
    }

    fn validate_limits(&self) -> Result<()> {
        if !(MINIMUM_TRANSACTION_BYTES_LIMIT..=MAXIMUM_TRANSACTION_BYTES_LIMIT)
            .contains(&self.limits.maximum_transaction_bytes)
        {
            return Err(Error::InvalidGenesis(format!(
                "maximum_transaction_bytes must be in {MINIMUM_TRANSACTION_BYTES_LIMIT}..={MAXIMUM_TRANSACTION_BYTES_LIMIT}"
            )));
        }
        let minimum_non_genesis_block = crate::EMPTY_BLOCK_V2_SIZE
            .checked_add(crate::MIN_TRANSACTION_V2_SIZE)
            .ok_or(Error::AmountOverflow)?;
        let minimum_non_genesis_block =
            u32::try_from(minimum_non_genesis_block).map_err(|_| Error::AmountOverflow)?;
        if self.limits.maximum_block_bytes < minimum_non_genesis_block
            || self.limits.maximum_block_bytes < self.limits.maximum_transaction_bytes
            || self.limits.maximum_block_bytes > MAXIMUM_BLOCK_BYTES_LIMIT
        {
            return Err(Error::InvalidGenesis(format!(
                "maximum_block_bytes must fit a header and mandatory coinbase, be at least maximum_transaction_bytes, and be at most {MAXIMUM_BLOCK_BYTES_LIMIT}"
            )));
        }
        if !(1..=MAXIMUM_TRANSACTIONS_LIMIT).contains(&self.limits.maximum_transactions_per_block) {
            return Err(Error::InvalidGenesis(format!(
                "maximum_transactions_per_block must be in 1..={MAXIMUM_TRANSACTIONS_LIMIT}"
            )));
        }
        Ok(())
    }

    fn validate_economics(&self) -> Result<()> {
        if self.economics.atoms_per_aur != crate::ATOMS_PER_AUR {
            return Err(Error::InvalidGenesis(
                "PoW Devnet v2 requires 100,000,000 atoms per AUR".into(),
            ));
        }
        if self.economics.block_subsidy == Amount::ZERO
            || self.economics.maximum_supply == Amount::ZERO
            || self.economics.block_subsidy > self.economics.maximum_supply
        {
            return Err(Error::InvalidGenesis(
                "block subsidy and maximum supply are inconsistent".into(),
            ));
        }
        if self.economics.coinbase_maturity_blocks != 0 {
            return Err(Error::InvalidGenesis(
                "coinbase maturity is not adopted by PoW Devnet v2".into(),
            ));
        }
        if self.limits.minimum_fee > self.economics.maximum_supply {
            return Err(Error::InvalidGenesis(
                "minimum fee exceeds maximum supply".into(),
            ));
        }
        Ok(())
    }

    fn validate_pow(&self) -> Result<()> {
        if self.pow.algorithm_id != ARGON2D_POW_ALGORITHM_ID || self.pow.argon_output_bytes != 32 {
            return Err(Error::InvalidGenesis(
                "PoW Devnet v2 requires Argon2d-v0x13 with a 32-byte output".into(),
            ));
        }
        if !(1_024..=MAXIMUM_ARGON_MEMORY_KIB).contains(&self.pow.argon_memory_kib)
            || !(1..=10).contains(&self.pow.argon_time_cost)
            || !(1..=64).contains(&self.pow.argon_lanes)
            || self.pow.argon_memory_kib < self.pow.argon_lanes.saturating_mul(8)
        {
            return Err(Error::InvalidGenesis(
                "Argon2 resource parameters are outside the supported safe bounds".into(),
            ));
        }
        if !(1..=3_600).contains(&self.pow.target_block_interval_seconds)
            || self.pow.asert_half_life_seconds < self.pow.target_block_interval_seconds
            || self.pow.asert_half_life_seconds > 31_536_000
        {
            return Err(Error::InvalidGenesis(
                "target interval or ASERT half-life is outside supported bounds".into(),
            ));
        }
        if self.pow.minimum_target.is_zero()
            || self.pow.minimum_target > self.pow.initial_target
            || self.pow.initial_target > self.pow.pow_limit
        {
            return Err(Error::InvalidGenesis(
                "minimum_target <= initial_target <= pow_limit and minimum_target > 0 is required"
                    .into(),
            ));
        }
        if self.pow.median_time_window < 3
            || self.pow.median_time_window > 101
            || self.pow.median_time_window % 2 == 0
            || !(1..=3_600).contains(&self.pow.maximum_future_drift_seconds)
        {
            return Err(Error::InvalidGenesis(
                "median-time window or future-drift bound is invalid".into(),
            ));
        }
        Ok(())
    }

    fn validate_allocations(&self) -> Result<()> {
        if !self.allocations.is_empty() {
            return Err(Error::InvalidGenesis(
                "PoW Devnet v2 freezes zero genesis issuance and forbids allocations".into(),
            ));
        }
        Ok(())
    }

    /// Exact subsidy authorized at `height`, capped by remaining supply.
    pub fn subsidy(&self, parent_total_supply: Amount, height: u64) -> Result<Amount> {
        if height == 0 {
            return Err(Error::InvalidHeight {
                expected: 1,
                actual: 0,
            });
        }
        if parent_total_supply > self.economics.maximum_supply {
            return Err(Error::CorruptStore(
                "parent total supply exceeds PoW v2 cap".into(),
            ));
        }
        let remaining = self
            .economics
            .maximum_supply
            .checked_sub(parent_total_supply)?;
        Ok(if remaining < self.economics.block_subsidy {
            remaining
        } else {
            self.economics.block_subsidy
        })
    }

    /// Returns the complete canonical bytes hashed into the v2 network identity.
    pub fn encode(&self) -> Result<Vec<u8>> {
        self.validate()?;
        let bytes = borsh::to_vec(self).map_err(|error| {
            Error::Serialization(format!("v2 genesis configuration encoding failed: {error}"))
        })?;
        if bytes.len() > MAX_GENESIS_CONFIG_V2_BYTES {
            return Err(Error::InvalidGenesis(
                "v2 genesis configuration exceeds its decoding limit".into(),
            ));
        }
        Ok(bytes)
    }

    /// Strictly decodes one bounded canonical v2 genesis configuration.
    pub fn decode(bytes: &[u8]) -> Result<Self> {
        if bytes.len() > MAX_GENESIS_CONFIG_V2_BYTES {
            return Err(Error::InvalidGenesis(
                "v2 genesis configuration exceeds its decoding limit".into(),
            ));
        }
        let config = Self::try_from_slice(bytes).map_err(|error| {
            Error::Serialization(format!("v2 genesis configuration decoding failed: {error}"))
        })?;
        config.validate()?;
        if config.encode()? != bytes {
            return Err(Error::Serialization(
                "v2 genesis configuration is not canonically encoded".into(),
            ));
        }
        Ok(config)
    }

    /// Canonical configuration commitment.
    pub fn config_hash(&self) -> Result<Hash256> {
        let bytes = self.encode()?;
        Ok(hash_tagged("genesis/config/v2", &[&bytes]))
    }

    /// Full network identity used in headers, transactions, handshakes, and replay protection.
    ///
    /// This binds the human-readable chain ID to every encoded consensus parameter, so changing
    /// economics, limits, Proof-of-Work, timestamp, or genesis fields necessarily creates a
    /// different identity even if an operator mistakenly reuses the same text label.
    pub fn consensus_identity_hash(&self) -> Result<Hash256> {
        let config_hash = self.config_hash()?;
        Ok(hash_tagged(
            "chain-id/config/v2",
            &[self.chain_id.as_bytes(), config_hash.as_bytes()],
        ))
    }
}

fn validate_text(value: &str, minimum: usize, maximum: usize, label: &str) -> Result<()> {
    if !(minimum..=maximum).contains(&value.len())
        || value.trim() != value
        || value.chars().any(char::is_control)
    {
        return Err(Error::InvalidGenesis(format!(
            "{label} must contain {minimum}..={maximum} bytes without surrounding whitespace or control characters"
        )));
    }
    Ok(())
}

fn validate_chain_id(value: &str) -> Result<()> {
    let suffix = value.strip_prefix("aura-devnet-").unwrap_or_default();
    if value.len() > 64
        || suffix.is_empty()
        || suffix.starts_with('-')
        || suffix.ends_with('-')
        || suffix.contains("--")
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
    {
        return Err(Error::InvalidGenesis(
            "PoW v2 chain_id must be a bounded lowercase aura-devnet-* identifier".into(),
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builtin_is_zero_allocation_and_reproducible() {
        let config = PowGenesisConfigV2::builtin_devnet();
        config.validate().expect("valid PoW Devnet config");
        assert!(config.allocations.is_empty());
        assert_eq!(
            config.config_hash().expect("hash"),
            config.config_hash().expect("same hash")
        );
        assert_ne!(
            config.consensus_identity_hash().expect("identity"),
            Hash256::ZERO
        );
    }

    #[test]
    fn regtest_cannot_alias_devnet() {
        let devnet = PowGenesisConfigV2::builtin_devnet();
        let regtest = PowGenesisConfigV2::local_regtest();
        regtest.validate().expect("valid isolated regtest");
        assert_ne!(
            devnet.consensus_identity_hash().expect("devnet identity"),
            regtest.consensus_identity_hash().expect("regtest identity")
        );
        assert_ne!(
            devnet.config_hash().expect("devnet hash"),
            regtest.config_hash().expect("regtest hash")
        );
    }

    #[test]
    fn every_consensus_parameter_is_bound_into_network_identity() {
        let baseline = PowGenesisConfigV2::builtin_devnet();
        let baseline_identity = baseline
            .consensus_identity_hash()
            .expect("baseline identity");

        let mut changed_fee = baseline.clone();
        changed_fee.limits.minimum_fee = Amount::from_atoms(
            changed_fee
                .limits
                .minimum_fee
                .atoms()
                .checked_add(1)
                .expect("small fee"),
        );
        assert_ne!(
            changed_fee
                .consensus_identity_hash()
                .expect("changed identity"),
            baseline_identity
        );

        let mut changed_pow = baseline;
        changed_pow.pow.target_block_interval_seconds = 16;
        assert_ne!(
            changed_pow
                .consensus_identity_hash()
                .expect("changed identity"),
            baseline_identity
        );
    }

    #[test]
    fn any_genesis_allocation_is_rejected() {
        let mut config = PowGenesisConfigV2::builtin_devnet();
        config.allocations.push(GenesisAllocationV2 {
            address: Address::from_public_key(Network::Devnet, &[7; 32]),
            available: Amount::from_atoms(1),
            locked: Amount::ZERO,
            purpose: "forbidden premine".into(),
        });
        assert!(matches!(config.validate(), Err(Error::InvalidGenesis(_))));
    }

    #[test]
    fn builtin_config_identity_and_genesis_have_frozen_golden_hashes() {
        let config = PowGenesisConfigV2::builtin_devnet();
        let state = crate::LedgerStateV2::from_genesis(&config).expect("state");
        let state_root = state.root().expect("state root");
        let genesis = crate::BlockV2::genesis(&config, state_root).expect("genesis");
        assert_eq!(
            hex::encode(config.encode().expect("config bytes")),
            "0200120000004175726120506f57204465766e657420763212000000617572612d6465766e65742d706f772d76320352554180e6886a00000000000020000008000010270000e80300000000000000e1f505000000000008af2f0000000000008a5d78456301000000000100000001000100000001000000200000000f00000000000000100e0000000000000fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000010b00780000000000000000000000"
        );
        assert_eq!(
            state_root.to_string(),
            "17a81e9a2e8d56266baf9f3b9136d28ea2f381eea1fead0aad46b6b06bfcb92f"
        );
        assert_eq!(
            config.config_hash().expect("config hash").to_string(),
            "12dc2d3543ba366e0914d6664b61ee05a3ab4fac863801be5ad40b769f0de352"
        );
        assert_eq!(
            config
                .consensus_identity_hash()
                .expect("identity")
                .to_string(),
            "cd1367f5feceec31b754d7e9044443aa5df65a834ae592ed376cd7eb511c9899"
        );
        assert_eq!(
            genesis.id().expect("genesis ID").to_string(),
            "292fd5d47d522ea52b405e1dd43ae1ccf5700ed49712bc9a45c73a1542a69b87"
        );
        let bytes = config.encode().expect("bytes");
        assert_eq!(PowGenesisConfigV2::decode(&bytes).expect("decode"), config);
        let mut trailing = bytes;
        trailing.push(0);
        assert!(PowGenesisConfigV2::decode(&trailing).is_err());
        assert!(PowGenesisConfigV2::decode(&vec![0; MAX_GENESIS_CONFIG_V2_BYTES + 1]).is_err());
    }

    #[test]
    fn production_networks_and_unsafe_pow_parameters_fail_closed() {
        let baseline = PowGenesisConfigV2::builtin_devnet();

        let mut mainnet = baseline.clone();
        mainnet.network = Network::Mainnet;
        assert!(matches!(
            mainnet.validate(),
            Err(Error::ConsensusUnavailable)
        ));

        let mut zero_target = baseline.clone();
        zero_target.pow.minimum_target = Target256::from_be_bytes([0; 32]);
        assert!(zero_target.validate().is_err());

        let mut excessive_memory = baseline.clone();
        excessive_memory.pow.argon_memory_kib = MAXIMUM_ARGON_MEMORY_KIB + 1;
        assert!(excessive_memory.validate().is_err());

        let mut even_median = baseline;
        even_median.pow.median_time_window = 10;
        assert!(even_median.validate().is_err());
    }

    #[test]
    fn block_limit_must_fit_the_mandatory_coinbase() {
        let mut config = PowGenesisConfigV2::local_regtest();
        config.limits.maximum_transaction_bytes = 256;
        config.limits.maximum_block_bytes =
            u32::try_from(crate::EMPTY_BLOCK_V2_SIZE + crate::MIN_TRANSACTION_V2_SIZE - 1)
                .expect("small bound");
        assert!(matches!(config.validate(), Err(Error::InvalidGenesis(_))));
        config.limits.maximum_block_bytes = config
            .limits
            .maximum_transaction_bytes
            .max(config.limits.maximum_block_bytes + 1);
        config.validate().expect("exact mandatory-block boundary");
    }

    #[test]
    fn subsidy_is_exact_and_caps_final_issuance() {
        let config = PowGenesisConfigV2::builtin_devnet();
        assert_eq!(
            config.subsidy(Amount::ZERO, 1).expect("first subsidy"),
            Amount::from_atoms(8 * crate::ATOMS_PER_AUR)
        );
        let almost_full = config
            .economics
            .maximum_supply
            .checked_sub(Amount::from_atoms(3))
            .expect("remaining");
        assert_eq!(
            config.subsidy(almost_full, 9).expect("capped subsidy"),
            Amount::from_atoms(3)
        );
        assert!(config.subsidy(Amount::ZERO, 0).is_err());
    }
}
