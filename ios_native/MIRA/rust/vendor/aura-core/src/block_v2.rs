//! Canonical Aura `PoW` Devnet v2 block and transaction-Merkle primitives.

use crate::{
    hash_tagged, Error, Hash256, Network, PowGenesisConfigV2, Result, Target256, TransactionV2,
    MIN_TRANSACTION_V2_SIZE,
};
use borsh::{BorshDeserialize, BorshSerialize};
use std::{
    collections::BTreeSet,
    io::{Read, Write},
};

/// Frozen block/header format version for Aura `PoW` Devnet v2.
pub const BLOCK_VERSION_V2: u16 = 2;
/// Header algorithm marker used only by the unique genesis block.
pub const GENESIS_POW_ALGORITHM_ID_V2: u16 = 0;
/// Header algorithm identifier for RFC 9106 Argon2d version 0x13.
pub const ARGON2D_POW_ALGORITHM_ID_V2: u16 = 1;
/// Exact canonical byte length of every v2 block header.
pub const BLOCK_HEADER_V2_SIZE: usize = 200;
/// Exact canonical byte length of a header followed by an empty transaction vector.
pub const EMPTY_BLOCK_V2_SIZE: usize = BLOCK_HEADER_V2_SIZE + 4;
const MAX_BORSH_TRANSACTIONS_V2: u32 = 50_000;

/// Canonical fields committed by an Aura `PoW` Devnet v2 block ID and work message.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct BlockHeaderV2 {
    /// Block format version, fixed to `2`.
    pub version: u16,
    /// `0` only for genesis and `1` for Argon2d-v0x13 non-genesis blocks.
    pub pow_algorithm: u16,
    /// Network namespace, canonically encoded as its fixed `u32` network ID.
    pub network: Network,
    /// Domain hash of the textual v2 chain ID.
    pub chain_id_hash: Hash256,
    /// Genesis is height zero.
    pub height: u64,
    /// ID of the previous block, all zero only for genesis.
    pub parent_block_id: Hash256,
    /// Whole seconds since the Unix epoch.
    pub timestamp_seconds: u64,
    /// Merkle root of ordered transaction witness IDs.
    pub transaction_root: Hash256,
    /// Hash of the complete post-block v2 ledger state.
    pub state_root: Hash256,
    /// Full 256-bit target encoded as an exact big-endian byte string.
    pub target: Target256,
    /// Public 128-bit mining search coordinate.
    pub nonce: u128,
}

impl BlockHeaderV2 {
    /// Builds the unique height-zero header committed by a v2 genesis configuration.
    pub fn genesis(config: &PowGenesisConfigV2, state_root: Hash256) -> Result<Self> {
        config.validate()?;
        Ok(Self {
            version: BLOCK_VERSION_V2,
            pow_algorithm: GENESIS_POW_ALGORITHM_ID_V2,
            network: config.network,
            chain_id_hash: config.consensus_identity_hash()?,
            height: 0,
            parent_block_id: Hash256::ZERO,
            timestamp_seconds: config.genesis_time_seconds,
            transaction_root: transaction_root_v2(&[])?,
            state_root,
            target: Target256::ZERO,
            nonce: 0,
        })
    }

    /// Builds a non-genesis candidate header with its frozen chain identity and algorithm ID.
    #[allow(clippy::too_many_arguments)]
    pub fn candidate(
        config: &PowGenesisConfigV2,
        height: u64,
        parent_block_id: Hash256,
        timestamp_seconds: u64,
        transaction_root: Hash256,
        state_root: Hash256,
        target: Target256,
        nonce: u128,
    ) -> Result<Self> {
        config.validate()?;
        if height == 0 {
            return Err(Error::InvalidHeight {
                expected: 1,
                actual: 0,
            });
        }
        if parent_block_id == Hash256::ZERO {
            return Err(Error::ParentNotFound(parent_block_id));
        }
        if target.is_zero() {
            return Err(Error::InvalidTarget);
        }
        Ok(Self {
            version: BLOCK_VERSION_V2,
            pow_algorithm: ARGON2D_POW_ALGORITHM_ID_V2,
            network: config.network,
            chain_id_hash: config.consensus_identity_hash()?,
            height,
            parent_block_id,
            timestamp_seconds,
            transaction_root,
            state_root,
            target,
            nonce,
        })
    }

    /// Returns the exact 200-byte canonical header encoding.
    pub fn encode(&self) -> Result<Vec<u8>> {
        let bytes = borsh::to_vec(self).map_err(|error| {
            Error::Serialization(format!("v2 block header encoding failed: {error}"))
        })?;
        if bytes.len() != BLOCK_HEADER_V2_SIZE {
            return Err(Error::Serialization(format!(
                "v2 block header encoded to {} bytes, expected {BLOCK_HEADER_V2_SIZE}",
                bytes.len()
            )));
        }
        Ok(bytes)
    }

    /// Strictly decodes exactly one fixed-size header and rejects trailing data.
    pub fn decode(bytes: &[u8]) -> Result<Self> {
        if bytes.len() != BLOCK_HEADER_V2_SIZE {
            return Err(Error::Serialization(format!(
                "v2 block header must contain exactly {BLOCK_HEADER_V2_SIZE} bytes"
            )));
        }
        let header = Self::try_from_slice(bytes).map_err(|error| {
            Error::Serialization(format!("v2 block header decoding failed: {error}"))
        })?;
        header.validate_known_fields()?;
        Ok(header)
    }

    /// Returns the domain-separated SHA-256 block ID of the exact canonical header.
    pub fn id(&self) -> Result<Hash256> {
        let bytes = self.encode()?;
        Ok(hash_tagged("block/header/v2", &[&bytes]))
    }

    /// Returns the exact canonical header bytes supplied to the `PoW` message-domain function.
    pub fn work_bytes(&self) -> Result<Vec<u8>> {
        self.encode()
    }

    /// Returns Aura's 32-byte domain-separated work-message digest.
    pub fn work_message(&self) -> Result<Hash256> {
        let bytes = self.work_bytes()?;
        Ok(hash_tagged("pow/message/v1", &[&bytes]))
    }

    /// Returns the parent-specific 32-byte Argon2 salt.
    #[must_use]
    pub fn pow_salt(&self) -> Hash256 {
        hash_tagged(
            "pow/salt/v1",
            &[
                self.chain_id_hash.as_bytes(),
                self.parent_block_id.as_bytes(),
            ],
        )
    }

    fn validate_known_fields(&self) -> Result<()> {
        if self.version != BLOCK_VERSION_V2 {
            return Err(Error::UnsupportedProtocol {
                expected: BLOCK_VERSION_V2,
                actual: self.version,
            });
        }
        if !matches!(
            self.pow_algorithm,
            GENESIS_POW_ALGORITHM_ID_V2 | ARGON2D_POW_ALGORITHM_ID_V2
        ) {
            return Err(Error::UnsupportedConsensus(self.pow_algorithm));
        }
        Ok(())
    }
}

/// An ordered Aura `PoW` Devnet v2 block.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BlockV2 {
    /// Canonical fixed-size header.
    pub header: BlockHeaderV2,
    /// Ordered, explicitly discriminated transactions.
    pub transactions: Vec<TransactionV2>,
}

impl BlockV2 {
    /// Constructs the unique empty-transaction genesis block.
    pub fn genesis(config: &PowGenesisConfigV2, state_root: Hash256) -> Result<Self> {
        let block = Self {
            header: BlockHeaderV2::genesis(config, state_root)?,
            transactions: Vec::new(),
        };
        block.verify_genesis(config)?;
        Ok(block)
    }

    /// Constructs a non-genesis candidate and commits its ordered transaction witnesses.
    #[allow(clippy::too_many_arguments)]
    pub fn candidate(
        config: &PowGenesisConfigV2,
        height: u64,
        parent_block_id: Hash256,
        timestamp_seconds: u64,
        transactions: Vec<TransactionV2>,
        state_root: Hash256,
        target: Target256,
        nonce: u128,
    ) -> Result<Self> {
        let transaction_root = transaction_root_v2(&transactions)?;
        let header = BlockHeaderV2::candidate(
            config,
            height,
            parent_block_id,
            timestamp_seconds,
            transaction_root,
            state_root,
            target,
            nonce,
        )?;
        let block = Self {
            header,
            transactions,
        };
        block.verify_body(config)?;
        Ok(block)
    }

    /// Calculates the v2 witness Merkle root for an ordered transaction list.
    pub fn transaction_root(transactions: &[TransactionV2]) -> Result<Hash256> {
        transaction_root_v2(transactions)
    }

    /// Returns the header-derived block ID.
    pub fn id(&self) -> Result<Hash256> {
        self.header.id()
    }

    /// Returns the exact canonical block bytes: header, `u32` count, then transactions.
    pub fn encode(&self) -> Result<Vec<u8>> {
        let mut bytes = Vec::with_capacity(self.encoded_size()?);
        BorshSerialize::serialize(self, &mut bytes)
            .map_err(|error| Error::Serialization(format!("v2 block encoding failed: {error}")))?;
        Ok(bytes)
    }

    /// Returns the exact canonical encoded block size.
    pub fn encoded_size(&self) -> Result<usize> {
        let transaction_bytes = self.transactions.iter().try_fold(0_usize, |total, tx| {
            total
                .checked_add(tx.encoded_size()?)
                .ok_or(Error::AmountOverflow)
        })?;
        EMPTY_BLOCK_V2_SIZE
            .checked_add(transaction_bytes)
            .ok_or(Error::AmountOverflow)
    }

    /// Strictly decodes a block while enforcing byte and transaction-count limits before allocation.
    pub fn decode(bytes: &[u8], maximum_size: u32, maximum_transactions: u32) -> Result<Self> {
        if bytes.len() > maximum_size as usize {
            return Err(Error::BlockTooLarge {
                maximum: maximum_size,
                actual: bytes.len(),
            });
        }
        if bytes.len() < EMPTY_BLOCK_V2_SIZE {
            return Err(Error::Serialization(
                "v2 block is shorter than its fixed header and transaction count".into(),
            ));
        }

        let (header_bytes, mut remaining) = bytes.split_at(BLOCK_HEADER_V2_SIZE);
        let header = BlockHeaderV2::decode(header_bytes)?;
        let count =
            <u32 as BorshDeserialize>::deserialize_reader(&mut remaining).map_err(|error| {
                Error::Serialization(format!(
                    "v2 block transaction-count decoding failed: {error}"
                ))
            })?;
        if count > maximum_transactions {
            return Err(Error::TooManyTransactions {
                maximum: maximum_transactions,
                actual: count as usize,
            });
        }

        let count_usize = count as usize;
        let minimum_payload = count_usize
            .checked_mul(MIN_TRANSACTION_V2_SIZE)
            .ok_or_else(|| Error::Serialization("v2 transaction count overflow".into()))?;
        if minimum_payload > remaining.len() {
            return Err(Error::Serialization(
                "v2 transaction count cannot fit in the remaining block bytes".into(),
            ));
        }

        let mut transactions = Vec::with_capacity(count_usize);
        for _ in 0..count {
            let transaction =
                TransactionV2::deserialize_reader(&mut remaining).map_err(|error| {
                    Error::Serialization(format!("v2 block transaction decoding failed: {error}"))
                })?;
            transaction.validate_version()?;
            transactions.push(transaction);
        }
        if !remaining.is_empty() {
            return Err(Error::Serialization(
                "trailing bytes after canonical v2 block".into(),
            ));
        }
        Ok(Self {
            header,
            transactions,
        })
    }

    /// Decodes using the consensus limits committed by a v2 genesis configuration.
    pub fn decode_with_config(bytes: &[u8], config: &PowGenesisConfigV2) -> Result<Self> {
        config.validate()?;
        Self::decode(
            bytes,
            config.limits.maximum_block_bytes,
            config.limits.maximum_transactions_per_block,
        )
    }

    /// Verifies canonical size/count limits, coinbase placement, unique intents, and Merkle root.
    pub fn verify_body(&self, config: &PowGenesisConfigV2) -> Result<()> {
        config.validate()?;
        self.header.validate_known_fields()?;
        if self.header.network != config.network {
            return Err(Error::NetworkMismatch {
                expected: config.network,
                actual: self.header.network,
            });
        }
        if self.header.chain_id_hash != config.consensus_identity_hash()? {
            return Err(Error::ChainIdMismatch);
        }
        if self.transactions.len() > config.limits.maximum_transactions_per_block as usize {
            return Err(Error::TooManyTransactions {
                maximum: config.limits.maximum_transactions_per_block,
                actual: self.transactions.len(),
            });
        }
        let encoded_size = self.encoded_size()?;
        if encoded_size > config.limits.maximum_block_bytes as usize {
            return Err(Error::BlockTooLarge {
                maximum: config.limits.maximum_block_bytes,
                actual: encoded_size,
            });
        }

        if self.header.height == 0 {
            return self.verify_genesis(config);
        }
        if self.header.pow_algorithm != ARGON2D_POW_ALGORITHM_ID_V2 {
            return Err(Error::UnsupportedConsensus(self.header.pow_algorithm));
        }
        if self.header.parent_block_id == Hash256::ZERO {
            return Err(Error::ParentNotFound(self.header.parent_block_id));
        }
        if self.header.target.is_zero() {
            return Err(Error::InvalidTarget);
        }

        let Some(TransactionV2::Coinbase(coinbase)) = self.transactions.first() else {
            return Err(Error::InvalidCoinbase(
                "a non-genesis block must begin with exactly one coinbase".into(),
            ));
        };
        coinbase.verify_identity(
            self.header.network,
            self.header.chain_id_hash,
            self.header.height,
        )?;

        let mut seen_intents = BTreeSet::new();
        let mut witness_ids = Vec::with_capacity(self.transactions.len());
        for (position, transaction) in self.transactions.iter().enumerate() {
            transaction.validate_version()?;
            match transaction {
                TransactionV2::Coinbase(_) if position != 0 => {
                    return Err(Error::InvalidCoinbase(
                        "a non-genesis block contains more than one coinbase".into(),
                    ));
                }
                TransactionV2::Coinbase(_) => {}
                TransactionV2::Transfer(transfer) => {
                    transfer
                        .body
                        .validate_identity(self.header.network, self.header.chain_id_hash)?;
                    let intent_id = transfer.intent_id()?;
                    if !seen_intents.insert(intent_id) {
                        return Err(Error::DuplicateTransaction(intent_id));
                    }
                }
            }
            witness_ids.push(transaction.witness_id()?);
        }
        if merkle_root_v2(&witness_ids) != self.header.transaction_root {
            return Err(Error::TransactionRootMismatch);
        }
        Ok(())
    }

    /// Verifies every special height-zero rule and the configured chain identity.
    pub fn verify_genesis(&self, config: &PowGenesisConfigV2) -> Result<()> {
        config.validate()?;
        let expected_root = transaction_root_v2(&[])?;
        let valid = self.header.version == BLOCK_VERSION_V2
            && self.header.pow_algorithm == GENESIS_POW_ALGORITHM_ID_V2
            && self.header.network == config.network
            && self.header.chain_id_hash == config.consensus_identity_hash()?
            && self.header.height == 0
            && self.header.parent_block_id == Hash256::ZERO
            && self.header.timestamp_seconds == config.genesis_time_seconds
            && self.header.transaction_root == expected_root
            && self.header.target == Target256::ZERO
            && self.header.nonce == 0
            && self.transactions.is_empty();
        if !valid {
            return Err(Error::GenesisMismatch);
        }
        Ok(())
    }
}

impl BorshSerialize for BlockV2 {
    fn serialize<W: Write>(&self, writer: &mut W) -> std::io::Result<()> {
        BorshSerialize::serialize(&self.header, writer)?;
        let count = u32::try_from(self.transactions.len()).map_err(|_| {
            std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "v2 transaction count exceeds u32",
            )
        })?;
        BorshSerialize::serialize(&count, writer)?;
        for transaction in &self.transactions {
            BorshSerialize::serialize(transaction, writer)?;
        }
        Ok(())
    }
}

impl BorshDeserialize for BlockV2 {
    fn deserialize_reader<R: Read>(reader: &mut R) -> std::io::Result<Self> {
        let header = BlockHeaderV2::deserialize_reader(reader)?;
        header
            .validate_known_fields()
            .map_err(|error| invalid_consensus_data(&error))?;
        let count = <u32 as BorshDeserialize>::deserialize_reader(reader)?;
        if count > MAX_BORSH_TRANSACTIONS_V2 {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!(
                    "v2 transaction count {count} exceeds hard decoding cap {MAX_BORSH_TRANSACTIONS_V2}"
                ),
            ));
        }
        let mut transactions = Vec::with_capacity(count as usize);
        for _ in 0..count {
            let transaction = TransactionV2::deserialize_reader(reader)?;
            transaction
                .validate_version()
                .map_err(|error| invalid_consensus_data(&error))?;
            transactions.push(transaction);
        }
        Ok(Self {
            header,
            transactions,
        })
    }
}

fn invalid_consensus_data(error: &Error) -> std::io::Error {
    std::io::Error::new(std::io::ErrorKind::InvalidData, error.to_string())
}

/// Computes the frozen v2 witness Merkle root for an ordered transaction list.
pub fn transaction_root_v2(transactions: &[TransactionV2]) -> Result<Hash256> {
    let witness_ids = transactions
        .iter()
        .map(TransactionV2::witness_id)
        .collect::<Result<Vec<_>>>()?;
    Ok(merkle_root_v2(&witness_ids))
}

fn merkle_root_v2(leaves: &[Hash256]) -> Hash256 {
    if leaves.is_empty() {
        return hash_tagged("merkle/empty/v2", &[]);
    }
    let mut level = leaves
        .iter()
        .map(|leaf| hash_tagged("merkle/leaf/v2", &[leaf.as_bytes()]))
        .collect::<Vec<_>>();
    while level.len() > 1 {
        let mut next = Vec::with_capacity(level.len().div_ceil(2));
        for pair in level.chunks(2) {
            let left = pair[0];
            let right = pair.get(1).copied().unwrap_or(left);
            next.push(hash_tagged(
                "merkle/node/v2",
                &[left.as_bytes(), right.as_bytes()],
            ));
        }
        level = next;
    }
    level[0]
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        Address, Amount, CoinbaseV2, SignedTransferV2, TransactionBodyV2, TRANSACTION_VERSION_V2,
    };
    use ed25519_dalek::SigningKey;

    fn coinbase(config: &PowGenesisConfigV2, height: u64, extra_nonce: u64) -> TransactionV2 {
        TransactionV2::Coinbase(CoinbaseV2 {
            version: TRANSACTION_VERSION_V2,
            network: config.network,
            chain_id_hash: config.consensus_identity_hash().expect("identity"),
            height,
            recipient: Address::from_public_key(config.network, &[8; 32]),
            payout: Amount::from_atoms(800_000_000),
            extra_nonce,
        })
    }

    fn transfer(config: &PowGenesisConfigV2, nonce: u64) -> TransactionV2 {
        let key = SigningKey::from_bytes(&[3; 32]);
        TransactionV2::Transfer(
            SignedTransferV2::sign(
                TransactionBodyV2 {
                    version: TRANSACTION_VERSION_V2,
                    network: config.network,
                    chain_id_hash: config.consensus_identity_hash().expect("identity"),
                    sender: Address::from_public_key(
                        config.network,
                        &key.verifying_key().to_bytes(),
                    ),
                    recipient: Address::from_public_key(config.network, &[9; 32]),
                    amount: Amount::from_atoms(10),
                    fee: config.limits.minimum_fee,
                    nonce,
                    valid_until_height: 100,
                },
                &key,
            )
            .expect("sign transfer"),
        )
    }

    fn candidate(transactions: Vec<TransactionV2>) -> BlockV2 {
        let config = PowGenesisConfigV2::local_regtest();
        BlockV2::candidate(
            &config,
            1,
            Hash256::from_bytes([0x33; 32]),
            1,
            transactions,
            Hash256::from_bytes([0x44; 32]),
            Target256::MAX,
            5,
        )
        .expect("candidate")
    }

    #[test]
    fn header_encoding_is_exact_fixed_width_and_strict() {
        let header = BlockHeaderV2 {
            version: BLOCK_VERSION_V2,
            pow_algorithm: ARGON2D_POW_ALGORITHM_ID_V2,
            network: Network::Devnet,
            chain_id_hash: Hash256::from_bytes([0x11; 32]),
            height: 0x0102_0304_0506_0708,
            parent_block_id: Hash256::from_bytes([0x22; 32]),
            timestamp_seconds: 0x1112_1314_1516_1718,
            transaction_root: Hash256::from_bytes([0x33; 32]),
            state_root: Hash256::from_bytes([0x44; 32]),
            target: Target256::from_be_bytes([
                0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d,
                0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b,
                0x1c, 0x1d, 0x1e, 0x1f,
            ]),
            nonce: 0x2122_2324_2526_2728_292a_2b2c_2d2e_2f30,
        };
        let bytes = header.encode().expect("header bytes");
        assert_eq!(bytes.len(), BLOCK_HEADER_V2_SIZE);
        assert_eq!(
            &bytes[152..184],
            header.target.as_be_bytes(),
            "target bytes are big-endian and unmodified"
        );
        assert_eq!(
            &bytes[184..200],
            &header.nonce.to_le_bytes(),
            "surrounding scalar integers remain little-endian"
        );
        assert_eq!(BlockHeaderV2::decode(&bytes).expect("decode"), header);

        let mut trailing = bytes.clone();
        trailing.push(0);
        assert!(BlockHeaderV2::decode(&trailing).is_err());
        assert!(BlockHeaderV2::decode(&bytes[..199]).is_err());

        let mut unknown_version = bytes.clone();
        unknown_version[..2].copy_from_slice(&3_u16.to_le_bytes());
        assert!(matches!(
            BlockHeaderV2::decode(&unknown_version),
            Err(Error::UnsupportedProtocol { .. })
        ));
        let mut unknown_algorithm = bytes;
        unknown_algorithm[2..4].copy_from_slice(&2_u16.to_le_bytes());
        assert!(matches!(
            BlockHeaderV2::decode(&unknown_algorithm),
            Err(Error::UnsupportedConsensus(2))
        ));
    }

    #[test]
    fn block_decoder_is_bounded_before_allocating_and_rejects_trailing_data() {
        let config = PowGenesisConfigV2::local_regtest();
        let block = candidate(vec![coinbase(&config, 1, 0), transfer(&config, 1)]);
        let bytes = block.encode().expect("block bytes");
        assert_eq!(
            BlockV2::decode_with_config(&bytes, &config).expect("decode"),
            block
        );
        assert_eq!(
            borsh::from_slice::<BlockV2>(&bytes).expect("bounded Borsh decode"),
            block
        );

        let mut trailing = bytes.clone();
        trailing.push(0);
        assert!(BlockV2::decode_with_config(&trailing, &config).is_err());
        assert!(matches!(
            BlockV2::decode(
                &bytes,
                u32::try_from(bytes.len() - 1).expect("small block"),
                10
            ),
            Err(Error::BlockTooLarge { .. })
        ));

        let mut count_bomb = block.header.encode().expect("header");
        count_bomb.extend_from_slice(&u32::MAX.to_le_bytes());
        assert!(matches!(
            BlockV2::decode(&count_bomb, 1_024, 10),
            Err(Error::TooManyTransactions { .. })
        ));

        let mut borsh_count_bomb = block.header.encode().expect("header");
        borsh_count_bomb.extend_from_slice(&(MAX_BORSH_TRANSACTIONS_V2 + 1).to_le_bytes());
        assert!(borsh::from_slice::<BlockV2>(&borsh_count_bomb).is_err());

        let mut impossible_count = block.header.encode().expect("header");
        impossible_count.extend_from_slice(&1_u32.to_le_bytes());
        assert!(BlockV2::decode(&impossible_count, 1_024, 10).is_err());

        let mut unknown_discriminant = block.header.encode().expect("header");
        unknown_discriminant.extend_from_slice(&1_u32.to_le_bytes());
        unknown_discriminant.push(2);
        unknown_discriminant.resize(EMPTY_BLOCK_V2_SIZE + MIN_TRANSACTION_V2_SIZE, 0);
        assert!(BlockV2::decode(&unknown_discriminant, 1_024, 10).is_err());
    }

    #[test]
    fn genesis_constructor_and_special_rules_are_exact() {
        let config = PowGenesisConfigV2::local_regtest();
        let block =
            BlockV2::genesis(&config, Hash256::from_bytes([0x55; 32])).expect("genesis block");
        assert_eq!(block.header.pow_algorithm, GENESIS_POW_ALGORITHM_ID_V2);
        assert_eq!(block.header.target, Target256::ZERO);
        assert_eq!(block.header.nonce, 0);
        assert_eq!(block.header.parent_block_id, Hash256::ZERO);
        assert!(block.transactions.is_empty());
        block.verify_genesis(&config).expect("valid genesis");

        let mut nonempty = block.clone();
        nonempty.transactions.push(coinbase(&config, 0, 0));
        assert!(matches!(
            nonempty.verify_genesis(&config),
            Err(Error::GenesisMismatch)
        ));
        let mut nonzero_nonce = block;
        nonzero_nonce.header.nonce = 1;
        assert!(matches!(
            nonzero_nonce.verify_genesis(&config),
            Err(Error::GenesisMismatch)
        ));
    }

    #[test]
    fn body_rules_enforce_coinbase_position_unique_intent_and_merkle_witnesses() {
        let config = PowGenesisConfigV2::local_regtest();
        let coinbase = coinbase(&config, 1, 0);
        let transfer = transfer(&config, 1);
        let block = candidate(vec![coinbase.clone(), transfer.clone()]);
        block.verify_body(&config).expect("valid body");

        let root = block.header.transaction_root;
        assert_ne!(
            root,
            transaction_root_v2(&[transfer.clone(), coinbase.clone()]).expect("reordered root")
        );

        let duplicate = vec![coinbase.clone(), transfer.clone(), transfer.clone()];
        let mut duplicate_block = block.clone();
        duplicate_block.transactions = duplicate;
        duplicate_block.header.transaction_root =
            transaction_root_v2(&duplicate_block.transactions).expect("duplicate root");
        assert!(matches!(
            duplicate_block.verify_body(&config),
            Err(Error::DuplicateTransaction(_))
        ));

        let mut second_coinbase = block.clone();
        second_coinbase.transactions.push(coinbase.clone());
        second_coinbase.header.transaction_root =
            transaction_root_v2(&second_coinbase.transactions).expect("root");
        assert!(matches!(
            second_coinbase.verify_body(&config),
            Err(Error::InvalidCoinbase(_))
        ));

        let mut transfer_first = block.clone();
        transfer_first.transactions = vec![transfer, coinbase];
        transfer_first.header.transaction_root =
            transaction_root_v2(&transfer_first.transactions).expect("root");
        assert!(matches!(
            transfer_first.verify_body(&config),
            Err(Error::InvalidCoinbase(_))
        ));

        let mut bad_root = block;
        bad_root.header.transaction_root = Hash256::ZERO;
        assert!(matches!(
            bad_root.verify_body(&config),
            Err(Error::TransactionRootMismatch)
        ));
    }

    #[test]
    fn odd_merkle_leaf_is_duplicated_and_witness_mutations_change_root() {
        let config = PowGenesisConfigV2::local_regtest();
        let one = coinbase(&config, 1, 0);
        let two = transfer(&config, 1);
        let three = transfer(&config, 2);
        let three_root = transaction_root_v2(&[one.clone(), two.clone(), three.clone()])
            .expect("three-leaf root");

        let witness_ids = [
            one.witness_id().expect("one"),
            two.witness_id().expect("two"),
            three.witness_id().expect("three"),
        ];
        let leaf0 = hash_tagged("merkle/leaf/v2", &[witness_ids[0].as_bytes()]);
        let leaf1 = hash_tagged("merkle/leaf/v2", &[witness_ids[1].as_bytes()]);
        let leaf2 = hash_tagged("merkle/leaf/v2", &[witness_ids[2].as_bytes()]);
        let left = hash_tagged("merkle/node/v2", &[leaf0.as_bytes(), leaf1.as_bytes()]);
        let right = hash_tagged("merkle/node/v2", &[leaf2.as_bytes(), leaf2.as_bytes()]);
        assert_eq!(
            three_root,
            hash_tagged("merkle/node/v2", &[left.as_bytes(), right.as_bytes()])
        );

        let mut altered = three;
        let TransactionV2::Transfer(transfer) = &mut altered else {
            unreachable!("fixture is a transfer")
        };
        transfer.signature[0] ^= 1;
        assert_ne!(
            transaction_root_v2(&[one, two, altered]).expect("altered root"),
            three_root
        );
    }

    #[test]
    fn golden_header_hex_id_and_work_message_are_stable() {
        let header = BlockHeaderV2 {
            version: BLOCK_VERSION_V2,
            pow_algorithm: ARGON2D_POW_ALGORITHM_ID_V2,
            network: Network::Devnet,
            chain_id_hash: Hash256::from_bytes([0x11; 32]),
            height: 0x0102_0304_0506_0708,
            parent_block_id: Hash256::from_bytes([0x22; 32]),
            timestamp_seconds: 0x1112_1314_1516_1718,
            transaction_root: Hash256::from_bytes([0x33; 32]),
            state_root: Hash256::from_bytes([0x44; 32]),
            target: Target256::from_be_bytes([
                0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d,
                0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b,
                0x1c, 0x1d, 0x1e, 0x1f,
            ]),
            nonce: 0x2122_2324_2526_2728_292a_2b2c_2d2e_2f30,
        };
        assert_eq!(
            hex::encode(header.encode().expect("header bytes")),
            golden_header_hex()
        );
        assert_eq!(
            header.id().expect("block ID").to_string(),
            golden_block_id()
        );
        assert_eq!(
            header.work_message().expect("work message").to_string(),
            golden_work_message()
        );
    }

    fn golden_header_hex() -> &'static str {
        "0200010003525541111111111111111111111111111111111111111111111111111111111111111108070605040302012222222222222222222222222222222222222222222222222222222222222222181716151413121133333333333333333333333333333333333333333333333333333333333333334444444444444444444444444444444444444444444444444444444444444444000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f302f2e2d2c2b2a292827262524232221"
    }

    fn golden_block_id() -> &'static str {
        "efc531fcf1e02f76beb8d265f2d994f3813c5c342605bbcd8e96adcdfd2e4902"
    }

    fn golden_work_message() -> &'static str {
        "97d0f5b59c8d5f549144b57ddff04641eb7da3416ac5ce207bddc87e9f229e53"
    }
}
