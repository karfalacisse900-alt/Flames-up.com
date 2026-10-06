# Captro messaging security audit

Captro's current messaging is server-readable, not end-to-end encrypted. Message bodies are sent to the Worker in plaintext over TLS and stored as readable database fields. Attachment access links do not encrypt media. Supabase RLS provides some participant filtering, but the inspected live policies and backend authorization contain serious gaps.

**Immediate priority:** a user-writable profile metadata field is trusted as an administrator role by the inspected Worker code. This is a credible privilege-escalation path into reported-message access. It needs a separately authorized remediation; no production permissions were changed during this audit.

## Scope and evidence

Audit date: October 5, 2026. Source revision: `ccdf4915df3087e7d5bb09f866a300af5d9a60cb`, branch `feature/recorded-voice-moderation`. Paths and line numbers below refer to that revision.

The audit includes native chat routes and models, Worker APIs, committed configuration and migrations, and read-only live Supabase catalog queries. The catalog queries covered policies, grants, columns, constraints, triggers, publication columns, and helper definitions. They did not read message history, users' credentials, private media, or provider secrets. The connected Captro project is `cclgvxukwccvtgrbcwie`, matching both Worker configuration URLs. Its branch listing returned no development branches.

Live database policy evidence is distinguished from source-based findings. The deployed Worker artifact was not compared with the source revision, so the described backend behavior is confirmed in code, not a production exploit demonstration. Provider access lists, backup retention, stored logs, bucket configuration, and physical-device behavior require further verification.

No exploitation, production mutation, history deletion, secret rotation, deployment, or TestFlight upload occurred. Only the three security documents accompanying this audit were added locally. Existing `supabase/.temp/` files were preserved. These documents contain sensitive findings and have not been pushed or published.

## Actual messaging paths

The active native inbox is `ChatNativeView` in `ios_native/MIRA/Sources/MIRANative/Screens/ProfileChatVerificationStudio.swift:2164`, opening `ConversationNativeView` at line 2229. Profile, commerce, and other group entry points also instantiate that conversation view; fixing only the inbox would not cover them all.

`ConversationNativeView.swift:247` sends readable text through the existing API client. Direct messages use `/messages`; groups use `/group-chats/:groupId/messages`. Foreground synchronization fetches readable messages, with Supabase Realtime notifications prompting API reconciliation. Story replies are another direct-message producer, separate from the normal chat composer.

| Material | Current locations and readers | Plaintext boundary |
| --- | --- | --- |
| Direct-message text | Native draft and `MIRAMessage.content`; Worker request; Supabase `app_messages.body`; native thread JSON caches | Worker and service-role/database operators can read it. Authorized participants can read it through APIs or database access. |
| Group text | Same native model; Worker; `app_group_messages.body`; caches | Worker/database readers and members can read it. Membership authorization has the gap below. |
| Inbox previews | API conversation assembly and `MIRAConversation.lastMessage`; local JSON cache | Readable server-generated previews and local copies; not ciphertext-derived previews. |
| Photos and videos | Local source files, shared media uploader, Cloudflare Images/Stream, R2 backup where used, database media references, decoded image and media caches | Providers and Worker processing can receive original media. Current pipeline can run automatic cloud moderation. |
| Thumbnails and posters | Provider-derived URLs, message payloads, native decoded-image cache | These are readable derivatives and must be included in an E2EE design, not treated as harmless metadata. |
| Audio and files | Server accepts media references; native models/renderers recognize audio; shared audio/file upload helpers exist | DM recording-to-delivery support was not verified. These types are not eligible for an encryption claim merely because a model field exists. |
| Transcripts | No dedicated DM transcript field found in the inspected message model/schema. Separate voice post/comment pipeline stores machine/display transcripts. | Public voice processing sends audio to OpenAI transcription and transcript to moderation. That flow must not become the private DM pipeline. |
| Reports | User-selected target ID, then server-readable reported message and server-selected nearby conversation context | Current moderator route reveals more than the reporter explicitly selected. Database operators can independently read ordinary history. |
| Push | Notification rows and APNs payload contain generic message body text but sender identity and routing identifiers | No actual DM body was found in current message push payloads; conversation existence and identity metadata still leave the device. |
| Keys | User access/refresh tokens in Keychain; provider/admin/signing credentials server-side | No per-device messaging identity, prekey, ratchet, or attachment-encryption key system was found in the inspected implementation. |

TLS and provider disk encryption are useful transport/storage protections, but neither prevents the backend or a privileged database reader from reading conversations.

## Findings requiring action

### Critical administrator trust boundary

Live `app_users` policies allow an authenticated user to update their own row, checking `supabase_user_id = auth.uid()`. Authenticated users have column privileges for `metadata`, `email`, `username`, verification fields, and other account fields. The inspected live triggers only maintain timestamps; no protected-field guard was present.

`backend-cf/src/index.ts:21175` initializes administrator role from `metadata.admin_role` or `metadata.role`. An authoritative `app_admin_roles` lookup can override it, but an absent role row or lookup failure retains the metadata fallback. It also trusts `metadata.is_admin` and recognized owner username/email. These profile fields are not a safe administrator authority under the live update policy.

**Consequence:** ordinary authenticated profile writes plausibly grant backend administrator permissions, including reported-message access. This is a confirmed unsafe composition of live privileges and inspected code; it has not been exploited against production. The first staging regression must demonstrate rejection of self-assigned roles and owner identities.

Required fix: authorize administrators solely through server-managed, non-user-writable records; fail closed on lookup errors. Restrict editable profile columns and server-owned account status/verification/revocation fields. Do not rely on client UI hiding these values. Reconcile existing role assignments before any production change.

### High message integrity and membership gaps

Live direct-message SELECT policy checks whether the caller is sender or receiver and whether the pair is blocked. INSERT checks sender identity, a different receiver, and blocking. These are useful protections but do not establish a request/acceptance or device authorization boundary.

Live UPDATE checks only whether the caller remains one participant. The authenticated role can update every message column, including body, sender, receiver, and conversation identifiers. No inspected constraint or trigger makes participants immutable. A recipient can therefore pass the row predicate while altering message content or retargeting the other participant. Staging must test recipient edits, sender impersonation, participant reassignment, and blocked-user updates explicitly.

Live `app_group_chat_members` INSERT checks only that `user_id` is the caller. It does not require an invitation, owner approval, or valid paid membership; role is not constrained by that policy. Constraints are a primary key and `(group_id, user_id)` uniqueness, without an inspected membership-validation trigger or foreign key. The Worker group guard trusts membership existence. Direct database self-enrollment therefore undermines that guard. A self-referencing SELECT policy also requires staging checks for RLS recursion; successful group-message exfiltration was not asserted or attempted in production.

Required fix: server-controlled membership creation with explicit invitation/join authorization, immutable message participants, narrowly scoped receipt updates, and consistent blocking/request checks across Worker, REST, and Realtime. E2EE must not conceal broken authorization behind ciphertext.

### High excessive database privileges

Live `anon`, `authenticated`, and `service_role` grants on `app_messages`, `app_group_messages`, and `app_group_chat_members` include SELECT, INSERT, UPDATE, DELETE, REFERENCES, TRIGGER, and TRUNCATE. RLS restricts row operations but does not protect TRUNCATE. A table grant does not by itself prove that PostgREST exposes a TRUNCATE operation; this is an unnecessary database-role privilege, not a demonstrated anonymous HTTP attack.

Use minimum table, column, and function privileges in staging. Audit related exposed tables and SECURITY DEFINER functions too. The service role bypasses participant RLS by design, so every Worker service-role path must have its own authorization checks.

### High private media uses public processing

`ConversationNativeView.swift:257` calls shared `MIRAMediaUploadService.upload` for chat photos/videos. `MIRAMediaUploadService.swift:260` uses `/media/upload-intent` and `/media/complete`, waiting for pre-publication moderation and a public delivery URL. No private-message purpose separates this upload from public feed media.

`index.ts:14008` processes media moderation jobs and calls `runWorkersAiImageModeration` using media samples. The chat photo/video path can therefore expose private conversation attachments to Cloudflare processing/AI. Approved provider delivery is not participant-only encryption. Committed Stream configuration sets signed playback off; Images signed-URL behavior defaults off when absent. Live runtime overrides and existing provider assets were not enumerated.

`wrangler.toml:51` and `:55` bind media backups and voice recordings to the same R2 bucket. Separate binding names do not create storage isolation. New private attachments need a separate opaque ciphertext path and bucket, with no public media processing, server thumbnails, transcription, or routine AI access.

### High transferable attachment links and caching

`index.ts:4930` signs R2 access links for 24 hours with the server JWT secret. That HMAC authorizes access; it does not encrypt the file. The signature is not tied to a viewer, device, conversation, or revocation version.

`serveMediaBackup` at `index.ts:24408` accepts a valid signed link without a current participant check. Its responses permit `public, max-age=31536000, immutable` caching, including media range responses. A copied link can remain useful after blocking or session revocation, and permitted browser/proxy caches can retain plaintext. Actual cache contents were not inspected.

The unsigned access path checks legacy D1 ownership/message/group records rather than consistently using the Supabase primary model. Some orphaned media is available to owners/admins. `messagePayload:5180` can sign referenced backup IDs; message creation does not visibly bind all accepted media references to an authorized uploader. Cross-asset signing is a code-based candidate requiring disposable-environment testing, not a demonstrated production exploit.

### High reporting exceeds user selection

`validateReportTarget` at `index.ts:4041` checks the reporter's access to the target. However, `/admin/messages/reported/:reportId` at `index.ts:24086` returns the reported plaintext and retrieves nearby pair messages, selecting up to 12 contextual entries within a time window. Those additional messages were not individually selected by the reporter.

The target design must upload only explicitly selected evidence after a disclosure preview. A report must never release a room key, ratchet state, or automatic surrounding history. An authorized case reviewer may read submitted evidence, not the underlying private room. Current report audit logging is useful but does not create that boundary.

### High session and device revocation is incomplete

Worker JWT verification checks signature/issuer/expiry or uses Supabase user validation. `resolveSupabaseSessionUser` at `index.ts:12312` retains identity and token times but not `session_id`. Middleware checks a profile `session_revoked_at`, which is user-writable under current privileges. The live `private.captro_current_app_user_id()` helper maps `auth.uid()` to an app user without checking active Auth session, crypto device, or revocation generation.

`MIRAChatRealtime.swift` authenticates with a user JWT and subscribes to participant-filtered inserts. Supabase Swift 2.49.0 transmits the selected column projection in the join configuration, so the normal native subscription is narrower than the database publication. The live publication nevertheless contains full plaintext message columns; an alternate authorized client can omit that projection. Subscription filters are not an authorization substitute.

No crypto-device enrollment registry was found. `MIRADeviceTrustService.swift` supplies monitoring/App Attest support signals for selected actions; it is not approval of a messaging identity key. Push `device_id` is also not an encryption device identity.

`MIRAAuthSession.swift:362` logout clears local tokens/cache scope but does not show a server logout call. Removing a refresh token or changing the screen does not prove an already-open Realtime connection or unexpired JWT has lost access. The conversation model clears revoked access on 403/404, not 401. Keep-open revocation tests remain mandatory.

### Medium local retention and account switching

`MIRAChatLocalStore.swift` caches readable messages and previews through `MIRALocalJSONCache` in `MIRAPerformance.swift:263`. Account-hashed filenames separate normal lookups but do not encrypt JSON. Decoded media also has readable disk caches. `storeOutgoingMedia:136` writes original files into a global UUID-named `MIRAChatMedia` directory without account-specific content encryption.

`MIRAAPIClient.swift:156` configures a substantial default HTTP disk cache. Logout clears URLCache and switches to guest scope but retains thread/image/source files. This is not a finding that iOS hardware encryption is absent; explicit file protection, device-lock, backup, and forensic behavior were not tested.

Async work can outlive the originating account. Scope calculation at save time and a global current-token provider require generation-bound cancellation and write checks. `MIRAPushTokenRegistry` deduplicates registration by token alone, so a same-device account switch can suppress registration for the new account. Test token unbinding, notification routing, playback, downloads, and late cache writes under account changes.

### Medium delivery and retry semantics

`GET /messages/:userId` at `index.ts:18639` marks incoming rows read during retrieval; it does not prove successful recipient decryption or user viewing. Sending has an in-flight guard, but `SendMessageBody` and `GroupMessageBody` in `MIRAModels.swift:1743` have no stable client request ID. The server duplicate-body check is a rate-control heuristic, not an idempotent operation. Retry removes a local item before resending and can duplicate a message if the first server response was lost.

Use separate persisted, decrypted/delivered, and viewed acknowledgments with narrow update authority. A persistent encrypted outbox and stable per-device message identifier must reconcile offline retries without discarding the original or advancing ratchets incorrectly.

### Medium logs and cloud AI boundaries

No routine chat-body print statements were found in the active native chat. Current DM notification bodies are generic. Those are positive boundaries to preserve.

The Worker duplicate-message query includes plaintext body in a PostgREST query string, exposing it to any configured URL/access logging. Error wrappers include upstream response excerpts. Client-event and log scrubbers block sensitive field names, not arbitrary sensitive values under other keys. Actual stored provider logs and retention were not inspected; this identifies reachable exposure paths, not a claim about a particular archived log entry.

Story replies call `screenCaptroText` at `index.ts:18155`, sending reply text to OpenAI moderation before storing it as a DM. The separate public voice pipeline in `backend-cf/src/voice.ts:284` sends voice post/comment audio for transcription and stores transcripts for moderation/review. Neither can be silently reused for E2EE conversations. Keep public content safety and user-selected private reporting distinct.

## Current keys and trust

Native access/refresh tokens use Keychain with `WhenUnlockedThisDeviceOnly`, a useful existing boundary. `/chat/realtime-config` returns only publishable/anon configuration behind authentication, not the Supabase service-role key. Provider keys and the permanent OpenAI credential are server environment variables in the inspected code; their actual values were not read.

The server media HMAC key is an application-wide access-signing credential, not a messaging encryption key. There is currently no supported mechanism making the backend unable to decrypt a DM. Database owners, service-role consumers, privileged provider operators, and some moderation paths can access readable material. Exact human IAM membership and historic export recipients remain to be inventoried by authorized operators.

## History and retention

The legacy transfer functions at `index.ts:14553` and `:14609` copy readable D1 messages into Supabase without deleting the source. Historical D1 rows, Supabase rows/backups, local JSON/media, provider derivatives, moderation samples, reports, notification metadata, and permitted caches may all survive a future encrypted cutover.

No historical user data was read or copied into a test environment. Encrypting a new table does not remove historical exposure. Existing `SECURITY_OPERATIONS.md` describes media routes generally as authenticated/visibility checked; it should not be treated as proof that the signed-link bypass and public cache headers above are safe.

The accompanying migration plan preserves old history with an explicit legacy boundary. Any purge, retention change, provider deletion, backup expiration, or conversion of private history requires its own approved plan. There must be no retroactive E2EE label on old messages.

## Verification results

| Check | Result |
| --- | --- |
| Native and Worker source trace | Completed for the paths cited above |
| Live Supabase policy/grant/schema/publication inspection | Completed with read-only catalog queries |
| Existing chat and club contract checks | 6 passed, 0 failed using Node 24.15.0 |
| Unrelated authenticated accounts through REST/Worker/Realtime | Not run; no isolated test project exists |
| Revocation with an unexpired token and open socket | Not run |
| Attachment bearer/cache and cross-asset attacks | Not run |
| Physical iPhone cache, lock, push, and media verification | Not run |
| E2EE protocol or content-type verification | Not implemented; no encryption claim permitted |

Baseline command: `node --experimental-strip-types --test tests/chat_realtime_contract.test.mjs tests/club_chat_context.test.mjs` from `backend-cf`. These tests are source-contract checks, not proof of participant-only access. An initial WSL Node 18 attempt failed because that version lacks type stripping; the successful command used Windows Node 24. No app runtime build or production API attack was performed.

The next phase requires an independently isolated environment and protocol/licensing approval. The default Worker development configuration points at the same Supabase URL and R2 buckets as production; running it unchanged is unsafe for security experiments.
