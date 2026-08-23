use crate::{Block, Error, Hash256, LedgerState, Network, Result};
use borsh::{BorshDeserialize, BorshSerialize};
use std::collections::BTreeMap;

/// Persisted block plus the post-block state needed for deterministic fork execution.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct BlockRecord {
    /// Block data.
    pub block: Block,
    /// Fully materialized post-block state. Phase 1 favors correctness over pruning.
    pub state: LedgerState,
    /// Sum of consensus score increments from genesis through this block.
    pub cumulative_score: u128,
}

/// Identity and canonical-tip metadata stored atomically with block imports.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct StoreMetadata {
    /// On-disk schema version. Unknown versions fail closed.
    pub schema_version: u32,
    /// Unique genesis block hash.
    pub genesis_hash: Hash256,
    /// Current deterministic fork-choice tip.
    pub tip_hash: Hash256,
    /// Independent network namespace.
    pub network: Network,
    /// Replay-protection chain ID hash.
    pub chain_id_hash: Hash256,
}

/// Minimal durable store contract used by the consensus-neutral chain manager.
pub trait ChainStore {
    /// Loads metadata, or `None` for a new store.
    fn metadata(&self) -> Result<Option<StoreMetadata>>;
    /// Returns every stored record's declared height and storage key.
    ///
    /// Implementations may decode records one at a time, but must not retain full state snapshots
    /// while building this bounded-memory index.
    fn record_index(&self) -> Result<Vec<(u64, Hash256)>>;
    /// Loads a block record by hash.
    fn record(&self, hash: Hash256) -> Result<Option<BlockRecord>>;
    /// Atomically writes the first block and store identity.
    fn initialize(&mut self, metadata: &StoreMetadata, genesis: &BlockRecord) -> Result<()>;
    /// Atomically writes a block and optionally advances the canonical tip.
    fn commit_block(&mut self, record: &BlockRecord, new_tip: Option<Hash256>) -> Result<()>;
}

/// Deterministic in-memory store used by unit and integration tests.
#[derive(Clone, Debug, Default)]
pub struct MemoryStore {
    metadata: Option<StoreMetadata>,
    records: BTreeMap<Hash256, BlockRecord>,
}

impl ChainStore for MemoryStore {
    fn metadata(&self) -> Result<Option<StoreMetadata>> {
        Ok(self.metadata.clone())
    }

    fn record_index(&self) -> Result<Vec<(u64, Hash256)>> {
        let mut index = self
            .records
            .iter()
            .map(|(hash, record)| (record.block.header.height, *hash))
            .collect::<Vec<_>>();
        index.sort_unstable();
        Ok(index)
    }

    fn record(&self, hash: Hash256) -> Result<Option<BlockRecord>> {
        Ok(self.records.get(&hash).cloned())
    }

    fn initialize(&mut self, metadata: &StoreMetadata, genesis: &BlockRecord) -> Result<()> {
        if self.metadata.is_some() || !self.records.is_empty() {
            return Err(Error::Storage(
                "store initialization requires empty metadata and records".into(),
            ));
        }
        self.records.insert(metadata.genesis_hash, genesis.clone());
        self.metadata = Some(metadata.clone());
        Ok(())
    }

    fn commit_block(&mut self, record: &BlockRecord, new_tip: Option<Hash256>) -> Result<()> {
        let hash = record.block.hash()?;
        if self.records.contains_key(&hash) {
            return Err(Error::DuplicateBlock(hash));
        }
        let mut metadata = self
            .metadata
            .clone()
            .ok_or_else(|| Error::Storage("store is not initialized".into()))?;
        if let Some(tip_hash) = new_tip {
            if tip_hash != hash {
                return Err(Error::Storage(
                    "new tip must equal the committed block hash".into(),
                ));
            }
            metadata.tip_hash = tip_hash;
        }
        self.records.insert(hash, record.clone());
        self.metadata = Some(metadata);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        Address, Amount, Block, Chain, GenesisAllocation, GenesisConfig, LedgerState,
        PhaseOneConsensus,
    };

    fn genesis_fixture() -> (StoreMetadata, BlockRecord) {
        let config = GenesisConfig::builtin(Network::Devnet);
        let state = LedgerState::from_genesis(&config).expect("genesis state");
        let block = Block::genesis(&config, &state).expect("genesis block");
        let genesis_hash = block.hash().expect("genesis hash");
        (
            StoreMetadata {
                schema_version: 1,
                genesis_hash,
                tip_hash: genesis_hash,
                network: config.network,
                chain_id_hash: config.chain_id_hash(),
            },
            BlockRecord {
                block,
                state,
                cumulative_score: 0,
            },
        )
    }

    fn child_record(metadata: &StoreMetadata, genesis: &BlockRecord) -> BlockRecord {
        let block = Block::dev_candidate(
            Network::Devnet,
            1,
            metadata.genesis_hash,
            1,
            Vec::new(),
            genesis.state.root().expect("state root"),
        )
        .expect("child block");
        BlockRecord {
            block,
            state: genesis.state.clone(),
            cumulative_score: 1,
        }
    }

    fn forked_store() -> (GenesisConfig, MemoryStore, Hash256, Hash256) {
        let config = GenesisConfig::builtin(Network::Devnet);
        let mut chain =
            Chain::initialize(MemoryStore::default(), config.clone(), PhaseOneConsensus)
                .expect("initialize chain");
        let genesis_hash = chain.metadata().expect("metadata").genesis_hash;

        let first = chain
            .prepare_dev_block_on(genesis_hash, Vec::new(), 1)
            .expect("first fork block");
        let first_hash = first.hash().expect("first hash");
        chain.import_block(first, 1).expect("import first fork");

        let second = chain
            .prepare_dev_block_on(genesis_hash, Vec::new(), 2)
            .expect("second fork block");
        let second_hash = second.hash().expect("second hash");
        chain.import_block(second, 2).expect("import second fork");

        let preferred = chain.metadata().expect("metadata").tip_hash;
        let nonpreferred = if preferred == first_hash {
            second_hash
        } else {
            first_hash
        };
        (config, chain.into_store(), preferred, nonpreferred)
    }

    #[test]
    fn initialization_requires_empty_records() {
        let (metadata, genesis) = genesis_fixture();
        let mut store = MemoryStore::default();
        store.records.insert(metadata.genesis_hash, genesis.clone());

        assert!(store.initialize(&metadata, &genesis).is_err());
        assert!(store.metadata.is_none());
        assert_eq!(store.records.len(), 1);
    }

    #[test]
    fn failed_commits_do_not_mutate_the_store() {
        let (metadata, genesis) = genesis_fixture();
        let child = child_record(&metadata, &genesis);
        let child_hash = child.block.hash().expect("child hash");
        let mut store = MemoryStore::default();

        assert!(store.commit_block(&child, Some(child_hash)).is_err());
        assert!(store.record(child_hash).expect("read record").is_none());

        store
            .initialize(&metadata, &genesis)
            .expect("initialize store");
        assert!(store.commit_block(&child, Some(Hash256::ZERO)).is_err());
        assert!(store.record(child_hash).expect("read record").is_none());
        assert_eq!(
            store.metadata().expect("read metadata"),
            Some(metadata.clone())
        );

        store
            .commit_block(&child, Some(child_hash))
            .expect("commit child");
        assert_eq!(
            store
                .metadata()
                .expect("read metadata")
                .expect("initialized metadata")
                .tip_hash,
            child_hash
        );
        assert_eq!(
            store.record_index().expect("record index"),
            vec![(0, metadata.genesis_hash), (1, child_hash)]
        );
    }

    #[test]
    fn opening_rejects_tampered_noncanonical_score_and_state() {
        let (config, mut score_store, _, nonpreferred) = forked_store();
        score_store
            .records
            .get_mut(&nonpreferred)
            .expect("nonpreferred record")
            .cumulative_score = 1_000;
        assert!(Chain::open_existing(score_store, config.clone(), PhaseOneConsensus).is_err());

        let (_, mut state_store, _, nonpreferred) = forked_store();
        let mut different_genesis = config.clone();
        different_genesis.allocations.push(GenesisAllocation {
            address: Address::from_public_key(Network::Devnet, &[9; 32]),
            available: Amount::from_atoms(1),
            locked: Amount::ZERO,
            purpose: "corrupt noncanonical snapshot test".into(),
        });
        state_store
            .records
            .get_mut(&nonpreferred)
            .expect("nonpreferred record")
            .state = LedgerState::from_genesis(&different_genesis).expect("alternate state");
        assert!(Chain::open_existing(state_store, config, PhaseOneConsensus).is_err());
    }

    #[test]
    fn opening_rejects_metadata_pointing_to_a_nonpreferred_fork() {
        let (config, mut store, preferred, nonpreferred) = forked_store();
        assert_ne!(preferred, nonpreferred);
        store
            .metadata
            .as_mut()
            .expect("initialized metadata")
            .tip_hash = nonpreferred;

        assert!(Chain::open_existing(store, config, PhaseOneConsensus).is_err());
    }

    #[test]
    fn opening_rejects_extra_genesis_and_unreachable_records() {
        let config = GenesisConfig::builtin(Network::Devnet);
        let (metadata, genesis) = genesis_fixture();
        let mut extra_genesis_store = MemoryStore::default();
        extra_genesis_store
            .initialize(&metadata, &genesis)
            .expect("initialize store");
        let extra_genesis = Block::dev_candidate(
            Network::Devnet,
            0,
            Hash256::ZERO,
            1,
            Vec::new(),
            genesis.state.root().expect("state root"),
        )
        .expect("extra height-zero block");
        let extra_hash = extra_genesis.hash().expect("extra block hash");
        extra_genesis_store.records.insert(
            extra_hash,
            BlockRecord {
                block: extra_genesis,
                state: genesis.state.clone(),
                cumulative_score: 0,
            },
        );
        assert!(
            Chain::open_existing(extra_genesis_store, config.clone(), PhaseOneConsensus).is_err()
        );

        let mut unreachable_store = MemoryStore::default();
        unreachable_store
            .initialize(&metadata, &genesis)
            .expect("initialize store");
        let missing_parent = crate::hash_tagged("test/missing-indexed-parent", &[b"missing"]);
        let unreachable = Block::dev_candidate(
            Network::Devnet,
            1,
            missing_parent,
            1,
            Vec::new(),
            genesis.state.root().expect("state root"),
        )
        .expect("unreachable block");
        let unreachable_hash = unreachable.hash().expect("unreachable hash");
        unreachable_store.records.insert(
            unreachable_hash,
            BlockRecord {
                block: unreachable,
                state: genesis.state,
                cumulative_score: 1,
            },
        );
        assert!(Chain::open_existing(unreachable_store, config, PhaseOneConsensus).is_err());
    }
}
