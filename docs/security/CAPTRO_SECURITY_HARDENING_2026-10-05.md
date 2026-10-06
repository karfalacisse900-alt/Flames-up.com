# Captro security hardening — local implementation report

Reviewed October 5, 2026 (America/New_York); tests completed October 6 UTC.

## Result and release status

This pass fixes demonstrated source-level privilege escalation, private-media
authorization/caching, overbroad reported-message access, and private-message
logging/AI-processing problems. An isolated database test validates a new
least-privilege migration. **Nothing was deployed, uploaded to TestFlight, or
applied to the production database. Production protection has not changed.**

This is not a claim that Captro is hack-proof or that every attack surface has
been independently penetration-tested. Human conversations remain plaintext on
the server and are not end-to-end encrypted. Existing history is preserved.

Source tested: branch `feature/recorded-voice-moderation`, base revision
`ccdf4915df3087e7d5bb09f866a300af5d9a60cb`, with the existing uncommitted voice
work plus the security changes below. No release/build number was incremented.

## Scope inspected

- Worker authentication, optional viewer authorization, profile updates,
  administrative roles, moderation/report routes and attachment signing/delivery.
- Supabase schema, profile/message/group RLS, grants and privileged helpers.
- Native Keychain/ATS configuration, logout/cache behavior, push registration,
  chat Realtime subscriptions and the active conversation error UI.
- Admin browser authentication storage, CSP and reported-message interface.
- Backend/admin dependencies and a pattern scan of 375 tracked text files for
  private-key material, common provider credentials and service-role JWTs.
- Existing payment/ledger, receipt/media, publishing/moderation, and voice tests
  were included in the regression run. This is not a new live payment audit.

The earlier `CAPTRO_MESSAGING_AUDIT_2026-10-05.md` remains the detailed baseline
architecture audit. Its historical production observations were not re-run as
production exploitation tests in this pass.

## Findings addressed

| Risk | Verified source problem | Local correction |
| --- | --- | --- |
| Critical: administrator escalation | `getAdminContext` trusted profile metadata and owner-name/email fallbacks when role lookup failed or returned nothing. | Only server-managed `app_admin_roles` assignments authorize access. Missing, failed, foreign, conflicting or disabled-account assignments fail closed. Legacy owner/admin gates use the same authority. |
| High: read-only admin could write | Two legacy write routes required only `admin:read`. | Post removal requires `content:write`; role assignment requires `roles:write` and the existing admin write rate limit. |
| High: direct database bypass | Authenticated clients could rewrite messages or self-insert group membership; profile writes could modify sensitive metadata. | Migration removes client mutation privileges on profiles, posts, comments and chat tables. Worker service-role writes remain unchanged. Admin-role access is server-only. |
| High: profile disclosure | The profile table contains email and private metadata, but its read policy exposes active rows broadly. | Migration removes direct client SELECT on `app_users`; existing Worker profile projections remain the supported route. Identity helpers keep narrowly scoped private reads. |
| High: table-wide destruction privilege | Broad grants include TRUNCATE, which RLS does not constrain. | Migration revokes TRUNCATE/REFERENCES/TRIGGER on public tables from public/anon/authenticated, plus corresponding future-table defaults for the migration owner. |
| High: attachment signing oracle | A message could refer to another user's backup ID, which the response serializer would sign. | Upload-owner validation before direct/group message insertion and again before signing historical message references. A forged reference does not receive a download signature. |
| High: private-media caching | R2 responses, including byte ranges, advertised year-long public immutable caching. | Full/range responses override storage metadata with private no-store and CDN no-store directives. Unattached media no longer has an admin/owner-name access bypass. |
| Privacy: excess report access | Selecting a reported message fetched up to 12 surrounding messages. | Both Supabase and legacy branches return only the reported message. Audit logging remains. Admin UI accurately labels the selected reported message. |
| Privacy: private content in diagnostics | Duplicate checks put message bodies in URL filters; database errors could include failed rows. | Bounded recent-message comparison occurs in the Worker, not a text-bearing URL filter. Private-message storage errors retain operation/table/status/machine code, not provider message/details/hints. |
| Privacy: automatic private-chat AI | Private Story replies were screened by cloud AI before being stored as DMs. | Remove automatic AI screening from this DM path; retain recipient/block/restriction/rate checks and selected reporting. Public Story thoughts/comments and other public moderation are unchanged. |
| Session inconsistency | Optional viewer authorization did not check the existing server revocation timestamp. | Apply the same timestamp check used by authenticated routes. This does not implement full device/session revocation. |
| UI: rejected session still showed chat | Conversation sync cleared visible content for 403/404 but not final 401. | Hide the rejected conversation and show a sign-in message. On 401 preserve its account-scoped disk snapshot/unsent drafts for reauthentication; do not delete server history. |
| Dependencies | Each package tree had five npm-reported vulnerabilities (four high, one moderate). | Updated lockfiles; Hono 4.13.13, Wrangler 4.147.0 and compatible Workers types 5.20261006.1; patched admin transitive packages. Both clean installs report zero known vulnerabilities. |

The migration also replaces recursive group-membership reads with a private,
fixed-search-path helper, checks active account status for identity mapping, and
keeps participant-only group SELECT access. It does not change media encryption,
membership product rules, billing, or historical content.

## Files changed for this security pass

- `backend-cf/src/index.ts`: active auth/admin/report/message/media paths above.
- `backend-cf/tests/security_boundaries.test.mjs`: executes actual production
  functions and route handlers against isolated dependencies; executes SQL in
  PGlite under synthetic authenticated/anon/service roles.
- `supabase/migrations/20261006012846_security_backend_write_boundary.sql`:
  generated with `supabase migration new`, edited and tested locally only.
- `admin-web/src/App.tsx`: reported-message privacy wording.
- `ios_native/MIRA/Sources/MIRANative/Screens/ConversationNativeView.swift`:
  session rejection handling and appropriate recovery text.
- `backend-cf/package.json`, `backend-cf/package-lock.json`,
  `admin-web/package-lock.json`: dependency security updates.
- This report. Other dirty voice/character/chat files existed before this pass
  and were preserved, not attributed to these security fixes.

## Verification actually performed

- Backend TypeScript check: **PASS** after dependency updates and final edits.
- Full backend regression suite: **231 PASS, 0 failures**.
- New security coverage: **12 PASS**. Exercises forged admin metadata, failed
  role lookups, role conflicts, disabled accounts, privileged legacy routes,
  selected-only reports, cross-owner attachment signing, private cache headers,
  orphan media access, private database errors, duplicate checks without body
  URL filters, private Story replies without AI, revoked optional sessions, and
  SQL access restrictions.
- Isolated SQL test uses Alice, Bob and unrelated Mallory. Unauthorized reads,
  membership insertion, profile/role forgery, message rewriting and TRUNCATE are
  denied. Service-side membership removal, blocking and account banning change
  the next authorized SELECT on the same database connection. Message history
  remains intact. **This is not a live Supabase Realtime/WebSocket revocation
  test or a physical-device test.**
- Admin web TypeScript/Vite production build: **PASS**.
- Clean `npm ci --ignore-scripts` for both projects: **PASS**, zero known audit
  vulnerabilities at verification time. Dependency lifecycle scripts were not
  executed. Wrangler's resolved dev dependency includes Miniflare
  `5.20261001.0-alpha`; the upgraded local Worker runtime still needs its own
  integration smoke test before release.
- Tracked secret-pattern scan: one match in `scan.ts` was a PEM-header parsing
  regex, not an embedded key. No actual credential found in the checked formats.
  This did not inspect Git history, remote logs, CI secrets, or untracked secret
  files and does not prove those are clear.
- `git diff --check`: **PASS** before this report.
- Native iOS build, simulator, physical iPhone and UI screenshots: **NOT RUN**.
  This Windows host has no Xcode or connected iPhone.
- No authenticated production attack test, production database migration,
  provider configuration mutation, deployment, or TestFlight upload performed.

## Remaining security work / rollout blockers

1. **Messaging encryption and private attachment architecture.** E2EE is still
   absent. Existing plaintext history, service-role access and public-provider
   image/video processing remain risks. Follow the existing protocol decision
   and migration plan; do not label chats encrypted or destroy old history.
2. **Signed download revocation.** Existing 24-hour links are transferable bearer
   capabilities, not device-bound authorization. This pass fixes who can obtain
   a new signature, not immediate invalidation of every previously issued link.
   Already cached responses also require an explicitly authorized CDN/cache
   invalidation plan; new headers cannot retroactively erase old copies.
3. **Real device/session revocation.** Native logout currently clears local
   credentials rather than completing a verified server/device revocation flow.
   RLS now checks active account state, but it does not validate every open JWT
   against `auth.sessions` or implement logout/device revocation. Test an open
   Realtime connection and issued media links after revocation in staging.
4. **Account-switch isolation.** Push registration deduplicates by device token,
   not account, and old account bindings may remain active. In-flight requests
   and cache writes need account-generation/cancellation tests. Native protected
   storage/cache cleanup and pending-message preservation need device testing.
5. **Broader RPC/logging review.** Other database helpers/RPC errors can still
   retain provider error text; only private-message storage errors were changed
   here. Audit every SECURITY DEFINER RPC and column-level grant against the
   actual deployed catalog, not only migrations. No blanket claim of all-table
   write isolation is made beyond the migration's explicit tables.
6. **Admin rollout prerequisite.** Confirm legitimate owner/admin assignments in
   `app_admin_roles` through an authorized operator before deployment. Accounts
   relying on the removed metadata/name fallback will intentionally lose admin
   access. Do not bootstrap by trusting mutable profile fields.
7. **Staging compatibility.** Apply the migration only to an approved isolated
   environment first. Verify login/profile updates, post/comment moderation,
   group joins, media delivery and native Realtime using supported clients.
   Confirm no released client depends on the revoked direct table operations.
   Do not restore insecure broad grants as a silent compatibility fallback.

Release approval is still required separately. Preserve existing data and audit
records; stage the migration/backend/native changes together with a tested
rollback plan that does not reinstate profile-based administrator access.

## References

Supabase explains why user-editable metadata must not authorize access and why
RLS and grants need to be designed together in its
[RLS documentation](https://supabase.com/docs/guides/database/postgres/row-level-security).
The upstream [Hono CORS advisory](https://github.com/honojs/hono/security/advisories/GHSA-8j4g-w8fx-2239)
supports patching the affected dependency; the npm audit also identified other
transitive advisories. Package audit severity is not evidence that every advisory
was remotely exploitable in Captro's specific configuration.
