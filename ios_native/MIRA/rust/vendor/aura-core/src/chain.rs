use crate::{
    Block, BlockRecord, ChainStore, ConsensusVerifier, Error, GenesisConfig, Hash256, LedgerState,
    Result, SignedTransaction, StoreMetadata, BLOCK_VERSION,
};
use std::collections::BTreeSet;

/// Result of importing one valid block.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ImportOutcome {
    /// Imported block hash.
    pub hash: Hash256,
    /// Whether fork choice advanced to this block.
    pub became_canonical_tip: bool,
    /// Number of previously canonical blocks replaced, zero for a simple extension.
    pub reorg_depth: u64,
    /// New canonical height after the import.
    pub canonical_height: u64,
}

/// Full canonical-chain verification summary.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VerificationReport {
    /// Genesis through tip, inclusive.
    pub blocks_verified: u64,
    /// Transactions deterministically re-executed.
    pub transactions_verified: u64,
    /// Verified tip hash.
    pub tip_hash: Hash256,
    /// Verified tip height.
    pub tip_height: u64,
}

/// Persistent chain manager with deterministic execution and fork selection.
pub struct Chain<S, C> {
    store: S,
    config: GenesisConfig,
    consensus: C,
}

impl<S: ChainStore, C: ConsensusVerifier> Chain<S, C> {
    /// Atomically initializes an empty store with the reproducible genesis block.
    pub fn initialize(mut store: S, config: GenesisConfig, consensus: C) -> Result<Self> {
        if store.metadata()?.is_some() {
            return Err(Error::Storage("chain store is already initialized".into()));
        }
        let (genesis_state, genesis, metadata) = Self::genesis_components(&config)?;
        let record = BlockRecord {
            block: genesis,
            state: genesis_state,
            cumulative_score: 0,
        };
        store.initialize(&metadata, &record)?;
        let chain = Self {
            store,
            config,
            consensus,
        };
        chain.verify_all_records(&metadata)?;
        chain.verify_canonical_chain()?;
        Ok(chain)
    }

    /// Opens an initialized store, fails closed on identity/integrity errors, verifies every
    /// stored fork, and rechecks the canonical path before returning.
    pub fn open_existing(store: S, config: GenesisConfig, consensus: C) -> Result<Self> {
        let (_, _, expected) = Self::genesis_components(&config)?;
        let metadata = store
            .metadata()?
            .ok_or_else(|| Error::CorruptStore("chain metadata is missing".into()))?;
        if metadata.schema_version != expected.schema_version {
            return Err(Error::CorruptStore(format!(
                "unsupported store schema version {}",
                metadata.schema_version
            )));
        }
        if metadata.genesis_hash != expected.genesis_hash
            || metadata.network != expected.network
            || metadata.chain_id_hash != expected.chain_id_hash
        {
            return Err(Error::GenesisMismatch);
        }
        let chain = Self {
            store,
            config,
            consensus,
        };
        chain.verify_all_records(&metadata)?;
        chain.verify_canonical_chain()?;
        Ok(chain)
    }

    fn genesis_components(config: &GenesisConfig) -> Result<(LedgerState, Block, StoreMetadata)> {
        config.validate()?;
        let genesis_state = LedgerState::from_genesis(config)?;
        let genesis = Block::genesis(config, &genesis_state)?;
        let genesis_hash = genesis.hash()?;
        let metadata = StoreMetadata {
            schema_version: 1,
            genesis_hash,
            tip_hash: genesis_hash,
            network: config.network,
            chain_id_hash: config.chain_id_hash(),
        };
        Ok((genesis_state, genesis, metadata))
    }

    /// Returns the immutable genesis configuration.
    #[must_use]
    pub const fn config(&self) -> &GenesisConfig {
        &self.config
    }

    /// Returns current store metadata.
    pub fn metadata(&self) -> Result<StoreMetadata> {
        self.store
            .metadata()?
            .ok_or_else(|| Error::CorruptStore("metadata is missing".into()))
    }

    /// Returns a block record by hash.
    pub fn record(&self, hash: Hash256) -> Result<Option<BlockRecord>> {
        self.checked_record(hash)
    }

    /// Returns the canonical tip record.
    pub fn tip(&self) -> Result<BlockRecord> {
        let metadata = self.metadata()?;
        self.required_record(metadata.tip_hash, "canonical tip")
    }

    /// Returns a canonical block record by height.
    pub fn canonical_record(&self, height: u64) -> Result<Option<BlockRecord>> {
        let mut current = self.tip()?;
        if height > current.block.header.height {
            return Ok(None);
        }
        while current.block.header.height > height {
            current = self.parent_record(&current)?;
        }
        if current.block.header.height == height {
            Ok(Some(current))
        } else {
            Err(Error::CorruptStore(
                "canonical ancestry skipped the requested height".into(),
            ))
        }
    }

    /// Executes transactions on any known parent and constructs a manual Devnet candidate.
    pub fn prepare_dev_block_on(
        &self,
        parent_hash: Hash256,
        transactions: Vec<SignedTransaction>,
        timestamp_ms: u64,
    ) -> Result<Block> {
        if self.config.network != crate::Network::Devnet {
            return Err(Error::ConsensusUnavailable);
        }
        let parent = self
            .checked_record(parent_hash)?
            .ok_or(Error::ParentNotFound(parent_hash))?;
        let height = parent
            .block
            .header
            .height
            .checked_add(1)
            .ok_or(Error::HeightExhausted)?;
        let next_state = self.execute_transactions(&parent.state, &transactions, height)?;
        Block::dev_candidate(
            self.config.network,
            height,
            parent_hash,
            timestamp_ms,
            transactions,
            next_state.root()?,
        )
    }

    /// Executes transactions on the canonical tip and constructs a manual Devnet candidate.
    pub fn prepare_dev_block(
        &self,
        transactions: Vec<SignedTransaction>,
        timestamp_ms: u64,
    ) -> Result<Block> {
        let metadata = self.metadata()?;
        self.prepare_dev_block_on(metadata.tip_hash, transactions, timestamp_ms)
    }

    /// Imports, validates, executes, persists, and deterministically fork-selects a block.
    pub fn import_block(&mut self, block: Block, now_ms: u64) -> Result<ImportOutcome> {
        let hash = block.hash()?;
        if self.checked_record(hash)?.is_some() {
            return Err(Error::DuplicateBlock(hash));
        }
        if block.header.height == 0 {
            return Err(Error::InvalidHeight {
                expected: 1,
                actual: 0,
            });
        }
        let parent = self
            .checked_record(block.header.parent_hash)?
            .ok_or(Error::ParentNotFound(block.header.parent_hash))?;
        if block.header.timestamp_ms
            > now_ms.saturating_add(self.config.parameters.maximum_future_drift_ms)
        {
            return Err(Error::FutureTimestamp);
        }
        let (state, score_increment) = self.validate_and_execute(&block, &parent)?;
        let cumulative_score = parent
            .cumulative_score
            .checked_add(score_increment)
            .ok_or(Error::ChainScoreOverflow)?;
        let record = BlockRecord {
            block,
            state,
            cumulative_score,
        };

        let metadata = self.metadata()?;
        let current_tip = self.required_record(metadata.tip_hash, "canonical tip")?;
        let becomes_tip = self.consensus.prefers_candidate(
            cumulative_score,
            hash,
            current_tip.cumulative_score,
            metadata.tip_hash,
        );
        let reorg_depth = if becomes_tip {
            self.reorg_depth(metadata.tip_hash, &record)?
        } else {
            0
        };
        self.store
            .commit_block(&record, becomes_tip.then_some(hash))?;
        let canonical_height = if becomes_tip {
            record.block.header.height
        } else {
            current_tip.block.header.height
        };
        Ok(ImportOutcome {
            hash,
            became_canonical_tip: becomes_tip,
            reorg_depth,
            canonical_height,
        })
    }

    /// Re-executes every canonical block from genesis and checks stored state/score.
    pub fn verify_canonical_chain(&self) -> Result<VerificationReport> {
        let metadata = self.metadata()?;
        let mut reversed_hashes = Vec::new();
        let mut hash = metadata.tip_hash;
        let mut visited = BTreeSet::new();
        let mut child_height = None;
        loop {
            if !visited.insert(hash) {
                return Err(Error::CorruptStore(
                    "cycle detected in canonical ancestry".into(),
                ));
            }
            let record = self.required_record(hash, "canonical block")?;
            if let Some(actual_child_height) = child_height {
                let expected_child_height = record
                    .block
                    .header
                    .height
                    .checked_add(1)
                    .ok_or(Error::HeightExhausted)?;
                if expected_child_height != actual_child_height {
                    return Err(Error::CorruptStore(format!(
                        "canonical parent height {} does not precede child height {actual_child_height}",
                        record.block.header.height
                    )));
                }
            }
            let is_genesis = record.block.header.height == 0;
            if is_genesis {
                if record.block.header.parent_hash != Hash256::ZERO {
                    return Err(Error::CorruptStore(
                        "genesis block has a nonzero parent".into(),
                    ));
                }
            } else {
                child_height = Some(record.block.header.height);
            }
            reversed_hashes.push(hash);
            if is_genesis {
                break;
            }
            hash = record.block.header.parent_hash;
        }
        reversed_hashes.reverse();

        let expected_block_count =
            u64::try_from(reversed_hashes.len()).map_err(|_| Error::HeightExhausted)?;
        let tip_height = expected_block_count
            .checked_sub(1)
            .ok_or_else(|| Error::CorruptStore("chain contains no genesis".into()))?;

        let first_hash = *reversed_hashes
            .first()
            .ok_or_else(|| Error::CorruptStore("chain contains no genesis".into()))?;
        if first_hash != metadata.genesis_hash {
            return Err(Error::GenesisMismatch);
        }
        let first = self.required_record(first_hash, "genesis")?;
        self.verify_genesis_record(&first)?;
        drop(first);

        let mut transactions_verified = 0_u64;
        for window in reversed_hashes.windows(2) {
            let parent_hash = window[0];
            let child_hash = window[1];
            let child = self.required_record(child_hash, "canonical child")?;
            let block = child.block.clone();
            let cumulative_score = child.cumulative_score;
            let transaction_count = child.block.transactions.len();
            drop(child);

            let parent = self.required_record(parent_hash, "canonical parent")?;
            let (executed_state, increment) = self.validate_and_execute(&block, &parent)?;
            let score = parent
                .cumulative_score
                .checked_add(increment)
                .ok_or(Error::ChainScoreOverflow)?;
            drop(parent);
            let child = self.required_record(child_hash, "canonical child")?;
            if executed_state != child.state {
                return Err(Error::CorruptStore(
                    "stored state differs from block execution".into(),
                ));
            }
            if score != cumulative_score {
                return Err(Error::CorruptStore(
                    "stored cumulative score is incorrect".into(),
                ));
            }
            transactions_verified = transactions_verified
                .checked_add(u64::try_from(transaction_count).map_err(|_| Error::AmountOverflow)?)
                .ok_or(Error::AmountOverflow)?;
        }
        Ok(VerificationReport {
            blocks_verified: expected_block_count,
            transactions_verified,
            tip_hash: metadata.tip_hash,
            tip_height,
        })
    }

    /// Consumes the manager and returns its store.
    #[must_use]
    pub fn into_store(self) -> S {
        self.store
    }

    fn verify_all_records(&self, metadata: &StoreMetadata) -> Result<()> {
        let mut index = self.store.record_index()?;
        index.sort_unstable();
        if index.is_empty() {
            return Err(Error::CorruptStore(
                "chain store contains no records".into(),
            ));
        }

        let mut verified = BTreeSet::new();
        let mut saw_genesis = false;
        let mut preferred: Option<(u128, Hash256)> = None;
        for (indexed_height, hash) in index {
            if verified.contains(&hash) {
                return Err(Error::CorruptStore(format!(
                    "record index contains duplicate block {hash}"
                )));
            }

            let record = self.required_record(hash, "indexed block")?;
            if record.block.header.height != indexed_height {
                return Err(Error::CorruptStore(format!(
                    "record index height {indexed_height} disagrees with block {hash} height {}",
                    record.block.header.height
                )));
            }
            let cumulative_score = record.cumulative_score;

            if indexed_height == 0 {
                if saw_genesis || hash != metadata.genesis_hash {
                    return Err(Error::CorruptStore(format!(
                        "unexpected extra height-zero block {hash}"
                    )));
                }
                self.verify_genesis_record(&record)?;
                saw_genesis = true;
            } else {
                let parent_hash = record.block.header.parent_hash;
                if !verified.contains(&parent_hash) {
                    return Err(Error::CorruptStore(format!(
                        "block {hash} has an unreachable or unverified parent {parent_hash}"
                    )));
                }
                let block = record.block.clone();
                drop(record);

                let parent = self.required_record(parent_hash, "indexed parent")?;
                let (executed_state, increment) = self.validate_and_execute(&block, &parent)?;
                let expected_score = parent
                    .cumulative_score
                    .checked_add(increment)
                    .ok_or(Error::ChainScoreOverflow)?;
                drop(parent);
                let stored_child = self.required_record(hash, "indexed child")?;
                if executed_state != stored_child.state {
                    return Err(Error::CorruptStore(format!(
                        "stored state for block {hash} differs from deterministic execution"
                    )));
                }
                if cumulative_score != expected_score {
                    return Err(Error::CorruptStore(format!(
                        "block {hash} has cumulative score {cumulative_score}, expected {expected_score}"
                    )));
                }
            }

            verified.insert(hash);
            match preferred {
                None => preferred = Some((cumulative_score, hash)),
                Some((current_score, current_hash))
                    if self.consensus.prefers_candidate(
                        cumulative_score,
                        hash,
                        current_score,
                        current_hash,
                    ) =>
                {
                    preferred = Some((cumulative_score, hash));
                }
                Some(_) => {}
            }
        }

        if !saw_genesis {
            return Err(Error::CorruptStore(
                "configured genesis record is missing".into(),
            ));
        }
        let (_, preferred_hash) = preferred
            .ok_or_else(|| Error::CorruptStore("chain store contains no preferred tip".into()))?;
        if metadata.tip_hash != preferred_hash {
            return Err(Error::CorruptStore(format!(
                "metadata tip {} is not the globally preferred stored tip {preferred_hash}",
                metadata.tip_hash
            )));
        }
        Ok(())
    }

    fn verify_genesis_record(&self, record: &BlockRecord) -> Result<()> {
        let expected_state = LedgerState::from_genesis(&self.config)?;
        let expected_genesis = Block::genesis(&self.config, &expected_state)?;
        if record.block != expected_genesis
            || record.state != expected_state
            || record.cumulative_score != 0
        {
            return Err(Error::GenesisMismatch);
        }
        Ok(())
    }

    fn execute_transactions(
        &self,
        parent_state: &LedgerState,
        transactions: &[SignedTransaction],
        height: u64,
    ) -> Result<LedgerState> {
        let mut state = parent_state.clone();
        state.validate_invariants(self.config.parameters.maximum_supply)?;
        for transaction in transactions {
            state.apply_transaction_to_valid_state(transaction, &self.config, height)?;
        }
        state.validate_invariants(self.config.parameters.maximum_supply)?;
        Ok(state)
    }

    fn validate_and_execute(
        &self,
        block: &Block,
        parent: &BlockRecord,
    ) -> Result<(LedgerState, u128)> {
        if parent.state.root()? != parent.block.header.state_root {
            return Err(Error::CorruptStore(
                "parent state does not match its block header".into(),
            ));
        }
        if block.header.version != BLOCK_VERSION {
            return Err(Error::UnsupportedProtocol {
                expected: BLOCK_VERSION,
                actual: block.header.version,
            });
        }
        if block.header.network != self.config.network {
            return Err(Error::NetworkMismatch {
                expected: self.config.network,
                actual: block.header.network,
            });
        }
        if block.header.parent_hash != parent.block.hash()? {
            return Err(Error::ParentNotFound(block.header.parent_hash));
        }
        block.verify_body(&self.config)?;
        let state =
            self.execute_transactions(&parent.state, &block.transactions, block.header.height)?;
        if state.root()? != block.header.state_root {
            return Err(Error::StateRootMismatch);
        }
        let score = self
            .consensus
            .verify_non_genesis(block, &parent.block.header, &self.config)?;
        if score == 0 {
            return Err(Error::InvalidConsensusCommitment);
        }
        Ok((state, score))
    }

    fn reorg_depth(&self, current_tip_hash: Hash256, candidate: &BlockRecord) -> Result<u64> {
        if candidate.block.header.parent_hash == current_tip_hash {
            return Ok(0);
        }
        let mut left = self.required_record(current_tip_hash, "current tip")?;
        let mut right =
            self.required_record(candidate.block.header.parent_hash, "candidate parent")?;
        let mut visited_left = BTreeSet::new();
        let mut visited_right = BTreeSet::new();

        while left.block.header.height > right.block.header.height {
            if !visited_left.insert(left.block.hash()?) {
                return Err(Error::CorruptStore("cycle in current ancestry".into()));
            }
            left = self.parent_record(&left)?;
        }
        while right.block.header.height > left.block.header.height {
            if !visited_right.insert(right.block.hash()?) {
                return Err(Error::CorruptStore("cycle in candidate ancestry".into()));
            }
            right = self.parent_record(&right)?;
        }
        while left.block.hash()? != right.block.hash()? {
            if left.block.header.height == 0 || right.block.header.height == 0 {
                return Err(Error::CorruptStore(
                    "forks do not share the configured genesis".into(),
                ));
            }
            if !visited_left.insert(left.block.hash()?)
                || !visited_right.insert(right.block.hash()?)
            {
                return Err(Error::CorruptStore("cycle in fork ancestry".into()));
            }
            left = self.parent_record(&left)?;
            right = self.parent_record(&right)?;
        }
        let current_height = self
            .required_record(current_tip_hash, "current tip")?
            .block
            .header
            .height;
        current_height
            .checked_sub(left.block.header.height)
            .ok_or_else(|| Error::CorruptStore("common ancestor exceeds tip height".into()))
    }

    fn parent_record(&self, record: &BlockRecord) -> Result<BlockRecord> {
        if record.block.header.height == 0 {
            return Err(Error::CorruptStore(
                "genesis block cannot have a parent record".into(),
            ));
        }
        let parent = self.required_record(record.block.header.parent_hash, "block parent")?;
        let expected_child_height = parent
            .block
            .header
            .height
            .checked_add(1)
            .ok_or(Error::HeightExhausted)?;
        if expected_child_height != record.block.header.height {
            return Err(Error::CorruptStore(format!(
                "parent height {} does not precede child height {}",
                parent.block.header.height, record.block.header.height
            )));
        }
        Ok(parent)
    }

    fn checked_record(&self, hash: Hash256) -> Result<Option<BlockRecord>> {
        let Some(record) = self.store.record(hash)? else {
            return Ok(None);
        };
        if record.block.hash()? != hash {
            return Err(Error::CorruptStore(format!(
                "block record is stored under the wrong hash {hash}"
            )));
        }
        if record.block.header.version != BLOCK_VERSION {
            return Err(Error::CorruptStore(format!(
                "block {hash} uses unsupported version {}",
                record.block.header.version
            )));
        }
        if record.block.header.network != self.config.network {
            return Err(Error::CorruptStore(format!(
                "block {hash} belongs to network {}",
                record.block.header.network
            )));
        }
        if record.state.root()? != record.block.header.state_root {
            return Err(Error::CorruptStore(format!(
                "state snapshot does not match block {hash}"
            )));
        }
        record
            .state
            .validate_invariants(self.config.parameters.maximum_supply)?;
        Ok(Some(record))
    }

    fn required_record(&self, hash: Hash256, label: &str) -> Result<BlockRecord> {
        self.checked_record(hash)?
            .ok_or_else(|| Error::CorruptStore(format!("{label} record {hash} is missing")))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        Address, Amount, GenesisAllocation, MemoryStore, Network, PhaseOneConsensus,
        TransactionBody, TRANSACTION_VERSION,
    };
    use ed25519_dalek::SigningKey;

    fn fixture() -> (GenesisConfig, SigningKey, Address) {
        let sender_key = SigningKey::from_bytes(&[7; 32]);
        let recipient_key = SigningKey::from_bytes(&[8; 32]);
        let sender =
            Address::from_public_key(Network::Devnet, &sender_key.verifying_key().to_bytes());
        let recipient =
            Address::from_public_key(Network::Devnet, &recipient_key.verifying_key().to_bytes());
        let mut config = GenesisConfig::builtin(Network::Devnet);
        config.chain_id = "aura-devnet-chain-test".into();
        config.parameters.minimum_fee = Amount::from_atoms(2);
        config.allocations.push(GenesisAllocation {
            address: sender,
            available: Amount::from_atoms(1_000),
            locked: Amount::ZERO,
            purpose: "unit-test allocation".into(),
        });
        (config, sender_key, recipient)
    }

    fn transfer(
        config: &GenesisConfig,
        key: &SigningKey,
        recipient: Address,
        amount: u64,
        nonce: u64,
    ) -> SignedTransaction {
        SignedTransaction::sign(
            TransactionBody {
                version: TRANSACTION_VERSION,
                network: config.network,
                chain_id_hash: config.chain_id_hash(),
                sender: Address::from_public_key(config.network, &key.verifying_key().to_bytes()),
                recipient,
                amount: Amount::from_atoms(amount),
                fee: config.parameters.minimum_fee,
                nonce,
                valid_until_height: 100,
            },
            key,
        )
        .expect("sign transaction")
    }

    #[test]
    fn transfer_is_executed_and_committed() {
        let (config, sender_key, recipient) = fixture();
        let sender =
            Address::from_public_key(Network::Devnet, &sender_key.verifying_key().to_bytes());
        let mut chain =
            Chain::initialize(MemoryStore::default(), config.clone(), PhaseOneConsensus)
                .expect("initialize chain");
        let tx = transfer(&config, &sender_key, recipient, 100, 1);
        let block = chain.prepare_dev_block(vec![tx], 1).expect("prepare block");
        let outcome = chain.import_block(block, 1).expect("import block");
        assert!(outcome.became_canonical_tip);
        let tip = chain.tip().expect("tip");
        assert_eq!(
            tip.state.account(recipient).available,
            Amount::from_atoms(100)
        );
        assert_eq!(tip.state.account(sender).available, Amount::from_atoms(898));
        assert_eq!(tip.state.fee_pool(), Amount::from_atoms(2));
        assert_eq!(
            chain
                .verify_canonical_chain()
                .expect("valid chain")
                .transactions_verified,
            1
        );
    }

    #[test]
    fn invalid_signature_and_insufficient_balance_are_rejected() {
        let (config, sender_key, recipient) = fixture();
        let chain = Chain::initialize(MemoryStore::default(), config.clone(), PhaseOneConsensus)
            .expect("initialize chain");
        let mut tampered = transfer(&config, &sender_key, recipient, 100, 1);
        tampered.signature[0] ^= 1;
        assert!(matches!(
            chain.prepare_dev_block(vec![tampered], 1),
            Err(Error::InvalidSignature)
        ));
        let too_large = transfer(&config, &sender_key, recipient, 2_000, 1);
        assert!(matches!(
            chain.prepare_dev_block(vec![too_large], 1),
            Err(Error::InsufficientBalance { .. })
        ));
    }

    #[test]
    fn replay_and_duplicate_transaction_are_rejected() {
        let (config, sender_key, recipient) = fixture();
        let mut chain =
            Chain::initialize(MemoryStore::default(), config.clone(), PhaseOneConsensus)
                .expect("initialize chain");
        let transaction = transfer(&config, &sender_key, recipient, 100, 1);
        let block = chain
            .prepare_dev_block(vec![transaction.clone()], 1)
            .expect("prepare first block");
        chain.import_block(block, 1).expect("import first block");
        assert!(matches!(
            chain.prepare_dev_block(vec![transaction], 2),
            Err(Error::InvalidNonce {
                expected: 2,
                actual: 1
            })
        ));

        let fresh = Chain::initialize(MemoryStore::default(), config.clone(), PhaseOneConsensus)
            .expect("fresh chain");
        let genesis = fresh.tip().expect("genesis");
        let duplicate = transfer(&config, &sender_key, recipient, 100, 1);
        let candidate = Block::dev_candidate(
            Network::Devnet,
            1,
            genesis.block.hash().expect("genesis hash"),
            1,
            vec![duplicate.clone(), duplicate],
            genesis.state.root().expect("state root"),
        )
        .expect("candidate");
        let mut fresh = fresh;
        assert!(matches!(
            fresh.import_block(candidate, 1),
            Err(Error::DuplicateTransaction(_))
        ));
    }

    #[test]
    fn existing_chain_reopens_and_reverifies_without_wall_clock_input() {
        let (mut config, _, _) = fixture();
        config.parameters.maximum_future_drift_ms = 10;
        let mut chain =
            Chain::initialize(MemoryStore::default(), config.clone(), PhaseOneConsensus)
                .expect("initialize chain");

        let too_far_ahead = chain.prepare_dev_block(Vec::new(), 12).expect("candidate");
        assert!(matches!(
            chain.import_block(too_far_ahead, 1),
            Err(Error::FutureTimestamp)
        ));

        let boundary = chain.prepare_dev_block(Vec::new(), 11).expect("candidate");
        chain
            .import_block(boundary, 1)
            .expect("future-drift boundary is admissible");
        let store = chain.into_store();
        let reopened = Chain::open_existing(store, config, PhaseOneConsensus)
            .expect("deterministically reopen chain");
        let report = reopened.verify_canonical_chain().expect("verify chain");
        assert_eq!(report.blocks_verified, 2);
        assert_eq!(report.tip_height, 1);
    }

    #[test]
    fn opening_an_uninitialized_store_fails_closed() {
        let (config, _, _) = fixture();
        assert!(matches!(
            Chain::open_existing(MemoryStore::default(), config, PhaseOneConsensus),
            Err(Error::CorruptStore(_))
        ));
    }

    #[test]
    fn tampered_roots_headers_and_unknown_parents_are_rejected() {
        let (config, _, _) = fixture();
        let mut chain = Chain::initialize(MemoryStore::default(), config, PhaseOneConsensus)
            .expect("initialize chain");
        let genesis = chain.tip().expect("genesis");

        let mut bad_root = chain.prepare_dev_block(Vec::new(), 1).expect("candidate");
        bad_root.header.state_root = Hash256::ZERO;
        assert!(matches!(
            chain.import_block(bad_root, 1),
            Err(Error::StateRootMismatch)
        ));

        let wrong_height = Block::dev_candidate(
            Network::Devnet,
            2,
            genesis.block.hash().expect("genesis hash"),
            1,
            Vec::new(),
            genesis.state.root().expect("state root"),
        )
        .expect("candidate");
        assert!(matches!(
            chain.import_block(wrong_height, 1),
            Err(Error::InvalidHeight {
                expected: 1,
                actual: 2
            })
        ));

        let unknown_parent = Block::dev_candidate(
            Network::Devnet,
            1,
            crate::hash_tagged("test/unknown-parent", &[b"unknown"]),
            1,
            Vec::new(),
            genesis.state.root().expect("state root"),
        )
        .expect("candidate");
        assert!(matches!(
            chain.import_block(unknown_parent, 1),
            Err(Error::ParentNotFound(_))
        ));
    }

    #[test]
    fn longer_fork_reorganizes_deterministically() {
        let (config, _, _) = fixture();
        let mut chain = Chain::initialize(MemoryStore::default(), config, PhaseOneConsensus)
            .expect("initialize chain");
        let genesis = chain.metadata().expect("metadata").genesis_hash;
        let a1 = chain.prepare_dev_block_on(genesis, vec![], 10).expect("a1");
        let a1_hash = a1.hash().expect("hash");
        chain.import_block(a1, 10).expect("import a1");
        let a2 = chain.prepare_dev_block_on(a1_hash, vec![], 20).expect("a2");
        let a2_hash = a2.hash().expect("hash");
        chain.import_block(a2, 20).expect("import a2");

        let b1 = chain.prepare_dev_block_on(genesis, vec![], 11).expect("b1");
        let b1_hash = b1.hash().expect("hash");
        chain.import_block(b1, 20).expect("import b1");
        // At equal score, the lower hash wins. Choose a timestamp that keeps A2 canonical so
        // importing B3 below exercises a two-block reorganization rather than a tip extension.
        let mut b2_timestamp = 21;
        let b2 = loop {
            let candidate = chain
                .prepare_dev_block_on(b1_hash, vec![], b2_timestamp)
                .expect("b2");
            if candidate.hash().expect("hash") > a2_hash {
                break candidate;
            }
            b2_timestamp += 1;
        };
        let b2_hash = b2.hash().expect("hash");
        chain.import_block(b2, b2_timestamp).expect("import b2");
        let b3 = chain
            .prepare_dev_block_on(b2_hash, vec![], b2_timestamp + 1)
            .expect("b3");
        let outcome = chain.import_block(b3, b2_timestamp + 1).expect("import b3");
        assert!(outcome.became_canonical_tip);
        assert_eq!(outcome.reorg_depth, 2);
        assert_eq!(outcome.canonical_height, 3);
    }

    #[test]
    fn mainnet_non_genesis_blocks_are_disabled() {
        let config = GenesisConfig::builtin(crate::Network::Mainnet);
        let chain = Chain::initialize(MemoryStore::default(), config, PhaseOneConsensus)
            .expect("initialize chain");
        assert!(matches!(
            chain.prepare_dev_block(vec![], 1_787_356_800_001),
            Err(Error::ConsensusUnavailable)
        ));
    }
}
