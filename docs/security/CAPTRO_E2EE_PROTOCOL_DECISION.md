# Captro messaging protocol decision

Decision status: **recommended, conditional on licensing and integration approval**. Use official Signal `libsignal` as the cryptographic session implementation for a staged E2EE direct-message system, retaining Captro Auth and backend only as authenticated ciphertext transport and device-directory services. Do not implement a new cryptographic protocol or an application-wide chat key.

This decision does not authorize production deployment, does not make existing messages encrypted, and is not a claim that the complete Captro integration has been reviewed. Licensing, a supported build strategy, an attachment implementation, and adversarial tests are prerequisites before shipping.

## Why libsignal

Signal maintains a Rust core with Swift, Java, and TypeScript interfaces. Its protocol family supplies asynchronous session establishment and per-message ratcheting rather than a permanent shared conversation password. The current upstream APIs must be used at a pinned revision; Captro must not reimplement cryptography from the protocol specifications. [Official implementation](https://github.com/signalapp/libsignal), [protocol specifications](https://signal.org/docs/).

Formal analysis of earlier Signal core protocols supports the protocol choice but is not a security certificate for today's library, post-quantum extensions, or Captro's storage/attachment glue. Record the exact dependency version and review scope before an implementation claim. [Formal analysis](https://eprint.iacr.org/2016/1013), [PQXDH specification](https://signal.org/docs/specifications/pqxdh/), [Double Ratchet specification](https://signal.org/docs/specifications/doubleratchet/).

## Licensing and maintenance gate

`libsignal` is licensed under **AGPLv3**. Captro must obtain legal approval for its source/distribution obligations and App Store delivery before adopting it. This audit does not assert compatibility with Captro's intended source license or authorize disclosure of the app source. [Upstream license](https://github.com/signalapp/libsignal/blob/main/LICENSE).

Upstream explicitly states that use outside Signal is unsupported and APIs can change without notice. Captro would own its bridge packaging, update monitoring, compatibility testing, and incident response. Maintained upstream does not mean a supported third-party product SLA. [Upstream README](https://github.com/signalapp/libsignal/blob/main/README.md).

The canonical Swift integration is CocoaPods; upstream does not support using Swift Package Manager to consume the published library. Captro uses SwiftPM, iOS 17, and Swift 5.9. A reproducible, checksum-verified native bridge/XCFramework build or an approved dependency-integration change is necessary. Test real iOS arm64 and supported simulator architectures; do not guess a package URL/version and commit a nonbuilding dependency. [Swift integration instructions](https://github.com/signalapp/libsignal/blob/main/swift/README.md).

## Alternative if AGPL cannot be accepted

The maintained **Matrix Rust SDK**, with Swift bindings and Apache 2.0 licensing, is the alternative decision to evaluate. Its crypto layer uses `vodozemac` for Olm/Megolm. It offers a broader messaging/device ecosystem, but adopting its full semantics requires a Matrix service boundary, identity integration, and history migration. Do not extract primitives and invent a Captro-specific substitute for Matrix key distribution or backup. [Matrix Rust SDK](https://github.com/matrix-org/matrix-rust-sdk), [vodozemac](https://github.com/matrix-org/vodozemac).

Least Authority reviewed a specific 2022 vodozemac revision; the audit excluded bindings and dependencies and identified issues requiring handling. It does not certify the current SDK or Captro integration. Megolm group session and backup tradeoffs also differ from pairwise ratcheted DMs. [Audit scope and findings](https://leastauthority.com/static/publications/LeastAuthority-Matrix_vodozemac_Final_Audit_Report.pdf).

Matrix is not automatically selected merely to avoid a licensing question: it is a materially broader architecture decision requiring approval. If neither path can meet licensing, operational, and review requirements, leave encrypted send unavailable rather than inventing crypto or delivering plaintext under an encryption label.

## Threat model

Protect message content and attachments against routine backend/database administrators, service-role reads, storage operators, network intermediaries, push services, and compromised analytics/AI integrations. Server authorization must separately limit metadata and ciphertext to participants and enrolled devices.

E2EE does not protect an unlocked compromised participant device, malicious recipients, screenshots, or evidence a user intentionally reports. It does not hide all timing, traffic size, participants, delivery state, or IP metadata. A server able to substitute identity/device keys can attack first contact unless users authenticate keys or an independently verifiable directory prevents substitution. TLS, ordinary login, and backend-generated device lists alone do not solve this.

## Account and device identities

Each account/device generates its own library-supported identity and session keys on device. Persist ratchets transactionally in an account-specific encrypted store. Protect local wrapping material using appropriate `ThisDeviceOnly` Keychain access; do not assume Secure Enclave supports the chosen protocol's key operations. Public identity/prekey bundles may be held by the server; private identity, session, and attachment keys may not.

First-device enrollment requires fresh authenticated account control and a new device identity. Additional devices require approval from an existing trusted device using a reviewed key-binding/verification flow, not just a successful password login. Bind the approval to the account, new device key, and enrollment version. Show users devices and revocation actions. App Attest can be an abuse signal, not a substitute for cryptographic device approval.

Device-list authenticity, rollback resistance, peer safety verification, and identity-change warnings must be specified and reviewed as part of the integration. A server-managed unsigned list is insufficient against a malicious server. Start with explicit peer key verification and block unapproved changes; evaluate key transparency before asserting protection against directory substitution at scale.

Multi-device delivery requires separate sessions/envelopes for authorized recipient devices and the sender's other trusted devices. Signal's Sesame document informs asynchronous device/session handling; it is not a turnkey device product delivered by the crypto library. Do not add an unreviewed group key to make fan-out easier. [Sesame specification](https://signal.org/docs/specifications/sesame/).

## Attachments and supported content

Encryption must cover original images, video, audio, files, thumbnails, posters, captions associated with private media, filenames where practical, and any private transcripts. Generate previews on participants' devices, encrypt them, and include their decryption metadata only inside encrypted messages. R2 stores opaque ciphertext separately from public feed buckets and processors.

The libsignal core alone is **not** a complete reviewed Captro attachment-format implementation. Before coding attachment encryption, identify a maintained compatible implementation, exact authenticated format, limits, streaming behavior, integrity verification, and license. Obtain review of the Swift binding and attachment handling. This is an explicit blocker, not permission to assemble an ad hoc CryptoKit chunking protocol. No independently reviewed compatible attachment integration has been selected by this audit.

Ciphertext delivery still needs current participant/device authorization, unguessable object references, range handling that cannot bypass validation, limited lifetime, and safe cache headers. Verify the whole attachment before exposing decoded media. Never fall back to Cloudflare Images/Stream, public links, server transcription, or raw uploads when encryption fails.

For the first implementation, support only verified direct-message content types. Group chat, story-to-DM replies, shared post links, legacy voice/file routes, and older clients must have explicit capability behavior. Unsupported paths remain unavailable or clearly legacy, never silently unencrypted alternatives inside an encrypted thread.

## Recovery and revocation

Initial recovery policy: no server-held decryption escrow and no automatic cloud key backup. Trusted-device transfer can restore supported history through a reviewed authenticated transfer. Losing every trusted device means private history cannot be recovered from ciphertext by resetting a password. Explain that before enrollment. Any later recovery-key backup needs a separate reviewed design and user opt-in.

Revoking a device removes it from future fan-out and message/attachment authorization, invalidates pending delivery access, and terminates or gates its existing connections. Reject stale device-directory versions during sends so a queued sender cannot continue encrypting to a revoked device unknowingly. Apply session/account revocation at authorization checks as well as refresh-token handling.

A revocation cannot erase messages/keys already downloaded by that device or undo screenshots. Changes require the selected library's supported session lifecycle; no custom shared-key rotation. Test revocation while the old JWT and socket are still alive.

## Requests and blocking

Define a separate request state before an unknown sender can deliver ordinary conversation content or private attachment access. Any permitted request text is encrypted to approved recipient devices, rate-limited, and disclosed only to that recipient. Acceptance is not implied by retrieval. Decide who may send requests through actual product policy, rather than inventing new privacy rules in a migration.

Blocking prevents new requests, messages, typing/presence, pushes, attachment grants, and queued delivery across all API and direct database paths. Enforce it when accepting an envelope and again when releasing it or its attachment. Preserve existing history and explain that already downloaded content remains with the participant. Define unblocking behavior without automatically delivering blocked-period queues.

## Acknowledgments and offline delivery

Persist a stable client message identifier per device and an encrypted outbox before transport. Atomically persist ratchet state and outgoing ciphertext; retries must reuse the same operation/ciphertext rather than independently advancing sessions for each HTTP retry. Make server uniqueness and acknowledgment authority explicit.

Distinguish server acceptance, recipient successful decryption/delivery, and recipient viewing. Do not mark read when a background API fetch runs. Receipts carry only necessary encrypted/authorized metadata, respect user privacy controls, and cannot alter participants or message contents. Bound duplicate/reorder handling and offline retention through the selected library and product requirements.

## Reporting and moderation

Routine moderators and cloud AI cannot decrypt conversations. For a report, the participant selects specific messages/media, previews precisely what will be disclosed, and explicitly submits that evidence to an access-controlled case system. Do not upload session keys or fetch nearby history. Moderation access is limited to those evidence objects and audited by case/purpose/retention.

A report may contain plaintext at the reporting boundary by deliberate user choice. Transport and storage of evidence must use independently protected case handling, not a room key. Do not claim transcript evidence proves authorship cryptographically; protocol deniability and a malicious reporting client limit that claim.

Public captions, public voice posts/comments, and feed safety keep their existing server moderation where appropriate. Private messaging must not silently share that pipeline. User-invoked AI processing of selected private material, if ever added, needs explicit disclosure and a separate permission boundary.

## Conditions before implementation and release

1. Approve libsignal licensing/distribution and maintenance ownership, or authorize evaluation of the broader Matrix alternative.
2. Select and review an attachment implementation before any media encryption claim.
3. Establish an isolated test database/Auth/Realtime, Worker, and private storage. No production data/secrets or inherited production bindings.
4. Fix the audit's role, membership, and row-integrity gaps in staging first.
5. Pass the documented multi-account, open-socket revocation, device, media, and cache tests; obtain independent security review.
6. Separately authorize a migration/retention plan and deployment. No current or new conversation is called E2EE until its actual supported paths pass verification.
