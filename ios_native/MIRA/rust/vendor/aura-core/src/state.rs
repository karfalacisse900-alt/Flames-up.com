use crate::{
    hash_borsh, Address, Amount, Error, GenesisAllocation, GenesisConfig, Hash256, Result,
    SignedTransaction,
};
use borsh::{BorshDeserialize, BorshSerialize};
use std::collections::BTreeMap;

/// Balance and replay-protection state for one Aura address.
#[derive(Clone, Debug, Default, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct Account {
    /// Spendable balance.
    pub available: Amount,
    /// Protocol-locked balance reserved for future bonds or dispute escrow.
    pub locked: Amount,
    /// Nonce of the most recently committed transaction.
    pub nonce: u64,
}

/// Canonical account-model state committed by every block header.
#[derive(Clone, Debug, Default, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct LedgerState {
    accounts: BTreeMap<Address, Account>,
    fee_pool: Amount,
    total_supply: Amount,
}

impl LedgerState {
    /// Builds the initial state from validated genesis allocations.
    pub fn from_genesis(config: &GenesisConfig) -> Result<Self> {
        config.validate()?;
        let mut state = Self::default();
        for allocation in &config.allocations {
            state.insert_allocation(allocation)?;
        }
        state.validate_invariants(config.parameters.maximum_supply)?;
        Ok(state)
    }

    fn insert_allocation(&mut self, allocation: &GenesisAllocation) -> Result<()> {
        let issued = allocation.available.checked_add(allocation.locked)?;
        self.total_supply = self.total_supply.checked_add(issued)?;
        self.accounts.insert(
            allocation.address,
            Account {
                available: allocation.available,
                locked: allocation.locked,
                nonce: 0,
            },
        );
        Ok(())
    }

    /// Returns an account, or a zero-valued account for an unused valid address.
    #[must_use]
    pub fn account(&self, address: Address) -> Account {
        self.accounts.get(&address).cloned().unwrap_or_default()
    }

    /// Returns the fee pool awaiting a future consensus-defined recipient.
    #[must_use]
    pub const fn fee_pool(&self) -> Amount {
        self.fee_pool
    }

    /// Returns all issued AUR, including locked funds and the undistributed fee pool.
    #[must_use]
    pub const fn total_supply(&self) -> Amount {
        self.total_supply
    }

    /// Applies a signed transfer atomically after all deterministic checks pass.
    pub fn apply_transaction(
        &mut self,
        transaction: &SignedTransaction,
        config: &GenesisConfig,
        candidate_height: u64,
    ) -> Result<()> {
        self.validate_invariants(config.parameters.maximum_supply)?;
        let mut next = self.clone();
        next.apply_transaction_to_valid_state(transaction, config, candidate_height)?;
        next.validate_invariants(config.parameters.maximum_supply)?;
        *self = next;
        Ok(())
    }

    pub(crate) fn apply_transaction_to_valid_state(
        &mut self,
        transaction: &SignedTransaction,
        config: &GenesisConfig,
        candidate_height: u64,
    ) -> Result<()> {
        transaction.verify(
            config.network,
            config.chain_id_hash(),
            config.parameters.minimum_fee,
            candidate_height,
            config.parameters.maximum_transaction_bytes,
        )?;

        let sender = self.account(transaction.body.sender);
        let expected_nonce = sender.nonce.checked_add(1).ok_or(Error::AmountOverflow)?;
        if transaction.body.nonce != expected_nonce {
            return Err(Error::InvalidNonce {
                expected: expected_nonce,
                actual: transaction.body.nonce,
            });
        }
        let debit = transaction.body.amount.checked_add(transaction.body.fee)?;
        let sender_available =
            sender
                .available
                .checked_sub(debit)
                .map_err(|_| Error::InsufficientBalance {
                    address: transaction.body.sender,
                })?;
        let recipient = self.account(transaction.body.recipient);
        let recipient_available = recipient.available.checked_add(transaction.body.amount)?;
        let fee_pool = self.fee_pool.checked_add(transaction.body.fee)?;

        self.accounts.insert(
            transaction.body.sender,
            Account {
                available: sender_available,
                locked: sender.locked,
                nonce: transaction.body.nonce,
            },
        );
        self.accounts.insert(
            transaction.body.recipient,
            Account {
                available: recipient_available,
                ..recipient
            },
        );
        self.fee_pool = fee_pool;
        Ok(())
    }

    /// Commits the complete canonical state with deterministic key ordering.
    pub fn root(&self) -> Result<Hash256> {
        hash_borsh("ledger-state/v1", self)
    }

    /// Checks the supply accounting invariant.
    pub fn validate_invariants(&self, maximum_supply: Amount) -> Result<()> {
        let mut accounted = u128::from(self.fee_pool.atoms());
        for account in self.accounts.values() {
            accounted = accounted
                .checked_add(u128::from(account.available.atoms()))
                .and_then(|value| value.checked_add(u128::from(account.locked.atoms())))
                .ok_or(Error::AmountOverflow)?;
        }
        if accounted != u128::from(self.total_supply.atoms()) {
            return Err(Error::CorruptStore(
                "account balances do not equal total supply".into(),
            ));
        }
        if self.total_supply > maximum_supply {
            return Err(Error::InvalidGenesis(
                "total supply exceeds the configured safety ceiling".into(),
            ));
        }
        Ok(())
    }
}
