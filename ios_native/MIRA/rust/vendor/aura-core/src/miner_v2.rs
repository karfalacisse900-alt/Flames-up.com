//! Genuine multithreaded Argon2d mining for Aura `PoW` Devnet v2.
//!
//! This module searches only a fully constructed, state-valid candidate. Target
//! calculation, coinbase construction, transaction selection, and stale-tip
//! detection belong to the chain/node coordinator. The public mining entry
//! point always executes the consensus Argon2d function for every work attempt.

use crate::{
    calculate_argon2d_work, verify_pow_digest, BlockV2, Error, PowDigest, PowError,
    PowGenesisConfigV2, PowParameters, PowTargetRequirement, Target256, ValidatedCandidateV2,
    WorkError,
};
use std::{
    fmt,
    panic::{catch_unwind, AssertUnwindSafe},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    thread::{self, JoinHandle},
    time::{Duration, Instant},
};

/// Hard safety bound for one local mining request.
pub const MAX_MINING_THREADS_V2: usize = 256;

/// An exact attempt count covering the complete `u128` nonce space.
///
/// `high == 1, low == 0` represents exactly `2^128`, which cannot be held in a
/// plain `u128` but is the number of coordinates in the full nonce space.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct AttemptCountV2 {
    high: u8,
    low: u128,
}

impl AttemptCountV2 {
    /// Zero completed work attempts.
    pub const ZERO: Self = Self { high: 0, low: 0 };
    const ONE: Self = Self { high: 0, low: 1 };

    /// Returns the count as `u128`, or `None` only for the full `2^128` space.
    #[must_use]
    pub const fn as_u128(self) -> Option<u128> {
        if self.high == 0 {
            Some(self.low)
        } else {
            None
        }
    }

    /// Whether this count represents every coordinate in the `u128` space.
    #[must_use]
    pub const fn is_full_nonce_space(self) -> bool {
        self.high == 1 && self.low == 0
    }

    fn checked_add(self, other: Self) -> Option<Self> {
        let (low, carry) = self.low.overflowing_add(other.low);
        let high = u16::from(self.high)
            .checked_add(u16::from(other.high))?
            .checked_add(u16::from(carry))?;
        if high > 1 || (high == 1 && low != 0) {
            return None;
        }
        Some(Self {
            high: u8::try_from(high).ok()?,
            low,
        })
    }

    fn increment(&mut self) -> Result<(), MinerErrorV2> {
        *self = self
            .checked_add(Self::ONE)
            .ok_or(MinerErrorV2::AttemptCountOverflow)?;
        Ok(())
    }

    #[allow(clippy::cast_precision_loss)]
    fn as_f64(self) -> f64 {
        if self.is_full_nonce_space() {
            2_f64.powi(128)
        } else {
            self.low as f64
        }
    }
}

impl fmt::Display for AttemptCountV2 {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.is_full_nonce_space() {
            formatter.write_str("340282366920938463463374607431768211456")
        } else {
            write!(formatter, "{}", self.low)
        }
    }
}

/// Non-consensus measurements from one completed mining invocation.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct MiningTelemetryV2 {
    /// Exact number of completed Argon2d evaluations.
    pub attempts: AttemptCountV2,
    /// Monotonic wall duration including worker startup and shutdown.
    pub elapsed: Duration,
    /// Measured completed attempts per elapsed second.
    ///
    /// This floating-point value is display telemetry only and never enters a
    /// block, target, difficulty, fork-choice, or other consensus calculation.
    pub attempts_per_second: f64,
}

/// A mined candidate and the exact work result that satisfied its target.
#[derive(Clone, Debug, PartialEq)]
pub struct MinedBlockV2 {
    /// Candidate with the winning public nonce installed in its header.
    pub block: BlockV2,
    /// Exact Argon2d output for the returned canonical header.
    pub work_digest: PowDigest,
    /// Measured work performed by all joined workers.
    pub telemetry: MiningTelemetryV2,
}

/// Terminal result of a successful mining invocation.
#[derive(Clone, Debug, PartialEq)]
pub enum MiningOutcomeV2 {
    /// Genuine work satisfying the candidate target was found.
    Mined(Box<MinedBlockV2>),
    /// The supplied stale-work flag was observed before a solution.
    Cancelled(MiningTelemetryV2),
    /// Every `u128` nonce assigned to every worker was tried without success.
    NonceSpaceExhausted(MiningTelemetryV2),
}

/// Mining setup, worker, and lifecycle failures.
#[derive(Debug, thiserror::Error)]
pub enum MinerErrorV2 {
    /// The configured worker count is outside the supported range.
    #[error("mining thread count {requested} is invalid; expected 1..={maximum}")]
    InvalidThreadCount { requested: usize, maximum: usize },
    /// The caller supplied an already-populated search coordinate.
    #[error("unsigned mining candidate must have nonce zero")]
    CandidateNonceNotZero,
    /// The candidate or chain configuration failed structural validation.
    #[error("invalid mining candidate: {0}")]
    InvalidCandidate(#[source] Error),
    /// The target is outside the configured inclusive bounds.
    #[error("invalid mining target: {0}")]
    InvalidTarget(#[source] WorkError),
    /// Argon2d construction or work evaluation failed.
    #[error("Proof-of-Work worker failed: {0}")]
    ProofOfWork(#[source] PowError),
    /// The operating system refused to start a requested worker.
    #[error("failed to spawn mining worker {worker_index}: {source}")]
    WorkerSpawn {
        worker_index: usize,
        #[source]
        source: std::io::Error,
    },
    /// A worker panicked; all other workers were stopped and joined.
    #[error("mining worker {worker_index} panicked")]
    WorkerPanicked { worker_index: usize },
    /// Internal accounting exceeded the complete nonce space.
    #[error("mining attempt counter exceeded the complete u128 nonce space")]
    AttemptCountOverflow,
    /// Workers returned without a solution, cancellation, exhaustion, or error.
    #[error("mining workers returned no terminal result")]
    MissingWorkerConclusion,
}

/// Mines a chain-validated Aura `PoW` Devnet v2 candidate.
///
/// Worker `i` starts at nonce `i` and advances by the accepted worker count.
/// Only [`crate::ChainV2`] can create the required capability through the public
/// API after validating the candidate ledger transition, coinbase, ASERT target,
/// timestamp, and state root. The candidate's frozen consensus configuration is
/// used automatically, preventing a caller from substituting easier work
/// parameters. Cancellation is checked before every Argon2d evaluation; an
/// evaluation already in progress is allowed to finish because the pinned
/// Argon2 API has no safe interruption mechanism. Every started thread is
/// joined before this function returns.
#[allow(clippy::needless_pass_by_value)]
pub fn mine_validated_candidate_v2(
    candidate: ValidatedCandidateV2,
    thread_count: usize,
    cancellation: Arc<AtomicBool>,
) -> Result<MiningOutcomeV2, MinerErrorV2> {
    let (candidate, config) = candidate
        .into_mining_parts()
        .map_err(MinerErrorV2::InvalidCandidate)?;
    let evaluator = Arc::new(
        |header: &crate::BlockHeaderV2, canonical_header: &[u8], parameters: PowParameters| {
            calculate_argon2d_work(
                canonical_header,
                header.chain_id_hash,
                header.parent_block_id,
                parameters,
            )
        },
    );
    mine_with_evaluator(candidate, &config, thread_count, &cancellation, &evaluator)
}

type WorkerHandle = JoinHandle<WorkerExit>;

enum WorkerExit {
    Completed(Result<WorkerReport, MinerErrorV2>),
    Panicked,
}

struct WorkerReport {
    attempts: AttemptCountV2,
    found: Option<(u128, PowDigest)>,
    exhausted: bool,
}

#[allow(clippy::too_many_lines, clippy::type_complexity)]
fn mine_with_evaluator<E>(
    candidate: BlockV2,
    config: &PowGenesisConfigV2,
    thread_count: usize,
    cancellation: &Arc<AtomicBool>,
    evaluator: &Arc<E>,
) -> Result<MiningOutcomeV2, MinerErrorV2>
where
    E: Fn(&crate::BlockHeaderV2, &[u8], PowParameters) -> Result<PowDigest, PowError>
        + Send
        + Sync
        + 'static,
{
    let started = Instant::now();
    let parameters = preflight(&candidate, config, thread_count)?;
    if cancellation.load(Ordering::Acquire) {
        return Ok(MiningOutcomeV2::Cancelled(telemetry(
            AttemptCountV2::ZERO,
            started.elapsed(),
        )));
    }

    let internal_stop = Arc::new(AtomicBool::new(false));
    let mut workers: Vec<(usize, WorkerHandle)> = Vec::with_capacity(thread_count);
    let stride = u128::try_from(thread_count).map_err(|_| MinerErrorV2::InvalidThreadCount {
        requested: thread_count,
        maximum: MAX_MINING_THREADS_V2,
    })?;

    for worker_index in 0..thread_count {
        if internal_stop.load(Ordering::Acquire) || cancellation.load(Ordering::Acquire) {
            break;
        }
        let header = candidate.header.clone();
        let worker_stop = Arc::clone(&internal_stop);
        let worker_cancellation = Arc::clone(cancellation);
        let worker_evaluator = Arc::clone(evaluator);
        let spawn = thread::Builder::new()
            .name(format!("aura-pow-v2-{worker_index}"))
            .spawn(move || {
                let panic_stop = Arc::clone(&worker_stop);
                let result = catch_unwind(AssertUnwindSafe(|| {
                    mine_worker(
                        header,
                        worker_index,
                        stride,
                        parameters,
                        worker_cancellation.as_ref(),
                        worker_stop.as_ref(),
                        worker_evaluator.as_ref(),
                    )
                }));
                if let Ok(report) = result {
                    WorkerExit::Completed(report)
                } else {
                    panic_stop.store(true, Ordering::Release);
                    WorkerExit::Panicked
                }
            });
        match spawn {
            Ok(handle) => workers.push((worker_index, handle)),
            Err(source) => {
                internal_stop.store(true, Ordering::Release);
                join_for_cleanup(workers);
                return Err(MinerErrorV2::WorkerSpawn {
                    worker_index,
                    source,
                });
            }
        }
    }

    let mut attempts = AttemptCountV2::ZERO;
    let mut found: Option<(u128, PowDigest)> = None;
    let mut exhausted_workers = 0_usize;
    let started_workers = workers.len();
    let mut first_error = None;
    let mut first_panic = None;

    for (worker_index, handle) in workers {
        match handle.join() {
            Ok(WorkerExit::Completed(Ok(report))) => {
                attempts = attempts
                    .checked_add(report.attempts)
                    .ok_or(MinerErrorV2::AttemptCountOverflow)?;
                if report.exhausted {
                    exhausted_workers = exhausted_workers.saturating_add(1);
                }
                if let Some(solution) = report.found {
                    if found.is_none_or(|current| solution.0 < current.0) {
                        found = Some(solution);
                    }
                }
            }
            Ok(WorkerExit::Completed(Err(error))) => {
                internal_stop.store(true, Ordering::Release);
                if first_error.is_none() {
                    first_error = Some(error);
                }
            }
            Ok(WorkerExit::Panicked) | Err(_) => {
                internal_stop.store(true, Ordering::Release);
                if first_panic.is_none() {
                    first_panic = Some(worker_index);
                }
            }
        }
    }

    if let Some(worker_index) = first_panic {
        return Err(MinerErrorV2::WorkerPanicked { worker_index });
    }
    if let Some(error) = first_error {
        return Err(error);
    }

    let measurements = telemetry(attempts, started.elapsed());
    if let Some((nonce, digest)) = found {
        let mut mined = candidate;
        mined.header.nonce = nonce;
        verify_pow_digest(
            digest,
            PowTargetRequirement {
                declared: mined.header.target,
                required: mined.header.target,
                minimum: config.pow.minimum_target,
                pow_limit: config.pow.pow_limit,
            },
        )
        .map_err(MinerErrorV2::ProofOfWork)?;
        return Ok(MiningOutcomeV2::Mined(Box::new(MinedBlockV2 {
            block: mined,
            work_digest: digest,
            telemetry: measurements,
        })));
    }
    if cancellation.load(Ordering::Acquire) {
        return Ok(MiningOutcomeV2::Cancelled(measurements));
    }
    if started_workers == thread_count && exhausted_workers == started_workers {
        return Ok(MiningOutcomeV2::NonceSpaceExhausted(measurements));
    }
    Err(MinerErrorV2::MissingWorkerConclusion)
}

#[allow(clippy::type_complexity)]
fn mine_worker<E>(
    mut header: crate::BlockHeaderV2,
    worker_index: usize,
    stride: u128,
    parameters: PowParameters,
    cancellation: &AtomicBool,
    internal_stop: &AtomicBool,
    evaluator: &E,
) -> Result<WorkerReport, MinerErrorV2>
where
    E: Fn(&crate::BlockHeaderV2, &[u8], PowParameters) -> Result<PowDigest, PowError>,
{
    let mut attempts = AttemptCountV2::ZERO;
    let mut nonce = u128::try_from(worker_index).map_err(|_| MinerErrorV2::AttemptCountOverflow)?;
    loop {
        if cancellation.load(Ordering::Acquire) || internal_stop.load(Ordering::Acquire) {
            return Ok(WorkerReport {
                attempts,
                found: None,
                exhausted: false,
            });
        }

        header.nonce = nonce;
        let canonical_header = header.encode().map_err(MinerErrorV2::InvalidCandidate)?;
        let digest = match evaluator(&header, &canonical_header, parameters) {
            Ok(digest) => digest,
            Err(error) => {
                internal_stop.store(true, Ordering::Release);
                return Err(MinerErrorV2::ProofOfWork(error));
            }
        };
        attempts.increment()?;

        match verify_pow_digest(
            digest,
            PowTargetRequirement {
                declared: header.target,
                required: header.target,
                minimum: Target256::ONE,
                pow_limit: Target256::MAX,
            },
        ) {
            Ok(()) => {
                internal_stop.store(true, Ordering::Release);
                return Ok(WorkerReport {
                    attempts,
                    found: Some((nonce, digest)),
                    exhausted: false,
                });
            }
            Err(PowError::InsufficientWork) => {}
            Err(error) => {
                internal_stop.store(true, Ordering::Release);
                return Err(MinerErrorV2::ProofOfWork(error));
            }
        }

        let Some(next_nonce) = nonce.checked_add(stride) else {
            return Ok(WorkerReport {
                attempts,
                found: None,
                exhausted: true,
            });
        };
        nonce = next_nonce;
    }
}

fn preflight(
    candidate: &BlockV2,
    config: &PowGenesisConfigV2,
    thread_count: usize,
) -> Result<PowParameters, MinerErrorV2> {
    if !(1..=MAX_MINING_THREADS_V2).contains(&thread_count) {
        return Err(MinerErrorV2::InvalidThreadCount {
            requested: thread_count,
            maximum: MAX_MINING_THREADS_V2,
        });
    }
    config.validate().map_err(MinerErrorV2::InvalidCandidate)?;
    candidate
        .verify_body(config)
        .map_err(MinerErrorV2::InvalidCandidate)?;
    if candidate.header.nonce != 0 {
        return Err(MinerErrorV2::CandidateNonceNotZero);
    }
    candidate
        .header
        .target
        .validate_bounds(config.pow.minimum_target, config.pow.pow_limit)
        .map_err(MinerErrorV2::InvalidTarget)?;
    let parameters = PowParameters::new(
        config.pow.argon_memory_kib,
        config.pow.argon_time_cost,
        config.pow.argon_lanes,
    );
    parameters.validate().map_err(MinerErrorV2::ProofOfWork)?;
    Ok(parameters)
}

fn telemetry(attempts: AttemptCountV2, elapsed: Duration) -> MiningTelemetryV2 {
    let seconds = elapsed.as_secs_f64();
    let attempts_per_second = if seconds > 0.0 {
        attempts.as_f64() / seconds
    } else {
        0.0
    };
    MiningTelemetryV2 {
        attempts,
        elapsed,
        attempts_per_second,
    }
}

fn join_for_cleanup(workers: Vec<(usize, WorkerHandle)>) {
    for (_, worker) in workers {
        let _ = worker.join();
    }
}

#[cfg(test)]
fn nonce_at_iteration(worker_index: usize, thread_count: usize, iteration: u128) -> Option<u128> {
    let stride = u128::try_from(thread_count).ok()?;
    let start = u128::try_from(worker_index).ok()?;
    let offset = stride.checked_mul(iteration)?;
    start.checked_add(offset)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        verify_argon2d_pow, Address, Amount, ChainV2, CoinbaseV2, Hash256, MemoryStoreV2,
        TransactionV2, TRANSACTION_VERSION_V2,
    };

    fn raw_candidate(config: &PowGenesisConfigV2, target: Target256) -> BlockV2 {
        let coinbase = TransactionV2::Coinbase(CoinbaseV2 {
            version: TRANSACTION_VERSION_V2,
            network: config.network,
            chain_id_hash: config.consensus_identity_hash().expect("identity"),
            height: 1,
            recipient: Address::from_public_key(config.network, &[8; 32]),
            payout: Amount::from_atoms(8 * crate::ATOMS_PER_AUR),
            extra_nonce: 0,
        });
        BlockV2::candidate(
            config,
            1,
            Hash256::from_bytes([0x33; 32]),
            1,
            vec![coinbase],
            Hash256::from_bytes([0x44; 32]),
            target,
            0,
        )
        .expect("valid unsigned candidate")
    }

    fn validated_candidate(config: &PowGenesisConfigV2) -> ValidatedCandidateV2 {
        let chain = ChainV2::initialize(MemoryStoreV2::default(), config.clone())
            .expect("initialize test chain");
        chain
            .prepare_candidate(
                Address::from_public_key(config.network, &[8; 32]),
                Vec::new(),
                1,
                0,
            )
            .expect("chain-validated candidate")
    }

    #[test]
    fn nonce_sequences_are_disjoint_and_stride_partitioned() {
        assert_eq!(
            (0..4)
                .map(|iteration| nonce_at_iteration(0, 3, iteration).expect("nonce"))
                .collect::<Vec<_>>(),
            vec![0, 3, 6, 9]
        );
        assert_eq!(
            (0..4)
                .map(|iteration| nonce_at_iteration(1, 3, iteration).expect("nonce"))
                .collect::<Vec<_>>(),
            vec![1, 4, 7, 10]
        );
        assert_eq!(
            (0..4)
                .map(|iteration| nonce_at_iteration(2, 3, iteration).expect("nonce"))
                .collect::<Vec<_>>(),
            vec![2, 5, 8, 11]
        );
        assert_eq!(nonce_at_iteration(0, 1, u128::MAX), Some(u128::MAX));
        assert_eq!(nonce_at_iteration(1, 2, u128::MAX), None);
    }

    #[test]
    fn genuine_regtest_mining_returns_recomputable_work() {
        let config = PowGenesisConfigV2::local_regtest();
        let outcome = mine_validated_candidate_v2(
            validated_candidate(&config),
            4,
            Arc::new(AtomicBool::new(false)),
        )
        .expect("mine regtest block");
        let MiningOutcomeV2::Mined(mined) = outcome else {
            panic!("easy regtest target must be mined");
        };
        assert!(mined
            .telemetry
            .attempts
            .as_u128()
            .is_some_and(|count| count > 0));
        assert!(mined.telemetry.attempts_per_second.is_finite());
        assert!(mined.telemetry.attempts_per_second > 0.0);

        let header_bytes = mined.block.header.encode().expect("canonical header");
        let verified = verify_argon2d_pow(
            &header_bytes,
            mined.block.header.chain_id_hash,
            mined.block.header.parent_block_id,
            PowTargetRequirement {
                declared: mined.block.header.target,
                required: mined.block.header.target,
                minimum: config.pow.minimum_target,
                pow_limit: config.pow.pow_limit,
            },
            PowParameters::new(
                config.pow.argon_memory_kib,
                config.pow.argon_time_cost,
                config.pow.argon_lanes,
            ),
        )
        .expect("recompute genuine work");
        assert_eq!(verified, mined.work_digest);
    }

    #[test]
    fn fake_work_is_rejected() {
        let requirement = PowTargetRequirement {
            declared: Target256::ONE,
            required: Target256::ONE,
            minimum: Target256::ONE,
            pow_limit: Target256::MAX,
        };
        assert!(matches!(
            verify_pow_digest(PowDigest::from_be_bytes([0xff; 32]), requirement),
            Err(PowError::InsufficientWork)
        ));
    }

    #[test]
    fn cancellation_before_start_returns_no_result_and_no_attempts() {
        let config = PowGenesisConfigV2::local_regtest();
        let cancellation = Arc::new(AtomicBool::new(true));
        let outcome = mine_validated_candidate_v2(validated_candidate(&config), 2, cancellation)
            .expect("cancel cleanly");
        let MiningOutcomeV2::Cancelled(telemetry) = outcome else {
            panic!("pre-cancelled work must not produce a block");
        };
        assert_eq!(telemetry.attempts, AttemptCountV2::ZERO);
    }

    #[test]
    fn thread_bounds_fail_before_work() {
        let config = PowGenesisConfigV2::local_regtest();
        for invalid in [0, MAX_MINING_THREADS_V2 + 1] {
            assert!(matches!(
                mine_validated_candidate_v2(
                    validated_candidate(&config),
                    invalid,
                    Arc::new(AtomicBool::new(false))
                ),
                Err(MinerErrorV2::InvalidThreadCount { .. })
            ));
        }
    }

    #[test]
    fn sealed_candidate_tampering_is_rejected_before_any_work() {
        let config = PowGenesisConfigV2::local_regtest();
        let mut candidate = validated_candidate(&config);
        let block = candidate.block_mut_for_miner_test();
        let TransactionV2::Coinbase(coinbase) = &mut block.transactions[0] else {
            panic!("candidate must start with coinbase")
        };
        coinbase.payout = coinbase
            .payout
            .checked_add(Amount::from_atoms(1))
            .expect("one atom");
        block.header.transaction_root =
            BlockV2::transaction_root(&block.transactions).expect("tampered root");

        assert!(matches!(
            mine_validated_candidate_v2(candidate, 1, Arc::new(AtomicBool::new(false))),
            Err(MinerErrorV2::InvalidCandidate(
                Error::InvalidMiningCapability
            ))
        ));
    }

    #[test]
    fn worker_panics_are_caught_after_all_workers_stop() {
        let config = PowGenesisConfigV2::local_regtest();
        let evaluator = Arc::new(
            |_header: &crate::BlockHeaderV2,
             _bytes: &[u8],
             _parameters: PowParameters|
             -> Result<PowDigest, PowError> { panic!("injected worker panic") },
        );
        assert!(matches!(
            mine_with_evaluator(
                raw_candidate(&config, Target256::MAX),
                &config,
                1,
                &Arc::new(AtomicBool::new(false)),
                &evaluator
            ),
            Err(MinerErrorV2::WorkerPanicked { worker_index: 0 })
        ));
    }

    #[test]
    fn worker_errors_stop_and_join_the_request() {
        let config = PowGenesisConfigV2::local_regtest();
        let evaluator = Arc::new(
            |_header: &crate::BlockHeaderV2, _bytes: &[u8], _parameters: PowParameters| {
                Err(PowError::CalculationFailed("injected".into()))
            },
        );
        assert!(matches!(
            mine_with_evaluator(
                raw_candidate(&config, Target256::MAX),
                &config,
                2,
                &Arc::new(AtomicBool::new(false)),
                &evaluator
            ),
            Err(MinerErrorV2::ProofOfWork(PowError::CalculationFailed(_)))
        ));
    }
}
