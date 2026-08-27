use crate::{hash_tagged, Error, Network, Result};
use bech32::{FromBase32, ToBase32, Variant};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use std::{fmt, str::FromStr};

/// An Aura account address: a network namespace plus a 20-byte public-key digest.
#[derive(
    Clone,
    Copy,
    PartialEq,
    Eq,
    PartialOrd,
    Ord,
    Hash,
    borsh::BorshSerialize,
    borsh::BorshDeserialize,
)]
pub struct Address {
    network: Network,
    payload: [u8; 20],
}

impl Address {
    /// Derives an address from an Ed25519 public key using domain-separated SHA-256.
    #[must_use]
    pub fn from_public_key(network: Network, public_key: &[u8; 32]) -> Self {
        let digest = hash_tagged("address/ed25519/v1", &[public_key]);
        let mut payload = [0_u8; 20];
        payload.copy_from_slice(&digest.as_bytes()[..20]);
        Self { network, payload }
    }

    /// Returns the address network.
    #[must_use]
    pub const fn network(self) -> Network {
        self.network
    }

    /// Returns the public-key digest payload.
    #[must_use]
    pub const fn payload(self) -> [u8; 20] {
        self.payload
    }
}

impl fmt::Display for Address {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        let encoded = bech32::encode(
            self.network.address_hrp(),
            self.payload.to_base32(),
            Variant::Bech32m,
        )
        .map_err(|_| fmt::Error)?;
        formatter.write_str(&encoded)
    }
}

impl fmt::Debug for Address {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "Address({self})")
    }
}

impl FromStr for Address {
    type Err = Error;

    fn from_str(value: &str) -> Result<Self> {
        if value.len() > 90 || value.to_ascii_lowercase() != value {
            return Err(Error::InvalidAddress(
                "address must be lowercase and at most 90 characters".into(),
            ));
        }
        let (hrp, data, variant) =
            bech32::decode(value).map_err(|error| Error::InvalidAddress(error.to_string()))?;
        if variant != Variant::Bech32m {
            return Err(Error::InvalidAddress("Bech32m checksum required".into()));
        }
        let network = Network::from_address_hrp(&hrp)
            .ok_or_else(|| Error::InvalidAddress("unknown address prefix".into()))?;
        let payload = Vec::<u8>::from_base32(&data)
            .map_err(|error| Error::InvalidAddress(error.to_string()))?;
        let payload: [u8; 20] = payload
            .try_into()
            .map_err(|_| Error::InvalidAddress("address payload must be 20 bytes".into()))?;
        Ok(Self { network, payload })
    }
}

impl Serialize for Address {
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str(&self.to_string())
    }
}

impl<'de> Deserialize<'de> for Address {
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        value.parse().map_err(serde::de::Error::custom)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn address_round_trip_and_checksum() {
        let address = Address::from_public_key(Network::Mainnet, &[7; 32]);
        let encoded = address.to_string();
        assert!(encoded.starts_with("aura1"));
        assert_eq!(encoded.parse::<Address>().expect("valid address"), address);

        let mut corrupted = encoded;
        corrupted.pop();
        corrupted.push('q');
        assert!(corrupted.parse::<Address>().is_err());
    }
}
