use crate::{hash_borsh, hash_tagged, Address, Amount, Error, Hash256, Network, Result};
use borsh::{BorshDeserialize, BorshSerialize};
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;

const MINIMUM_TRANSACTION_BYTES: u32 = 256;
const MAXIMUM_TRANSACTION_BYTES: u32 = 1024 * 1024;
const MAXIMUM_BLOCK_BYTES: u32 = 16 * 1024 * 1024;
const MAXIMUM_TRANSACTIONS_PER_BLOCK: u32 = 50_000;
const MAXIMUM_FUTURE_DRIFT_MS: u64 = 60 * 60 * 1000;
const MAXIMUM_GENESIS_ALLOCATIONS: usize = 10_000;

/// Consensus-neutral chain limits committed at genesis.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, BorshSerialize, BorshDeserialize)]
#[serde(deny_unknown_fields)]
pub struct ChainParameters {
    /// Protocol envelope version accepted by the chain.
    pub protocol_version: u16,
    /// Maximum deterministic Borsh-encoded block size.
    pub maximum_block_bytes: u32,
    /// Maximum deterministic Borsh-encoded transaction size.
    pub maximum_transaction_bytes: u32,
    /// Maximum transactions in one block.
    pub maximum_transactions_per_block: u32,
    /// Minimum fee in atomic AUR units.
    pub minimum_fee: Amount,
    /// Maximum permitted block timestamp lead over local time.
    pub maximum_future_drift_ms: u64,
    /// Technical supply ceiling; not an issuance promise.
    pub maximum_supply: Amount,
}

impl Default for ChainParameters {
    fn default() -> Self {
        // Phase-1 convenience fixtures. A production genesis must specify and review each value.
        Self {
            protocol_version: 1,
            maximum_block_bytes: 2 * 1024 * 1024,
            maximum_transaction_bytes: 2 * 1024,
            maximum_transactions_per_block: 10_000,
            minimum_fee: Amount::from_atoms(1_000),
            maximum_future_drift_ms: 120_000,
            maximum_supply: Amount::from_atoms(1_000_000_000 * crate::ATOMS_PER_AUR),
        }
    }
}

/// A transparent balance assigned by a specific genesis file.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, BorshSerialize, BorshDeserialize)]
#[serde(deny_unknown_fields)]
pub struct GenesisAllocation {
    /// Recipient address.
    pub address: Address,
    /// Initially spendable AUR.
    pub available: Amount,
    /// Initially locked AUR.
    pub locked: Amount,
    /// Human-readable public disclosure; committed to the genesis hash.
    pub purpose: String,
}

/// Reproducible configuration that creates an Aura genesis block.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize, BorshSerialize, BorshDeserialize)]
#[serde(deny_unknown_fields)]
pub struct GenesisConfig {
    /// Display name.
    pub chain_name: String,
    /// Textual replay-protection namespace.
    pub chain_id: String,
    /// Independent network namespace.
    pub network: Network,
    /// Milliseconds since Unix epoch.
    pub genesis_time_ms: u64,
    /// Consensus-neutral validation limits.
    pub parameters: ChainParameters,
    /// Fully disclosed initial balances.
    pub allocations: Vec<GenesisAllocation>,
}

impl GenesisConfig {
    /// Returns a Phase-1, zero-allocation fixture; this is not a production launch genesis.
    #[must_use]
    pub fn builtin(network: Network) -> Self {
        let (name, timestamp) = match network {
            Network::Mainnet => ("Aura Mainnet", 1_787_356_800_000),
            Network::Testnet => ("Aura Testnet", 1_787_356_800_000),
            Network::Devnet => ("Aura Devnet", 0),
        };
        Self {
            chain_name: name.into(),
            chain_id: network.canonical_chain_id().into(),
            network,
            genesis_time_ms: timestamp,
            parameters: ChainParameters::default(),
            allocations: Vec::new(),
        }
    }

    /// Validates bounded strings, network identity, parameters, and allocations.
    pub fn validate(&self) -> Result<()> {
        if self.chain_name.trim().is_empty()
            || self.chain_name.trim() != self.chain_name
            || self.chain_name.len() > 64
            || self.chain_name.chars().any(char::is_control)
        {
            return Err(Error::InvalidGenesis(
                "chain_name must contain 1..=64 bytes without surrounding whitespace or control characters".into(),
            ));
        }
        let expected_prefix = match self.network {
            Network::Mainnet => "aura-mainnet-",
            Network::Testnet => "aura-testnet-",
            Network::Devnet => "aura-devnet-",
        };
        let suffix = self
            .chain_id
            .strip_prefix(expected_prefix)
            .unwrap_or_default();
        if self.chain_id.len() > 64
            || suffix.is_empty()
            || suffix.starts_with('-')
            || suffix.ends_with('-')
            || suffix.contains("--")
            || !self
                .chain_id
                .bytes()
                .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
        {
            return Err(Error::InvalidGenesis(format!(
                "chain_id must begin with {expected_prefix:?}, have nonempty lowercase ASCII letter/digit segments separated by single hyphens, and contain at most 64 bytes"
            )));
        }
        self.validate_operational_limits()?;

        let mut addresses = BTreeSet::new();
        let mut supply = Amount::ZERO;
        for allocation in &self.allocations {
            if allocation.address.network() != self.network {
                return Err(Error::AddressNetworkMismatch {
                    expected: self.network,
                    actual: allocation.address.network(),
                });
            }
            if !addresses.insert(allocation.address) {
                return Err(Error::InvalidGenesis(format!(
                    "duplicate allocation for {}",
                    allocation.address
                )));
            }
            if allocation.purpose.trim().is_empty()
                || allocation.purpose.trim() != allocation.purpose
                || allocation.purpose.len() > 160
                || allocation.purpose.chars().any(char::is_control)
            {
                return Err(Error::InvalidGenesis(
                    "every allocation needs a 1..=160 byte public purpose without surrounding whitespace or control characters".into(),
                ));
            }
            supply = supply
                .checked_add(allocation.available)?
                .checked_add(allocation.locked)?;
        }
        if supply > self.parameters.maximum_supply {
            return Err(Error::InvalidGenesis(
                "genesis allocations exceed maximum_supply".into(),
            ));
        }
        Ok(())
    }

    fn validate_operational_limits(&self) -> Result<()> {
        if self.parameters.protocol_version != 1 {
            return Err(Error::InvalidGenesis(
                "Phase 1 supports protocol_version 1 only".into(),
            ));
        }
        if !(MINIMUM_TRANSACTION_BYTES..=MAXIMUM_TRANSACTION_BYTES)
            .contains(&self.parameters.maximum_transaction_bytes)
        {
            return Err(Error::InvalidGenesis(
                format!(
                    "maximum_transaction_bytes must be in {MINIMUM_TRANSACTION_BYTES}..={MAXIMUM_TRANSACTION_BYTES}"
                ),
            ));
        }
        if self.parameters.maximum_block_bytes < self.parameters.maximum_transaction_bytes
            || self.parameters.maximum_block_bytes > MAXIMUM_BLOCK_BYTES
        {
            return Err(Error::InvalidGenesis(format!(
                "maximum_block_bytes must be at least maximum_transaction_bytes and at most {MAXIMUM_BLOCK_BYTES}"
            )));
        }
        if !(1..=MAXIMUM_TRANSACTIONS_PER_BLOCK)
            .contains(&self.parameters.maximum_transactions_per_block)
        {
            return Err(Error::InvalidGenesis(format!(
                "maximum_transactions_per_block must be in 1..={MAXIMUM_TRANSACTIONS_PER_BLOCK}"
            )));
        }
        if !(1..=MAXIMUM_FUTURE_DRIFT_MS).contains(&self.parameters.maximum_future_drift_ms) {
            return Err(Error::InvalidGenesis(format!(
                "maximum_future_drift_ms must be in 1..={MAXIMUM_FUTURE_DRIFT_MS}"
            )));
        }
        if self.parameters.maximum_supply == Amount::ZERO {
            return Err(Error::InvalidGenesis(
                "maximum_supply must be greater than zero".into(),
            ));
        }
        if self.parameters.minimum_fee > self.parameters.maximum_supply {
            return Err(Error::InvalidGenesis(
                "minimum_fee cannot exceed maximum_supply".into(),
            ));
        }
        if self.allocations.len() > MAXIMUM_GENESIS_ALLOCATIONS {
            return Err(Error::InvalidGenesis(format!(
                "allocations cannot contain more than {MAXIMUM_GENESIS_ALLOCATIONS} entries"
            )));
        }
        Ok(())
    }

    /// Hash of the complete, canonical genesis configuration.
    pub fn config_hash(&self) -> Result<Hash256> {
        self.validate()?;
        hash_borsh("genesis/config/v1", self)
    }

    /// Domain hash used by transactions to prevent replay across chain IDs.
    #[must_use]
    pub fn chain_id_hash(&self) -> Hash256 {
        hash_tagged("chain-id/v1", &[self.chain_id.as_bytes()])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builtins_are_reproducible_and_distinct() {
        let main = GenesisConfig::builtin(Network::Mainnet);
        let test = GenesisConfig::builtin(Network::Testnet);
        assert_eq!(
            main.config_hash().expect("valid"),
            main.config_hash().expect("valid")
        );
        assert_ne!(
            main.config_hash().expect("valid"),
            test.config_hash().expect("valid")
        );
        assert!(main.allocations.is_empty());
    }

    #[test]
    fn duplicate_allocations_are_rejected() {
        let mut config = GenesisConfig::builtin(Network::Devnet);
        let address = Address::from_public_key(Network::Devnet, &[1; 32]);
        let allocation = GenesisAllocation {
            address,
            available: Amount::from_atoms(1),
            locked: Amount::ZERO,
            purpose: "test".into(),
        };
        config.allocations = vec![allocation.clone(), allocation];
        assert!(config.validate().is_err());
    }

    #[test]
    fn genesis_json_rejects_unknown_fields_at_every_level() {
        let mut config = GenesisConfig::builtin(Network::Devnet);
        config.allocations.push(GenesisAllocation {
            address: Address::from_public_key(Network::Devnet, &[2; 32]),
            available: Amount::from_atoms(1),
            locked: Amount::ZERO,
            purpose: "schema test".into(),
        });
        let value = serde_json::to_value(config).expect("serialize genesis");

        let mut top_level = value.clone();
        top_level
            .as_object_mut()
            .expect("genesis object")
            .insert("unexpected".into(), serde_json::Value::Bool(true));
        assert!(serde_json::from_value::<GenesisConfig>(top_level).is_err());

        let mut parameters = value.clone();
        parameters["parameters"]
            .as_object_mut()
            .expect("parameters object")
            .insert("unexpected".into(), serde_json::Value::Bool(true));
        assert!(serde_json::from_value::<GenesisConfig>(parameters).is_err());

        let mut allocation = value;
        allocation["allocations"][0]
            .as_object_mut()
            .expect("allocation object")
            .insert("unexpected".into(), serde_json::Value::Bool(true));
        assert!(serde_json::from_value::<GenesisConfig>(allocation).is_err());
    }

    #[test]
    fn unsafe_operational_limits_are_rejected() {
        let baseline = GenesisConfig::builtin(Network::Devnet);

        let mut config = baseline.clone();
        config.parameters.maximum_transaction_bytes = MAXIMUM_TRANSACTION_BYTES + 1;
        assert!(config.validate().is_err());

        let mut config = baseline.clone();
        config.parameters.maximum_block_bytes = MAXIMUM_BLOCK_BYTES + 1;
        assert!(config.validate().is_err());

        let mut config = baseline.clone();
        config.parameters.maximum_transactions_per_block = MAXIMUM_TRANSACTIONS_PER_BLOCK + 1;
        assert!(config.validate().is_err());

        let mut config = baseline.clone();
        config.parameters.maximum_future_drift_ms = MAXIMUM_FUTURE_DRIFT_MS + 1;
        assert!(config.validate().is_err());

        let mut config = baseline.clone();
        config.parameters.maximum_supply = Amount::from_atoms(1);
        config.parameters.minimum_fee = Amount::from_atoms(2);
        assert!(config.validate().is_err());

        for invalid_suffix in ["", "-bad", "bad-", "bad--suffix"] {
            let mut config = baseline.clone();
            config.chain_id = format!("aura-devnet-{invalid_suffix}");
            assert!(config.validate().is_err());
        }

        let allocation = GenesisAllocation {
            address: Address::from_public_key(Network::Devnet, &[3; 32]),
            available: Amount::ZERO,
            locked: Amount::ZERO,
            purpose: "allocation bound test".into(),
        };
        let mut config = baseline.clone();
        config.allocations = vec![allocation; MAXIMUM_GENESIS_ALLOCATIONS + 1];
        assert!(config.validate().is_err());

        let mut config = baseline;
        config.chain_id = "aura-devnet-".into();
        assert!(config.validate().is_err());
    }
}
