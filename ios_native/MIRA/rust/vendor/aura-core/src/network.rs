use serde::{Deserialize, Serialize};
use std::{fmt, str::FromStr};

/// An independent Aura network namespace.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Network {
    /// Aura Mainnet. Genesis-only in Phase 1.
    Mainnet,
    /// Aura Testnet. Genesis-only in Phase 1.
    Testnet,
    /// Aura Devnet, with explicitly insecure manual block production.
    Devnet,
}

impl Network {
    /// Stable numeric network identifier included in addresses and protocol messages.
    #[must_use]
    pub const fn id(self) -> u32 {
        match self {
            Self::Mainnet => 0x4155_5201,
            Self::Testnet => 0x4155_5202,
            Self::Devnet => 0x4155_5203,
        }
    }

    /// Bech32m human-readable prefix.
    #[must_use]
    pub const fn address_hrp(self) -> &'static str {
        match self {
            Self::Mainnet => "aura",
            Self::Testnet => "taura",
            Self::Devnet => "daura",
        }
    }

    /// Canonical chain identifier for the built-in network specification.
    #[must_use]
    pub const fn canonical_chain_id(self) -> &'static str {
        match self {
            Self::Mainnet => "aura-mainnet-1",
            Self::Testnet => "aura-testnet-1",
            Self::Devnet => "aura-devnet-1",
        }
    }

    /// Parses an address prefix into its network.
    #[must_use]
    pub fn from_address_hrp(hrp: &str) -> Option<Self> {
        match hrp {
            "aura" => Some(Self::Mainnet),
            "taura" => Some(Self::Testnet),
            "daura" => Some(Self::Devnet),
            _ => None,
        }
    }
}

impl fmt::Display for Network {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::Mainnet => "mainnet",
            Self::Testnet => "testnet",
            Self::Devnet => "devnet",
        })
    }
}

impl FromStr for Network {
    type Err = String;

    fn from_str(value: &str) -> std::result::Result<Self, Self::Err> {
        match value.to_ascii_lowercase().as_str() {
            "mainnet" => Ok(Self::Mainnet),
            "testnet" => Ok(Self::Testnet),
            "devnet" | "regtest" => Ok(Self::Devnet),
            _ => Err(format!("unknown Aura network {value:?}")),
        }
    }
}

impl borsh::BorshSerialize for Network {
    fn serialize<W: std::io::Write>(&self, writer: &mut W) -> std::io::Result<()> {
        borsh::BorshSerialize::serialize(&self.id(), writer)
    }
}

impl borsh::BorshDeserialize for Network {
    fn deserialize_reader<R: std::io::Read>(reader: &mut R) -> std::io::Result<Self> {
        let id = <u32 as borsh::BorshDeserialize>::deserialize_reader(reader)?;
        match id {
            0x4155_5201 => Ok(Self::Mainnet),
            0x4155_5202 => Ok(Self::Testnet),
            0x4155_5203 => Ok(Self::Devnet),
            _ => Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                format!("unknown Aura network id {id:#010x}"),
            )),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn canonical_encoding_uses_explicit_network_id() {
        let encoded = borsh::to_vec(&Network::Mainnet).expect("encode network");
        assert_eq!(encoded, Network::Mainnet.id().to_le_bytes());

        let unknown = 0x4155_52ff_u32.to_le_bytes();
        assert!(borsh::from_slice::<Network>(&unknown).is_err());
    }
}
