//! Canonical Aura `PoW` Devnet v2 transaction primitives.

use crate::{hash_tagged, Address, Amount, Error, Hash256, Network, Result};
use borsh::{BorshDeserialize, BorshSerialize};
use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};
use std::io::{Read, Write};

/// Frozen transaction format version for Aura `PoW` Devnet v2.
pub const TRANSACTION_VERSION_V2: u16 = 2;
/// Canonical enum discriminant for a coinbase transaction.
pub const COINBASE_DISCRIMINANT_V2: u8 = 0;
/// Canonical enum discriminant for a signed transfer transaction.
pub const TRANSFER_DISCRIMINANT_V2: u8 = 1;
/// Canonical enum discriminant for an owner-authorized purchase-proof transaction.
pub const PURCHASE_PROOF_DISCRIMINANT_V2: u8 = 2;
/// Canonical proof-claim format version.
pub const PURCHASE_PROOF_VERSION_V2: u16 = 1;
/// Closed proof-type value for a purchase.
pub const PURCHASE_PROOF_TYPE_V2: u8 = 1;
pub const VERIFICATION_LEVEL_DOCUMENT_V2: u8 = 2;
pub const VERIFICATION_LEVEL_TRANSACTION_V2: u8 = 3;
pub const VERIFICATION_LEVEL_MERCHANT_SIGNED_V2: u8 = 4;

/// Encoded bytes in a coinbase payload, excluding its enum discriminant.
pub const COINBASE_V2_PAYLOAD_SIZE: usize = 86;
/// Encoded bytes in a signed-transfer payload, excluding its enum discriminant.
pub const SIGNED_TRANSFER_V2_PAYLOAD_SIZE: usize = 214;
/// Encoded bytes in a signed purchase-proof payload, excluding its enum discriminant.
pub const SIGNED_PURCHASE_PROOF_V2_PAYLOAD_SIZE: usize = 480;
/// Smallest canonical encoded v2 transaction, including its enum discriminant.
pub const MIN_TRANSACTION_V2_SIZE: usize = 1 + COINBASE_V2_PAYLOAD_SIZE;
/// Largest canonical encoded v2 transaction, including its enum discriminant.
pub const MAX_TRANSACTION_V2_SIZE: usize = 1 + SIGNED_PURCHASE_PROOF_V2_PAYLOAD_SIZE;

/// Fields authorized by an Aura `PoW` Devnet v2 transfer signature.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct TransactionBodyV2 {
    /// Transaction encoding and validation version.
    pub version: u16,
    /// Network namespace, canonically encoded as its fixed `u32` network ID.
    pub network: Network,
    /// Domain hash of the textual v2 chain ID.
    pub chain_id_hash: Hash256,
    /// Account spending AUR.
    pub sender: Address,
    /// Account receiving AUR.
    pub recipient: Address,
    /// Atomic AUR units transferred.
    pub amount: Amount,
    /// Atomic AUR units paid to the block miner.
    pub fee: Amount,
    /// Exactly the sender's previous committed nonce plus one.
    pub nonce: u64,
    /// Last admissible block height; zero means no expiry.
    pub valid_until_height: u64,
}

impl TransactionBodyV2 {
    /// Returns the exact Borsh-compatible body bytes authorized by Ed25519.
    pub fn encode(&self) -> Result<Vec<u8>> {
        encode_value(self, "v2 transaction body")
    }

    /// Strictly decodes one body and rejects unknown versions or trailing bytes.
    pub fn decode(bytes: &[u8]) -> Result<Self> {
        let body: Self = decode_value(bytes, "v2 transaction body")?;
        body.validate_version()?;
        Ok(body)
    }

    /// Returns the domain-separated digest signed by a transfer witness.
    pub fn signing_hash(&self) -> Result<Hash256> {
        let bytes = self.encode()?;
        Ok(hash_tagged("transaction/signing/v2", &[&bytes]))
    }

    fn validate_version(&self) -> Result<()> {
        if self.version != TRANSACTION_VERSION_V2 {
            return Err(Error::UnsupportedProtocol {
                expected: TRANSACTION_VERSION_V2,
                actual: self.version,
            });
        }
        Ok(())
    }

    pub(crate) fn validate_identity(
        &self,
        expected_network: Network,
        expected_chain_id_hash: Hash256,
    ) -> Result<()> {
        self.validate_version()?;
        if self.network != expected_network {
            return Err(Error::NetworkMismatch {
                expected: expected_network,
                actual: self.network,
            });
        }
        if self.chain_id_hash != expected_chain_id_hash {
            return Err(Error::ChainIdMismatch);
        }
        for address in [self.sender, self.recipient] {
            if address.network() != expected_network {
                return Err(Error::AddressNetworkMismatch {
                    expected: expected_network,
                    actual: address.network(),
                });
            }
        }
        Ok(())
    }
}

/// A canonical Aura `PoW` Devnet v2 transfer signed with Ed25519.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct SignedTransferV2 {
    /// Signed transfer fields.
    pub body: TransactionBodyV2,
    /// Raw Ed25519 verifying key.
    pub public_key: [u8; 32],
    /// Raw Ed25519 signature over [`TransactionBodyV2::signing_hash`].
    pub signature: [u8; 64],
}

impl SignedTransferV2 {
    /// Signs the exact v2 body digest with an Ed25519 key.
    pub fn sign(body: TransactionBodyV2, signing_key: &SigningKey) -> Result<Self> {
        let public_key = signing_key.verifying_key().to_bytes();
        let signature = signing_key.sign(body.signing_hash()?.as_bytes()).to_bytes();
        Ok(Self {
            body,
            public_key,
            signature,
        })
    }

    /// Returns the exact payload bytes, excluding the enclosing enum discriminant.
    pub fn encode(&self) -> Result<Vec<u8>> {
        encode_value(self, "v2 signed transfer")
    }

    /// Strictly decodes one transfer payload with a byte limit.
    pub fn decode(bytes: &[u8], maximum_size: u32) -> Result<Self> {
        enforce_transaction_size(bytes.len(), maximum_size)?;
        let transfer: Self = decode_value(bytes, "v2 signed transfer")?;
        transfer.body.validate_version()?;
        Ok(transfer)
    }

    /// Returns the domain-separated digest authorized by the signature.
    pub fn signing_hash(&self) -> Result<Hash256> {
        self.body.signing_hash()
    }

    /// Identifies the authorized intent while deliberately excluding the signature witness.
    pub fn intent_id(&self) -> Result<Hash256> {
        let mut bytes = self.body.encode()?;
        bytes.extend_from_slice(&self.public_key);
        Ok(hash_tagged("transaction/id/v2", &[&bytes]))
    }

    /// Commits the canonical enum discriminant and every transfer field, including signature.
    pub fn witness_id(&self) -> Result<Hash256> {
        let bytes = encode_transaction_variant(TRANSFER_DISCRIMINANT_V2, self)?;
        Ok(hash_tagged("transaction/witness/v2", &[&bytes]))
    }

    /// Performs context-independent checks, chain-identity checks, and strict Ed25519 verification.
    ///
    /// Exact next-nonce and sufficient-balance checks require parent state and remain execution
    /// rules. Call [`Self::verify_with_expected_nonce`] when the next nonce is already known.
    pub fn verify(
        &self,
        expected_network: Network,
        expected_chain_id_hash: Hash256,
        minimum_fee: Amount,
        candidate_height: u64,
        maximum_size: u32,
    ) -> Result<()> {
        self.body
            .validate_identity(expected_network, expected_chain_id_hash)?;
        if self.body.sender == self.body.recipient {
            return Err(Error::SelfTransfer);
        }
        if self.body.amount == Amount::ZERO {
            return Err(Error::ZeroAmount);
        }
        if self.body.fee < minimum_fee {
            return Err(Error::FeeTooLow {
                minimum: minimum_fee.atoms(),
                actual: self.body.fee.atoms(),
            });
        }
        if self.body.nonce == 0 {
            return Err(Error::InvalidNonce {
                expected: 1,
                actual: 0,
            });
        }
        if self.body.valid_until_height != 0 && candidate_height > self.body.valid_until_height {
            return Err(Error::TransactionExpired {
                expires: self.body.valid_until_height,
                height: candidate_height,
            });
        }
        // A debit that cannot fit in the frozen u64 amount type can never execute.
        self.body.amount.checked_add(self.body.fee)?;
        let encoded_size = 1_usize
            .checked_add(self.encode()?.len())
            .ok_or(Error::AmountOverflow)?;
        if encoded_size > maximum_size as usize {
            return Err(Error::TransactionTooLarge);
        }

        let verifying_key =
            VerifyingKey::from_bytes(&self.public_key).map_err(|_| Error::InvalidPublicKey)?;
        let derived = Address::from_public_key(expected_network, &self.public_key);
        if derived != self.body.sender {
            return Err(Error::SenderKeyMismatch);
        }
        let signature = Signature::from_bytes(&self.signature);
        verifying_key
            .verify_strict(self.signing_hash()?.as_bytes(), &signature)
            .map_err(|_| Error::InvalidSignature)
    }

    /// Verifies the transfer and enforces the exact next nonce supplied by the state executor.
    pub fn verify_with_expected_nonce(
        &self,
        expected_network: Network,
        expected_chain_id_hash: Hash256,
        minimum_fee: Amount,
        candidate_height: u64,
        maximum_size: u32,
        expected_nonce: u64,
    ) -> Result<()> {
        self.verify(
            expected_network,
            expected_chain_id_hash,
            minimum_fee,
            candidate_height,
            maximum_size,
        )?;
        if self.body.nonce != expected_nonce {
            return Err(Error::InvalidNonce {
                expected: expected_nonce,
                actual: self.body.nonce,
            });
        }
        Ok(())
    }
}

/// Privacy-safe claim attested by an authorized Devnet verifier.
///
/// Raw receipt bytes, merchant text, line items, exact location, and provider response data are
/// deliberately absent. The commitments and nullifier are opaque 32-byte values constructed in
/// the private verifier boundary.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct PurchaseProofClaimV2 {
    pub version: u16,
    pub network: Network,
    pub chain_id_hash: Hash256,
    pub proof_type: u8,
    pub owner: Address,
    pub subject_commitment: Hash256,
    pub business_commitment: Hash256,
    pub product_commitment: Hash256,
    pub location_commitment: Hash256,
    pub receipt_nullifier: Hash256,
    pub verification_level: u8,
    pub provider_attestation_hash: Hash256,
    pub timestamp_seconds: u64,
    pub verifier_public_key: [u8; 32],
}

impl PurchaseProofClaimV2 {
    pub fn encode(&self) -> Result<Vec<u8>> {
        encode_value(self, "v2 purchase-proof claim")
    }

    pub fn signing_hash(&self) -> Result<Hash256> {
        Ok(hash_tagged(
            "proof/purchase/verifier-signing/v1",
            &[&self.encode()?],
        ))
    }

    pub fn proof_id(&self) -> Result<Hash256> {
        Ok(hash_tagged("proof/purchase/id/v1", &[&self.encode()?]))
    }

    fn validate(
        &self,
        config: &crate::PowGenesisConfigV2,
        candidate_timestamp_seconds: u64,
    ) -> Result<()> {
        if self.version != PURCHASE_PROOF_VERSION_V2 || self.proof_type != PURCHASE_PROOF_TYPE_V2 {
            return Err(Error::InvalidPurchaseProof(
                "unsupported proof version or proof type".into(),
            ));
        }
        if self.network != config.network {
            return Err(Error::NetworkMismatch {
                expected: config.network,
                actual: self.network,
            });
        }
        if self.chain_id_hash != config.consensus_identity_hash()? {
            return Err(Error::ChainIdMismatch);
        }
        if self.owner.network() != config.network {
            return Err(Error::AddressNetworkMismatch {
                expected: config.network,
                actual: self.owner.network(),
            });
        }
        if self.subject_commitment == Hash256::ZERO
            || self.business_commitment == Hash256::ZERO
            || self.receipt_nullifier == Hash256::ZERO
            || self.provider_attestation_hash == Hash256::ZERO
        {
            return Err(Error::InvalidPurchaseProof(
                "required proof commitments must be nonzero".into(),
            ));
        }
        if self.verification_level < config.purchase_proofs.minimum_verification_level
            || self.verification_level > VERIFICATION_LEVEL_MERCHANT_SIGNED_V2
        {
            return Err(Error::InvalidPurchaseProof(
                "verification level is not accepted by this chain".into(),
            ));
        }
        if self.timestamp_seconds == 0 || self.timestamp_seconds > candidate_timestamp_seconds {
            return Err(Error::InvalidPurchaseProof(
                "proof timestamp is zero or later than its candidate block".into(),
            ));
        }
        if candidate_timestamp_seconds.saturating_sub(self.timestamp_seconds)
            > config.purchase_proofs.maximum_age_seconds
        {
            return Err(Error::InvalidPurchaseProof(
                "proof is older than the configured inclusion window".into(),
            ));
        }
        if config
            .purchase_proofs
            .authorized_verifiers
            .binary_search(&self.verifier_public_key)
            .is_err()
        {
            return Err(Error::UnauthorizedProofVerifier);
        }
        Ok(())
    }
}

/// Verifier witness over a privacy-safe purchase claim.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct AttestedPurchaseProofV2 {
    pub claim: PurchaseProofClaimV2,
    pub verifier_signature: [u8; 64],
}

impl AttestedPurchaseProofV2 {
    pub fn attest(claim: PurchaseProofClaimV2, signing_key: &SigningKey) -> Result<Self> {
        if signing_key.verifying_key().to_bytes() != claim.verifier_public_key {
            return Err(Error::InvalidVerifierSignature);
        }
        let verifier_signature = signing_key
            .sign(claim.signing_hash()?.as_bytes())
            .to_bytes();
        Ok(Self {
            claim,
            verifier_signature,
        })
    }

    /// Strictly decodes one verifier attestation and rejects trailing bytes.
    pub fn decode(bytes: &[u8]) -> Result<Self> {
        decode_value(bytes, "v2 attested purchase proof")
    }

    fn verify(
        &self,
        config: &crate::PowGenesisConfigV2,
        candidate_timestamp_seconds: u64,
    ) -> Result<()> {
        self.claim.validate(config, candidate_timestamp_seconds)?;
        let key = VerifyingKey::from_bytes(&self.claim.verifier_public_key)
            .map_err(|_| Error::InvalidVerifierSignature)?;
        let signature = Signature::from_bytes(&self.verifier_signature);
        key.verify_strict(self.claim.signing_hash()?.as_bytes(), &signature)
            .map_err(|_| Error::InvalidVerifierSignature)
    }
}

/// Fee, replay protection, and verifier envelope authorized by the proof owner's wallet.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct PurchaseProofBodyV2 {
    pub attested_proof: AttestedPurchaseProofV2,
    pub fee: Amount,
    pub nonce: u64,
    pub valid_until_height: u64,
}

impl PurchaseProofBodyV2 {
    pub fn encode(&self) -> Result<Vec<u8>> {
        encode_value(self, "v2 purchase-proof transaction body")
    }

    pub fn signing_hash(&self) -> Result<Hash256> {
        Ok(hash_tagged(
            "transaction/proof/signing/v2",
            &[&self.encode()?],
        ))
    }

    /// Strictly decodes one owner-signing body and rejects trailing bytes.
    pub fn decode(bytes: &[u8]) -> Result<Self> {
        decode_value(bytes, "v2 purchase-proof transaction body")
    }
}

/// A verifier-attested purchase proof authorized by the owner wallet.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct SignedPurchaseProofV2 {
    pub body: PurchaseProofBodyV2,
    pub owner_public_key: [u8; 32],
    pub owner_signature: [u8; 64],
}

impl SignedPurchaseProofV2 {
    pub fn sign(body: PurchaseProofBodyV2, signing_key: &SigningKey) -> Result<Self> {
        let owner_public_key = signing_key.verifying_key().to_bytes();
        if Address::from_public_key(body.attested_proof.claim.network, &owner_public_key)
            != body.attested_proof.claim.owner
        {
            return Err(Error::SenderKeyMismatch);
        }
        let owner_signature = signing_key.sign(body.signing_hash()?.as_bytes()).to_bytes();
        Ok(Self {
            body,
            owner_public_key,
            owner_signature,
        })
    }

    pub fn encode(&self) -> Result<Vec<u8>> {
        encode_value(self, "v2 signed purchase proof")
    }

    pub fn proof_id(&self) -> Result<Hash256> {
        self.body.attested_proof.claim.proof_id()
    }

    pub fn intent_id(&self) -> Result<Hash256> {
        let mut bytes = self.body.encode()?;
        bytes.extend_from_slice(&self.owner_public_key);
        Ok(hash_tagged("transaction/proof/id/v2", &[&bytes]))
    }

    pub fn witness_id(&self) -> Result<Hash256> {
        let bytes = encode_transaction_variant(PURCHASE_PROOF_DISCRIMINANT_V2, self)?;
        Ok(hash_tagged("transaction/proof/witness/v2", &[&bytes]))
    }

    #[must_use]
    pub const fn owner(&self) -> Address {
        self.body.attested_proof.claim.owner
    }

    #[must_use]
    pub fn receipt_nullifier(&self) -> Hash256 {
        self.body.attested_proof.claim.receipt_nullifier
    }

    pub fn verify(
        &self,
        config: &crate::PowGenesisConfigV2,
        candidate_height: u64,
        candidate_timestamp_seconds: u64,
    ) -> Result<()> {
        if !config.purchase_proofs.enabled {
            return Err(Error::InvalidPurchaseProof(
                "purchase proofs are disabled".into(),
            ));
        }
        self.body
            .attested_proof
            .verify(config, candidate_timestamp_seconds)?;
        if self.body.fee < config.limits.minimum_fee {
            return Err(Error::FeeTooLow {
                minimum: config.limits.minimum_fee.atoms(),
                actual: self.body.fee.atoms(),
            });
        }
        if self.body.nonce == 0 {
            return Err(Error::InvalidNonce {
                expected: 1,
                actual: 0,
            });
        }
        if self.body.valid_until_height != 0 && candidate_height > self.body.valid_until_height {
            return Err(Error::TransactionExpired {
                expires: self.body.valid_until_height,
                height: candidate_height,
            });
        }
        let encoded_size = 1_usize
            .checked_add(self.encode()?.len())
            .ok_or(Error::AmountOverflow)?;
        if encoded_size > config.limits.maximum_transaction_bytes as usize {
            return Err(Error::TransactionTooLarge);
        }
        let key = VerifyingKey::from_bytes(&self.owner_public_key)
            .map_err(|_| Error::InvalidPublicKey)?;
        if Address::from_public_key(config.network, &self.owner_public_key) != self.owner() {
            return Err(Error::SenderKeyMismatch);
        }
        let signature = Signature::from_bytes(&self.owner_signature);
        key.verify_strict(self.body.signing_hash()?.as_bytes(), &signature)
            .map_err(|_| Error::InvalidSignature)
    }
}

/// The sole issuance transaction permitted at position zero of a non-genesis block.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct CoinbaseV2 {
    /// Transaction encoding and validation version.
    pub version: u16,
    /// Network namespace, canonically encoded as its fixed `u32` network ID.
    pub network: Network,
    /// Domain hash of the textual v2 chain ID.
    pub chain_id_hash: Hash256,
    /// Height of the block containing this coinbase.
    pub height: u64,
    /// Miner account receiving the exact subsidy-plus-fee payout.
    pub recipient: Address,
    /// Atomic AUR units paid by this coinbase.
    pub payout: Amount,
    /// Miner-controlled commitment coordinate independent of the header nonce.
    pub extra_nonce: u64,
}

impl CoinbaseV2 {
    /// Returns the exact payload bytes, excluding the enclosing enum discriminant.
    pub fn encode(&self) -> Result<Vec<u8>> {
        encode_value(self, "v2 coinbase")
    }

    /// Strictly decodes one coinbase payload with a byte limit.
    pub fn decode(bytes: &[u8], maximum_size: u32) -> Result<Self> {
        enforce_transaction_size(bytes.len(), maximum_size)?;
        let coinbase: Self = decode_value(bytes, "v2 coinbase")?;
        coinbase.validate_version()?;
        Ok(coinbase)
    }

    /// Commits the canonical enum discriminant and every coinbase field.
    pub fn witness_id(&self) -> Result<Hash256> {
        let bytes = encode_transaction_variant(COINBASE_DISCRIMINANT_V2, self)?;
        Ok(hash_tagged("coinbase/witness/v2", &[&bytes]))
    }

    /// Checks the context fields that bind this coinbase to one block and chain.
    pub fn verify_identity(
        &self,
        expected_network: Network,
        expected_chain_id_hash: Hash256,
        expected_height: u64,
    ) -> Result<()> {
        self.validate_version()?;
        if self.network != expected_network {
            return Err(Error::NetworkMismatch {
                expected: expected_network,
                actual: self.network,
            });
        }
        if self.chain_id_hash != expected_chain_id_hash {
            return Err(Error::ChainIdMismatch);
        }
        if self.height != expected_height {
            return Err(Error::InvalidHeight {
                expected: expected_height,
                actual: self.height,
            });
        }
        if self.recipient.network() != expected_network {
            return Err(Error::AddressNetworkMismatch {
                expected: expected_network,
                actual: self.recipient.network(),
            });
        }
        Ok(())
    }

    fn validate_version(&self) -> Result<()> {
        if self.version != TRANSACTION_VERSION_V2 {
            return Err(Error::UnsupportedProtocol {
                expected: TRANSACTION_VERSION_V2,
                actual: self.version,
            });
        }
        Ok(())
    }
}

/// Explicitly discriminated Aura `PoW` Devnet v2 transaction.
#[derive(Clone, Debug, PartialEq, Eq)]
// Boxing this consensus value would spread allocation/fallibility through every hostile parser
// and validation path. Its fixed bounded size is intentional and covered by canonical vectors.
#[allow(clippy::large_enum_variant)]
pub enum TransactionV2 {
    /// Block issuance and fee payout. Canonical discriminant `0`.
    Coinbase(CoinbaseV2),
    /// Ed25519-authorized account transfer. Canonical discriminant `1`.
    Transfer(SignedTransferV2),
    /// Verifier-attested and owner-authorized privacy-safe purchase proof. Discriminant `2`.
    PurchaseProof(SignedPurchaseProofV2),
}

impl TransactionV2 {
    /// Returns the frozen one-byte canonical discriminant.
    #[must_use]
    pub const fn discriminant(&self) -> u8 {
        match self {
            Self::Coinbase(_) => COINBASE_DISCRIMINANT_V2,
            Self::Transfer(_) => TRANSFER_DISCRIMINANT_V2,
            Self::PurchaseProof(_) => PURCHASE_PROOF_DISCRIMINANT_V2,
        }
    }

    /// Returns the exact canonical enum bytes.
    pub fn encode(&self) -> Result<Vec<u8>> {
        encode_value(self, "v2 transaction")
    }

    /// Strictly decodes one bounded transaction and rejects trailing bytes.
    pub fn decode(bytes: &[u8], maximum_size: u32) -> Result<Self> {
        enforce_transaction_size(bytes.len(), maximum_size)?;
        let transaction: Self = decode_value(bytes, "v2 transaction")?;
        transaction.validate_version()?;
        Ok(transaction)
    }

    /// Returns the canonical encoded byte length.
    pub fn encoded_size(&self) -> Result<usize> {
        self.encode().map(|bytes| bytes.len())
    }

    /// Returns the non-coinbase transaction ID, or `None` for a coinbase.
    pub fn intent_id(&self) -> Result<Option<Hash256>> {
        match self {
            Self::Coinbase(_) => Ok(None),
            Self::Transfer(transfer) => transfer.intent_id().map(Some),
            Self::PurchaseProof(proof) => proof.intent_id().map(Some),
        }
    }

    /// Returns the exact-witness commitment used by the block Merkle tree.
    pub fn witness_id(&self) -> Result<Hash256> {
        match self {
            Self::Coinbase(coinbase) => coinbase.witness_id(),
            Self::Transfer(transfer) => transfer.witness_id(),
            Self::PurchaseProof(proof) => proof.witness_id(),
        }
    }

    /// Returns the coinbase payload when this is the coinbase variant.
    #[must_use]
    pub const fn as_coinbase(&self) -> Option<&CoinbaseV2> {
        match self {
            Self::Coinbase(coinbase) => Some(coinbase),
            Self::Transfer(_) | Self::PurchaseProof(_) => None,
        }
    }

    /// Returns the signed transfer when this is the transfer variant.
    #[must_use]
    pub const fn as_transfer(&self) -> Option<&SignedTransferV2> {
        match self {
            Self::Transfer(transfer) => Some(transfer),
            Self::Coinbase(_) | Self::PurchaseProof(_) => None,
        }
    }

    #[must_use]
    pub const fn as_purchase_proof(&self) -> Option<&SignedPurchaseProofV2> {
        match self {
            Self::PurchaseProof(proof) => Some(proof),
            Self::Coinbase(_) | Self::Transfer(_) => None,
        }
    }

    #[must_use]
    pub const fn sender(&self) -> Option<Address> {
        match self {
            Self::Coinbase(_) => None,
            Self::Transfer(transfer) => Some(transfer.body.sender),
            Self::PurchaseProof(proof) => Some(proof.owner()),
        }
    }

    #[must_use]
    pub const fn nonce(&self) -> Option<u64> {
        match self {
            Self::Coinbase(_) => None,
            Self::Transfer(transfer) => Some(transfer.body.nonce),
            Self::PurchaseProof(proof) => Some(proof.body.nonce),
        }
    }

    #[must_use]
    pub const fn fee(&self) -> Option<Amount> {
        match self {
            Self::Coinbase(_) => None,
            Self::Transfer(transfer) => Some(transfer.body.fee),
            Self::PurchaseProof(proof) => Some(proof.body.fee),
        }
    }

    /// Total amount removed from the sender before the miner receives the fee.
    pub fn debit(&self) -> Result<Option<Amount>> {
        match self {
            Self::Coinbase(_) => Ok(None),
            Self::Transfer(transfer) => transfer
                .body
                .amount
                .checked_add(transfer.body.fee)
                .map(Some),
            Self::PurchaseProof(proof) => Ok(Some(proof.body.fee)),
        }
    }

    /// Performs all context-independent and candidate-context checks for a non-coinbase
    /// transaction. Exact shared account nonce and balance checks remain state rules.
    pub fn verify_non_coinbase(
        &self,
        config: &crate::PowGenesisConfigV2,
        candidate_height: u64,
        candidate_timestamp_seconds: u64,
    ) -> Result<()> {
        match self {
            Self::Coinbase(_) => Err(Error::InvalidCoinbase(
                "coinbase cannot enter transaction gossip or mempool".into(),
            )),
            Self::Transfer(transfer) => transfer.verify(
                config.network,
                config.consensus_identity_hash()?,
                config.limits.minimum_fee,
                candidate_height,
                config.limits.maximum_transaction_bytes,
            ),
            Self::PurchaseProof(proof) => {
                proof.verify(config, candidate_height, candidate_timestamp_seconds)
            }
        }
    }

    pub(crate) fn validate_version(&self) -> Result<()> {
        match self {
            Self::Coinbase(coinbase) => coinbase.validate_version(),
            Self::Transfer(transfer) => transfer.body.validate_version(),
            Self::PurchaseProof(proof) => {
                if proof.body.attested_proof.claim.version == PURCHASE_PROOF_VERSION_V2 {
                    Ok(())
                } else {
                    Err(Error::UnsupportedProtocol {
                        expected: PURCHASE_PROOF_VERSION_V2,
                        actual: proof.body.attested_proof.claim.version,
                    })
                }
            }
        }
    }
}

impl From<SignedTransferV2> for TransactionV2 {
    fn from(value: SignedTransferV2) -> Self {
        Self::Transfer(value)
    }
}

impl From<SignedPurchaseProofV2> for TransactionV2 {
    fn from(value: SignedPurchaseProofV2) -> Self {
        Self::PurchaseProof(value)
    }
}

impl BorshSerialize for TransactionV2 {
    fn serialize<W: Write>(&self, writer: &mut W) -> std::io::Result<()> {
        BorshSerialize::serialize(&self.discriminant(), writer)?;
        match self {
            Self::Coinbase(coinbase) => BorshSerialize::serialize(coinbase, writer),
            Self::Transfer(transfer) => BorshSerialize::serialize(transfer, writer),
            Self::PurchaseProof(proof) => BorshSerialize::serialize(proof, writer),
        }
    }
}

impl BorshDeserialize for TransactionV2 {
    fn deserialize_reader<R: Read>(reader: &mut R) -> std::io::Result<Self> {
        let discriminant = <u8 as BorshDeserialize>::deserialize_reader(reader)?;
        match discriminant {
            COINBASE_DISCRIMINANT_V2 => CoinbaseV2::deserialize_reader(reader).map(Self::Coinbase),
            TRANSFER_DISCRIMINANT_V2 => {
                SignedTransferV2::deserialize_reader(reader).map(Self::Transfer)
            }
            PURCHASE_PROOF_DISCRIMINANT_V2 => {
                SignedPurchaseProofV2::deserialize_reader(reader).map(Self::PurchaseProof)
            }
            unknown => Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!("unknown v2 transaction discriminant {unknown}"),
            )),
        }
    }
}

fn encode_transaction_variant<T: BorshSerialize>(discriminant: u8, value: &T) -> Result<Vec<u8>> {
    let mut bytes = Vec::new();
    BorshSerialize::serialize(&discriminant, &mut bytes).map_err(|error| {
        Error::Serialization(format!(
            "v2 transaction discriminant encoding failed: {error}"
        ))
    })?;
    BorshSerialize::serialize(value, &mut bytes).map_err(|error| {
        Error::Serialization(format!("v2 transaction payload encoding failed: {error}"))
    })?;
    Ok(bytes)
}

fn encode_value<T: BorshSerialize>(value: &T, label: &str) -> Result<Vec<u8>> {
    borsh::to_vec(value)
        .map_err(|error| Error::Serialization(format!("{label} encoding failed: {error}")))
}

fn decode_value<T: BorshDeserialize>(bytes: &[u8], label: &str) -> Result<T> {
    T::try_from_slice(bytes)
        .map_err(|error| Error::Serialization(format!("{label} decoding failed: {error}")))
}

fn enforce_transaction_size(actual: usize, maximum: u32) -> Result<()> {
    if actual > maximum as usize {
        return Err(Error::TransactionTooLarge);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::PowGenesisConfigV2;

    fn transfer_fixture() -> SignedTransferV2 {
        let key = SigningKey::from_bytes(&[3; 32]);
        let network = Network::Devnet;
        SignedTransferV2::sign(
            TransactionBodyV2 {
                version: TRANSACTION_VERSION_V2,
                network,
                chain_id_hash: Hash256::from_bytes([0x11; 32]),
                sender: Address::from_public_key(network, &key.verifying_key().to_bytes()),
                recipient: Address::from_public_key(network, &[9; 32]),
                amount: Amount::from_atoms(0x0102_0304_0506_0708),
                fee: Amount::from_atoms(0x1112_1314_1516_1718),
                nonce: 0x2122_2324_2526_2728,
                valid_until_height: 0x3132_3334_3536_3738,
            },
            &key,
        )
        .expect("sign fixture")
    }

    fn coinbase_fixture() -> CoinbaseV2 {
        CoinbaseV2 {
            version: TRANSACTION_VERSION_V2,
            network: Network::Devnet,
            chain_id_hash: Hash256::from_bytes([0x22; 32]),
            height: 7,
            recipient: Address::from_public_key(Network::Devnet, &[8; 32]),
            payout: Amount::from_atoms(800_000_123),
            extra_nonce: 9,
        }
    }

    fn purchase_proof_fixture() -> (PowGenesisConfigV2, SignedPurchaseProofV2) {
        let config = PowGenesisConfigV2::local_regtest();
        let owner_key = SigningKey::from_bytes(&[7; 32]);
        let verifier_key = SigningKey::from_bytes(&[42; 32]);
        let owner = Address::from_public_key(config.network, &owner_key.verifying_key().to_bytes());
        let claim = PurchaseProofClaimV2 {
            version: PURCHASE_PROOF_VERSION_V2,
            network: config.network,
            chain_id_hash: config.consensus_identity_hash().expect("identity"),
            proof_type: PURCHASE_PROOF_TYPE_V2,
            owner,
            subject_commitment: Hash256::from_bytes([1; 32]),
            business_commitment: Hash256::from_bytes([2; 32]),
            product_commitment: Hash256::from_bytes([3; 32]),
            location_commitment: Hash256::from_bytes([4; 32]),
            receipt_nullifier: Hash256::from_bytes([5; 32]),
            verification_level: VERIFICATION_LEVEL_DOCUMENT_V2,
            provider_attestation_hash: Hash256::from_bytes([6; 32]),
            timestamp_seconds: config.genesis_time_seconds.saturating_add(1),
            verifier_public_key: verifier_key.verifying_key().to_bytes(),
        };
        let attested = AttestedPurchaseProofV2::attest(claim, &verifier_key).expect("attest");
        let proof = SignedPurchaseProofV2::sign(
            PurchaseProofBodyV2 {
                attested_proof: attested,
                fee: config.limits.minimum_fee,
                nonce: 1,
                valid_until_height: 100,
            },
            &owner_key,
        )
        .expect("owner sign");
        (config, proof)
    }

    #[test]
    fn fixed_payload_sizes_and_enum_discriminants_are_canonical() {
        let transfer = transfer_fixture();
        let coinbase = coinbase_fixture();
        assert_eq!(transfer.encode().expect("transfer bytes").len(), 214);
        assert_eq!(coinbase.encode().expect("coinbase bytes").len(), 86);

        let transfer_bytes = TransactionV2::Transfer(transfer)
            .encode()
            .expect("transfer enum");
        let coinbase_bytes = TransactionV2::Coinbase(coinbase)
            .encode()
            .expect("coinbase enum");
        assert_eq!(transfer_bytes.len(), 1 + SIGNED_TRANSFER_V2_PAYLOAD_SIZE);
        assert_eq!(coinbase_bytes.len(), MIN_TRANSACTION_V2_SIZE);
        assert_eq!(transfer_bytes[0], TRANSFER_DISCRIMINANT_V2);
        assert_eq!(coinbase_bytes[0], COINBASE_DISCRIMINANT_V2);

        let (_, proof) = purchase_proof_fixture();
        let proof_bytes = TransactionV2::PurchaseProof(proof.clone())
            .encode()
            .expect("proof enum");
        assert_eq!(
            proof.encode().expect("proof payload").len(),
            SIGNED_PURCHASE_PROOF_V2_PAYLOAD_SIZE
        );
        assert_eq!(proof_bytes.len(), MAX_TRANSACTION_V2_SIZE);
        assert_eq!(proof_bytes[0], PURCHASE_PROOF_DISCRIMINANT_V2);
    }

    #[test]
    fn purchase_proof_signatures_chain_identity_and_canonical_round_trip_are_enforced() {
        let (config, proof) = purchase_proof_fixture();
        proof
            .verify(&config, 1, config.genesis_time_seconds.saturating_add(1))
            .expect("valid proof");
        let transaction = TransactionV2::PurchaseProof(proof.clone());
        let bytes = transaction.encode().expect("encode");
        assert_eq!(
            TransactionV2::decode(&bytes, config.limits.maximum_transaction_bytes).expect("decode"),
            transaction
        );

        let mut invalid_verifier = proof.clone();
        invalid_verifier.body.attested_proof.verifier_signature[0] ^= 1;
        assert!(matches!(
            invalid_verifier.verify(&config, 1, config.genesis_time_seconds.saturating_add(1)),
            Err(Error::InvalidVerifierSignature)
        ));

        let owner_key = SigningKey::from_bytes(&[7; 32]);
        let verifier_key = SigningKey::from_bytes(&[42; 32]);
        let mut wrong_claim = proof.body.attested_proof.claim.clone();
        wrong_claim.chain_id_hash = Hash256::from_bytes([0x99; 32]);
        let wrong_attestation = AttestedPurchaseProofV2::attest(wrong_claim, &verifier_key)
            .expect("attest wrong chain");
        let wrong_chain = SignedPurchaseProofV2::sign(
            PurchaseProofBodyV2 {
                attested_proof: wrong_attestation,
                fee: config.limits.minimum_fee,
                nonce: 1,
                valid_until_height: 100,
            },
            &owner_key,
        )
        .expect("owner sign wrong chain");
        assert!(matches!(
            wrong_chain.verify(&config, 1, config.genesis_time_seconds.saturating_add(1)),
            Err(Error::ChainIdMismatch)
        ));
    }

    #[test]
    fn strict_round_trip_rejects_trailing_oversized_unknown_and_truncated_data() {
        for transaction in [
            TransactionV2::Coinbase(coinbase_fixture()),
            TransactionV2::Transfer(transfer_fixture()),
        ] {
            let bytes = transaction.encode().expect("canonical bytes");
            assert_eq!(
                TransactionV2::decode(&bytes, u32::try_from(bytes.len()).expect("small fixture"))
                    .expect("decode"),
                transaction
            );

            let mut trailing = bytes.clone();
            trailing.push(0);
            assert!(TransactionV2::decode(&trailing, 1_024).is_err());
            assert!(matches!(
                TransactionV2::decode(
                    &bytes,
                    u32::try_from(bytes.len() - 1).expect("nonempty fixture")
                ),
                Err(Error::TransactionTooLarge)
            ));
            for length in 0..bytes.len() {
                assert!(TransactionV2::decode(&bytes[..length], 1_024).is_err());
            }
        }

        let unknown = [2_u8];
        assert!(TransactionV2::decode(&unknown, 1_024).is_err());
    }

    #[test]
    fn decoders_reject_unknown_versions_and_network_ids() {
        let transaction = TransactionV2::Transfer(transfer_fixture());
        let mut bytes = transaction.encode().expect("canonical bytes");
        bytes[1..3].copy_from_slice(&3_u16.to_le_bytes());
        assert!(matches!(
            TransactionV2::decode(&bytes, 1_024),
            Err(Error::UnsupportedProtocol {
                expected: TRANSACTION_VERSION_V2,
                actual: 3
            })
        ));

        let mut bytes = transaction.encode().expect("canonical bytes");
        bytes[3..7].copy_from_slice(&u32::MAX.to_le_bytes());
        assert!(TransactionV2::decode(&bytes, 1_024).is_err());
    }

    #[test]
    fn signature_intent_and_witness_commitments_have_frozen_semantics() {
        let transfer = transfer_fixture();
        transfer
            .verify(
                Network::Devnet,
                transfer.body.chain_id_hash,
                Amount::from_atoms(1),
                1,
                1_024,
            )
            .expect("valid transfer");

        let intent_id = transfer.intent_id().expect("intent ID");
        let witness_id = transfer.witness_id().expect("witness ID");
        let mut altered_signature = transfer.clone();
        altered_signature.signature[0] ^= 1;
        assert_eq!(
            altered_signature.intent_id().expect("same intent"),
            intent_id
        );
        assert_ne!(
            altered_signature.witness_id().expect("different witness"),
            witness_id
        );
        assert!(matches!(
            altered_signature.verify(
                Network::Devnet,
                altered_signature.body.chain_id_hash,
                Amount::from_atoms(1),
                1,
                1_024,
            ),
            Err(Error::InvalidSignature)
        ));

        let mut altered_body = transfer;
        altered_body.body.amount = Amount::from_atoms(1);
        assert_ne!(
            altered_body.intent_id().expect("different intent"),
            intent_id
        );
        assert!(matches!(
            altered_body.verify(
                Network::Devnet,
                altered_body.body.chain_id_hash,
                Amount::from_atoms(1),
                1,
                1_024,
            ),
            Err(Error::InvalidSignature)
        ));
    }

    #[test]
    fn transfer_verification_enforces_context_and_exact_next_nonce() {
        let transfer = transfer_fixture();
        let chain_id_hash = transfer.body.chain_id_hash;
        transfer
            .verify_with_expected_nonce(
                Network::Devnet,
                chain_id_hash,
                Amount::from_atoms(1),
                1,
                1_024,
                transfer.body.nonce,
            )
            .expect("valid context");
        assert!(matches!(
            transfer.verify_with_expected_nonce(
                Network::Devnet,
                chain_id_hash,
                Amount::from_atoms(1),
                1,
                1_024,
                transfer.body.nonce + 1,
            ),
            Err(Error::InvalidNonce { .. })
        ));
        assert!(matches!(
            transfer.verify(
                Network::Testnet,
                chain_id_hash,
                Amount::from_atoms(1),
                1,
                1_024,
            ),
            Err(Error::NetworkMismatch { .. })
        ));
        assert!(matches!(
            transfer.verify(
                Network::Devnet,
                Hash256::ZERO,
                Amount::from_atoms(1),
                1,
                1_024,
            ),
            Err(Error::ChainIdMismatch)
        ));
    }

    #[test]
    fn coinbase_identity_and_witness_bind_every_context_field() {
        let coinbase = coinbase_fixture();
        coinbase
            .verify_identity(Network::Devnet, coinbase.chain_id_hash, coinbase.height)
            .expect("valid coinbase identity");
        let witness = coinbase.witness_id().expect("coinbase witness");
        let mut altered = coinbase;
        altered.extra_nonce += 1;
        assert_ne!(altered.witness_id().expect("altered witness"), witness);
    }

    #[test]
    fn golden_transfer_hex_and_hashes_are_stable() {
        let transfer = transfer_fixture();
        let transaction = TransactionV2::Transfer(transfer.clone());
        let bytes = transaction.encode().expect("canonical transaction");

        // Literal vectors are filled from the frozen field order and domain construction. Keeping
        // them in the test makes any consensus-visible byte or hash change explicit.
        assert_eq!(hex::encode(&bytes), golden_transfer_hex());
        assert_eq!(
            transfer.signing_hash().expect("signing hash").to_string(),
            golden_signing_hash()
        );
        assert_eq!(
            transfer.intent_id().expect("intent ID").to_string(),
            golden_intent_id()
        );
        assert_eq!(
            transfer.witness_id().expect("witness ID").to_string(),
            golden_witness_id()
        );
    }

    // Kept as functions so rustfmt does not obscure the long, protocol-significant literals.
    fn golden_transfer_hex() -> &'static str {
        "01020003525541111111111111111111111111111111111111111111111111111111111111111103525541b8af6cf634c592658e001125504d95e652db90e303525541d101bc972a983e961efc6e961ed3b8baae642eea0807060504030201181716151413121128272625242322213837363534333231ed4928c628d1c2c6eae90338905995612959273a5c63f93636c14614ac8737d1e565f3c9cfdc7796afbf3d4158f345157a5eb503e989ecf68906e5bb85d2e4f9dbcdfd78aca95c6e3dd8c5d098a14f8fca7d080b2dad6a89761988948b38900d"
    }

    fn golden_signing_hash() -> &'static str {
        "c2d4ca04e1c52950df3aa5f6e69eaf73a7a7d9b3540c44d80374cb7f9681b8f9"
    }

    fn golden_intent_id() -> &'static str {
        "2e86b62c476f96992e5e83c2eb82e2d7a104772aa13f9844b083e5cd9bdaad31"
    }

    fn golden_witness_id() -> &'static str {
        "f324843df78f9d1f7a606ccc4c3a6ff0fe9bf0afadd22b687e63ba06169bd12d"
    }
}
