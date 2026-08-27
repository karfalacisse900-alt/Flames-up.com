use crate::{Error, KdfParams, Result, WalletPassword};
use argon2::{Algorithm, Argon2, Params, Version};
use aura_core::Network;
use chacha20poly1305::{
    aead::{Aead, Payload},
    KeyInit, XChaCha20Poly1305, XNonce,
};
use rand_core::{OsRng, RngCore};
use zeroize::Zeroizing;

pub(crate) const MAX_ENVELOPE_BYTES: usize = 4 * 1024;
const MAGIC: [u8; 8] = *b"AURAWLT\0";
const ENVELOPE_VERSION: u16 = 1;
const KDF_ARGON2ID: u8 = 1;
const ARGON2_VERSION_0X13: u8 = 0x13;
const SALT_BYTES: usize = 16;
const NONCE_BYTES: usize = 24;
const KEY_BYTES: usize = 32;
const PAYLOAD_VERSION: u16 = 1;
const PLAINTEXT_BYTES: usize = 2 + KEY_BYTES;
const AEAD_TAG_BYTES: usize = 16;
const CIPHERTEXT_BYTES: usize = PLAINTEXT_BYTES + AEAD_TAG_BYTES;

// magic + format + network + KDF + Argon2 version + three KDF u32 values + salt + nonce + length
pub(crate) const HEADER_BYTES: usize = 8 + 2 + 4 + 1 + 1 + 4 + 4 + 4 + SALT_BYTES + NONCE_BYTES + 4;

pub(crate) struct OpenedEnvelope {
    pub(crate) network: Network,
    pub(crate) secret_key: Zeroizing<[u8; KEY_BYTES]>,
}

struct ParsedEnvelope<'a> {
    network: Network,
    kdf: KdfParams,
    salt: [u8; SALT_BYTES],
    nonce: [u8; NONCE_BYTES],
    authenticated_header: &'a [u8],
    ciphertext: &'a [u8],
}

pub(crate) fn seal(
    network: Network,
    secret_key: &[u8; KEY_BYTES],
    password: &WalletPassword,
    kdf: KdfParams,
) -> Result<Vec<u8>> {
    kdf.validate()?;

    let mut salt = [0_u8; SALT_BYTES];
    let mut nonce = [0_u8; NONCE_BYTES];
    OsRng.fill_bytes(&mut salt);
    OsRng.fill_bytes(&mut nonce);

    let mut header = Vec::with_capacity(HEADER_BYTES);
    header.extend_from_slice(&MAGIC);
    header.extend_from_slice(&ENVELOPE_VERSION.to_le_bytes());
    header.extend_from_slice(&network.id().to_le_bytes());
    header.push(KDF_ARGON2ID);
    header.push(ARGON2_VERSION_0X13);
    header.extend_from_slice(&kdf.memory_kib().to_le_bytes());
    header.extend_from_slice(&kdf.time_cost().to_le_bytes());
    header.extend_from_slice(&kdf.parallelism().to_le_bytes());
    header.extend_from_slice(&salt);
    header.extend_from_slice(&nonce);
    header.extend_from_slice(&(CIPHERTEXT_BYTES as u32).to_le_bytes());
    if header.len() != HEADER_BYTES {
        return Err(Error::CryptographicFailure);
    }

    let key = derive_key(password.as_bytes(), &salt, kdf)?;
    let cipher =
        XChaCha20Poly1305::new_from_slice(key.as_ref()).map_err(|_| Error::CryptographicFailure)?;
    let mut plaintext = Zeroizing::new(Vec::with_capacity(PLAINTEXT_BYTES));
    plaintext.extend_from_slice(&PAYLOAD_VERSION.to_le_bytes());
    plaintext.extend_from_slice(secret_key);
    let ciphertext = cipher
        .encrypt(
            XNonce::from_slice(&nonce),
            Payload {
                msg: plaintext.as_slice(),
                aad: &header,
            },
        )
        .map_err(|_| Error::CryptographicFailure)?;
    if ciphertext.len() != CIPHERTEXT_BYTES {
        return Err(Error::CryptographicFailure);
    }

    let mut envelope = header;
    envelope.extend_from_slice(&ciphertext);
    if envelope.len() > MAX_ENVELOPE_BYTES {
        return Err(Error::EnvelopeTooLarge {
            maximum: MAX_ENVELOPE_BYTES,
        });
    }
    Ok(envelope)
}

pub(crate) fn open(bytes: &[u8], password: &WalletPassword) -> Result<OpenedEnvelope> {
    let parsed = parse(bytes)?;
    let key = derive_key(password.as_bytes(), &parsed.salt, parsed.kdf)?;
    let cipher =
        XChaCha20Poly1305::new_from_slice(key.as_ref()).map_err(|_| Error::CryptographicFailure)?;
    let plaintext = cipher
        .decrypt(
            XNonce::from_slice(&parsed.nonce),
            Payload {
                msg: parsed.ciphertext,
                aad: parsed.authenticated_header,
            },
        )
        .map(Zeroizing::new)
        .map_err(|_| Error::AuthenticationFailed)?;

    if plaintext.len() != PLAINTEXT_BYTES {
        return Err(Error::MalformedPayload);
    }
    let payload_version = u16::from_le_bytes(
        plaintext[..2]
            .try_into()
            .map_err(|_| Error::MalformedPayload)?,
    );
    if payload_version != PAYLOAD_VERSION {
        return Err(Error::MalformedPayload);
    }
    let mut secret_key = Zeroizing::new([0_u8; KEY_BYTES]);
    secret_key.copy_from_slice(&plaintext[2..]);
    Ok(OpenedEnvelope {
        network: parsed.network,
        secret_key,
    })
}

fn parse(bytes: &[u8]) -> Result<ParsedEnvelope<'_>> {
    if bytes.len() > MAX_ENVELOPE_BYTES {
        return Err(Error::EnvelopeTooLarge {
            maximum: MAX_ENVELOPE_BYTES,
        });
    }
    if bytes.len() < HEADER_BYTES {
        return Err(Error::TruncatedEnvelope);
    }

    let mut cursor = 0_usize;
    if take::<8>(bytes, &mut cursor)? != MAGIC {
        return Err(Error::InvalidMagic);
    }
    let version = read_u16(bytes, &mut cursor)?;
    if version != ENVELOPE_VERSION {
        return Err(Error::UnsupportedEnvelopeVersion(version));
    }
    let network = network_from_id(read_u32(bytes, &mut cursor)?)?;
    let kdf_id = read_u8(bytes, &mut cursor)?;
    if kdf_id != KDF_ARGON2ID {
        return Err(Error::UnsupportedKdf(kdf_id));
    }
    let argon2_version = read_u8(bytes, &mut cursor)?;
    if argon2_version != ARGON2_VERSION_0X13 {
        return Err(Error::UnsupportedArgon2Version(argon2_version));
    }
    let kdf = KdfParams::new(
        read_u32(bytes, &mut cursor)?,
        read_u32(bytes, &mut cursor)?,
        read_u32(bytes, &mut cursor)?,
    )?;
    let salt = take::<SALT_BYTES>(bytes, &mut cursor)?;
    let nonce = take::<NONCE_BYTES>(bytes, &mut cursor)?;
    let ciphertext_length = usize::try_from(read_u32(bytes, &mut cursor)?)
        .map_err(|_| Error::InvalidCiphertextLength)?;
    if cursor != HEADER_BYTES || ciphertext_length != CIPHERTEXT_BYTES {
        return Err(Error::InvalidCiphertextLength);
    }
    let expected_length = cursor
        .checked_add(ciphertext_length)
        .ok_or(Error::InvalidCiphertextLength)?;
    if bytes.len() < expected_length {
        return Err(Error::TruncatedEnvelope);
    }
    if bytes.len() > expected_length {
        return Err(Error::TrailingBytes);
    }

    Ok(ParsedEnvelope {
        network,
        kdf,
        salt,
        nonce,
        authenticated_header: &bytes[..HEADER_BYTES],
        ciphertext: &bytes[HEADER_BYTES..expected_length],
    })
}

fn derive_key(
    password: &[u8],
    salt: &[u8; SALT_BYTES],
    kdf: KdfParams,
) -> Result<Zeroizing<[u8; KEY_BYTES]>> {
    kdf.validate()?;
    let params = Params::new(
        kdf.memory_kib(),
        kdf.time_cost(),
        kdf.parallelism(),
        Some(KEY_BYTES),
    )
    .map_err(|_| Error::UnsafeKdfParameters)?;
    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);
    let mut key = Zeroizing::new([0_u8; KEY_BYTES]);
    argon2
        .hash_password_into(password, salt, key.as_mut())
        .map_err(|_| Error::CryptographicFailure)?;
    Ok(key)
}

fn network_from_id(id: u32) -> Result<Network> {
    for network in [Network::Mainnet, Network::Testnet, Network::Devnet] {
        if network.id() == id {
            return Ok(network);
        }
    }
    Err(Error::UnsupportedNetwork(id))
}

fn read_u8(bytes: &[u8], cursor: &mut usize) -> Result<u8> {
    let value = *bytes.get(*cursor).ok_or(Error::TruncatedEnvelope)?;
    *cursor = cursor.checked_add(1).ok_or(Error::TruncatedEnvelope)?;
    Ok(value)
}

fn read_u16(bytes: &[u8], cursor: &mut usize) -> Result<u16> {
    Ok(u16::from_le_bytes(take(bytes, cursor)?))
}

fn read_u32(bytes: &[u8], cursor: &mut usize) -> Result<u32> {
    Ok(u32::from_le_bytes(take(bytes, cursor)?))
}

fn take<const N: usize>(bytes: &[u8], cursor: &mut usize) -> Result<[u8; N]> {
    let end = cursor.checked_add(N).ok_or(Error::TruncatedEnvelope)?;
    let value = bytes
        .get(*cursor..end)
        .ok_or(Error::TruncatedEnvelope)?
        .try_into()
        .map_err(|_| Error::TruncatedEnvelope)?;
    *cursor = end;
    Ok(value)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn password(value: &str) -> WalletPassword {
        WalletPassword::new(value.as_bytes().to_vec()).expect("valid test password")
    }

    fn test_kdf() -> KdfParams {
        KdfParams::new(crate::MIN_MEMORY_KIB, 1, 1).expect("bounded test KDF")
    }

    #[test]
    fn wrong_password_is_an_authentication_failure() {
        let envelope =
            seal(Network::Devnet, &[7; 32], &password("correct"), test_kdf()).expect("seal wallet");
        assert!(matches!(
            open(&envelope, &password("wrong")),
            Err(Error::AuthenticationFailed)
        ));
    }

    #[test]
    fn ciphertext_tampering_is_an_authentication_failure() {
        let mut envelope =
            seal(Network::Devnet, &[8; 32], &password("correct"), test_kdf()).expect("seal wallet");
        envelope[HEADER_BYTES] ^= 0x80;
        assert!(matches!(
            open(&envelope, &password("correct")),
            Err(Error::AuthenticationFailed)
        ));
    }

    #[test]
    fn truncation_and_trailing_bytes_are_rejected() {
        let envelope =
            seal(Network::Devnet, &[9; 32], &password("correct"), test_kdf()).expect("seal wallet");
        let mut truncated = envelope.clone();
        truncated.pop();
        assert!(matches!(
            open(&truncated, &password("correct")),
            Err(Error::TruncatedEnvelope)
        ));

        let mut trailing = envelope;
        trailing.push(0);
        assert!(matches!(
            open(&trailing, &password("correct")),
            Err(Error::TrailingBytes)
        ));
    }

    #[test]
    fn oversized_kdf_parameters_are_rejected_before_derivation() {
        let mut envelope = seal(Network::Devnet, &[10; 32], &password("correct"), test_kdf())
            .expect("seal wallet");
        // The memory-cost field begins after magic, format, network, KDF ID, and Argon2 version.
        const MEMORY_OFFSET: usize = 8 + 2 + 4 + 1 + 1;
        envelope[MEMORY_OFFSET..MEMORY_OFFSET + 4]
            .copy_from_slice(&(crate::MAX_MEMORY_KIB + 1).to_le_bytes());
        assert!(matches!(
            open(&envelope, &password("correct")),
            Err(Error::UnsafeKdfParameters)
        ));
    }

    #[test]
    fn fresh_envelopes_use_unique_salts_and_nonces() {
        let first = seal(Network::Devnet, &[11; 32], &password("same"), test_kdf())
            .expect("first envelope");
        let second = seal(Network::Devnet, &[11; 32], &password("same"), test_kdf())
            .expect("second envelope");
        assert_ne!(first, second);
    }
}
