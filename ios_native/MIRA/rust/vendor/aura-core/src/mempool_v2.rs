//! Validated, bounded transaction staging for Aura `PoW` Devnet v2.

use crate::{Address, Error, Hash256, LedgerStateV2, PowGenesisConfigV2, SignedTransferV2};
use std::{
    cmp::Ordering,
    collections::{BTreeMap, BTreeSet, BinaryHeap},
};
use thiserror::Error;

/// Hard implementation ceilings for operator-configured mempool resources.
const MAX_MEMPOOL_TRANSACTIONS_V2: usize = 1_000_000;
const MAX_MEMPOOL_BYTES_V2: usize = 1024 * 1024 * 1024;

/// Local resource limits. These do not change consensus validity.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MempoolLimitsV2 {
    pub maximum_transactions: usize,
    pub maximum_bytes: usize,
}

impl Default for MempoolLimitsV2 {
    fn default() -> Self {
        Self {
            maximum_transactions: 50_000,
            maximum_bytes: 64 * 1024 * 1024,
        }
    }
}

/// A successfully admitted transaction and any lower-priority tails evicted for space.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AdmissionOutcomeV2 {
    pub intent_id: Hash256,
    pub evicted: Vec<Hash256>,
}

/// Result of rebuilding the pool after a canonical extension or reorganization.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ReconcileOutcomeV2 {
    pub retained: usize,
    pub reintroduced: Vec<Hash256>,
    pub removed: Vec<Hash256>,
    pub rejected: Vec<(Hash256, String)>,
}

/// Mempool-policy failures. Consensus failures retain their exact core error.
#[derive(Debug, Error)]
pub enum MempoolErrorV2 {
    #[error(transparent)]
    Consensus(#[from] Error),
    #[error("mempool limits are invalid")]
    InvalidLimits,
    #[error("transaction {0} is already in the mempool")]
    Duplicate(Hash256),
    #[error("sender {sender} already has a different transaction at nonce {nonce}")]
    ConflictingNonce { sender: Address, nonce: u64 },
    #[error("transaction nonce {actual} is already committed; next canonical nonce is {expected}")]
    NonceAlreadyCommitted { expected: u64, actual: u64 },
    #[error(
        "transaction nonce {actual} creates a mempool gap; next admissible nonce is {expected}"
    )]
    NonceGap { expected: u64, actual: u64 },
    #[error("pending debits exceed the canonical balance of {0}")]
    PendingOverspend(Address),
    #[error("transaction priority is too low for the configured mempool limits")]
    PriorityTooLow,
    #[error("mempool accounting overflow")]
    AccountingOverflow,
}

/// One immutable validated entry.
#[derive(Clone, Debug, PartialEq, Eq)]
struct MempoolEntryV2 {
    transfer: SignedTransferV2,
    intent_id: Hash256,
    encoded_size: usize,
}

/// A bounded mempool tied to one exact genesis configuration.
///
/// Incoming transfers are never treated as spendable until they are in canonical state. Pending
/// transactions from one sender must therefore form a contiguous nonce chain funded entirely by
/// that sender's canonical balance.
#[derive(Clone, Debug)]
pub struct MempoolV2 {
    config: PowGenesisConfigV2,
    limits: MempoolLimitsV2,
    entries: BTreeMap<Hash256, MempoolEntryV2>,
    sender_nonces: BTreeMap<(Address, u64), Hash256>,
    total_bytes: usize,
}

impl MempoolV2 {
    /// Creates an empty pool after validating both consensus identity and local resource limits.
    pub fn new(
        config: PowGenesisConfigV2,
        limits: MempoolLimitsV2,
    ) -> Result<Self, MempoolErrorV2> {
        config.validate()?;
        if limits.maximum_transactions == 0
            || limits.maximum_transactions > MAX_MEMPOOL_TRANSACTIONS_V2
            || limits.maximum_bytes == 0
            || limits.maximum_bytes > MAX_MEMPOOL_BYTES_V2
        {
            return Err(MempoolErrorV2::InvalidLimits);
        }
        Ok(Self {
            config,
            limits,
            entries: BTreeMap::new(),
            sender_nonces: BTreeMap::new(),
            total_bytes: 0,
        })
    }

    /// Number of currently staged transfers.
    #[must_use]
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// Whether no transfers are staged.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// Exact canonical bytes currently charged against the local pool limit.
    #[must_use]
    pub const fn total_bytes(&self) -> usize {
        self.total_bytes
    }

    /// Returns a staged transfer by its signature-independent intent ID.
    #[must_use]
    pub fn get(&self, intent_id: Hash256) -> Option<&SignedTransferV2> {
        self.entries.get(&intent_id).map(|entry| &entry.transfer)
    }

    /// Returns all intent IDs in stable byte order.
    #[must_use]
    pub fn intent_ids(&self) -> Vec<Hash256> {
        self.entries.keys().copied().collect()
    }

    /// Verifies and atomically admits a transfer against the canonical state.
    ///
    /// If the pool is full, only nonce-chain tails are eviction candidates. This guarantees that
    /// eviction cannot strand a higher-nonce descendant. Fee rate wins, then absolute fee, then
    /// lower intent ID; this is deterministic local policy and is not a consensus rule.
    pub fn admit(
        &mut self,
        transfer: SignedTransferV2,
        canonical_state: &LedgerStateV2,
        candidate_height: u64,
    ) -> Result<AdmissionOutcomeV2, MempoolErrorV2> {
        let mut next = self.clone();
        let intent_id = next.insert_checked(transfer, canonical_state, candidate_height)?;
        let mut evicted = Vec::new();
        while next.entries.len() > next.limits.maximum_transactions
            || next.total_bytes > next.limits.maximum_bytes
        {
            let victim = next
                .lowest_priority_tail()
                .ok_or(MempoolErrorV2::AccountingOverflow)?;
            next.remove_exact(victim)?;
            evicted.push(victim);
        }
        if !next.entries.contains_key(&intent_id) {
            return Err(MempoolErrorV2::PriorityTooLow);
        }
        *self = next;
        Ok(AdmissionOutcomeV2 { intent_id, evicted })
    }

    /// Selects a deterministic, state-valid block candidate while preserving sender nonce order.
    ///
    /// `maximum_bytes` covers transfer encodings only; the caller must reserve the header,
    /// transaction-count prefix, and coinbase bytes from the consensus block limit.
    #[must_use]
    pub fn select_for_block(
        &self,
        canonical_state: &LedgerStateV2,
        candidate_height: u64,
        maximum_transfers: usize,
        maximum_bytes: usize,
    ) -> Vec<SignedTransferV2> {
        if maximum_transfers == 0 || maximum_bytes == 0 {
            return Vec::new();
        }
        let mut state = canonical_state.clone();
        let mut heap = BinaryHeap::new();
        for ((sender, nonce), intent_id) in &self.sender_nonces {
            let Some(expected) = canonical_state.account(*sender).nonce.checked_add(1) else {
                continue;
            };
            if *nonce == expected {
                if let Some(entry) = self.entries.get(intent_id) {
                    heap.push(PriorityItemV2::from_entry(entry));
                }
            }
        }

        let mut selected = Vec::new();
        let mut selected_bytes = 0_usize;
        while let Some(item) = heap.pop() {
            if selected.len() >= maximum_transfers {
                break;
            }
            let Some(entry) = self.entries.get(&item.intent_id) else {
                continue;
            };
            let Some(next_size) = selected_bytes.checked_add(entry.encoded_size) else {
                continue;
            };
            if next_size > maximum_bytes {
                // Descendants cannot be selected without this sender nonce.
                continue;
            }
            if state
                .apply_transfer_for_candidate(&entry.transfer, &self.config, candidate_height)
                .is_err()
            {
                continue;
            }
            selected_bytes = next_size;
            selected.push(entry.transfer.clone());

            if let Some(next_nonce) = entry.transfer.body.nonce.checked_add(1) {
                if let Some(next_id) = self
                    .sender_nonces
                    .get(&(entry.transfer.body.sender, next_nonce))
                {
                    if let Some(next_entry) = self.entries.get(next_id) {
                        heap.push(PriorityItemV2::from_entry(next_entry));
                    }
                }
            }
        }
        selected
    }

    /// Rebuilds the pool against new canonical state and returns eligible abandoned transfers.
    ///
    /// `confirmed` must contain every transfer intent on the newly connected canonical path.
    /// `abandoned` should contain transfers from disconnected blocks. Coinbase transactions are
    /// deliberately not accepted by this API.
    pub fn reconcile_after_chain_change(
        &mut self,
        canonical_state: &LedgerStateV2,
        candidate_height: u64,
        confirmed: &BTreeSet<Hash256>,
        abandoned: Vec<SignedTransferV2>,
    ) -> ReconcileOutcomeV2 {
        let old_ids: BTreeSet<_> = self.entries.keys().copied().collect();
        let abandoned_ids: BTreeSet<_> = abandoned
            .iter()
            .filter_map(|transfer| transfer.intent_id().ok())
            .collect();
        let mut candidates: BTreeMap<Hash256, SignedTransferV2> = self
            .entries
            .values()
            .map(|entry| (entry.intent_id, entry.transfer.clone()))
            .collect();
        for transfer in abandoned {
            if let Ok(intent_id) = transfer.intent_id() {
                candidates.entry(intent_id).or_insert(transfer);
            }
        }

        let mut ordered: Vec<_> = candidates.into_iter().collect();
        ordered.sort_by(|(left_id, left), (right_id, right)| {
            left.body
                .sender
                .cmp(&right.body.sender)
                .then_with(|| left.body.nonce.cmp(&right.body.nonce))
                .then_with(|| left_id.cmp(right_id))
        });

        let mut rebuilt = Self {
            config: self.config.clone(),
            limits: self.limits,
            entries: BTreeMap::new(),
            sender_nonces: BTreeMap::new(),
            total_bytes: 0,
        };
        let mut rejected = Vec::new();
        for (intent_id, transfer) in ordered {
            if confirmed.contains(&intent_id) {
                continue;
            }
            if let Err(error) = rebuilt.admit(transfer, canonical_state, candidate_height) {
                rejected.push((intent_id, error.to_string()));
            }
        }

        let new_ids: BTreeSet<_> = rebuilt.entries.keys().copied().collect();
        let reintroduced = new_ids
            .difference(&old_ids)
            .filter(|intent_id| abandoned_ids.contains(intent_id))
            .copied()
            .collect();
        let removed = old_ids.difference(&new_ids).copied().collect();
        let retained = rebuilt.entries.len();
        *self = rebuilt;
        ReconcileOutcomeV2 {
            retained,
            reintroduced,
            removed,
            rejected,
        }
    }

    fn insert_checked(
        &mut self,
        transfer: SignedTransferV2,
        canonical_state: &LedgerStateV2,
        candidate_height: u64,
    ) -> Result<Hash256, MempoolErrorV2> {
        transfer.verify(
            self.config.network,
            self.config.consensus_identity_hash()?,
            self.config.limits.minimum_fee,
            candidate_height,
            self.config.limits.maximum_transaction_bytes,
        )?;
        let intent_id = transfer.intent_id()?;
        if self.entries.contains_key(&intent_id) {
            return Err(MempoolErrorV2::Duplicate(intent_id));
        }
        let sender = transfer.body.sender;
        let nonce = transfer.body.nonce;
        if self.sender_nonces.contains_key(&(sender, nonce)) {
            return Err(MempoolErrorV2::ConflictingNonce { sender, nonce });
        }

        let account = canonical_state.account(sender);
        let canonical_next = account
            .nonce
            .checked_add(1)
            .ok_or(MempoolErrorV2::AccountingOverflow)?;
        if nonce < canonical_next {
            return Err(MempoolErrorV2::NonceAlreadyCommitted {
                expected: canonical_next,
                actual: nonce,
            });
        }
        let pending_count = self
            .sender_nonces
            .range((sender, 0)..=(sender, u64::MAX))
            .count();
        let pending_count =
            u64::try_from(pending_count).map_err(|_| MempoolErrorV2::AccountingOverflow)?;
        let expected = canonical_next
            .checked_add(pending_count)
            .ok_or(MempoolErrorV2::AccountingOverflow)?;
        if nonce != expected {
            return Err(MempoolErrorV2::NonceGap {
                expected,
                actual: nonce,
            });
        }

        let mut pending_debit = 0_u128;
        for ((pending_sender, _), pending_id) in
            self.sender_nonces.range((sender, 0)..=(sender, u64::MAX))
        {
            debug_assert_eq!(*pending_sender, sender);
            let entry = self
                .entries
                .get(pending_id)
                .ok_or(MempoolErrorV2::AccountingOverflow)?;
            pending_debit = pending_debit
                .checked_add(u128::from(entry.transfer.body.amount.atoms()))
                .and_then(|value| value.checked_add(u128::from(entry.transfer.body.fee.atoms())))
                .ok_or(MempoolErrorV2::AccountingOverflow)?;
        }
        pending_debit = pending_debit
            .checked_add(u128::from(transfer.body.amount.atoms()))
            .and_then(|value| value.checked_add(u128::from(transfer.body.fee.atoms())))
            .ok_or(MempoolErrorV2::AccountingOverflow)?;
        if pending_debit > u128::from(account.available.atoms()) {
            return Err(MempoolErrorV2::PendingOverspend(sender));
        }

        let encoded_size = transfer
            .encode()?
            .len()
            .checked_add(1)
            .ok_or(MempoolErrorV2::AccountingOverflow)?;
        self.total_bytes = self
            .total_bytes
            .checked_add(encoded_size)
            .ok_or(MempoolErrorV2::AccountingOverflow)?;
        self.sender_nonces.insert((sender, nonce), intent_id);
        self.entries.insert(
            intent_id,
            MempoolEntryV2 {
                transfer,
                intent_id,
                encoded_size,
            },
        );
        Ok(intent_id)
    }

    fn lowest_priority_tail(&self) -> Option<Hash256> {
        self.entries
            .values()
            .filter(|entry| {
                entry
                    .transfer
                    .body
                    .nonce
                    .checked_add(1)
                    .is_none_or(|next_nonce| {
                        !self
                            .sender_nonces
                            .contains_key(&(entry.transfer.body.sender, next_nonce))
                    })
            })
            .min_by(|left, right| compare_priority(left, right))
            .map(|entry| entry.intent_id)
    }

    fn remove_exact(&mut self, intent_id: Hash256) -> Result<(), MempoolErrorV2> {
        let entry = self
            .entries
            .remove(&intent_id)
            .ok_or(MempoolErrorV2::AccountingOverflow)?;
        self.sender_nonces
            .remove(&(entry.transfer.body.sender, entry.transfer.body.nonce));
        self.total_bytes = self
            .total_bytes
            .checked_sub(entry.encoded_size)
            .ok_or(MempoolErrorV2::AccountingOverflow)?;
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct PriorityItemV2 {
    intent_id: Hash256,
    fee_atoms: u64,
    encoded_size: usize,
}

impl PriorityItemV2 {
    fn from_entry(entry: &MempoolEntryV2) -> Self {
        Self {
            intent_id: entry.intent_id,
            fee_atoms: entry.transfer.body.fee.atoms(),
            encoded_size: entry.encoded_size,
        }
    }
}

impl Ord for PriorityItemV2 {
    fn cmp(&self, other: &Self) -> Ordering {
        compare_fee_priority(
            self.fee_atoms,
            self.encoded_size,
            self.intent_id,
            other.fee_atoms,
            other.encoded_size,
            other.intent_id,
        )
    }
}

impl PartialOrd for PriorityItemV2 {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

fn compare_priority(left: &MempoolEntryV2, right: &MempoolEntryV2) -> Ordering {
    compare_fee_priority(
        left.transfer.body.fee.atoms(),
        left.encoded_size,
        left.intent_id,
        right.transfer.body.fee.atoms(),
        right.encoded_size,
        right.intent_id,
    )
}

/// Greater means higher priority. A lower intent ID wins the final tie.
fn compare_fee_priority(
    left_fee: u64,
    left_size: usize,
    left_id: Hash256,
    right_fee: u64,
    right_size: usize,
    right_id: Hash256,
) -> Ordering {
    let left_rate = u128::from(left_fee) * right_size as u128;
    let right_rate = u128::from(right_fee) * left_size as u128;
    left_rate
        .cmp(&right_rate)
        .then_with(|| left_fee.cmp(&right_fee))
        .then_with(|| right_id.cmp(&left_id))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        Amount, CoinbaseV2, Network, TransactionBodyV2, TransactionV2, POW_PROTOCOL_VERSION,
        TRANSACTION_VERSION_V2,
    };
    use ed25519_dalek::SigningKey;

    struct Fixture {
        config: PowGenesisConfigV2,
        state: LedgerStateV2,
        sender_a: SigningKey,
        sender_b: SigningKey,
        recipient: Address,
    }

    fn fixture() -> Fixture {
        let sender_a = SigningKey::from_bytes(&[51; 32]);
        let sender_b = SigningKey::from_bytes(&[52; 32]);
        let recipient_key = SigningKey::from_bytes(&[53; 32]);
        let mut config = PowGenesisConfigV2::local_regtest();
        config.economics.block_subsidy = Amount::from_atoms(1_000_000);
        let mut state = LedgerStateV2::from_genesis(&config).expect("zero-issuance genesis");
        for (height, key) in [(1_u64, &sender_a), (2, &sender_b)] {
            let recipient =
                Address::from_public_key(Network::Devnet, &key.verifying_key().to_bytes());
            let payout = config
                .subsidy(state.total_supply(), height)
                .expect("subsidy");
            state = LedgerStateV2::execute_block(
                &state,
                &[TransactionV2::Coinbase(CoinbaseV2 {
                    version: POW_PROTOCOL_VERSION,
                    network: config.network,
                    chain_id_hash: config.consensus_identity_hash().expect("identity"),
                    height,
                    recipient,
                    payout,
                    extra_nonce: 0,
                })],
                &config,
                height,
            )
            .expect("fund sender through consensus coinbase")
            .state;
        }
        Fixture {
            config,
            state,
            sender_a,
            sender_b,
            recipient: Address::from_public_key(
                Network::Devnet,
                &recipient_key.verifying_key().to_bytes(),
            ),
        }
    }

    fn signed(
        config: &PowGenesisConfigV2,
        key: &SigningKey,
        recipient: Address,
        amount: u64,
        fee: u64,
        nonce: u64,
        expiry: u64,
    ) -> SignedTransferV2 {
        SignedTransferV2::sign(
            TransactionBodyV2 {
                version: TRANSACTION_VERSION_V2,
                network: config.network,
                chain_id_hash: config.consensus_identity_hash().expect("identity"),
                sender: Address::from_public_key(config.network, &key.verifying_key().to_bytes()),
                recipient,
                amount: Amount::from_atoms(amount),
                fee: Amount::from_atoms(fee),
                nonce,
                valid_until_height: expiry,
            },
            key,
        )
        .expect("sign")
    }

    #[test]
    fn admits_only_signed_contiguous_funded_transactions() {
        let fixture = fixture();
        let mut pool =
            MempoolV2::new(fixture.config.clone(), MempoolLimitsV2::default()).expect("pool");
        let first = signed(
            &fixture.config,
            &fixture.sender_a,
            fixture.recipient,
            100,
            1_000,
            1,
            100,
        );
        pool.admit(first.clone(), &fixture.state, 1)
            .expect("admit first");
        assert!(matches!(
            pool.admit(first, &fixture.state, 1),
            Err(MempoolErrorV2::Duplicate(_))
        ));
        let gap = signed(
            &fixture.config,
            &fixture.sender_a,
            fixture.recipient,
            100,
            1_000,
            3,
            100,
        );
        assert!(matches!(
            pool.admit(gap, &fixture.state, 1),
            Err(MempoolErrorV2::NonceGap {
                expected: 2,
                actual: 3
            })
        ));
        let second = signed(
            &fixture.config,
            &fixture.sender_a,
            fixture.recipient,
            100,
            1_000,
            2,
            100,
        );
        pool.admit(second, &fixture.state, 1).expect("admit second");
        assert_eq!(pool.len(), 2);
    }

    #[test]
    fn invalid_signature_chain_fee_expiry_and_overspend_are_rejected_atomically() {
        let fixture = fixture();
        let mut pool =
            MempoolV2::new(fixture.config.clone(), MempoolLimitsV2::default()).expect("pool");
        let mut invalid = signed(
            &fixture.config,
            &fixture.sender_a,
            fixture.recipient,
            100,
            1_000,
            1,
            100,
        );
        invalid.signature[0] ^= 1;
        assert!(matches!(
            pool.admit(invalid, &fixture.state, 1),
            Err(MempoolErrorV2::Consensus(Error::InvalidSignature))
        ));

        let low_fee = signed(
            &fixture.config,
            &fixture.sender_a,
            fixture.recipient,
            100,
            999,
            1,
            100,
        );
        assert!(matches!(
            pool.admit(low_fee, &fixture.state, 1),
            Err(MempoolErrorV2::Consensus(Error::FeeTooLow { .. }))
        ));
        let expired = signed(
            &fixture.config,
            &fixture.sender_a,
            fixture.recipient,
            100,
            1_000,
            1,
            1,
        );
        assert!(matches!(
            pool.admit(expired, &fixture.state, 2),
            Err(MempoolErrorV2::Consensus(Error::TransactionExpired { .. }))
        ));
        let overspend = signed(
            &fixture.config,
            &fixture.sender_a,
            fixture.recipient,
            1_000_000,
            1_000,
            1,
            100,
        );
        assert!(matches!(
            pool.admit(overspend, &fixture.state, 1),
            Err(MempoolErrorV2::PendingOverspend(_))
        ));
        assert!(pool.is_empty());
    }

    #[test]
    fn conflicting_sender_nonce_is_rejected() {
        let fixture = fixture();
        let mut pool =
            MempoolV2::new(fixture.config.clone(), MempoolLimitsV2::default()).expect("pool");
        let first = signed(
            &fixture.config,
            &fixture.sender_a,
            fixture.recipient,
            100,
            1_000,
            1,
            100,
        );
        let conflict = signed(
            &fixture.config,
            &fixture.sender_a,
            fixture.recipient,
            101,
            2_000,
            1,
            100,
        );
        pool.admit(first, &fixture.state, 1).expect("first");
        assert!(matches!(
            pool.admit(conflict, &fixture.state, 1),
            Err(MempoolErrorV2::ConflictingNonce { .. })
        ));
        assert_eq!(pool.len(), 1);
    }

    #[test]
    fn pending_debits_cannot_double_spend_canonical_balance() {
        let fixture = fixture();
        let mut pool =
            MempoolV2::new(fixture.config.clone(), MempoolLimitsV2::default()).expect("pool");
        let first = signed(
            &fixture.config,
            &fixture.sender_a,
            fixture.recipient,
            998_000,
            1_000,
            1,
            100,
        );
        pool.admit(first, &fixture.state, 1).expect("first");
        let second = signed(
            &fixture.config,
            &fixture.sender_a,
            fixture.recipient,
            1,
            1_000,
            2,
            100,
        );
        assert!(matches!(
            pool.admit(second, &fixture.state, 1),
            Err(MempoolErrorV2::PendingOverspend(_))
        ));
        assert_eq!(pool.len(), 1);
    }

    #[test]
    fn higher_fee_rate_evicts_only_a_nonce_tail() {
        let fixture = fixture();
        let one_tx_bytes = signed(
            &fixture.config,
            &fixture.sender_a,
            fixture.recipient,
            1,
            1_000,
            1,
            100,
        )
        .encode()
        .expect("encode")
        .len()
            + 1;
        let limits = MempoolLimitsV2 {
            maximum_transactions: 2,
            maximum_bytes: one_tx_bytes * 2,
        };
        let mut pool = MempoolV2::new(fixture.config.clone(), limits).expect("pool");
        let a1 = signed(
            &fixture.config,
            &fixture.sender_a,
            fixture.recipient,
            1,
            1_000,
            1,
            100,
        );
        let a2 = signed(
            &fixture.config,
            &fixture.sender_a,
            fixture.recipient,
            1,
            1_000,
            2,
            100,
        );
        let a1_id = a1.intent_id().expect("id");
        let a2_id = a2.intent_id().expect("id");
        pool.admit(a1, &fixture.state, 1).expect("a1");
        pool.admit(a2, &fixture.state, 1).expect("a2");
        let b1 = signed(
            &fixture.config,
            &fixture.sender_b,
            fixture.recipient,
            1,
            9_000,
            1,
            100,
        );
        let outcome = pool.admit(b1, &fixture.state, 1).expect("higher fee");
        assert_eq!(outcome.evicted, vec![a2_id]);
        assert!(pool.get(a1_id).is_some());
        assert!(pool.get(a2_id).is_none());
    }

    #[test]
    fn low_priority_new_tail_is_rejected_without_mutation() {
        let fixture = fixture();
        let limits = MempoolLimitsV2 {
            maximum_transactions: 1,
            maximum_bytes: 1_024,
        };
        let mut pool = MempoolV2::new(fixture.config.clone(), limits).expect("pool");
        let high = signed(
            &fixture.config,
            &fixture.sender_a,
            fixture.recipient,
            1,
            9_000,
            1,
            100,
        );
        let high_id = high.intent_id().expect("id");
        pool.admit(high, &fixture.state, 1).expect("high");
        let low = signed(
            &fixture.config,
            &fixture.sender_b,
            fixture.recipient,
            1,
            1_000,
            1,
            100,
        );
        assert!(matches!(
            pool.admit(low, &fixture.state, 1),
            Err(MempoolErrorV2::PriorityTooLow)
        ));
        assert_eq!(pool.intent_ids(), vec![high_id]);
    }

    #[test]
    fn candidate_selection_orders_fee_rate_and_preserves_nonce_dependencies() {
        let fixture = fixture();
        let mut pool =
            MempoolV2::new(fixture.config.clone(), MempoolLimitsV2::default()).expect("pool");
        let a1 = signed(
            &fixture.config,
            &fixture.sender_a,
            fixture.recipient,
            1,
            1_000,
            1,
            100,
        );
        let a2 = signed(
            &fixture.config,
            &fixture.sender_a,
            fixture.recipient,
            1,
            20_000,
            2,
            100,
        );
        let b1 = signed(
            &fixture.config,
            &fixture.sender_b,
            fixture.recipient,
            1,
            5_000,
            1,
            100,
        );
        for transfer in [a1.clone(), a2.clone(), b1.clone()] {
            pool.admit(transfer, &fixture.state, 1).expect("admit");
        }
        let selected = pool.select_for_block(&fixture.state, 1, 3, 10_000);
        let ids: Vec<_> = selected
            .iter()
            .map(|transfer| transfer.intent_id().expect("id"))
            .collect();
        assert_eq!(ids[0], b1.intent_id().expect("b1"));
        assert_eq!(ids[1], a1.intent_id().expect("a1"));
        assert_eq!(ids[2], a2.intent_id().expect("a2"));
    }

    #[test]
    fn confirmed_transactions_leave_and_abandoned_transactions_return() {
        let fixture = fixture();
        let mut pool =
            MempoolV2::new(fixture.config.clone(), MempoolLimitsV2::default()).expect("pool");
        let transfer = signed(
            &fixture.config,
            &fixture.sender_a,
            fixture.recipient,
            1,
            1_000,
            1,
            100,
        );
        let intent_id = transfer.intent_id().expect("id");
        pool.admit(transfer.clone(), &fixture.state, 1)
            .expect("admit");
        let report = pool.reconcile_after_chain_change(
            &fixture.state,
            1,
            &BTreeSet::from([intent_id]),
            Vec::new(),
        );
        assert!(pool.is_empty());
        assert_eq!(report.removed, vec![intent_id]);

        let report =
            pool.reconcile_after_chain_change(&fixture.state, 1, &BTreeSet::new(), vec![transfer]);
        assert_eq!(report.reintroduced, vec![intent_id]);
        assert!(pool.get(intent_id).is_some());
    }

    #[test]
    fn reorg_rebuild_drops_now_invalid_replay_and_keeps_next_nonce() {
        let fixture = fixture();
        let first = signed(
            &fixture.config,
            &fixture.sender_a,
            fixture.recipient,
            1,
            1_000,
            1,
            100,
        );
        let second = signed(
            &fixture.config,
            &fixture.sender_a,
            fixture.recipient,
            1,
            1_000,
            2,
            100,
        );
        let mut pool =
            MempoolV2::new(fixture.config.clone(), MempoolLimitsV2::default()).expect("pool");
        pool.admit(first.clone(), &fixture.state, 1).expect("first");
        pool.admit(second.clone(), &fixture.state, 1)
            .expect("second");

        let execution = LedgerStateV2::execute_block(
            &fixture.state,
            &[
                crate::TransactionV2::Coinbase(crate::CoinbaseV2 {
                    version: crate::POW_PROTOCOL_VERSION,
                    network: fixture.config.network,
                    chain_id_hash: fixture.config.consensus_identity_hash().expect("identity"),
                    height: 1,
                    recipient: fixture.recipient,
                    payout: fixture
                        .config
                        .economics
                        .block_subsidy
                        .checked_add(fixture.config.limits.minimum_fee)
                        .expect("payout"),
                    extra_nonce: 0,
                }),
                crate::TransactionV2::Transfer(first.clone()),
            ],
            &fixture.config,
            1,
        )
        .expect("execute");
        let first_id = first.intent_id().expect("first ID");
        pool.reconcile_after_chain_change(
            &execution.state,
            2,
            &BTreeSet::from([first_id]),
            Vec::new(),
        );
        assert!(pool.get(first_id).is_none());
        assert!(pool.get(second.intent_id().expect("second ID")).is_some());
    }

    #[test]
    fn hostile_limit_values_fail_closed() {
        let fixture = fixture();
        for limits in [
            MempoolLimitsV2 {
                maximum_transactions: 0,
                maximum_bytes: 1,
            },
            MempoolLimitsV2 {
                maximum_transactions: 1,
                maximum_bytes: 0,
            },
            MempoolLimitsV2 {
                maximum_transactions: MAX_MEMPOOL_TRANSACTIONS_V2 + 1,
                maximum_bytes: 1,
            },
        ] {
            assert!(matches!(
                MempoolV2::new(fixture.config.clone(), limits),
                Err(MempoolErrorV2::InvalidLimits)
            ));
        }
    }
}
