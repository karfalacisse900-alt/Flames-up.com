import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const authSession = readFileSync(
  new URL('../../ios_native/MIRA/Sources/MIRANative/Services/MIRAAuthSession.swift', import.meta.url),
  'utf8',
);
const authView = readFileSync(
  new URL('../../ios_native/MIRA/Sources/MIRANative/Screens/AuthNativeView.swift', import.meta.url),
  'utf8',
);
const rootView = readFileSync(
  new URL('../../ios_native/MIRA/Sources/MIRANative/App/MIRANativeRootView.swift', import.meta.url),
  'utf8',
);
const mainFeed = readFileSync(
  new URL('../../ios_native/MIRA/Sources/MIRANative/Screens/MainFeedView.swift', import.meta.url),
  'utf8',
);
const authDiagnostics = readFileSync(
  new URL('../../ios_native/MIRA/Sources/MIRANative/Services/MIRAAuthDiagnostics.swift', import.meta.url),
  'utf8',
);
const apiClient = readFileSync(
  new URL('../../ios_native/MIRA/Sources/MIRANative/Services/MIRAAPIClient.swift', import.meta.url),
  'utf8',
);
const keychain = readFileSync(
  new URL('../../ios_native/MIRA/Sources/MIRANative/Services/MIRAKeychainSessionProvider.swift', import.meta.url),
  'utf8',
);

test('guest access is persisted and routed into the app without an auth token', () => {
  assert.match(authSession, /@Published public private\(set\) var isGuest: Bool/);
  assert.match(authSession, /private static let guestModeKey = "native\.auth\.guest\.v1"/);
  assert.match(authSession, /public func continueAsGuest\(\)[\s\S]*setGuestMode\(true\)/);
  assert.match(authSession, /public func exitGuestMode\(\)[\s\S]*setGuestMode\(false\)/);
  assert.match(rootView, /if authSession\.user == nil && !authSession\.isGuest/);
  assert.match(rootView, /GuestSignInRequiredView/);
  assert.match(authView, /Text\("Continue as Guest"\)/);
  assert.match(mainFeed, /\/posts\/world-board\?limit=/);
  assert.match(mainFeed, /private let publicFeedCacheKey = "native\.main\.public\.feed\.v1"/);
  assert.match(mainFeed, /if isGuestFeedMode \{[\s\S]*?\/posts\/world-board\?limit=/);
});

test('native OAuth preserves provider requirements before calling Captro', () => {
  assert.match(authView, /GIDConfiguration\([\s\S]*serverClientID: googleServerClientID/);
  assert.match(authView, /result\.user\.refreshTokensIfNeeded\(\)/);
  assert.match(authView, /request\.nonce = sha256\(nonce\)/);
  assert.match(authView, /nonce: nonce,[\s\S]*api: api/);
  assert.equal((authView.match(/\.onOpenURL/g) ?? []).length, 0);
  assert.equal((rootView.match(/\.onOpenURL/g) ?? []).length, 1);
  assert.match(rootView, /MIRAAuthDiagnostics\.callbackReceived\(url, googleHandled: googleHandled\)/);
  assert.match(authView, /isGoogleCancellation\(error\)/);
  assert.match(authView, /isAppleCancellation\(error\)/);
  assert.match(authSession, /guard !isWorking else \{[\s\S]*duplicate_request_ignored/);
  assert.match(authSession, /backend_session_created/);
  assert.match(authSession, /session_persisted/);
  assert.match(authSession, /auth_state_updated/);
  assert.match(authDiagnostics, /case providerCancelled/);
  assert.match(authDiagnostics, /case credentialExchangeFailure/);
  assert.match(authDiagnostics, /case sessionFailure/);
  assert.match(apiClient, /!isCredentialRequest,[\s\S]*status == 401 \|\| status == 403/);
  assert.match(authSession, /private actor MIRAAuthRefreshCoordinator/);
  assert.match(authSession, /if let inFlight/);
  assert.doesNotMatch(authSession, /refreshAccessTokenIfNeeded[\s\S]{0,120}if isWorking \{ return false \}/);
  assert.match(keychain, /else \{[\s\S]*clearRefreshToken\(\)/);
});

test('terms validation explains the requirement instead of making auth look inert', () => {
  const canSubmit = authView.match(/private var canSubmit: Bool \{[\s\S]*?\r?\n  \}/)?.[0] ?? '';
  assert.notEqual(canSubmit, '');
  assert.doesNotMatch(canSubmit, /hasAcceptedCurrentTerms/);
  assert.match(authView, /guard requireTermsAcceptance\(\) else \{ return \}/);
  assert.match(authView, /Accept Captro's terms before continuing with Apple/);
});
