# Aura wallet crate

`aura-wallet` is the stage-3 local key-storage boundary for Aura. It generates
Ed25519 keys with the operating-system CSPRNG, encrypts them with Argon2id
v0x13 plus XChaCha20-Poly1305, and writes a bounded, versioned wallet envelope
using atomic replacement.

The crate does not implement balances, transaction submission, confirmations,
mining, networking, recovery phrases, or hardware-wallet support. Those
features must use validated node state and their later protocol stages.

On Unix, wallet files are created with owner-only `0600` permissions whenever
the platform permits it. On Windows, this crate does not alter NTFS ACLs; it
reports that limitation through `PermissionStatus::PlatformDefaultAcl`.
Encryption remains mandatory on every platform, but production installers
must separately establish and test an appropriate user-only Windows ACL.

Build this isolated crate before it is added to the root workspace with:

```text
cargo test --manifest-path crates/aura-wallet/Cargo.toml --locked
```

