CAPTRO STUDIO — UNPUBLISHED PROFESSIONAL WORKSPACE

Reuse the existing Captro account, Worker, admin review and creator/business APIs.
No separate account database, payment ledger or publishing system is introduced.

Development (from studio-web):
  npm ci
  npm run dev
  npm run build
  node tests/studio.browser.mjs
  node tests/session.browser.mjs

The browser checks require the dev server at http://127.0.0.1:4180/ and Edge.
They intercept API requests with isolated fixtures; sample businesses are never
published. session.browser.mjs exercises actual API-client code with controlled
responses, including account changes during delayed 401/refresh requests.

For an authorized integration environment, set VITE_CAPTRO_API_BASE to its API
base including /api. The existing default is https://api.flames-up.com/api.
Configure the matching Worker's CAPTRO_STUDIO_ORIGIN to the exact Studio HTTPS
root origin. Align public/_headers connect-src with that API. Do not put server
credentials or provider secrets in Vite variables.

Prepare the Business ordering and Professional migration dependencies before
using the new APIs. See ../docs/professional-accounts-studio-verification-20261115.txt
for schema prerequisites, rollout order, checks, and remaining limits.

Sign in with the existing account/password, or open Studio from iPhone Settings
for a single-use 60-second handoff. A delegated Studio session expires in one hour.
Apple/Google-only users reuse their iPhone account; no duplicate signup is offered.
Server checks enforce current account status, independent professional roles,
ownership, session expiry and endpoint scope. Approval never enables live checkout.

No deployment, production migration, site publication or live payment is authorized
by the development/test commands above.
