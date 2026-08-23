use crate::{
    block::{dev_commitment_digest, DEV_MANUAL_ENGINE_ID},
    Block, BlockHeader, Error, GenesisConfig, Hash256, Network, Result, BLOCK_VERSION,
};

/// Early modular header-verification boundary; production `PoW` requires a broader consensus API.
pub trait ConsensusVerifier: Clone + Send + Sync + 'static {
    /// Verifies a non-genesis block and returns its positive fork-choice score increment.
    fn verify_non_genesis(
        &self,
        block: &Block,
        parent: &BlockHeader,
        config: &GenesisConfig,
    ) -> Result<u128>;

    /// Applies the engine's deterministic fork-choice rule.
    fn prefers_candidate(
        &self,
        candidate_score: u128,
        candidate_hash: Hash256,
        current_score: u128,
        current_hash: Hash256,
    ) -> bool;
}

/// Honest Phase 1 verifier: manual blocks work only on Devnet.
#[derive(Clone, Copy, Debug, Default)]
pub struct PhaseOneConsensus;

impl ConsensusVerifier for PhaseOneConsensus {
    fn verify_non_genesis(
        &self,
        block: &Block,
        parent: &BlockHeader,
        config: &GenesisConfig,
    ) -> Result<u128> {
        let header = &block.header;
        if header.version != BLOCK_VERSION {
            return Err(Error::UnsupportedProtocol {
                expected: BLOCK_VERSION,
                actual: header.version,
            });
        }
        if header.network != config.network {
            return Err(Error::NetworkMismatch {
                expected: config.network,
                actual: header.network,
            });
        }
        let expected_height = parent.height.checked_add(1).ok_or(Error::HeightExhausted)?;
        if header.height != expected_height {
            return Err(Error::InvalidHeight {
                expected: expected_height,
                actual: header.height,
            });
        }
        if header.timestamp_ms <= parent.timestamp_ms {
            return Err(Error::NonMonotonicTimestamp);
        }
        if config.network != Network::Devnet {
            return Err(Error::ConsensusUnavailable);
        }
        if header.consensus.engine_id != DEV_MANUAL_ENGINE_ID {
            return Err(Error::UnsupportedConsensus(header.consensus.engine_id));
        }
        let expected = dev_commitment_digest(
            header.network,
            header.height,
            header.parent_hash,
            header.timestamp_ms,
            header.transaction_root,
            header.state_root,
        );
        if header.consensus.digest != expected {
            return Err(Error::InvalidConsensusCommitment);
        }

        // Manual Devnet blocks all contribute one unit. This is deterministic fork handling,
        // not proof of work/stake and must never be described as decentralized consensus.
        Ok(1)
    }

    fn prefers_candidate(
        &self,
        candidate_score: u128,
        candidate_hash: Hash256,
        current_score: u128,
        current_hash: Hash256,
    ) -> bool {
        candidate_score > current_score
            || (candidate_score == current_score && candidate_hash < current_hash)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::LedgerState;

    #[test]
    fn height_overflow_is_rejected() {
        let config = GenesisConfig::builtin(Network::Devnet);
        let state = LedgerState::from_genesis(&config).expect("genesis state");
        let mut parent = Block::genesis(&config, &state)
            .expect("genesis block")
            .header;
        parent.height = u64::MAX;
        let candidate = Block::dev_candidate(
            Network::Devnet,
            0,
            parent.hash().expect("parent hash"),
            1,
            Vec::new(),
            state.root().expect("state root"),
        )
        .expect("candidate");

        assert!(matches!(
            PhaseOneConsensus.verify_non_genesis(&candidate, &parent, &config),
            Err(Error::HeightExhausted)
        ));
    }
}
