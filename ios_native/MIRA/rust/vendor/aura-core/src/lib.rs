//! Consensus-neutral primitives and deterministic state transition rules for Aura.
//!
//! Phase 1 deliberately permits non-genesis blocks only on Aura Devnet through
//! [`PhaseOneConsensus`]. Mainnet and testnet block production remain disabled until the
//! specified Proof-of-Work, difficulty, cumulative-work, networking, and multi-node gates pass.

mod address;
mod amount;
mod block;
mod block_v2;
mod chain;
mod chain_v2;
mod consensus;
mod difficulty;
mod error;
mod genesis;
mod genesis_v2;
mod hash;
mod mempool_v2;
mod merkle;
mod miner_v2;
mod network;
mod pow;
mod state;
mod state_v2;
mod store;
mod store_v2;
mod transaction;
mod transaction_v2;
mod work;

pub use address::Address;
pub use amount::Amount;
pub use block::{Block, BlockHeader, ConsensusCommitment, BLOCK_VERSION};
pub use block_v2::{
    transaction_root_v2, BlockHeaderV2, BlockV2, ARGON2D_POW_ALGORITHM_ID_V2, BLOCK_HEADER_V2_SIZE,
    BLOCK_VERSION_V2, EMPTY_BLOCK_V2_SIZE, GENESIS_POW_ALGORITHM_ID_V2,
};
pub use chain::{Chain, ImportOutcome, VerificationReport};
pub use chain_v2::{
    prefers_candidate as prefers_pow_candidate, CanonicalPurchaseProofV2, ChainV2,
    ConfirmationStatusV2, ImportOutcomeV2, ValidatedCandidateV2, VerificationReportV2,
};
pub use consensus::{ConsensusVerifier, PhaseOneConsensus};
pub use difficulty::{
    calculate_asert_target, median_time_past, validate_consensus_timestamp,
    validate_live_timestamp, DifficultyError, DifficultyParameters,
    DEVNET_V2_DIFFICULTY_PARAMETERS,
};
pub use error::{Error, Result};
pub use genesis::{ChainParameters, GenesisAllocation, GenesisConfig};
pub use genesis_v2::{
    ConsensusLimitsV2, EconomicParametersV2, GenesisAllocationV2, PowGenesisConfigV2,
    PowParametersV2, PurchaseProofParametersV2, ARGON2D_POW_ALGORITHM_ID,
    DEVNET_PURCHASE_VERIFIER_PUBLIC_KEY, MAX_GENESIS_CONFIG_V2_BYTES, POW_DEVNET_CHAIN_ID,
    POW_DEVNET_GENESIS_TIME_SECONDS, POW_PROTOCOL_VERSION, PURCHASE_PROOF_CONSENSUS_VERSION,
    REGTEST_PURCHASE_VERIFIER_PUBLIC_KEY,
};
pub use hash::{hash_borsh, hash_tagged, Hash256};
pub use mempool_v2::{
    AdmissionOutcomeV2, MempoolErrorV2, MempoolLimitsV2, MempoolV2, ReconcileOutcomeV2,
};
pub use miner_v2::{
    mine_validated_candidate_v2, AttemptCountV2, MinedBlockV2, MinerErrorV2, MiningOutcomeV2,
    MiningTelemetryV2, MAX_MINING_THREADS_V2,
};
pub use network::Network;
pub use pow::{
    calculate_argon2d_work, pow_message_digest, pow_salt, verify_argon2d_pow, verify_pow_digest,
    PowDigest, PowError, PowParameters, PowTargetRequirement, DEVNET_V2_POW_PARAMETERS,
    POW_ALGORITHM_ARGON2D_V13,
};
pub use state::{Account, LedgerState};
pub use state_v2::{BlockExecutionV2, LedgerStateV2};
pub use store::{BlockRecord, ChainStore, MemoryStore, StoreMetadata};
pub use store_v2::{
    BlockRecordV2, ChainStoreV2, MemoryStoreV2, ReorgPlanV2, StoreMetadataV2,
    POW_STORE_SCHEMA_VERSION,
};
pub use transaction::{SignedTransaction, TransactionBody, TRANSACTION_VERSION};
pub use transaction_v2::{
    AttestedPurchaseProofV2, CoinbaseV2, PurchaseProofBodyV2, PurchaseProofClaimV2,
    SignedPurchaseProofV2, SignedTransferV2, TransactionBodyV2, TransactionV2,
    COINBASE_DISCRIMINANT_V2, COINBASE_V2_PAYLOAD_SIZE, MAX_TRANSACTION_V2_SIZE,
    MIN_TRANSACTION_V2_SIZE, PURCHASE_PROOF_DISCRIMINANT_V2, PURCHASE_PROOF_TYPE_V2,
    PURCHASE_PROOF_VERSION_V2, SIGNED_PURCHASE_PROOF_V2_PAYLOAD_SIZE,
    SIGNED_TRANSFER_V2_PAYLOAD_SIZE, TRANSACTION_VERSION_V2, TRANSFER_DISCRIMINANT_V2,
    VERIFICATION_LEVEL_DOCUMENT_V2, VERIFICATION_LEVEL_MERCHANT_SIGNED_V2,
    VERIFICATION_LEVEL_TRANSACTION_V2,
};
pub use work::{
    block_work, calculate_block_work, BlockWork256, CumulativeWork512, Target256, WorkError,
};

/// Phase-1 fixture for the number of atomic units in one AUR; not a frozen production policy.
pub const ATOMS_PER_AUR: u64 = 100_000_000;
