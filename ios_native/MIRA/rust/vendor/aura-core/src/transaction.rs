use crate::{hash_borsh, Address, Amount, Error, Hash256, Network, Result};
use borsh::{BorshDeserialize, BorshSerialize};
use ed25519_dalek::{Signature, Signer, SigningKey, VerifyingKey};

/// Current canonical Aura transaction format version.
pub const TRANSACTION_VERSION: u16 = 1;

/// Fields authorized by an Aura transaction signature.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct TransactionBody {
    /// Transaction encoding and validation version.
    pub version: u16,
    /// Network namespace used by both addresses.
    pub network: Network,
    /// Domain hash of the textual chain ID, preventing cross-chain replay.
    pub chain_id_hash: Hash256,
    /// Account spending AUR.
    pub sender: Address,
    /// Account receiving AUR.
    pub recipient: Address,
    /// Atomic AUR units transferred.
    pub amount: Amount,
    /// Atomic AUR units offered as the network fee.
    pub fee: Amount,
    /// Exactly the sender's previous committed nonce plus one.
    pub nonce: u64,
    /// Last block height at which the transaction is valid; zero means no expiry.
    pub valid_until_height: u64,
}

/// A canonical Aura transfer transaction signed with Ed25519.
#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
pub struct SignedTransaction {
    /// Signed transaction fields.
    pub body: TransactionBody,
    /// Raw Ed25519 verifying key.
    pub public_key: [u8; 32],
    /// Raw Ed25519 signature over [`Self::signing_hash`].
    pub signature: [u8; 64],
}

#[derive(BorshSerialize)]
struct TransactionIdPreimage {
    body: TransactionBody,
    public_key: [u8; 32],
}

impl SignedTransaction {
    /// Signs a transaction body. Wallet persistence and recovery belong to protocol gate 3.
    pub fn sign(body: TransactionBody, signing_key: &SigningKey) -> Result<Self> {
        let public_key = signing_key.verifying_key().to_bytes();
        let signing_hash = hash_borsh("transaction/signing/v1", &body)?;
        let signature = signing_key.sign(signing_hash.as_bytes()).to_bytes();
        Ok(Self {
            body,
            public_key,
            signature,
        })
    }

    /// Hash authorized by the Ed25519 signature.
    pub fn signing_hash(&self) -> Result<Hash256> {
        hash_borsh("transaction/signing/v1", &self.body)
    }

    /// Transaction identifier for the authorized payload and signer, excluding the signature
    /// witness so alternate encodings cannot create a second identifier for the same intent.
    pub fn id(&self) -> Result<Hash256> {
        hash_borsh(
            "transaction/id/v1",
            &TransactionIdPreimage {
                body: self.body.clone(),
                public_key: self.public_key,
            },
        )
    }

    /// Commitment to the exact signed transaction bytes, including the signature witness.
    pub fn witness_id(&self) -> Result<Hash256> {
        hash_borsh("transaction/witness/v1", self)
    }

    /// Deterministically encodes the transaction for storage or future P2P transport.
    pub fn encode(&self) -> Result<Vec<u8>> {
        borsh::to_vec(self)
            .map_err(|error| Error::Serialization(format!("transaction encoding failed: {error}")))
    }

    /// Decodes a canonical transaction with a strict byte limit.
    pub fn decode(bytes: &[u8], maximum_size: u32) -> Result<Self> {
        if bytes.len() > maximum_size as usize {
            return Err(Error::TransactionTooLarge);
        }
        Self::try_from_slice(bytes)
            .map_err(|error| Error::Serialization(format!("transaction decoding failed: {error}")))
    }

    /// Applies context-independent and chain-context validation.
    pub fn verify(
        &self,
        expected_network: Network,
        expected_chain_id_hash: Hash256,
        minimum_fee: Amount,
        candidate_height: u64,
        maximum_size: u32,
    ) -> Result<()> {
        if self.body.version != TRANSACTION_VERSION {
            return Err(Error::UnsupportedProtocol {
                expected: TRANSACTION_VERSION,
                actual: self.body.version,
            });
        }
        if self.body.network != expected_network {
            return Err(Error::NetworkMismatch {
                expected: expected_network,
                actual: self.body.network,
            });
        }
        if self.body.chain_id_hash != expected_chain_id_hash {
            return Err(Error::ChainIdMismatch);
        }
        for address in [self.body.sender, self.body.recipient] {
            if address.network() != expected_network {
                return Err(Error::AddressNetworkMismatch {
                    expected: expected_network,
                    actual: address.network(),
                });
            }
        }
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
        if self.encode()?.len() > maximum_size as usize {
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
}

#[cfg(test)]
mod tests {
    use super::*;

    fn transaction(key: &SigningKey) -> SignedTransaction {
        let network = Network::Devnet;
        SignedTransaction::sign(
            TransactionBody {
                version: TRANSACTION_VERSION,
                network,
                chain_id_hash: crate::hash_tagged("chain-id/v1", &[b"aura-devnet-1"]),
                sender: Address::from_public_key(network, &key.verifying_key().to_bytes()),
                recipient: Address::from_public_key(network, &[9; 32]),
                amount: Amount::from_atoms(10),
                fee: Amount::from_atoms(1),
                nonce: 1,
                valid_until_height: 10,
            },
            key,
        )
        .expect("sign transaction")
    }

    #[test]
    fn signature_covers_every_body_field() {
        let key = SigningKey::from_bytes(&[3; 32]);
        let mut tx = transaction(&key);
        let chain_hash = tx.body.chain_id_hash;
        tx.verify(Network::Devnet, chain_hash, Amount::from_atoms(1), 1, 2048)
            .expect("valid transaction");

        tx.body.amount = Amount::from_atoms(11);
        assert!(matches!(
            tx.verify(Network::Devnet, chain_hash, Amount::from_atoms(1), 1, 2048),
            Err(Error::InvalidSignature)
        ));
    }

    #[test]
    fn rejects_cross_network_replay() {
        let key = SigningKey::from_bytes(&[4; 32]);
        let tx = transaction(&key);
        assert!(matches!(
            tx.verify(
                Network::Testnet,
                tx.body.chain_id_hash,
                Amount::from_atoms(1),
                1,
                2048
            ),
            Err(Error::NetworkMismatch { .. })
        ));
    }

    #[test]
    fn rejects_wrong_chain_low_fee_and_expired_transactions() {
        let key = SigningKey::from_bytes(&[6; 32]);
        let transaction = transaction(&key);
        let chain_hash = transaction.body.chain_id_hash;
        let other_chain = crate::hash_tagged("chain-id/v1", &[b"aura-devnet-other"]);

        assert!(matches!(
            transaction.verify(Network::Devnet, other_chain, Amount::from_atoms(1), 1, 2048),
            Err(Error::ChainIdMismatch)
        ));
        assert!(matches!(
            transaction.verify(Network::Devnet, chain_hash, Amount::from_atoms(2), 1, 2048),
            Err(Error::FeeTooLow {
                minimum: 2,
                actual: 1
            })
        ));
        assert!(matches!(
            transaction.verify(Network::Devnet, chain_hash, Amount::from_atoms(1), 11, 2048),
            Err(Error::TransactionExpired {
                expires: 10,
                height: 11
            })
        ));
    }

    #[test]
    fn transaction_id_excludes_the_signature_witness() {
        let key = SigningKey::from_bytes(&[5; 32]);
        let transaction = transaction(&key);
        let mut altered_witness = transaction.clone();
        altered_witness.signature[0] ^= 1;

        assert_eq!(
            transaction.id().expect("transaction ID"),
            altered_witness.id().expect("altered transaction ID")
        );
        assert_ne!(
            transaction.witness_id().expect("witness ID"),
            altered_witness.witness_id().expect("altered witness ID")
        );
        assert!(matches!(
            altered_witness.verify(
                Network::Devnet,
                altered_witness.body.chain_id_hash,
                Amount::from_atoms(1),
                1,
                2048
            ),
            Err(Error::InvalidSignature)
        ));
    }
}
