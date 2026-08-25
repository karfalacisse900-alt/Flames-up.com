use crate::{
    block_work, calculate_asert_target, validate_consensus_timestamp, validate_live_timestamp,
    verify_argon2d_pow, Address, Amount, BlockRecordV2, BlockV2, BlockWork256, ChainStoreV2,
    CoinbaseV2, CumulativeWork512, DifficultyError, DifficultyParameters, Error, Hash256,
    LedgerStateV2, PowError, PowGenesisConfigV2, PowParameters, PowTargetRequirement, ReorgPlanV2,
    Result, SignedPurchaseProofV2, SignedTransferV2, StoreMetadataV2, TransactionV2,
    ARGON2D_POW_ALGORITHM_ID_V2, BLOCK_VERSION_V2, POW_PROTOCOL_VERSION, POW_STORE_SCHEMA_VERSION,
};
use std::collections::BTreeSet;

/// Result of independently validating and importing one `PoW` v2 block.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ImportOutcomeV2 {
    pub block_id: Hash256,
    pub block_work: BlockWork256,
    pub cumulative_work: CumulativeWork512,
    pub became_canonical_tip: bool,
    pub canonical_height: u64,
    pub reorg: Option<ReorgPlanV2>,
}

/// Complete deterministic verification summary for a `PoW` v2 canonical path.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VerificationReportV2 {
    pub blocks_verified: u128,
    pub transfers_verified: u128,
    pub tip_hash: Hash256,
    pub tip_height: u64,
    pub cumulative_work: CumulativeWork512,
}

/// Stored-branch transaction position and current canonical confirmation count.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ConfirmationStatusV2 {
    pub block_hash: Hash256,
    pub block_height: u64,
    pub confirmations: u64,
}

/// Canonical purchase proof plus its real block-derived confirmation state.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CanonicalPurchaseProofV2 {
    pub proof: SignedPurchaseProofV2,
    pub transaction_id: Hash256,
    pub confirmation: ConfirmationStatusV2,
}

/// Opaque authorization to run miners over one fully validated candidate.
///
/// Only [`ChainV2::prepare_candidate`] and [`ChainV2::prepare_candidate_on`] can
/// construct this capability through Aura's public API. Before returning it,
/// the chain manager checks the parent snapshot, linkage, deterministic ASERT
/// target, median-time rule, canonical body, exact coinbase payout, every
/// transfer, and the resulting state root. The frozen consensus configuration
/// travels with the candidate so a caller cannot mine it under mismatched work
/// parameters.
///
/// A shared block view is available for telemetry, but the validated block and
/// configuration cannot be replaced or mutated by downstream callers:
///
/// ```compile_fail
/// use aura_core::{BlockV2, PowGenesisConfigV2, ValidatedCandidateV2};
///
/// fn forge(
///     block: BlockV2,
///     validated_against: PowGenesisConfigV2,
/// ) -> ValidatedCandidateV2 {
///     ValidatedCandidateV2 {
///         block,
///         validated_against,
///         validated_block_id: aura_core::Hash256::ZERO,
///         validated_config_hash: aura_core::Hash256::ZERO,
///     }
/// }
/// ```
#[must_use = "a validated candidate must be mined or deliberately discarded"]
#[derive(Debug)]
pub struct ValidatedCandidateV2 {
    block: BlockV2,
    validated_against: PowGenesisConfigV2,
    validated_block_id: Hash256,
    validated_config_hash: Hash256,
}

impl ValidatedCandidateV2 {
    /// Read-only candidate view for truthful mining telemetry.
    #[must_use]
    pub const fn block(&self) -> &BlockV2 {
        &self.block
    }

    pub(crate) fn into_mining_parts(self) -> Result<(BlockV2, PowGenesisConfigV2)> {
        if self.block.id()? != self.validated_block_id
            || self.validated_against.config_hash()? != self.validated_config_hash
        {
            return Err(Error::InvalidMiningCapability);
        }
        Ok((self.block, self.validated_against))
    }

    #[cfg(test)]
    pub(crate) fn block_mut_for_miner_test(&mut self) -> &mut BlockV2 {
        &mut self.block
    }
}

/// Aura's independently validating `PoW` v2 chain manager.
pub struct ChainV2<S> {
    store: S,
    config: PowGenesisConfigV2,
}

impl<S: ChainStoreV2> ChainV2<S> {
    /// Creates the unique v2 genesis in an empty store.
    pub fn initialize(mut store: S, config: PowGenesisConfigV2) -> Result<Self> {
        if store.metadata_v2()?.is_some() || !store.record_index_v2()?.is_empty() {
            return Err(Error::Storage("PoW v2 store is already initialized".into()));
        }
        let (state, block, metadata) = Self::genesis_components(&config)?;
        let record = BlockRecordV2 {
            block,
            state,
            block_work: BlockWork256::ZERO,
            cumulative_work: CumulativeWork512::ZERO,
        };
        store.initialize_v2(&metadata, &record)?;
        let chain = Self { store, config };
        chain.verify_all_records()?;
        Ok(chain)
    }

    /// Opens a v2 store only after verifying identity, every retained branch, state, work, and tip.
    pub fn open_existing(store: S, config: PowGenesisConfigV2) -> Result<Self> {
        let (_, _, expected) = Self::genesis_components(&config)?;
        let metadata = store
            .metadata_v2()?
            .ok_or_else(|| Error::CorruptStore("PoW v2 metadata is missing".into()))?;
        if metadata.schema_version != POW_STORE_SCHEMA_VERSION {
            return Err(Error::CorruptStore(format!(
                "unsupported PoW store schema version {}",
                metadata.schema_version
            )));
        }
        if metadata.consensus_spec_hash != expected.consensus_spec_hash
            || metadata.genesis_hash != expected.genesis_hash
            || metadata.network != expected.network
            || metadata.chain_id_hash != expected.chain_id_hash
        {
            return Err(Error::GenesisMismatch);
        }
        let chain = Self { store, config };
        chain.verify_all_records()?;
        Ok(chain)
    }

    fn genesis_components(
        config: &PowGenesisConfigV2,
    ) -> Result<(LedgerStateV2, BlockV2, StoreMetadataV2)> {
        config.validate()?;
        let state = LedgerStateV2::from_genesis(config)?;
        let block = BlockV2::genesis(config, state.root()?)?;
        let genesis_hash = block.id()?;
        Ok((
            state,
            block,
            StoreMetadataV2 {
                schema_version: POW_STORE_SCHEMA_VERSION,
                consensus_spec_hash: config.config_hash()?,
                genesis_hash,
                tip_hash: genesis_hash,
                network: config.network,
                chain_id_hash: config.consensus_identity_hash()?,
            },
        ))
    }

    #[must_use]
    pub const fn config(&self) -> &PowGenesisConfigV2 {
        &self.config
    }

    pub fn metadata(&self) -> Result<StoreMetadataV2> {
        self.store
            .metadata_v2()?
            .ok_or_else(|| Error::CorruptStore("PoW v2 metadata is missing".into()))
    }

    pub fn record(&self, hash: Hash256) -> Result<Option<BlockRecordV2>> {
        self.checked_record(hash)
    }

    pub fn tip(&self) -> Result<BlockRecordV2> {
        let metadata = self.metadata()?;
        self.required_record(metadata.tip_hash, "canonical tip")
    }

    pub fn canonical_record(&self, height: u64) -> Result<Option<BlockRecordV2>> {
        let Some(hash) = self.store.canonical_hash_v2(height)? else {
            return Ok(None);
        };
        self.checked_record(hash)
    }

    /// Constructs a fully state-valid candidate on any retained branch.
    ///
    /// The returned block has nonce zero but has not been accepted. It becomes a valid block only
    /// after a mining worker finds a nonce whose Argon2d result satisfies its required target.
    pub fn prepare_candidate_on(
        &self,
        parent_hash: Hash256,
        miner: Address,
        transfers: Vec<SignedTransferV2>,
        timestamp_seconds: u64,
        extra_nonce: u64,
    ) -> Result<ValidatedCandidateV2> {
        self.prepare_candidate_transactions_on(
            parent_hash,
            miner,
            transfers.into_iter().map(TransactionV2::Transfer).collect(),
            timestamp_seconds,
            extra_nonce,
        )
    }

    /// Constructs a fully state-valid candidate containing any supported non-coinbase v2
    /// transaction. Coinbase creation remains internal and exact.
    pub fn prepare_candidate_transactions_on(
        &self,
        parent_hash: Hash256,
        miner: Address,
        pending: Vec<TransactionV2>,
        timestamp_seconds: u64,
        extra_nonce: u64,
    ) -> Result<ValidatedCandidateV2> {
        if miner.network() != self.config.network {
            return Err(Error::AddressNetworkMismatch {
                expected: self.config.network,
                actual: miner.network(),
            });
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
        self.validate_median_time(parent_hash, timestamp_seconds)?;

        // Validate candidate transactions in exact block order while calculating miner fees.
        let mut unsettled = parent.state.clone();
        let mut fees = Amount::ZERO;
        for transaction in &pending {
            let fee = unsettled.apply_transaction_for_candidate(
                transaction,
                &self.config,
                height,
                timestamp_seconds,
            )?;
            fees = fees.checked_add(fee)?;
        }
        let subsidy = self.config.subsidy(parent.state.total_supply(), height)?;
        let payout = subsidy.checked_add(fees)?;
        let mut transactions = Vec::with_capacity(pending.len().saturating_add(1));
        transactions.push(TransactionV2::Coinbase(CoinbaseV2 {
            version: POW_PROTOCOL_VERSION,
            network: self.config.network,
            chain_id_hash: self.config.consensus_identity_hash()?,
            height,
            recipient: miner,
            payout,
            extra_nonce,
        }));
        transactions.extend(pending);

        let execution = LedgerStateV2::execute_block(
            &parent.state,
            &transactions,
            &self.config,
            height,
            timestamp_seconds,
        )?;
        let target = self.required_target(&parent)?;
        let block = BlockV2::candidate(
            &self.config,
            height,
            parent_hash,
            timestamp_seconds,
            transactions,
            execution.state.root()?,
            target,
            0,
        )?;

        // Re-run the complete pre-work and state checks at the capability boundary. This keeps
        // future candidate-construction changes from accidentally granting mining authority for
        // an incompletely validated block.
        self.validate_candidate_without_work(&block, &parent)?;
        Ok(ValidatedCandidateV2 {
            validated_block_id: block.id()?,
            validated_config_hash: self.config.config_hash()?,
            block,
            validated_against: self.config.clone(),
        })
    }

    /// Constructs a state-valid candidate on the current canonical tip.
    pub fn prepare_candidate(
        &self,
        miner: Address,
        transfers: Vec<SignedTransferV2>,
        timestamp_seconds: u64,
        extra_nonce: u64,
    ) -> Result<ValidatedCandidateV2> {
        let metadata = self.metadata()?;
        self.prepare_candidate_on(
            metadata.tip_hash,
            miner,
            transfers,
            timestamp_seconds,
            extra_nonce,
        )
    }

    /// Constructs a candidate from the current canonical tip using supported non-coinbase
    /// transactions selected by the unified mempool.
    pub fn prepare_candidate_transactions(
        &self,
        miner: Address,
        pending: Vec<TransactionV2>,
        timestamp_seconds: u64,
        extra_nonce: u64,
    ) -> Result<ValidatedCandidateV2> {
        let metadata = self.metadata()?;
        self.prepare_candidate_transactions_on(
            metadata.tip_hash,
            miner,
            pending,
            timestamp_seconds,
            extra_nonce,
        )
    }

    /// Imports a block produced from local mining work only if it still extends the canonical tip.
    ///
    /// Network-received blocks continue to use [`Self::import_block`] so valid competing branches
    /// are retained. This stricter local path closes the candidate-preparation/mining race: a
    /// solution found after another block changes the tip is reported as stale and is not stored.
    pub fn import_locally_mined_block(
        &mut self,
        block: BlockV2,
        now_seconds: u64,
    ) -> Result<ImportOutcomeV2> {
        let current_tip = self.metadata()?.tip_hash;
        if block.header.parent_block_id != current_tip {
            return Err(Error::StaleMiningCandidate {
                current_tip,
                candidate_parent: block.header.parent_block_id,
            });
        }
        self.import_block(block, now_seconds)
    }

    /// Validates, executes, persists, and fork-selects a received or locally mined block.
    pub fn import_block(&mut self, block: BlockV2, now_seconds: u64) -> Result<ImportOutcomeV2> {
        let block_id = block.id()?;
        if self.checked_record(block_id)?.is_some() {
            return Err(Error::DuplicateBlock(block_id));
        }
        if block.header.height == 0 {
            return Err(Error::InvalidHeight {
                expected: 1,
                actual: 0,
            });
        }
        let parent = self
            .checked_record(block.header.parent_block_id)?
            .ok_or(Error::ParentNotFound(block.header.parent_block_id))?;
        validate_live_timestamp(
            block.header.timestamp_seconds,
            now_seconds,
            self.config.pow.maximum_future_drift_seconds,
        )
        .map_err(map_difficulty_error)?;

        let (state, verified_work) = self.validate_and_execute(&block, &parent)?;
        let cumulative_work = parent
            .cumulative_work
            .checked_add_block(verified_work)
            .map_err(|_| Error::CumulativeWorkOverflow)?;
        let record = BlockRecordV2 {
            block,
            state,
            block_work: verified_work,
            cumulative_work,
        };

        let metadata = self.metadata()?;
        let current_tip = self.required_record(metadata.tip_hash, "canonical tip")?;
        let becomes_tip = prefers_candidate(
            record.cumulative_work,
            block_id,
            current_tip.cumulative_work,
            metadata.tip_hash,
        );
        let reorg = if becomes_tip {
            Some(self.build_reorg_plan(metadata.tip_hash, &record)?)
        } else {
            None
        };
        self.store.commit_block_v2(&record, reorg.as_ref())?;
        let canonical_height = if becomes_tip {
            record.block.header.height
        } else {
            current_tip.block.header.height
        };
        Ok(ImportOutcomeV2 {
            block_id,
            block_work: verified_work,
            cumulative_work,
            became_canonical_tip: becomes_tip,
            canonical_height,
            reorg,
        })
    }

    /// Recomputes and verifies all retained branches and canonical indexes.
    pub fn verify_all_records(&self) -> Result<VerificationReportV2> {
        let metadata = self.metadata()?;
        let mut index = self.store.record_index_v2()?;
        index.sort_unstable();
        if index.is_empty() {
            return Err(Error::CorruptStore(
                "PoW v2 store contains no blocks".into(),
            ));
        }

        let mut verified = BTreeSet::new();
        let mut saw_genesis = false;
        let mut preferred: Option<(CumulativeWork512, Hash256)> = None;
        for (indexed_height, hash) in index {
            if !verified.insert(hash) {
                return Err(Error::CorruptStore(format!(
                    "duplicate PoW v2 record index entry {hash}"
                )));
            }
            let record = self.required_record(hash, "indexed PoW block")?;
            if record.block.header.height != indexed_height {
                return Err(Error::CorruptStore(
                    "PoW v2 record index height mismatch".into(),
                ));
            }
            if indexed_height == 0 {
                if saw_genesis || hash != metadata.genesis_hash {
                    return Err(Error::CorruptStore(
                        "unexpected additional PoW v2 genesis record".into(),
                    ));
                }
                self.verify_genesis_record(&record)?;
                saw_genesis = true;
            } else {
                let parent_hash = record.block.header.parent_block_id;
                if !verified.contains(&parent_hash) {
                    return Err(Error::CorruptStore(format!(
                        "PoW v2 block {hash} has an unreachable parent {parent_hash}"
                    )));
                }
                let parent = self.required_record(parent_hash, "indexed PoW parent")?;
                let (state, work) = self.validate_and_execute(&record.block, &parent)?;
                let cumulative = parent
                    .cumulative_work
                    .checked_add_block(work)
                    .map_err(|_| Error::CumulativeWorkOverflow)?;
                if state != record.state
                    || work != record.block_work
                    || cumulative != record.cumulative_work
                {
                    return Err(Error::CorruptStore(format!(
                        "stored state or work for PoW v2 block {hash} is incorrect"
                    )));
                }
            }

            match preferred {
                None => preferred = Some((record.cumulative_work, hash)),
                Some((work, tip)) if prefers_candidate(record.cumulative_work, hash, work, tip) => {
                    preferred = Some((record.cumulative_work, hash));
                }
                Some(_) => {}
            }
        }
        if !saw_genesis {
            return Err(Error::GenesisMismatch);
        }
        let (preferred_work, preferred_hash) = preferred
            .ok_or_else(|| Error::CorruptStore("PoW v2 store has no preferred tip".into()))?;
        if metadata.tip_hash != preferred_hash {
            return Err(Error::CorruptStore(format!(
                "stored PoW v2 tip {} is not greatest-work tip {preferred_hash}",
                metadata.tip_hash
            )));
        }

        let (blocks, transfers, height) = self.verify_canonical_indexes(&metadata)?;
        Ok(VerificationReportV2 {
            blocks_verified: blocks,
            transfers_verified: transfers,
            tip_hash: preferred_hash,
            tip_height: height,
            cumulative_work: preferred_work,
        })
    }

    /// Finds a transfer only on the current canonical path and derives confirmations from depth.
    pub fn confirmations(&self, intent_id: Hash256) -> Result<Option<ConfirmationStatusV2>> {
        let tip = self.tip()?;
        for height in (0..=tip.block.header.height).rev() {
            let record = self.canonical_record(height)?.ok_or_else(|| {
                Error::CorruptStore(format!("canonical height {height} is missing"))
            })?;
            for transaction in &record.block.transactions {
                if transaction.intent_id()? == Some(intent_id) {
                    return Ok(Some(ConfirmationStatusV2 {
                        block_hash: record.block.id()?,
                        block_height: height,
                        confirmations: tip
                            .block
                            .header
                            .height
                            .checked_sub(height)
                            .and_then(|depth| depth.checked_add(1))
                            .ok_or(Error::HeightExhausted)?,
                    }));
                }
            }
        }
        Ok(None)
    }

    /// Finds a purchase proof only on the current canonical path.
    pub fn canonical_purchase_proof(
        &self,
        proof_id: Hash256,
    ) -> Result<Option<CanonicalPurchaseProofV2>> {
        let tip = self.tip()?;
        for height in (0..=tip.block.header.height).rev() {
            let record = self.canonical_record(height)?.ok_or_else(|| {
                Error::CorruptStore(format!("canonical height {height} is missing"))
            })?;
            for transaction in &record.block.transactions {
                let Some(proof) = transaction.as_purchase_proof() else {
                    continue;
                };
                if proof.proof_id()? != proof_id {
                    continue;
                }
                return Ok(Some(CanonicalPurchaseProofV2 {
                    proof: proof.clone(),
                    transaction_id: proof.intent_id()?,
                    confirmation: ConfirmationStatusV2 {
                        block_hash: record.block.id()?,
                        block_height: height,
                        confirmations: tip
                            .block
                            .header
                            .height
                            .checked_sub(height)
                            .and_then(|depth| depth.checked_add(1))
                            .ok_or(Error::HeightExhausted)?,
                    },
                }));
            }
        }
        Ok(None)
    }

    /// Returns whether the canonical path already commits the private verifier's nullifier.
    pub fn canonical_contains_purchase_nullifier(&self, nullifier: Hash256) -> Result<bool> {
        let tip = self.tip()?;
        for height in (0..=tip.block.header.height).rev() {
            let record = self.canonical_record(height)?.ok_or_else(|| {
                Error::CorruptStore(format!("canonical height {height} is missing"))
            })?;
            if record.block.transactions.iter().any(|transaction| {
                transaction
                    .as_purchase_proof()
                    .is_some_and(|proof| proof.receipt_nullifier() == nullifier)
            }) {
                return Ok(true);
            }
        }
        Ok(false)
    }

    #[must_use]
    pub fn into_store(self) -> S {
        self.store
    }

    fn validate_and_execute(
        &self,
        block: &BlockV2,
        parent: &BlockRecordV2,
    ) -> Result<(LedgerStateV2, BlockWork256)> {
        let expected_target = self.validate_header_and_body(block, parent)?;
        let header = &block.header;

        // Expensive work is checked only after linkage, target, timestamp, and bounded body checks.
        let requirement = PowTargetRequirement {
            declared: header.target,
            required: expected_target,
            minimum: self.config.pow.minimum_target,
            pow_limit: self.config.pow.pow_limit,
        };
        verify_argon2d_pow(
            &header.work_bytes()?,
            header.chain_id_hash,
            header.parent_block_id,
            requirement,
            self.pow_parameters(),
        )
        .map_err(map_pow_error)?;

        let state = self.execute_and_verify_state(block, parent)?;
        let work = block_work(header.target).map_err(|_| Error::InvalidTarget)?;
        Ok((state, work))
    }

    fn validate_candidate_without_work(
        &self,
        block: &BlockV2,
        parent: &BlockRecordV2,
    ) -> Result<()> {
        if block.header.nonce != 0 {
            return Err(Error::InvalidProofOfWork);
        }
        self.validate_header_and_body(block, parent)?;
        self.execute_and_verify_state(block, parent)?;
        Ok(())
    }

    fn validate_header_and_body(
        &self,
        block: &BlockV2,
        parent: &BlockRecordV2,
    ) -> Result<crate::Target256> {
        if parent.state.root()? != parent.block.header.state_root {
            return Err(Error::CorruptStore(
                "PoW v2 parent snapshot does not match its state root".into(),
            ));
        }
        let header = &block.header;
        if header.version != BLOCK_VERSION_V2 {
            return Err(Error::UnsupportedProtocol {
                expected: BLOCK_VERSION_V2,
                actual: header.version,
            });
        }
        if header.pow_algorithm != ARGON2D_POW_ALGORITHM_ID_V2 {
            return Err(Error::UnsupportedConsensus(header.pow_algorithm));
        }
        if header.network != self.config.network {
            return Err(Error::NetworkMismatch {
                expected: self.config.network,
                actual: header.network,
            });
        }
        if header.chain_id_hash != self.config.consensus_identity_hash()? {
            return Err(Error::ChainIdMismatch);
        }
        if header.parent_block_id != parent.block.id()? {
            return Err(Error::ParentNotFound(header.parent_block_id));
        }
        let expected_height = parent
            .block
            .header
            .height
            .checked_add(1)
            .ok_or(Error::HeightExhausted)?;
        if header.height != expected_height {
            return Err(Error::InvalidHeight {
                expected: expected_height,
                actual: header.height,
            });
        }

        let expected_target = self.required_target(parent)?;
        if header.target != expected_target {
            return Err(Error::UnexpectedTarget);
        }
        self.validate_median_time(header.parent_block_id, header.timestamp_seconds)?;
        block.verify_body(&self.config)?;
        self.validate_purchase_proof_history(block, parent)?;
        Ok(expected_target)
    }

    fn validate_purchase_proof_history(
        &self,
        block: &BlockV2,
        parent: &BlockRecordV2,
    ) -> Result<()> {
        let mut candidate_ids = BTreeSet::new();
        let mut candidate_nullifiers = BTreeSet::new();
        for transaction in &block.transactions {
            let Some(proof) = transaction.as_purchase_proof() else {
                continue;
            };
            let proof_id = proof.proof_id()?;
            if !candidate_ids.insert(proof_id) {
                return Err(Error::DuplicateProof(proof_id));
            }
            let nullifier = proof.receipt_nullifier();
            if !candidate_nullifiers.insert(nullifier) {
                return Err(Error::DuplicateProofNullifier(nullifier));
            }
        }
        if candidate_ids.is_empty() {
            return Ok(());
        }

        let mut ancestor = parent.clone();
        loop {
            for transaction in &ancestor.block.transactions {
                let Some(proof) = transaction.as_purchase_proof() else {
                    continue;
                };
                let proof_id = proof.proof_id()?;
                if candidate_ids.contains(&proof_id) {
                    return Err(Error::DuplicateProof(proof_id));
                }
                let nullifier = proof.receipt_nullifier();
                if candidate_nullifiers.contains(&nullifier) {
                    return Err(Error::DuplicateProofNullifier(nullifier));
                }
            }
            if ancestor.block.header.height == 0 {
                break;
            }
            ancestor = self.required_record(
                ancestor.block.header.parent_block_id,
                "purchase-proof ancestor",
            )?;
        }
        Ok(())
    }

    fn execute_and_verify_state(
        &self,
        block: &BlockV2,
        parent: &BlockRecordV2,
    ) -> Result<LedgerStateV2> {
        let header = &block.header;
        let execution = LedgerStateV2::execute_block(
            &parent.state,
            &block.transactions,
            &self.config,
            header.height,
            header.timestamp_seconds,
        )?;
        if execution.state.root()? != header.state_root {
            return Err(Error::StateRootMismatch);
        }
        Ok(execution.state)
    }

    fn required_target(&self, parent: &BlockRecordV2) -> Result<crate::Target256> {
        calculate_asert_target(
            parent.block.header.height,
            parent.block.header.timestamp_seconds,
            self.config.genesis_time_seconds,
            self.difficulty_parameters()?,
        )
        .map_err(map_difficulty_error)
    }

    fn difficulty_parameters(&self) -> Result<DifficultyParameters> {
        Ok(DifficultyParameters {
            target_block_interval_seconds: self.config.pow.target_block_interval_seconds,
            asert_half_life_seconds: self.config.pow.asert_half_life_seconds,
            initial_target: self.config.pow.initial_target,
            pow_limit: self.config.pow.pow_limit,
            minimum_target: self.config.pow.minimum_target,
            median_time_window: u8::try_from(self.config.pow.median_time_window).map_err(|_| {
                Error::InvalidGenesis("median-time window does not fit its frozen width".into())
            })?,
            maximum_future_drift_seconds: self.config.pow.maximum_future_drift_seconds,
        })
    }

    fn pow_parameters(&self) -> PowParameters {
        PowParameters::new(
            self.config.pow.argon_memory_kib,
            self.config.pow.argon_time_cost,
            self.config.pow.argon_lanes,
        )
    }

    fn validate_median_time(&self, parent_hash: Hash256, candidate: u64) -> Result<()> {
        let mut timestamps = Vec::new();
        let mut record = self.required_record(parent_hash, "timestamp parent")?;
        for _ in 0..self.config.pow.median_time_window {
            timestamps.push(record.block.header.timestamp_seconds);
            if record.block.header.height == 0 {
                break;
            }
            record =
                self.required_record(record.block.header.parent_block_id, "timestamp ancestor")?;
        }
        timestamps.reverse();
        validate_consensus_timestamp(
            candidate,
            &timestamps,
            u8::try_from(self.config.pow.median_time_window).map_err(|_| {
                Error::InvalidGenesis("median-time window does not fit its frozen width".into())
            })?,
        )
        .map_err(map_difficulty_error)
    }

    fn verify_genesis_record(&self, record: &BlockRecordV2) -> Result<()> {
        let state = LedgerStateV2::from_genesis(&self.config)?;
        let block = BlockV2::genesis(&self.config, state.root()?)?;
        if record.block != block
            || record.state != state
            || record.block_work != BlockWork256::ZERO
            || record.cumulative_work != CumulativeWork512::ZERO
        {
            return Err(Error::GenesisMismatch);
        }
        Ok(())
    }

    fn verify_canonical_indexes(&self, metadata: &StoreMetadataV2) -> Result<(u128, u128, u64)> {
        let tip = self.required_record(metadata.tip_hash, "canonical tip")?;
        let tip_height = tip.block.header.height;
        let mut canonical = self.store.canonical_index_v2()?;
        canonical.sort_unstable_by_key(|(height, _)| *height);
        let expected_entries = u128::from(tip_height) + 1;
        if u128::try_from(canonical.len()).map_err(|_| Error::HeightExhausted)? != expected_entries
        {
            return Err(Error::CorruptStore(
                "canonical PoW v2 index has missing, duplicate, or stale heights".into(),
            ));
        }
        for (position, (height, _)) in canonical.iter().enumerate() {
            if u128::try_from(position).map_err(|_| Error::HeightExhausted)? != u128::from(*height)
            {
                return Err(Error::CorruptStore(
                    "canonical PoW v2 index is not contiguous from genesis".into(),
                ));
            }
        }
        let mut transfers = 0_u128;
        let mut expected_hash = metadata.tip_hash;
        for (height, hash) in canonical.into_iter().rev() {
            if hash != expected_hash {
                return Err(Error::CorruptStore(
                    "canonical PoW v2 tip or parent mapping is inconsistent".into(),
                ));
            }
            let record = self.required_record(hash, "canonical indexed block")?;
            if record.block.header.height != height {
                return Err(Error::CorruptStore(
                    "canonical PoW v2 height index is inconsistent".into(),
                ));
            }
            transfers = transfers
                .checked_add(
                    u128::try_from(
                        record
                            .block
                            .transactions
                            .iter()
                            .filter(|tx| matches!(tx, TransactionV2::Transfer(_)))
                            .count(),
                    )
                    .map_err(|_| Error::AmountOverflow)?,
                )
                .ok_or(Error::AmountOverflow)?;
            expected_hash = record.block.header.parent_block_id;
        }
        if expected_hash != Hash256::ZERO {
            return Err(Error::CorruptStore(
                "canonical PoW v2 index does not terminate at genesis".into(),
            ));
        }
        Ok((expected_entries, transfers, tip_height))
    }

    fn build_reorg_plan(
        &self,
        current_tip_hash: Hash256,
        candidate: &BlockRecordV2,
    ) -> Result<ReorgPlanV2> {
        let candidate_hash = candidate.block.id()?;
        let mut left_hash = current_tip_hash;
        let mut left = self.required_record(left_hash, "current tip")?;
        let mut right_hash = candidate_hash;
        let mut right = candidate.clone();
        let mut disconnect = Vec::new();
        let mut connect_reverse = Vec::new();
        let mut visited_left = BTreeSet::new();
        let mut visited_right = BTreeSet::new();

        while left.block.header.height > right.block.header.height {
            if !visited_left.insert(left_hash) {
                return Err(Error::CorruptStore(
                    "cycle in old canonical ancestry".into(),
                ));
            }
            disconnect.push(left_hash);
            left_hash = left.block.header.parent_block_id;
            left = self.required_record(left_hash, "old branch parent")?;
        }
        while right.block.header.height > left.block.header.height {
            if !visited_right.insert(right_hash) {
                return Err(Error::CorruptStore("cycle in candidate ancestry".into()));
            }
            connect_reverse.push(right_hash);
            right_hash = right.block.header.parent_block_id;
            right = self.required_record(right_hash, "candidate branch parent")?;
        }
        while left_hash != right_hash {
            if left.block.header.height == 0 || right.block.header.height == 0 {
                return Err(Error::CorruptStore(
                    "PoW v2 branches do not share configured genesis".into(),
                ));
            }
            if !visited_left.insert(left_hash) || !visited_right.insert(right_hash) {
                return Err(Error::CorruptStore("cycle in PoW v2 fork ancestry".into()));
            }
            disconnect.push(left_hash);
            connect_reverse.push(right_hash);
            left_hash = left.block.header.parent_block_id;
            right_hash = right.block.header.parent_block_id;
            left = self.required_record(left_hash, "old fork parent")?;
            right = self.required_record(right_hash, "new fork parent")?;
        }
        connect_reverse.reverse();
        Ok(ReorgPlanV2 {
            old_tip: current_tip_hash,
            new_tip: candidate_hash,
            common_ancestor: left_hash,
            disconnect,
            connect: connect_reverse,
        })
    }

    fn checked_record(&self, hash: Hash256) -> Result<Option<BlockRecordV2>> {
        let Some(record) = self.store.record_v2(hash)? else {
            return Ok(None);
        };
        if record.block.id()? != hash {
            return Err(Error::CorruptStore(format!(
                "PoW v2 block is stored under wrong ID {hash}"
            )));
        }
        if record.block.header.network != self.config.network
            || record.block.header.chain_id_hash != self.config.consensus_identity_hash()?
        {
            return Err(Error::CorruptStore(format!(
                "PoW v2 block {hash} belongs to another chain"
            )));
        }
        if record.state.root()? != record.block.header.state_root {
            return Err(Error::CorruptStore(format!(
                "PoW v2 state snapshot does not match block {hash}"
            )));
        }
        record
            .state
            .validate_invariants(self.config.economics.maximum_supply)?;
        Ok(Some(record))
    }

    fn required_record(&self, hash: Hash256, label: &str) -> Result<BlockRecordV2> {
        self.checked_record(hash)?
            .ok_or_else(|| Error::CorruptStore(format!("{label} record {hash} is missing")))
    }
}

/// Greatest exact accepted work wins; equal work uses only lower tip ID, never height.
#[must_use]
pub fn prefers_candidate(
    candidate_work: CumulativeWork512,
    candidate_hash: Hash256,
    current_work: CumulativeWork512,
    current_hash: Hash256,
) -> bool {
    candidate_work > current_work
        || (candidate_work == current_work && candidate_hash < current_hash)
}

fn map_pow_error(error: PowError) -> Error {
    match error {
        PowError::TargetMismatch => Error::UnexpectedTarget,
        PowError::InvalidTarget(_) => Error::InvalidTarget,
        PowError::InsufficientWork => Error::InvalidProofOfWork,
        PowError::InvalidParameters(message) | PowError::CalculationFailed(message) => {
            Error::InvalidGenesis(format!("Argon2d consensus error: {message}"))
        }
    }
}

fn map_difficulty_error(error: DifficultyError) -> Error {
    match error {
        DifficultyError::TimestampNotAfterMedian => Error::NonMonotonicTimestamp,
        DifficultyError::TimestampTooFarInFuture => Error::FutureTimestamp,
        DifficultyError::InvalidTarget(_) => Error::InvalidTarget,
        other => Error::InvalidGenesis(format!("difficulty consensus error: {other}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        calculate_argon2d_work, MemoryStoreV2, PowDigest, Target256, TransactionBodyV2,
        TRANSACTION_VERSION_V2,
    };
    use ed25519_dalek::SigningKey;

    fn mine(candidate: ValidatedCandidateV2, config: &PowGenesisConfigV2) -> BlockV2 {
        let (block, validated_config) = candidate.into_mining_parts().expect("sealed candidate");
        assert_eq!(&validated_config, config, "candidate froze another config");
        mine_raw(block, config)
    }

    fn mine_raw(mut block: BlockV2, config: &PowGenesisConfigV2) -> BlockV2 {
        for nonce in 0..10_000_u128 {
            block.header.nonce = nonce;
            let digest = calculate_argon2d_work(
                &block.header.work_bytes().expect("header"),
                block.header.chain_id_hash,
                block.header.parent_block_id,
                PowParameters::new(
                    config.pow.argon_memory_kib,
                    config.pow.argon_time_cost,
                    config.pow.argon_lanes,
                ),
            )
            .expect("attempt");
            if digest.as_be_bytes() <= block.header.target.as_be_bytes() {
                return block;
            }
        }
        panic!("regtest target should be solved quickly")
    }

    fn setup() -> (
        PowGenesisConfigV2,
        ChainV2<MemoryStoreV2>,
        SigningKey,
        Address,
    ) {
        let key = SigningKey::from_bytes(&[21; 32]);
        let recipient_key = SigningKey::from_bytes(&[22; 32]);
        let recipient = Address::from_public_key(
            crate::Network::Devnet,
            &recipient_key.verifying_key().to_bytes(),
        );
        let config = PowGenesisConfigV2::local_regtest();
        let chain = ChainV2::initialize(MemoryStoreV2::default(), config.clone())
            .expect("initialize PoW chain");
        (config, chain, key, recipient)
    }

    #[test]
    fn genuine_pow_coinbase_and_transfer_lifecycle_updates_confirmations() {
        let (config, mut chain, miner_key, recipient) = setup();
        let miner = Address::from_public_key(config.network, &miner_key.verifying_key().to_bytes());
        let first = chain
            .prepare_candidate(miner, Vec::new(), 1, 1)
            .expect("candidate");
        let first = mine(first, &config);
        let first_outcome = chain.import_block(first, 1).expect("valid PoW block");
        assert!(first_outcome.became_canonical_tip);
        assert_eq!(
            chain.tip().expect("tip").state.account(miner).available,
            config.economics.block_subsidy
        );

        let transfer = SignedTransferV2::sign(
            TransactionBodyV2 {
                version: TRANSACTION_VERSION_V2,
                network: config.network,
                chain_id_hash: config.consensus_identity_hash().expect("identity"),
                sender: miner,
                recipient,
                amount: Amount::from_atoms(10_000),
                fee: config.limits.minimum_fee,
                nonce: 1,
                valid_until_height: 100,
            },
            &miner_key,
        )
        .expect("sign transfer");
        let intent = transfer.intent_id().expect("intent");
        let second = chain
            .prepare_candidate(miner, vec![transfer], 2, 2)
            .expect("candidate");
        let second = mine(second, &config);
        chain.import_block(second, 2).expect("transfer block");
        assert_eq!(
            chain
                .confirmations(intent)
                .expect("status")
                .expect("confirmed")
                .confirmations,
            1
        );

        let third = mine(
            chain
                .prepare_candidate(miner, Vec::new(), 3, 3)
                .expect("candidate"),
            &config,
        );
        chain.import_block(third, 3).expect("third block");
        assert_eq!(
            chain
                .confirmations(intent)
                .expect("status")
                .expect("confirmed")
                .confirmations,
            2
        );
        let report = chain.verify_all_records().expect("verify all branches");
        assert_eq!(report.blocks_verified, 4);
        assert_eq!(report.transfers_verified, 1);
    }

    #[test]
    fn fake_work_wrong_target_and_bad_reward_do_not_mutate_tip() {
        let (config, mut chain, miner_key, _) = setup();
        let miner = Address::from_public_key(config.network, &miner_key.verifying_key().to_bytes());
        let original_tip = chain.metadata().expect("metadata").tip_hash;

        let fake = chain
            .prepare_candidate(miner, Vec::new(), 1, 0)
            .expect("candidate");
        let (mut fake, _) = fake.into_mining_parts().expect("sealed candidate");
        // Find a nonce that specifically does not satisfy a hard target, then claim that target.
        fake.header.target = Target256::ONE;
        assert!(matches!(
            chain.import_block(fake, 1),
            Err(Error::UnexpectedTarget)
        ));

        let overpaid = chain
            .prepare_candidate(miner, Vec::new(), 1, 0)
            .expect("candidate");
        let (mut overpaid, _) = overpaid.into_mining_parts().expect("sealed candidate");
        let TransactionV2::Coinbase(coinbase) = &mut overpaid.transactions[0] else {
            unreachable!()
        };
        coinbase.payout = coinbase
            .payout
            .checked_add(Amount::from_atoms(1))
            .expect("overpay");
        overpaid.header.transaction_root =
            BlockV2::transaction_root(&overpaid.transactions).expect("root");
        overpaid.header.state_root = chain.tip().expect("tip").state.root().expect("wrong root");
        let overpaid = mine_raw(overpaid, &config);
        assert!(matches!(
            chain.import_block(overpaid, 1),
            Err(Error::CoinbasePayoutMismatch { .. } | Error::StateRootMismatch)
        ));
        assert_eq!(chain.metadata().expect("metadata").tip_hash, original_tip);
    }

    #[test]
    fn locally_mined_candidate_is_rejected_if_the_tip_changed_during_work() {
        let (config, mut chain, miner_key, _) = setup();
        let miner = Address::from_public_key(config.network, &miner_key.verifying_key().to_bytes());
        let genesis = chain.metadata().expect("metadata").tip_hash;
        let stale_candidate = chain
            .prepare_candidate(miner, Vec::new(), 1, 10)
            .expect("stale candidate");
        let winning_candidate = chain
            .prepare_candidate(miner, Vec::new(), 1, 11)
            .expect("winning candidate");
        let winning_block = mine(winning_candidate, &config);
        let winning_id = winning_block.id().expect("winning ID");
        chain
            .import_locally_mined_block(winning_block, 1)
            .expect("winning local block");

        let stale_block = mine(stale_candidate, &config);
        let stale_id = stale_block.id().expect("stale ID");
        assert!(matches!(
            chain.import_locally_mined_block(stale_block, 1),
            Err(Error::StaleMiningCandidate {
                current_tip,
                candidate_parent,
            }) if current_tip == winning_id && candidate_parent == genesis
        ));
        assert_eq!(chain.metadata().expect("metadata").tip_hash, winning_id);
        assert!(chain.record(stale_id).expect("record lookup").is_none());
    }

    #[test]
    fn equal_work_tie_ignores_height_and_uses_only_tip_hash() {
        let work = CumulativeWork512::from_be_bytes([7; 64]);
        let low = Hash256::from_bytes([1; 32]);
        let high = Hash256::from_bytes([2; 32]);
        assert!(prefers_candidate(work, low, work, high));
        assert!(!prefers_candidate(work, high, work, low));
    }

    #[test]
    fn equal_work_sibling_with_lower_id_reorganizes_canonically() {
        let (config, mut chain, miner_key, _) = setup();
        let miner = Address::from_public_key(config.network, &miner_key.verifying_key().to_bytes());
        let genesis = chain.metadata().expect("metadata").genesis_hash;
        let first = mine(
            chain
                .prepare_candidate_on(genesis, miner, Vec::new(), 1, 11)
                .expect("first sibling"),
            &config,
        );
        let second = mine(
            chain
                .prepare_candidate_on(genesis, miner, Vec::new(), 1, 12)
                .expect("second sibling"),
            &config,
        );
        let first_id = first.id().expect("first ID");
        let second_id = second.id().expect("second ID");
        let (low, low_id, high, high_id) = if first_id < second_id {
            (first, first_id, second, second_id)
        } else {
            (second, second_id, first, first_id)
        };

        let high_outcome = chain.import_block(high, 1).expect("import high ID");
        assert!(high_outcome.became_canonical_tip);
        assert_eq!(chain.metadata().expect("metadata").tip_hash, high_id);
        let low_outcome = chain.import_block(low, 1).expect("import low ID");
        assert!(low_outcome.became_canonical_tip);
        let plan = low_outcome.reorg.expect("equal-work tie reorg");
        assert_eq!(plan.common_ancestor, genesis);
        assert_eq!(plan.disconnect, vec![high_id]);
        assert_eq!(plan.connect, vec![low_id]);
        assert_eq!(chain.metadata().expect("metadata").tip_hash, low_id);
    }

    #[test]
    fn invalid_pow_digest_vector_is_not_accidentally_zero() {
        let digest = PowDigest::from_be_bytes([1; 32]);
        assert_ne!(digest.as_be_bytes(), &[0; 32]);
    }

    #[test]
    fn shorter_branch_with_more_work_reorganizes_supply_and_balances() {
        let mut config = PowGenesisConfigV2::local_regtest();
        config.pow.target_block_interval_seconds = 15;
        config.pow.asert_half_life_seconds = 15;
        let miner_a = Address::from_public_key(config.network, &[31; 32]);
        let miner_b = Address::from_public_key(config.network, &[32; 32]);
        let mut chain =
            ChainV2::initialize(MemoryStoreV2::default(), config.clone()).expect("initialize");
        let genesis = chain.metadata().expect("metadata").genesis_hash;

        let mut a_parent = genesis;
        let scheduled_targets =
            ["ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"; 4];
        for (height, timestamp) in [15_u64, 30, 45, 60].into_iter().enumerate() {
            let candidate = chain
                .prepare_candidate_on(a_parent, miner_a, Vec::new(), timestamp, height as u64)
                .expect("A candidate");
            assert_eq!(
                candidate.block().header.target.to_string(),
                scheduled_targets[height]
            );
            let solved = mine(candidate, &config);
            a_parent = solved.id().expect("A ID");
            chain.import_block(solved, timestamp).expect("import A");
        }
        let a_tip = chain.tip().expect("A tip");
        assert_eq!(a_tip.block.header.height, 4);
        assert_eq!(
            a_tip.state.account(miner_a).available,
            Amount::from_atoms(4 * 8 * crate::ATOMS_PER_AUR)
        );

        let mut b_parent = genesis;
        let mut winning_outcome = None;
        let fast_targets = [
            "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            "86117fffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            "46347fffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        ];
        for (index, timestamp) in [1_u64, 2, 3].into_iter().enumerate() {
            let candidate = chain
                .prepare_candidate_on(b_parent, miner_b, Vec::new(), timestamp, 100 + index as u64)
                .expect("B candidate");
            assert_eq!(
                candidate.block().header.target.to_string(),
                fast_targets[index]
            );
            let solved = mine(candidate, &config);
            b_parent = solved.id().expect("B ID");
            let outcome = chain.import_block(solved, 60).expect("import B");
            if outcome.became_canonical_tip {
                winning_outcome = Some(outcome);
            }
        }

        let winning = winning_outcome.expect("harder shorter branch must win");
        let plan = winning.reorg.expect("real reorg plan");
        assert_eq!(plan.disconnect.len(), 4);
        assert_eq!(plan.connect.len(), 3);
        let tip = chain.tip().expect("B tip");
        assert_eq!(tip.block.header.height, 3, "winning branch is shorter");
        assert!(tip.cumulative_work > a_tip.cumulative_work);
        assert_eq!(tip.state.account(miner_a).available, Amount::ZERO);
        assert_eq!(
            tip.state.account(miner_b).available,
            Amount::from_atoms(3 * 8 * crate::ATOMS_PER_AUR)
        );
        assert_eq!(
            tip.state.total_supply(),
            Amount::from_atoms(3 * 8 * crate::ATOMS_PER_AUR)
        );

        let store = chain.into_store();
        let reopened = ChainV2::open_existing(store, config).expect("reopen all branches");
        assert_eq!(
            reopened.tip().expect("tip").block.id().expect("ID"),
            b_parent
        );
    }

    #[test]
    fn genuine_argon2_result_above_required_target_is_rejected_without_mutation() {
        let mut config = PowGenesisConfigV2::local_regtest();
        config.pow.initial_target = Target256::ONE;
        config.pow.pow_limit = Target256::ONE;
        config.pow.minimum_target = Target256::ONE;
        let miner = Address::from_public_key(config.network, &[41; 32]);
        let mut chain = ChainV2::initialize(MemoryStoreV2::default(), config.clone())
            .expect("initialize hard regtest");
        let genesis = chain.metadata().expect("metadata").genesis_hash;
        let candidate = chain
            .prepare_candidate(miner, Vec::new(), 1, 0)
            .expect("candidate");
        let (candidate, _) = candidate.into_mining_parts().expect("sealed candidate");
        assert!(matches!(
            chain.import_block(candidate, 1),
            Err(Error::InvalidProofOfWork)
        ));
        assert_eq!(chain.metadata().expect("metadata").tip_hash, genesis);
        assert_eq!(chain.store.record_index_v2().expect("index").len(), 1);
    }

    #[test]
    fn reopening_rejects_canonical_index_pointing_at_a_non_tip_sibling() {
        let (config, mut chain, miner_key, _) = setup();
        let miner = Address::from_public_key(config.network, &miner_key.verifying_key().to_bytes());
        let genesis = chain.metadata().expect("metadata").genesis_hash;
        let first = mine(
            chain
                .prepare_candidate_on(genesis, miner, Vec::new(), 1, 1)
                .expect("first sibling"),
            &config,
        );
        let first_id = first.id().expect("first ID");
        chain.import_block(first, 1).expect("import first");
        let second = mine(
            chain
                .prepare_candidate_on(genesis, miner, Vec::new(), 1, 2)
                .expect("second sibling"),
            &config,
        );
        let second_id = second.id().expect("second ID");
        chain.import_block(second, 1).expect("import second");
        let tip = chain.metadata().expect("metadata").tip_hash;
        let non_tip = if tip == first_id { second_id } else { first_id };
        let mut store = chain.into_store();
        store.corrupt_canonical_for_test(1, non_tip);

        assert!(matches!(
            ChainV2::open_existing(store, config),
            Err(Error::CorruptStore(_))
        ));
    }

    #[test]
    fn reopening_rejects_sparse_stale_canonical_heights() {
        let (config, mut chain, miner_key, _) = setup();
        let miner = Address::from_public_key(config.network, &miner_key.verifying_key().to_bytes());
        let block = mine(
            chain
                .prepare_candidate(miner, Vec::new(), 1, 0)
                .expect("candidate"),
            &config,
        );
        chain.import_block(block, 1).expect("import");
        let tip = chain.metadata().expect("metadata").tip_hash;
        let mut store = chain.into_store();
        store.corrupt_canonical_for_test(9, tip);

        assert!(matches!(
            ChainV2::open_existing(store, config),
            Err(Error::CorruptStore(_))
        ));
    }

    #[test]
    fn confirmations_disappear_when_a_stronger_branch_abandons_the_transfer() {
        let mut config = PowGenesisConfigV2::local_regtest();
        config.pow.target_block_interval_seconds = 15;
        config.pow.asert_half_life_seconds = 15;
        let sender_key = SigningKey::from_bytes(&[61; 32]);
        let recipient_key = SigningKey::from_bytes(&[62; 32]);
        let sender =
            Address::from_public_key(config.network, &sender_key.verifying_key().to_bytes());
        let recipient =
            Address::from_public_key(config.network, &recipient_key.verifying_key().to_bytes());
        let competing_miner = Address::from_public_key(config.network, &[63; 32]);
        let mut chain =
            ChainV2::initialize(MemoryStoreV2::default(), config.clone()).expect("initialize");
        let genesis = chain.metadata().expect("metadata").genesis_hash;

        let a1 = mine(
            chain
                .prepare_candidate_on(genesis, sender, Vec::new(), 15, 0)
                .expect("A1"),
            &config,
        );
        let a1_id = a1.id().expect("A1 ID");
        chain.import_block(a1, 30).expect("import A1");
        let transfer = SignedTransferV2::sign(
            TransactionBodyV2 {
                version: TRANSACTION_VERSION_V2,
                network: config.network,
                chain_id_hash: config.consensus_identity_hash().expect("identity"),
                sender,
                recipient,
                amount: Amount::from_atoms(10_000),
                fee: config.limits.minimum_fee,
                nonce: 1,
                valid_until_height: 100,
            },
            &sender_key,
        )
        .expect("sign");
        let intent_id = transfer.intent_id().expect("intent");
        let a2 = mine(
            chain
                .prepare_candidate_on(a1_id, sender, vec![transfer], 30, 1)
                .expect("A2"),
            &config,
        );
        chain.import_block(a2, 30).expect("import A2");
        assert_eq!(
            chain
                .confirmations(intent_id)
                .expect("confirmation lookup")
                .expect("confirmed")
                .confirmations,
            1
        );

        let b1 = mine(
            chain
                .prepare_candidate_on(genesis, competing_miner, Vec::new(), 1, 2)
                .expect("B1"),
            &config,
        );
        let b1_id = b1.id().expect("B1 ID");
        chain.import_block(b1, 30).expect("import B1");
        let b2 = mine(
            chain
                .prepare_candidate_on(b1_id, competing_miner, Vec::new(), 2, 3)
                .expect("B2"),
            &config,
        );
        let outcome = chain.import_block(b2, 30).expect("import B2");
        assert!(outcome.became_canonical_tip);
        assert!(outcome.reorg.expect("reorg").disconnect.len() >= 2);
        assert_eq!(chain.confirmations(intent_id).expect("lookup"), None);
        assert_eq!(
            chain.tip().expect("tip").state.account(recipient).available,
            Amount::ZERO
        );
    }
}
