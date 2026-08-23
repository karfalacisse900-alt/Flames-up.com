use crate::{
    BlockV2, BlockWork256, CumulativeWork512, Error, Hash256, LedgerStateV2, Network, Result,
};
use borsh::{BorshDeserialize, BorshSerialize};
use std::collections::BTreeMap;

/// PoW-v2 database schema. It is never compatible with Phase-1 manual records.
pub const POW_STORE_SCHEMA_VERSION: u32 = 2;

/// One independently validated `PoW` block and its complete branch-local post-state.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct BlockRecordV2 {
    pub block: BlockV2,
    pub state: LedgerStateV2,
    pub block_work: BlockWork256,
    pub cumulative_work: CumulativeWork512,
}

/// Durable chain identity and canonical pointers for `PoW` v2.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct StoreMetadataV2 {
    pub schema_version: u32,
    pub consensus_spec_hash: Hash256,
    pub genesis_hash: Hash256,
    pub tip_hash: Hash256,
    pub network: Network,
    pub chain_id_hash: Hash256,
}

/// Exact disconnect/connect order for an atomic canonical branch switch.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct ReorgPlanV2 {
    pub old_tip: Hash256,
    pub new_tip: Hash256,
    pub common_ancestor: Hash256,
    /// Old tip toward (but excluding) the common ancestor.
    pub disconnect: Vec<Hash256>,
    /// Child of the common ancestor through the new tip.
    pub connect: Vec<Hash256>,
}

impl ReorgPlanV2 {
    /// True only for a direct canonical extension with no disconnected block.
    #[must_use]
    pub fn is_extension(&self) -> bool {
        self.disconnect.is_empty()
            && self.common_ancestor == self.old_tip
            && self.connect.as_slice() == [self.new_tip]
    }
}

/// Durable storage boundary for v2 blocks, branches, state snapshots, and canonical indexes.
pub trait ChainStoreV2 {
    fn metadata_v2(&self) -> Result<Option<StoreMetadataV2>>;
    fn record_index_v2(&self) -> Result<Vec<(u64, Hash256)>>;
    fn record_v2(&self, hash: Hash256) -> Result<Option<BlockRecordV2>>;
    /// Returns every persisted canonical height mapping so audits can reject sparse stale keys.
    fn canonical_index_v2(&self) -> Result<Vec<(u64, Hash256)>>;
    fn canonical_hash_v2(&self, height: u64) -> Result<Option<Hash256>>;
    fn initialize_v2(&mut self, metadata: &StoreMetadataV2, genesis: &BlockRecordV2) -> Result<()>;
    /// Atomically stores the block and, when supplied, applies the complete canonical reorg.
    fn commit_block_v2(
        &mut self,
        record: &BlockRecordV2,
        reorg: Option<&ReorgPlanV2>,
    ) -> Result<()>;
}

/// In-memory v2 store used by deterministic consensus and reorganization tests.
#[derive(Clone, Debug, Default)]
pub struct MemoryStoreV2 {
    metadata: Option<StoreMetadataV2>,
    records: BTreeMap<Hash256, BlockRecordV2>,
    canonical: BTreeMap<u64, Hash256>,
}

#[cfg(test)]
impl MemoryStoreV2 {
    pub(crate) fn corrupt_canonical_for_test(&mut self, height: u64, hash: Hash256) {
        self.canonical.insert(height, hash);
    }
}

impl ChainStoreV2 for MemoryStoreV2 {
    fn metadata_v2(&self) -> Result<Option<StoreMetadataV2>> {
        Ok(self.metadata.clone())
    }

    fn record_index_v2(&self) -> Result<Vec<(u64, Hash256)>> {
        let mut index = self
            .records
            .iter()
            .map(|(hash, record)| (record.block.header.height, *hash))
            .collect::<Vec<_>>();
        index.sort_unstable();
        Ok(index)
    }

    fn record_v2(&self, hash: Hash256) -> Result<Option<BlockRecordV2>> {
        Ok(self.records.get(&hash).cloned())
    }

    fn canonical_index_v2(&self) -> Result<Vec<(u64, Hash256)>> {
        Ok(self
            .canonical
            .iter()
            .map(|(height, hash)| (*height, *hash))
            .collect())
    }

    fn canonical_hash_v2(&self, height: u64) -> Result<Option<Hash256>> {
        Ok(self.canonical.get(&height).copied())
    }

    fn initialize_v2(&mut self, metadata: &StoreMetadataV2, genesis: &BlockRecordV2) -> Result<()> {
        if self.metadata.is_some() || !self.records.is_empty() || !self.canonical.is_empty() {
            return Err(Error::Storage(
                "PoW v2 initialization requires an empty store".into(),
            ));
        }
        if metadata.schema_version != POW_STORE_SCHEMA_VERSION
            || genesis.block.header.height != 0
            || genesis.block.id()? != metadata.genesis_hash
            || metadata.tip_hash != metadata.genesis_hash
            || genesis.block_work != BlockWork256::ZERO
            || genesis.cumulative_work != CumulativeWork512::ZERO
        {
            return Err(Error::Storage(
                "PoW v2 genesis record and metadata are inconsistent".into(),
            ));
        }
        self.records.insert(metadata.genesis_hash, genesis.clone());
        self.canonical.insert(0, metadata.genesis_hash);
        self.metadata = Some(metadata.clone());
        Ok(())
    }

    fn commit_block_v2(
        &mut self,
        record: &BlockRecordV2,
        reorg: Option<&ReorgPlanV2>,
    ) -> Result<()> {
        let hash = record.block.id()?;
        if self.records.contains_key(&hash) {
            return Err(Error::DuplicateBlock(hash));
        }
        let current_metadata = self
            .metadata
            .clone()
            .ok_or_else(|| Error::Storage("PoW v2 store is not initialized".into()))?;

        // Validate against clones first so every failure leaves all store state unchanged.
        let mut next_records = self.records.clone();
        let mut next_canonical = self.canonical.clone();
        let mut next_metadata = current_metadata.clone();
        next_records.insert(hash, record.clone());

        if let Some(plan) = reorg {
            validate_reorg_plan(
                &current_metadata,
                &next_records,
                &next_canonical,
                record,
                plan,
            )?;
            let ancestor_height = next_records
                .get(&plan.common_ancestor)
                .ok_or_else(|| Error::CorruptStore("reorg ancestor is missing".into()))?
                .block
                .header
                .height;
            next_canonical.retain(|height, _| *height <= ancestor_height);
            for connected_hash in &plan.connect {
                let connected = next_records.get(connected_hash).ok_or_else(|| {
                    Error::CorruptStore(format!("reorg connect block {connected_hash} is missing"))
                })?;
                next_canonical.insert(connected.block.header.height, *connected_hash);
            }
            next_metadata.tip_hash = plan.new_tip;
        }

        self.records = next_records;
        self.canonical = next_canonical;
        self.metadata = Some(next_metadata);
        Ok(())
    }
}

fn validate_reorg_plan(
    metadata: &StoreMetadataV2,
    records: &BTreeMap<Hash256, BlockRecordV2>,
    canonical: &BTreeMap<u64, Hash256>,
    new_record: &BlockRecordV2,
    plan: &ReorgPlanV2,
) -> Result<()> {
    let new_hash = new_record.block.id()?;
    if plan.old_tip != metadata.tip_hash
        || plan.new_tip != new_hash
        || plan.connect.last().copied() != Some(new_hash)
    {
        return Err(Error::Storage(
            "reorg plan does not connect the current and candidate tips".into(),
        ));
    }
    let ancestor = records
        .get(&plan.common_ancestor)
        .ok_or_else(|| Error::CorruptStore("reorg common ancestor is missing".into()))?;
    if canonical.get(&ancestor.block.header.height) != Some(&plan.common_ancestor) {
        return Err(Error::CorruptStore(
            "reorg common ancestor is not canonical".into(),
        ));
    }

    let mut expected_child = plan.old_tip;
    for disconnected_hash in &plan.disconnect {
        if *disconnected_hash != expected_child {
            return Err(Error::CorruptStore(
                "disconnect order does not start at the old tip".into(),
            ));
        }
        let disconnected = records.get(disconnected_hash).ok_or_else(|| {
            Error::CorruptStore(format!("disconnect block {disconnected_hash} is missing"))
        })?;
        if canonical.get(&disconnected.block.header.height) != Some(disconnected_hash) {
            return Err(Error::CorruptStore(
                "disconnect plan references a noncanonical block".into(),
            ));
        }
        expected_child = disconnected.block.header.parent_block_id;
    }
    if expected_child != plan.common_ancestor {
        return Err(Error::CorruptStore(
            "disconnect order does not end at the common ancestor".into(),
        ));
    }

    let mut expected_parent = plan.common_ancestor;
    let mut expected_height = ancestor.block.header.height;
    for connected_hash in &plan.connect {
        let connected = records.get(connected_hash).ok_or_else(|| {
            Error::CorruptStore(format!("connect block {connected_hash} is missing"))
        })?;
        expected_height = expected_height
            .checked_add(1)
            .ok_or(Error::HeightExhausted)?;
        if connected.block.header.parent_block_id != expected_parent
            || connected.block.header.height != expected_height
        {
            return Err(Error::CorruptStore(
                "connect order is not a contiguous child path".into(),
            ));
        }
        expected_parent = *connected_hash;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    // Store attack tests are otherwise exercised through ChainV2, where valid PoW fixtures exist.
    #[test]
    fn extension_helper_rejects_internally_inconsistent_short_plans() {
        let old_tip = Hash256::from_bytes([1; 32]);
        let new_tip = Hash256::from_bytes([2; 32]);
        let valid = ReorgPlanV2 {
            old_tip,
            new_tip,
            common_ancestor: old_tip,
            disconnect: Vec::new(),
            connect: vec![new_tip],
        };
        assert!(valid.is_extension());
        assert!(!ReorgPlanV2 {
            common_ancestor: Hash256::ZERO,
            ..valid.clone()
        }
        .is_extension());
        assert!(!ReorgPlanV2 {
            connect: vec![Hash256::ZERO],
            ..valid
        }
        .is_extension());
    }
}
