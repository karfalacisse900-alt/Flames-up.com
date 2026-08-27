use crate::{Address, Hash256, Network};
use thiserror::Error;

/// Errors produced by Aura protocol validation and storage adapters.
#[derive(Debug, Error)]
pub enum Error {
    #[error("address is malformed: {0}")]
    InvalidAddress(String),
    #[error("address belongs to {actual:?}, expected {expected:?}")]
    AddressNetworkMismatch { expected: Network, actual: Network },
    #[error("amount arithmetic overflow")]
    AmountOverflow,
    #[error("amount arithmetic underflow")]
    AmountUnderflow,
    #[error("amount must be greater than zero")]
    ZeroAmount,
    #[error("unsupported protocol version {actual}; expected {expected}")]
    UnsupportedProtocol { expected: u16, actual: u16 },
    #[error("network mismatch: expected {expected:?}, got {actual:?}")]
    NetworkMismatch { expected: Network, actual: Network },
    #[error("transaction was signed for a different chain")]
    ChainIdMismatch,
    #[error("public key does not derive the sender address")]
    SenderKeyMismatch,
    #[error("invalid Ed25519 public key")]
    InvalidPublicKey,
    #[error("invalid Ed25519 signature")]
    InvalidSignature,
    #[error("purchase proof is malformed: {0}")]
    InvalidPurchaseProof(String),
    #[error("purchase proof verifier is not authorized by this chain")]
    UnauthorizedProofVerifier,
    #[error("purchase proof verifier signature is invalid")]
    InvalidVerifierSignature,
    #[error("purchase proof nullifier {0} already exists on this branch")]
    DuplicateProofNullifier(Hash256),
    #[error("purchase proof {0} already exists on this branch")]
    DuplicateProof(Hash256),
    #[error("transaction nonce {actual} is invalid; expected {expected}")]
    InvalidNonce { expected: u64, actual: u64 },
    #[error("transaction expired at height {expires}; candidate height is {height}")]
    TransactionExpired { expires: u64, height: u64 },
    #[error("fee {actual} is below the network minimum {minimum}")]
    FeeTooLow { minimum: u64, actual: u64 },
    #[error("transaction sender and recipient are identical")]
    SelfTransfer,
    #[error("transaction exceeds the maximum encoded size")]
    TransactionTooLarge,
    #[error("insufficient available balance for {address}")]
    InsufficientBalance { address: Address },
    #[error("genesis configuration is invalid: {0}")]
    InvalidGenesis(String),
    #[error("block {0} already exists")]
    DuplicateBlock(Hash256),
    #[error("parent block {0} was not found")]
    ParentNotFound(Hash256),
    #[error("block height {actual} is invalid; expected {expected}")]
    InvalidHeight { expected: u64, actual: u64 },
    #[error("block height space is exhausted")]
    HeightExhausted,
    #[error("block timestamp must be greater than its parent timestamp")]
    NonMonotonicTimestamp,
    #[error("block timestamp exceeds the allowed future drift")]
    FutureTimestamp,
    #[error("block has {actual} transactions; maximum is {maximum}")]
    TooManyTransactions { maximum: u32, actual: usize },
    #[error("encoded block is {actual} bytes; maximum is {maximum}")]
    BlockTooLarge { maximum: u32, actual: usize },
    #[error("transaction Merkle root does not match block contents")]
    TransactionRootMismatch,
    #[error("state root does not match deterministic execution")]
    StateRootMismatch,
    #[error("duplicate transaction {0} in block")]
    DuplicateTransaction(Hash256),
    #[error("consensus engine {0} is not supported in this phase")]
    UnsupportedConsensus(u16),
    #[error("Phase 1 block production is restricted to Aura Devnet")]
    ConsensusUnavailable,
    #[error("consensus commitment is invalid")]
    InvalidConsensusCommitment,
    #[error("Proof-of-Work target is invalid")]
    InvalidTarget,
    #[error("Proof-of-Work result does not satisfy the required target")]
    InvalidProofOfWork,
    #[error("validated mining candidate integrity check failed")]
    InvalidMiningCapability,
    #[error("block target does not match the deterministic required target")]
    UnexpectedTarget,
    #[error(
        "locally mined candidate extends stale parent {candidate_parent}; current canonical tip is {current_tip}"
    )]
    StaleMiningCandidate {
        current_tip: Hash256,
        candidate_parent: Hash256,
    },
    #[error("cumulative Proof-of-Work arithmetic overflow")]
    CumulativeWorkOverflow,
    #[error("coinbase transaction is invalid: {0}")]
    InvalidCoinbase(String),
    #[error("coinbase payout is {actual} atoms; consensus requires exactly {expected} atoms")]
    CoinbasePayoutMismatch { expected: u64, actual: u64 },
    #[error("total issued supply exceeds the consensus cap")]
    SupplyCapExceeded,
    #[error("the database contains only a legacy manual Devnet chain; it cannot be treated as Proof of Work")]
    LegacyManualChain,
    #[error("cumulative chain score overflow")]
    ChainScoreOverflow,
    #[error("stored chain does not match the supplied genesis configuration")]
    GenesisMismatch,
    #[error("chain store is corrupt: {0}")]
    CorruptStore(String),
    #[error("storage failure: {0}")]
    Storage(String),
    #[error("canonical serialization failed: {0}")]
    Serialization(String),
}

/// Aura core result type.
pub type Result<T> = std::result::Result<T, Error>;
