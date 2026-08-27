# Vendored Aura crates

`aura-core` and `aura-wallet` are plain source copies from the Aura Desktop repository
(`crates/aura-core`, `crates/aura-wallet`), taken at commit
`ed6fe302845d15fafe42c81a12e59ead966b310a` (2026-08-22). That repository does not yet have a
shared git remote, so a git or registry dependency was not possible; these are full copies, not
a subset, so they stay a faithful match of the real, reviewed Aura consensus types and wallet
crypto rather than a hand-trimmed reimplementation.

**This is a temporary arrangement.** Before this drifts, the Aura Desktop repository should
either get a real git remote (so this can become a pinned git dependency) or the two projects
should share a published/workspace crate. Until then, keep these copies in sync by hand when the
source crates change, and note the source commit hash here when you do.

Nothing in `mira_core`'s wallet FFI reimplements or forks any cryptography from these crates --
it only calls their existing public API (`aura_wallet::Wallet`, `aura_core::Address`, etc.).
