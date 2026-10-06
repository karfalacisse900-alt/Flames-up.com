# Captro live voice and conversation implementation

The active native voice and human conversation routes have local implementation changes. Live voice is **not yet accepted as fixed**: no authenticated provider session, audible iPhone exchange, or native runtime capture was available in this environment. No backend deployment, TestFlight upload, production permission change, or history deletion was performed.

## Existing failure evidence

Source inspection found that both credential minting and native session configuration disabled automatic replies with `create_response: false`. A separate committed-item queue issued manual `response.create` events and tried to recover response races. This was replaced by automatic semantic VAD response creation, with no duplicate manual response request.

Other demonstrated code defects were broad retries for provider/authentication/configuration failures, full conversation recreation on headphone route changes, and microphone chunks queued before mute that could survive an unmute. These paths now distinguish permanent failures, restart only the audio engine for route changes, and invalidate microphone chunks across mute generations.

These are source-level defects, not a demonstrated explanation for a particular deployed iPhone failure. Cloudflare CLI authentication was expired. The deployed `/api/ai/realtime/session` unauthenticated probe returned HTTP 401, `Not authenticated`, with request ID `a460cdfd1c482fc4`. That proves route reachability and its authentication gate only. The intended OpenAI project, active key, model entitlement, and funded billing account remain unverified. Do not request or paste permanent secrets into chat.

## Active routes and changed files

All paths below are relative to the repository root.

- `ios_native/MIRA/Sources/MIRANative/Services/CaptroRealtimeVoiceSession.swift`: the actual Capture live session; automatic VAD, independent connection/mute/playback signals, generation guards, bounded recovery, foreground cleanup, audio routing, playback-level tap, correlation diagnostics.
- `Screens/CaptroCaptureAssistantView.swift` under the same native source root: focused Captro AI screen, elapsed timer, mute/end controls, first-use AI processing disclosure, optional transcript/output menu, existing recording-to-editor handoff.
- `Components/CaptroVoiceCharacterView.swift` and `Components/CaptroVoiceVisualState.swift`: separate body/eye/mouth layers based on the supplied PNG and motion spec. The character renderer is replaceable independently of the session. Breathing/blinking use an animation clock; mouth opening uses actual rendered assistant audio. Happy/joking are explicit expression hooks, not guessed emotions.
- `Screens/ConversationNativeView.swift`: compact room header, left-aligned grouped group discussion, pale sage direct outgoing bubbles, optional pinned row, new-message indicator, real audio-message rendering, deliberate human voice recording/upload/retry.
- `Screens/ProfileChatVerificationStudio.swift`: only the active `ChatNativeView` area gains a distinct Captro AI entry to the same live voice screen; Profile is not redesigned.
- `Components/CaptroChatVoiceComponents.swift`: separate human voice recorder/preview and actual AVPlayer playback. It never invokes AI or automatic transcription.
- `Components/CaptroVoiceComponents.swift`: cancellation check after permission resolution prevents a canceled recording start from opening the microphone late.
- `backend-cf/src/index.ts`, `realtime-session.ts`, and `realtime-diagnostics.ts`: existing authenticated Realtime mint route, current flat credential validation, semantic VAD configuration, classified safe provider failures, finite expiry validation, secret-safe diagnostic allowlist.
- Tests: `realtime_session.test.mjs`, `realtime_diagnostics.test.mjs`, `capture_assistant_guard.test.mjs`, `voice_pipeline.test.mjs`, `club_chat_context.test.mjs`.

Home, Settings, composer, database schema, RLS, existing message history, and public voice-post/comment moderation pipelines are unchanged. Existing API client, keychain-backed Captro authentication, R2 attachment upload, signed message-media delivery, room synchronization/local cache, recorder, playback coordinator, and native editor handoff are reused. Human chat has no new E2EE label; the separate messaging security audit and migration restrictions still apply. Existing signed-link/caching and historical plaintext risks are not solved by this UI patch.

## Transport and session configuration

This patch retains one native Realtime **WebSocket** PCM stream and AVAudioEngine voice-processing/playback path. It is continuous streaming, not recorded-clip uploading. There is no second microphone transport, WebView, prerecorded greeting, or permanent client API key. The selected model is `gpt-realtime-2.1`, voice `marin`, with PCM 24 kHz on the provider boundary; device input is converted from its actual negotiated format.

VAD is `semantic_vad`, eagerness `medium`, `create_response: true`, `interrupt_response: true`. Backend credential minting uses `POST /v1/realtime/client_secrets`, validates flat `value` and `expires_at`, and bounds ordinary responses to 256 output tokens. Established sessions are not restarted on credential connection expiry. Existing per-user mint rate limits remain.

OpenAI recommends WebRTC for mobile clients. It was not added here: the repository has no native WebRTC audio-device integration, whereas its current engine provides a real render tap and played-buffer acknowledgments needed for measured mouth movement and WebSocket truncation. A WebRTC migration would require validated library/device ownership and playback instrumentation rather than an untested parallel audio stack. Consequently `/v1/realtime/calls`, SDP, ICE, and WebRTC behavior were **not tested or implemented** in this patch. This transport choice still requires physical-device validation.

Server VAD cancels generated responses on interruption; the native client stops playback, discards queued output, and truncates at the actual player position. Ready requires a session acknowledgment with the expected configuration, active engine, and first PCM send. Receiving speech remains separately observable; permission alone is never Ready.

Official contracts checked: [Realtime WebSockets](https://developers.openai.com/api/docs/guides/voice-websockets?voice-api=realtime), [WebRTC](https://developers.openai.com/api/docs/guides/voice-webrtc), [turn detection](https://developers.openai.com/api/docs/guides/realtime-vad), and [conversation interruption](https://developers.openai.com/api/docs/guides/realtime-conversations).

## Verification results

Source revision: `ccdf4915df3087e7d5bb09f866a300af5d9a60cb` plus the uncommitted changes listed above. Repository configuration remains marketing version 1.0.1, project version 2; these are not a claim about the latest TestFlight build. Environment: Windows PowerShell, Node 24.15.0, WSL Linux without Swift/Xcode, no accessible physical iPhone.

- Backend TypeScript: `node node_modules/typescript/bin/tsc --noEmit` — PASS.
- Full backend/contract suite: `node --experimental-strip-types --test tests/*.test.mjs` — 219 PASS, zero failures (observed suite duration about 5.3 seconds).
- Targeted voice/diagnostic/recorded-content regression suite — 29 PASS.
- Native compilation, physical iPhone, runtime screenshots/recording — NOT RUN.
- Authenticated OpenAI session creation, account/project and billing request — NOT RUN.
- Actual microphone frames sent, provider speech_started, completed turn, automatic response, AI audio received and audible playback — NOT OBSERVED in a live attempt.
- Barge-in, 20-turn conversation, speaker/Bluetooth routing, mute, interruption, route/network recovery, repeated start/end, canceled connection, denied permission, account-switch isolation, latency, smoothness and resource usage — NOT RUN on device. No timing/performance claim is made for these.

## Required acceptance run

Restore existing Cloudflare diagnostic access locally with `wrangler login`; use an authenticated consenting Captro test account. Make one session request with the deployed intended configuration and correlate its provider request ID/project headers with privacy-safe client stages. Never log headers, tokens, full SDP, private transcripts, or audio. Do not run repository production smoke scripts that create/delete real users or posts without reviewing their side effects.

Build through the supported macOS/Xcode workflow without upload. On a physical iPhone, record version/revision/device/OS and prove: speak naturally, pause, receive an audible automatic answer, interrupt, continue for 20 turns, mute during both speakers, end during playback, and verify microphone shutdown. Exercise AirPods, route changes, incoming interruption, background exit, Wi-Fi/cellular switch, offline recovery, permission denial, canceled startup, invalid provider configuration, model/quota/rate errors, transcript/output controls, and account switching. Verify human text/media/voice sends and failures with authorized test participants; no AI endpoint should receive their messages.

Measure start-to-ready, completed-turn-to-audible-answer, interruption-to-playback-stop, and failed stage durations from consenting runtime traces. Capture actual empty/active/error voice and direct/group room screenshots. If recording cannot include both audio sides, document that limitation and use device playback observation plus event traces. Deploy or upload only after separate user approval. The supplied character image is no longer a blocker; visual fidelity and all live/device acceptance remain blocked by unavailable authenticated diagnostics and iOS runtime/device access.
