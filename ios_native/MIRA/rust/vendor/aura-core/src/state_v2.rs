use crate::{
    hash_tagged, Account, Address, Amount, CoinbaseV2, Error, Hash256, PowGenesisConfigV2, Result,
    SignedPurchaseProofV2, SignedTransferV2, TransactionV2, POW_PROTOCOL_VERSION,
};
use borsh::{BorshDeserialize, BorshSerialize};
use std::collections::BTreeMap;

/// Monetary state for Aura `PoW` v2.
///
/// Reputation is intentionally absent and cannot create or mutate monetary balances.
#[derive(Clone, Debug, Default, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct LedgerStateV2 {
    accounts: BTreeMap<Address, Account>,
    total_supply: Amount,
}

/// Deterministic accounting result for one complete non-genesis block.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BlockExecutionV2 {
    pub state: LedgerStateV2,
    pub transaction_fees: Amount,
    pub subsidy: Amount,
    pub required_coinbase_payout: Amount,
}

impl LedgerStateV2 {
    /// Constructs the frozen zero-issuance genesis state and rejects any allocation.
    pub fn from_genesis(config: &PowGenesisConfigV2) -> Result<Self> {
        config.validate()?;
        let mut state = Self::default();
        for allocation in &config.allocations {
            let issued = allocation.available.checked_add(allocation.locked)?;
            state.total_supply = state.total_supply.checked_add(issued)?;
            state.accounts.insert(
                allocation.address,
                Account {
                    available: allocation.available,
                    locked: allocation.locked,
                    nonce: 0,
                },
            );
        }
        state.validate_invariants(config.economics.maximum_supply)?;
        Ok(state)
    }

    /// Returns an existing account or a zero-valued account for an unused address.
    #[must_use]
    pub fn account(&self, address: Address) -> Account {
        self.accounts.get(&address).cloned().unwrap_or_default()
    }

    /// Total AUR issued by explicit genesis allocations and validated subsidies.
    #[must_use]
    pub const fn total_supply(&self) -> Amount {
        self.total_supply
    }

    /// Canonical post-state commitment.
    pub fn root(&self) -> Result<Hash256> {
        let bytes = self.encode()?;
        Ok(hash_tagged("ledger-state/v2", &[&bytes]))
    }

    /// Exact canonical monetary-state bytes committed by [`Self::root`].
    pub fn encode(&self) -> Result<Vec<u8>> {
        borsh::to_vec(self).map_err(|error| {
            Error::Serialization(format!("v2 ledger-state encoding failed: {error}"))
        })
    }

    /// Validates and applies one transfer atomically, returning the fee removed from the sender.
    ///
    /// This stage-local method intentionally leaves the fee temporarily outside account balances.
    /// A complete block MUST finish with [`execute_block`] so its coinbase returns fees to an
    /// account and restores the total-supply invariant.
    pub fn apply_transfer_for_candidate(
        &mut self,
        transfer: &SignedTransferV2,
        config: &PowGenesisConfigV2,
        candidate_height: u64,
    ) -> Result<Amount> {
        let mut next = self.clone();
        let fee = next.apply_transfer_unsettled(transfer, config, candidate_height)?;
        *self = next;
        Ok(fee)
    }

    /// Validates and applies one non-coinbase transaction to candidate monetary state.
    ///
    /// Purchase proofs debit only their fee and increment the owner's shared account nonce. The
    /// proof/nullifier history remains separately derived from canonical block transactions.
    pub fn apply_transaction_for_candidate(
        &mut self,
        transaction: &TransactionV2,
        config: &PowGenesisConfigV2,
        candidate_height: u64,
        candidate_timestamp_seconds: u64,
    ) -> Result<Amount> {
        let mut next = self.clone();
        let fee = match transaction {
            TransactionV2::Coinbase(_) => {
                return Err(Error::InvalidCoinbase(
                    "coinbase cannot enter the non-coinbase candidate path".into(),
                ));
            }
            TransactionV2::Transfer(transfer) => {
                next.apply_transfer_unsettled(transfer, config, candidate_height)?
            }
            TransactionV2::PurchaseProof(proof) => next.apply_purchase_proof_unsettled(
                proof,
                config,
                candidate_height,
                candidate_timestamp_seconds,
            )?,
        };
        *self = next;
        Ok(fee)
    }

    fn apply_transfer_unsettled(
        &mut self,
        transfer: &SignedTransferV2,
        config: &PowGenesisConfigV2,
        candidate_height: u64,
    ) -> Result<Amount> {
        transfer.verify(
            config.network,
            config.consensus_identity_hash()?,
            config.limits.minimum_fee,
            candidate_height,
            config.limits.maximum_transaction_bytes,
        )?;
        let sender = self.account(transfer.body.sender);
        let expected_nonce = sender.nonce.checked_add(1).ok_or(Error::AmountOverflow)?;
        if transfer.body.nonce != expected_nonce {
            return Err(Error::InvalidNonce {
                expected: expected_nonce,
                actual: transfer.body.nonce,
            });
        }
        let debit = transfer.body.amount.checked_add(transfer.body.fee)?;
        let sender_available =
            sender
                .available
                .checked_sub(debit)
                .map_err(|_| Error::InsufficientBalance {
                    address: transfer.body.sender,
                })?;
        let recipient = self.account(transfer.body.recipient);
        let recipient_available = recipient.available.checked_add(transfer.body.amount)?;

        self.accounts.insert(
            transfer.body.sender,
            Account {
                available: sender_available,
                locked: sender.locked,
                nonce: transfer.body.nonce,
            },
        );
        self.accounts.insert(
            transfer.body.recipient,
            Account {
                available: recipient_available,
                ..recipient
            },
        );
        Ok(transfer.body.fee)
    }

    fn apply_purchase_proof_unsettled(
        &mut self,
        proof: &SignedPurchaseProofV2,
        config: &PowGenesisConfigV2,
        candidate_height: u64,
        candidate_timestamp_seconds: u64,
    ) -> Result<Amount> {
        proof.verify(config, candidate_height, candidate_timestamp_seconds)?;
        let owner_address = proof.owner();
        let owner = self.account(owner_address);
        let expected_nonce = owner.nonce.checked_add(1).ok_or(Error::AmountOverflow)?;
        if proof.body.nonce != expected_nonce {
            return Err(Error::InvalidNonce {
                expected: expected_nonce,
                actual: proof.body.nonce,
            });
        }
        let available = owner.available.checked_sub(proof.body.fee).map_err(|_| {
            Error::InsufficientBalance {
                address: owner_address,
            }
        })?;
        self.accounts.insert(
            owner_address,
            Account {
                available,
                locked: owner.locked,
                nonce: proof.body.nonce,
            },
        );
        Ok(proof.body.fee)
    }

    /// Executes a complete v2 block atomically and validates exact coinbase issuance and fees.
    pub fn execute_block(
        parent: &Self,
        transactions: &[TransactionV2],
        config: &PowGenesisConfigV2,
        height: u64,
        timestamp_seconds: u64,
    ) -> Result<BlockExecutionV2> {
        parent.validate_invariants(config.economics.maximum_supply)?;
        let Some(TransactionV2::Coinbase(coinbase)) = transactions.first() else {
            return Err(Error::InvalidCoinbase(
                "a non-genesis block must begin with exactly one coinbase".into(),
            ));
        };
        validate_coinbase_identity(coinbase, config, height)?;

        let mut next = parent.clone();
        let mut fees = Amount::ZERO;
        for transaction in &transactions[1..] {
            match transaction {
                TransactionV2::Coinbase(_) => {
                    return Err(Error::InvalidCoinbase(
                        "a block contains more than one coinbase".into(),
                    ));
                }
                TransactionV2::Transfer(transfer) => {
                    let fee = next.apply_transfer_unsettled(transfer, config, height)?;
                    fees = fees.checked_add(fee)?;
                }
                TransactionV2::PurchaseProof(proof) => {
                    let fee = next.apply_purchase_proof_unsettled(
                        proof,
                        config,
                        height,
                        timestamp_seconds,
                    )?;
                    fees = fees.checked_add(fee)?;
                }
            }
        }

        let subsidy = config.subsidy(parent.total_supply, height)?;
        let required_payout = subsidy.checked_add(fees)?;
        if coinbase.payout != required_payout {
            return Err(Error::CoinbasePayoutMismatch {
                expected: required_payout.atoms(),
                actual: coinbase.payout.atoms(),
            });
        }

        let miner = next.account(coinbase.recipient);
        let available = miner.available.checked_add(required_payout)?;
        next.accounts
            .insert(coinbase.recipient, Account { available, ..miner });
        next.total_supply = next.total_supply.checked_add(subsidy)?;
        next.validate_invariants(config.economics.maximum_supply)?;

        Ok(BlockExecutionV2 {
            state: next,
            transaction_fees: fees,
            subsidy,
            required_coinbase_payout: required_payout,
        })
    }

    /// Checks exact supply accounting with no application-controlled mint path.
    pub fn validate_invariants(&self, maximum_supply: Amount) -> Result<()> {
        let mut accounted = 0_u128;
        for account in self.accounts.values() {
            accounted = accounted
                .checked_add(u128::from(account.available.atoms()))
                .and_then(|value| value.checked_add(u128::from(account.locked.atoms())))
                .ok_or(Error::AmountOverflow)?;
        }
        if accounted != u128::from(self.total_supply.atoms()) {
            return Err(Error::CorruptStore(
                "PoW v2 account balances do not equal total issued supply".into(),
            ));
        }
        if self.total_supply > maximum_supply {
            return Err(Error::SupplyCapExceeded);
        }
        Ok(())
    }
}

fn validate_coinbase_identity(
    coinbase: &CoinbaseV2,
    config: &PowGenesisConfigV2,
    height: u64,
) -> Result<()> {
    if coinbase.version != POW_PROTOCOL_VERSION {
        return Err(Error::UnsupportedProtocol {
            expected: POW_PROTOCOL_VERSION,
            actual: coinbase.version,
        });
    }
    if coinbase.network != config.network || coinbase.recipient.network() != config.network {
        return Err(Error::NetworkMismatch {
            expected: config.network,
            actual: coinbase.network,
        });
    }
    if coinbase.chain_id_hash != config.consensus_identity_hash()? {
        return Err(Error::ChainIdMismatch);
    }
    if coinbase.height != height {
        return Err(Error::InvalidHeight {
            expected: height,
            actual: coinbase.height,
        });
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{TransactionBodyV2, TRANSACTION_VERSION_V2};
    use ed25519_dalek::SigningKey;

    fn fixture() -> (
        PowGenesisConfigV2,
        LedgerStateV2,
        SigningKey,
        Address,
        Address,
    ) {
        let sender_key = SigningKey::from_bytes(&[11; 32]);
        let recipient_key = SigningKey::from_bytes(&[12; 32]);
        let sender = Address::from_public_key(
            crate::Network::Devnet,
            &sender_key.verifying_key().to_bytes(),
        );
        let recipient = Address::from_public_key(
            crate::Network::Devnet,
            &recipient_key.verifying_key().to_bytes(),
        );
        let mut config = PowGenesisConfigV2::local_regtest();
        config.economics.block_subsidy = Amount::from_atoms(10_000);
        let genesis = LedgerStateV2::from_genesis(&config).expect("zero-issuance genesis");
        let subsidy = config.subsidy(Amount::ZERO, 1).expect("first subsidy");
        let funded = LedgerStateV2::execute_block(
            &genesis,
            &[coinbase(&config, 1, sender, subsidy)],
            &config,
            1,
            config.genesis_time_seconds.saturating_add(1),
        )
        .expect("fund sender through a consensus coinbase")
        .state;
        (config, funded, sender_key, sender, recipient)
    }

    fn transfer(
        config: &PowGenesisConfigV2,
        key: &SigningKey,
        recipient: Address,
        amount: u64,
        nonce: u64,
    ) -> SignedTransferV2 {
        SignedTransferV2::sign(
            TransactionBodyV2 {
                version: TRANSACTION_VERSION_V2,
                network: config.network,
                chain_id_hash: config.consensus_identity_hash().expect("identity"),
                sender: Address::from_public_key(config.network, &key.verifying_key().to_bytes()),
                recipient,
                amount: Amount::from_atoms(amount),
                fee: config.limits.minimum_fee,
                nonce,
                valid_until_height: 100,
            },
            key,
        )
        .expect("sign transfer")
    }

    fn coinbase(
        config: &PowGenesisConfigV2,
        height: u64,
        recipient: Address,
        payout: Amount,
    ) -> TransactionV2 {
        TransactionV2::Coinbase(CoinbaseV2 {
            version: POW_PROTOCOL_VERSION,
            network: config.network,
            chain_id_hash: config.consensus_identity_hash().expect("identity"),
            height,
            recipient,
            payout,
            extra_nonce: 7,
        })
    }

    #[test]
    fn exact_coinbase_settles_fees_and_only_subsidy_mints() {
        let (config, parent, sender_key, sender, recipient) = fixture();
        let transfer = transfer(&config, &sender_key, recipient, 2_000, 1);
        let subsidy = config.subsidy(parent.total_supply(), 2).expect("subsidy");
        let payout = subsidy
            .checked_add(config.limits.minimum_fee)
            .expect("payout");
        let transactions = vec![
            coinbase(&config, 2, recipient, payout),
            TransactionV2::Transfer(transfer),
        ];
        let result = LedgerStateV2::execute_block(
            &parent,
            &transactions,
            &config,
            2,
            config.genesis_time_seconds.saturating_add(2),
        )
        .expect("execute block");

        assert_eq!(result.subsidy, subsidy);
        assert_eq!(result.transaction_fees, config.limits.minimum_fee);
        assert_eq!(
            result.state.total_supply(),
            parent
                .total_supply()
                .checked_add(subsidy)
                .expect("issued supply")
        );
        assert_eq!(
            result.state.account(sender).available,
            Amount::from_atoms(10_000 - 2_000 - config.limits.minimum_fee.atoms())
        );
        assert_eq!(
            result.state.account(recipient).available,
            Amount::from_atoms(2_000)
                .checked_add(payout)
                .expect("recipient total")
        );
    }

    #[test]
    fn overpay_underpay_duplicate_and_misplaced_coinbase_are_rejected_atomically() {
        let (config, parent, _, _, miner) = fixture();
        let subsidy = config.subsidy(parent.total_supply(), 2).expect("subsidy");

        for wrong in [
            subsidy.checked_add(Amount::from_atoms(1)).expect("overpay"),
            subsidy
                .checked_sub(Amount::from_atoms(1))
                .expect("underpay"),
        ] {
            let transactions = vec![coinbase(&config, 2, miner, wrong)];
            assert!(matches!(
                LedgerStateV2::execute_block(
                    &parent,
                    &transactions,
                    &config,
                    2,
                    config.genesis_time_seconds.saturating_add(2),
                ),
                Err(Error::CoinbasePayoutMismatch { .. })
            ));
            assert_eq!(parent.total_supply(), Amount::from_atoms(10_000));
        }

        let duplicate = vec![
            coinbase(&config, 2, miner, subsidy),
            coinbase(&config, 2, miner, subsidy),
        ];
        assert!(matches!(
            LedgerStateV2::execute_block(
                &parent,
                &duplicate,
                &config,
                2,
                config.genesis_time_seconds.saturating_add(2),
            ),
            Err(Error::InvalidCoinbase(_))
        ));

        assert!(matches!(
            LedgerStateV2::execute_block(
                &parent,
                &[],
                &config,
                2,
                config.genesis_time_seconds.saturating_add(2),
            ),
            Err(Error::InvalidCoinbase(_))
        ));
    }

    #[test]
    fn replay_overspend_and_bad_signature_leave_parent_unchanged() {
        let (config, parent, sender_key, _, recipient) = fixture();
        let snapshot = parent.clone();

        let mut bad_signature = transfer(&config, &sender_key, recipient, 1, 1);
        bad_signature.signature[0] ^= 1;
        let mut candidate_state = parent.clone();
        assert!(matches!(
            candidate_state.apply_transfer_for_candidate(&bad_signature, &config, 2),
            Err(Error::InvalidSignature)
        ));
        assert_eq!(candidate_state, snapshot);

        let subsidy = config.subsidy(parent.total_supply(), 2).expect("subsidy");
        let bad_block = vec![
            coinbase(&config, 2, recipient, subsidy),
            TransactionV2::Transfer(bad_signature),
        ];
        assert!(matches!(
            LedgerStateV2::execute_block(
                &parent,
                &bad_block,
                &config,
                2,
                config.genesis_time_seconds.saturating_add(2),
            ),
            Err(Error::InvalidSignature)
        ));

        let overspend = transfer(&config, &sender_key, recipient, 10_000, 1);
        assert!(matches!(
            candidate_state.apply_transfer_for_candidate(&overspend, &config, 2),
            Err(Error::InsufficientBalance { .. })
        ));
        assert_eq!(candidate_state, snapshot);
        let over_block = vec![
            coinbase(&config, 2, recipient, subsidy),
            TransactionV2::Transfer(overspend),
        ];
        assert!(matches!(
            LedgerStateV2::execute_block(
                &parent,
                &over_block,
                &config,
                2,
                config.genesis_time_seconds.saturating_add(2),
            ),
            Err(Error::InsufficientBalance { .. })
        ));

        let valid = transfer(&config, &sender_key, recipient, 100, 1);
        candidate_state
            .apply_transfer_for_candidate(&valid, &config, 2)
            .expect("first application");
        let after_first = candidate_state.clone();
        assert!(matches!(
            candidate_state.apply_transfer_for_candidate(&valid, &config, 2),
            Err(Error::InvalidNonce {
                expected: 2,
                actual: 1
            })
        ));
        assert_eq!(candidate_state, after_first);
        assert_eq!(parent, snapshot);
    }

    #[test]
    fn empty_and_post_coinbase_state_encodings_have_golden_roots() {
        let config = PowGenesisConfigV2::builtin_devnet();
        let empty = LedgerStateV2::from_genesis(&config).expect("empty state");
        let miner = Address::from_public_key(config.network, &[7; 32]);
        let subsidy = config.subsidy(Amount::ZERO, 1).expect("subsidy");
        let funded = LedgerStateV2::execute_block(
            &empty,
            &[coinbase(&config, 1, miner, subsidy)],
            &config,
            1,
            config.genesis_time_seconds.saturating_add(1),
        )
        .expect("coinbase")
        .state;
        assert_eq!(
            hex::encode(empty.encode().expect("empty bytes")),
            "000000000000000000000000"
        );
        assert_eq!(
            empty.root().expect("empty root").to_string(),
            "17a81e9a2e8d56266baf9f3b9136d28ea2f381eea1fead0aad46b6b06bfcb92f"
        );
        assert_eq!(
            hex::encode(funded.encode().expect("funded bytes")),
            "010000000352554112c07ceb80af849db05f5de46bf8e35231a5a3e60008af2f00000000000000000000000000000000000000000008af2f00000000"
        );
        assert_eq!(
            funded.root().expect("funded root").to_string(),
            "f2334734d90cba78ee193f45ff0e1a6bc20a2cf3348825620de043547ba5da90"
        );
    }
}
