use crate::{
    hash_borsh, hash_tagged, merkle, Error, GenesisConfig, Hash256, LedgerState, Network, Result,
    SignedTransaction,
};
use borsh::{BorshDeserialize, BorshSerialize};
use std::collections::BTreeSet;

/// Current canonical Aura block format version.
pub const BLOCK_VERSION: u16 = 1;
/// Genesis marker, not a live consensus engine.
pub const GENESIS_ENGINE_ID: u16 = 0;
/// Explicitly insecure local/manual Devnet engine; never production Proof of Work.
pub const DEV_MANUAL_ENGINE_ID: u16 = 1;

/// Opaque commitment owned by a modular consensus engine.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct ConsensusCommitment {
    /// Stable consensus engine identifier.
    pub engine_id: u16,
    /// Engine-specific commitment. It is not interpreted by the state machine.
    pub digest: Hash256,
}

/// Canonical fields committed by an Aura block hash.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct BlockHeader {
    /// Block format version.
    pub version: u16,
    /// Independent network namespace.
    pub network: Network,
    /// Genesis is height zero.
    pub height: u64,
    /// Hash of the previous block; zero only for genesis.
    pub parent_hash: Hash256,
    /// Milliseconds since Unix epoch.
    pub timestamp_ms: u64,
    /// Merkle root of ordered signed-transaction witness IDs.
    pub transaction_root: Hash256,
    /// Hash of the complete post-block ledger state.
    pub state_root: Hash256,
    /// Modular consensus commitment.
    pub consensus: ConsensusCommitment,
}

impl BlockHeader {
    /// Block identifier.
    pub fn hash(&self) -> Result<Hash256> {
        hash_borsh("block/header/v1", self)
    }
}

/// An ordered Aura block.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct Block {
    /// Canonical header.
    pub header: BlockHeader,
    /// Ordered signed transactions.
    pub transactions: Vec<SignedTransaction>,
}

impl Block {
    /// Constructs the unique block at height zero for a genesis config.
    pub fn genesis(config: &GenesisConfig, state: &LedgerState) -> Result<Self> {
        let expected_state = LedgerState::from_genesis(config)?;
        if state != &expected_state {
            return Err(Error::GenesisMismatch);
        }
        let transaction_root = merkle::root(&[]);
        Ok(Self {
            header: BlockHeader {
                version: BLOCK_VERSION,
                network: config.network,
                height: 0,
                parent_hash: Hash256::ZERO,
                timestamp_ms: config.genesis_time_ms,
                transaction_root,
                state_root: state.root()?,
                consensus: ConsensusCommitment {
                    engine_id: GENESIS_ENGINE_ID,
                    digest: config.config_hash()?,
                },
            },
            transactions: Vec::new(),
        })
    }

    /// Builds an executable but explicitly non-secure manual Devnet block.
    pub fn dev_candidate(
        network: Network,
        height: u64,
        parent_hash: Hash256,
        timestamp_ms: u64,
        transactions: Vec<SignedTransaction>,
        state_root: Hash256,
    ) -> Result<Self> {
        let witness_ids = transactions
            .iter()
            .map(SignedTransaction::witness_id)
            .collect::<Result<Vec<_>>>()?;
        let transaction_root = merkle::root(&witness_ids);
        let digest = dev_commitment_digest(
            network,
            height,
            parent_hash,
            timestamp_ms,
            transaction_root,
            state_root,
        );
        Ok(Self {
            header: BlockHeader {
                version: BLOCK_VERSION,
                network,
                height,
                parent_hash,
                timestamp_ms,
                transaction_root,
                state_root,
                consensus: ConsensusCommitment {
                    engine_id: DEV_MANUAL_ENGINE_ID,
                    digest,
                },
            },
            transactions,
        })
    }

    /// Returns the block identifier.
    pub fn hash(&self) -> Result<Hash256> {
        self.header.hash()
    }

    /// Returns the deterministic encoded block size.
    pub fn encoded_size(&self) -> Result<usize> {
        borsh::to_vec(self)
            .map(|bytes| bytes.len())
            .map_err(|error| Error::Serialization(format!("block encoding failed: {error}")))
    }

    /// Deterministically encodes a block for storage or future P2P transport.
    pub fn encode(&self) -> Result<Vec<u8>> {
        borsh::to_vec(self)
            .map_err(|error| Error::Serialization(format!("block encoding failed: {error}")))
    }

    /// Strictly decodes a canonical block and rejects oversized or trailing data.
    pub fn decode(bytes: &[u8], maximum_size: u32) -> Result<Self> {
        if bytes.len() > maximum_size as usize {
            return Err(Error::BlockTooLarge {
                maximum: maximum_size,
                actual: bytes.len(),
            });
        }
        Self::try_from_slice(bytes)
            .map_err(|error| Error::Serialization(format!("block decoding failed: {error}")))
    }

    /// Verifies body count, byte size, intent-ID uniqueness, and the witness Merkle commitment.
    pub fn verify_body(&self, config: &GenesisConfig) -> Result<()> {
        if self.transactions.len() > config.parameters.maximum_transactions_per_block as usize {
            return Err(Error::TooManyTransactions {
                maximum: config.parameters.maximum_transactions_per_block,
                actual: self.transactions.len(),
            });
        }
        let encoded_size = self.encoded_size()?;
        if encoded_size > config.parameters.maximum_block_bytes as usize {
            return Err(Error::BlockTooLarge {
                maximum: config.parameters.maximum_block_bytes,
                actual: encoded_size,
            });
        }
        let mut seen = BTreeSet::new();
        let mut witness_ids = Vec::with_capacity(self.transactions.len());
        for transaction in &self.transactions {
            let id = transaction.id()?;
            if !seen.insert(id) {
                return Err(Error::DuplicateTransaction(id));
            }
            witness_ids.push(transaction.witness_id()?);
        }
        if merkle::root(&witness_ids) != self.header.transaction_root {
            return Err(Error::TransactionRootMismatch);
        }
        Ok(())
    }
}

/// Computes the transparent Phase 1 Devnet manual-engine commitment.
#[must_use]
pub fn dev_commitment_digest(
    network: Network,
    height: u64,
    parent_hash: Hash256,
    timestamp_ms: u64,
    transaction_root: Hash256,
    state_root: Hash256,
) -> Hash256 {
    hash_tagged(
        "consensus/dev-manual/v1",
        &[
            &network.id().to_le_bytes(),
            &height.to_le_bytes(),
            parent_hash.as_bytes(),
            &timestamp_ms.to_le_bytes(),
            transaction_root.as_bytes(),
            state_root.as_bytes(),
        ],
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn block_encoding_is_canonical_and_strict() {
        let config = GenesisConfig::builtin(Network::Devnet);
        let state = LedgerState::from_genesis(&config).expect("genesis state");
        let block = Block::genesis(&config, &state).expect("genesis block");
        let bytes = block.encode().expect("encode block");
        assert_eq!(
            Block::decode(&bytes, config.parameters.maximum_block_bytes).expect("decode block"),
            block
        );

        let mut trailing = bytes.clone();
        trailing.push(0);
        assert!(Block::decode(&trailing, config.parameters.maximum_block_bytes).is_err());
        let too_small = u32::try_from(bytes.len() - 1).expect("genesis block fits in u32");
        assert!(matches!(
            Block::decode(&bytes, too_small),
            Err(Error::BlockTooLarge { .. })
        ));
    }

    #[test]
    fn body_tampering_breaks_the_transaction_root() {
        let config = GenesisConfig::builtin(Network::Devnet);
        let state = LedgerState::from_genesis(&config).expect("genesis state");
        let mut block = Block::genesis(&config, &state).expect("genesis block");
        block.header.transaction_root = Hash256::ZERO;
        assert!(matches!(
            block.verify_body(&config),
            Err(Error::TransactionRootMismatch)
        ));
    }

    #[test]
    fn genesis_rejects_state_from_a_different_configuration() {
        let config = GenesisConfig::builtin(Network::Devnet);
        let mut allocated = config.clone();
        allocated.allocations.push(crate::GenesisAllocation {
            address: crate::Address::from_public_key(Network::Devnet, &[4; 32]),
            available: crate::Amount::from_atoms(1),
            locked: crate::Amount::ZERO,
            purpose: "mismatched state test".into(),
        });
        let mismatched_state = LedgerState::from_genesis(&allocated).expect("allocated state");

        assert!(matches!(
            Block::genesis(&config, &mismatched_state),
            Err(Error::GenesisMismatch)
        ));
    }
}
