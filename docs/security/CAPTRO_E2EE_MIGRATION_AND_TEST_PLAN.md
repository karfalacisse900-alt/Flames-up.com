# Captro encrypted messaging migration and security tests

This plan stages authorization repairs and encrypted messaging without changing production permissions or destroying history. It is a test plan, not evidence that encryption or access tests have passed. The accompanying audit describes the current system; the protocol decision identifies the licensing and implementation gates.

Source baseline: `ccdf4915df3087e7d5bb09f866a300af5d9a60cb`, audited October 5, 2026.

## Safe test environment

The existing default and production Worker environments point at the same Supabase project and R2 buckets. Do not run adversarial tests using `wrangler dev` with those bindings. The connected project has no development branch. Docker is available locally, but no isolated Auth/REST/Realtime/Worker stack was provisioned or verified during the audit.

Use a local, independently configured Supabase stack and local Worker/R2 simulation for initial tests. A dedicated development project can follow only after resource-creation approval. Each needs separate Auth users, JWT signing material, service credentials, database, storage bindings, push sink, and analytics/AI sinks. No production history export, snapshot, credentials, device tokens, or bucket copy is permitted.

The test launcher must fail if its URLs/project/bucket names match production. Disable outgoing real APNs and AI calls; capture synthetic test payloads at controlled sinks instead. Real interoperability tests may use separately approved provider test credentials, never private customer material. Keep canary content and keys out of published artifacts.

Reproduce the current policies in the disposable stack first, then apply proposed staging-only repairs. Do not modify the managed `realtime` schema: use supported public application tables and Realtime configuration. Supabase's July 2026 schema lockdown preserves policy management on supported Realtime resources but restricts schema modification. [Supabase change notice](https://supabase.com/changelog/realtime-schema-locked-down-against-modification).

## Proposed changes and ownership

These are new design requirements, not claims that these fields or services currently exist.

| Area | Staged change | Existing code to integrate |
| --- | --- | --- |
| Authorization | Authoritative admin roles, safe profile columns, controlled membership, immutable participants, request/block/device gates | Worker `getAdminContext`, message/group guards; Supabase grants and policies |
| Auth lifecycle | Bind requests to validated account/session/device and a revocation generation; server logout plus local cleanup | Worker auth resolver; `MIRAAuthSession`; `MIRAChatRealtime` |
| Cryptographic client | Pinned official protocol bindings, account/device key store, approved enrollment, transactional ratchets/outbox | Native API/auth ownership; new narrowly scoped messaging crypto service |
| Ciphertext transport | Versioned encrypted envelope with sender device, recipient device, stable client message ID, ciphertext and bounded metadata | Existing message routing adapted without plaintext body delivery |
| Device registry | Public identity/prekey bundles, approved enrollment and directory version, revocation records; no private keys | New schema after protocol review, not `app_push_tokens` reuse |
| Attachments | Separate ciphertext bucket, private authorized retrieval, encrypted previews, integrity verification, no public processing | R2 transport with a separate path; never the feed uploader |
| Local retention | Account/device encrypted storage, explicit file protection, generation-bound async work, backup policy | `MIRAChatLocalStore`, JSON/image caches, API cache, outgoing media storage |
| Reporting | Explicit selected evidence, separate case access and retention, no surrounding-history fetch | Report UI and report authorization; replace the current admin context expansion |
| Push and telemetry | Generic notification without sender/content preview; allowlisted metadata; no plaintext URLs/error excerpts | Push service/registry, event sanitizers, Worker query/log helpers |

Design the schema and SQL privileges after the chosen library's actual store/capability requirements are understood. Do not add invented compatibility columns to production. Use database uniqueness for message idempotency and device-bound receipt authority, with server authorization inside the accepting/retrieval transaction.

The server may know routing and device metadata but must receive only opaque message/attachment content. Service-role access must not reconstruct a readable preview, transcript, or attachment key. A developer debugging hook cannot bypass this rule.

## Historical migration

Maintain a separate legacy history boundary. Preserve existing messages and attachments initially; do not overwrite plaintext rows with fake ciphertext or delete D1 after import. Preserve ordering and identifiers so replies, reports, and user-visible history still make sense.

New encrypted conversations must have an explicit version/capability epoch and an independently enforced encrypted-only send route. Old clients cannot send plaintext into that epoch. Reject unsupported versions/types with a clear update or unsupported-content error. Never route a failed encrypted send into the old `/messages` body path.

Allow legacy history to be viewed as **legacy server-readable history**, not E2EE. Starting an encrypted session does not relabel prior messages. If voluntary client-side historical import is offered later, explain that importing a private copy does not erase server originals, provider derivatives, reports, logs, or backups.

Before production migration, authorized operators must inventory historical retention for:

- Supabase live rows, backups/PITR, exported snapshots, and Realtime/log retention.
- Legacy D1 messages and exports retained after transfer.
- Cloudflare Images/Stream/R2 originals, previews, moderation samples, jobs, and provider retention.
- Signed-link/browser/CDN caches permitted by current headers.
- Local thread JSON, decoded images, outgoing originals, HTTP cache, device/iCloud backups where applicable.
- Reports, reviewer exports, notification metadata, and any external AI submissions.

Record purpose, owner, retention duration, legal holds, deletion mechanism, and residual copies outside Captro control. Any purge or retention change requires explicit authorization and a reversible migration/backup plan where appropriate. Restoring an old backup must not reactivate revoked devices or roll back encryption capability policy.

Production rollout is separately authorized only after staged review. Prefer a limited capability-gated pilot, with no plaintext fallback and no unsupported content promises. A rollback disables new encrypted sending while preserving ciphertext/history and keys; it must not quietly switch those rooms back to plaintext.

## Test identities and access paths

Create synthetic unrelated accounts A, B, and C through real test Auth. A and B are participants; C is not. Add a reviewer account M with only report-case access. Give A two separately enrolled devices A1/A2 and B device B1. Add an authenticated but unenrolled A3. Use an anonymous client too. Keep their tokens distinct, and never use the service role when demonstrating participant access.

Exercise each operation through the native client, Worker HTTP, direct Supabase REST, and a raw Supabase Realtime client without the native projection/filter. Test storage endpoints, signed or authorized retrieval, byte ranges, receipts, presence/typing, reports, and push separately. A UI denial is not proof that the underlying endpoint denied access.

Test fixtures may contain unique canary text and synthetic image/video/audio/file assets. Capture only synthetic data; avoid raw secret/token logging. Save response status, permitted metadata, assertion results, source revision, migration hashes, dependency revisions, environment identity, and device/OS version as reproducible evidence.

## Authorization test matrix

| Test | Required result |
| --- | --- |
| C reads A/B thread, inbox preview, message ID, REST table, or Realtime event | No body, ciphertext, private metadata, attachment grant, or existence leak beyond explicitly permitted policy |
| Anonymous client uses the same paths | Rejected; no content or private routing data |
| B edits A's message body, participants, group, device, or encryption version | Rejected; receipts cannot mutate these fields |
| A sends as B, inserts a third-party receiver/device, or spoofs an acknowledgment | Rejected at Worker and direct database boundaries |
| C self-enrolls in an A/B private group or sets owner role | Rejected without invitation/approved join authority |
| A updates profile metadata to administrator or changes profile identity to an owner | No admin privilege; server-managed fields cannot be user-written |
| Admin-role lookup fails | Fail closed; no metadata fallback |
| Unenrolled A3 has a valid account token | Cannot receive/decrypt/enroll itself or fetch private ciphertext/keys |
| C copies an attachment reference, URL, or byte-range request | Rejected by current authorization; no plaintext derivative endpoint |
| A references B's unrelated asset in a new message | Rejected; no signing-oracle/cross-asset access |
| Unapproved device directory changes, rollback, or key substitution | Send blocked/warned according to reviewed verification policy; no silent trust |

Inspect grants independently. Test unnecessary TRUNCATE/DDL privileges only against disposable local tables/database roles, not production and not by assuming a public HTTP operation exists. Assert least privilege for table columns and function execution. Confirm RLS remains active through every applicable access path, and explicitly account for service-role bypass.

## Open connection revocation test

1. Enroll A1/A2/B1 and open A2's Realtime connection. Keep its unexpired access token and live subscription. Deliver and decrypt a pre-revocation message to prove the fixture works.
2. Revoke A2 from A1. Record the server's revocation commit/version and acknowledgment. Do not close A2 or refresh its token in the test.
3. Have B1 send new messages and attachments after that acknowledgment. A2 must receive no new private delivery event/payload/grant and cannot fetch the new mailbox or attachment using its old token. Stale sender-device lists must be rejected/refreshed rather than fan out to A2.
4. Attempt A2 sends, receipts, typing/presence, signed-link refresh, reconnect, direct REST queries, and queued upload completion. All revoked operations must fail. Current A1/B1 sessions must continue correctly.
5. Race sends, delivery reads, and revocation. Define the linearization point: after revocation acknowledgment no new delivery authorization is issued to A2. Evidence must distinguish already downloaded content from newly authorized delivery.
6. Repeat with Auth session logout, account suspension, group-member removal where supported, and blocking while the connection remains open.

A test that closes the socket first is insufficient. JWT expiry alone is insufficient. If Realtime authorization is cached too broadly to satisfy the requirement, use a controlled delivery relay that checks account/session/device state per delivery and terminates revoked subscriptions. Do not assume SQL policy changes retroactively close a live socket; prove the behavior.

Revocation cannot erase already delivered plaintext or keys. Tests and user-facing explanations must state that limitation honestly.

## Encryption and content tests

Use library interoperability fixtures, not self-encryption round trips alone. Verify session setup, prekey consumption, ratchet persistence, duplicates, reordering, crash recovery, and concurrent sends using the pinned implementation. Corrupt envelopes and attachments; reject tampering, wrong keys, replay beyond supported windows, invalid sender/device binding, oversized input, and unsupported versions without plaintext fallback.

Inspect synthetic Worker requests, Supabase rows/events, R2 objects, push sink, error/log/analytics sink, and AI sink for the canary content. The server should have ciphertext and minimum metadata only. No private-media request may reach the public media moderation or transcription path. Use independent negative tests on the old plaintext routes to ensure they cannot write into an encrypted epoch.

Every actually supported content type needs its own result: text, image, video, thumbnail, poster, audio/voice, file, private transcript if introduced, quoted reply, shared link, and story-to-DM reply. Unimplemented types are **unsupported**, not passed. Verify orientation, media integrity, playback, cancellation, retry, and background state on real devices. Public voice posts/comments are a separate feature and do not inherit DM encryption.

For reports, select exactly two synthetic messages and one attachment, confirm the disclosure preview, and inspect the case record. M may read only those approved evidence items. M cannot query or expand the room, retrieve ordinary attachment keys, or request nearby messages. Keep case access/retention auditable and deny unrelated reviewers.

## Requests blocking retries and acknowledgments

Unknown-sender requests must not create an accepted thread, emit presence, or authorize ordinary attachment delivery. Test accepted, rejected, canceled, expired, rate-limited, and duplicate requests against actual selected product rules. C cannot enumerate A's pending requests or bypass acceptance through direct INSERT.

Block while a sender is online and while its encrypted outbox is offline. Once the block commits, reject new and queued delivery/grants; do not flush blocked-period messages after unblock unless the product explicitly supports and discloses it. Already received history remains intact.

Simulate server acceptance followed by dropped response, airplane mode, app termination, duplicate taps, expired token, out-of-order receipts, and retry after relaunch. Require one stable message identity, no duplicate visible send, no ratchet-state loss, and no source-media deletion. Server acceptance is not delivery; delivery requires successful recipient decryption; read requires the appropriate viewer action/control.

## Device storage and account switching

On physical iPhones, switch A to C while upload, HTTP retrieval, Realtime handling, decryption, image decode, cache write, playback, and push registration are in flight. Late A work cannot use C's token, attach to C's connection, write into C's cache, or appear on C's screen. Test switching back without destroying A's history.

Check lock/unlock, app kill, OS backup behavior, local file protection, HTTP/thumbnail caches, notification previews, and logout/session revocation. Ensure temporary decrypted files and keys have a documented lifecycle. Key storage, encrypted local database, and backup exclusion must be inspected, not inferred from hashed filenames.

Push tokens must be account-bound and unregistered/rebound safely. A notification for A cannot load A's data under C; locked-screen pushes contain no private text/media/transcript or unnecessary identity. Screenshot prevention and remote wiping are not promised.

## Release gates and evidence

Required evidence includes:

1. Selected protocol/dependency revision, license approval, bridge build provenance, and independent review scope.
2. Schema/grant/policy diff, staged authorization regressions, and multi-account native/HTTP/REST/Realtime results.
3. Open-socket revocation traces with the old token kept alive, including race outcomes and existing-history limitations.
4. Per-content-type interoperability, integrity, and absence-of-plaintext tests across server/storage/push/AI/log boundaries.
5. Physical iPhone device-enrollment, recovery, cache/account-switch, offline retry, playback, and notification results.
6. Approved retention/migration plan and separate deployment authorization.

Current status: only the audit and existing six source-contract checks are complete. All staged adversarial, crypto, open-socket, migration, and physical-device tests above are **not run**. No implementation or conversation may be described as verified E2EE until the relevant gates pass.
