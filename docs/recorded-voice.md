# Recorded voice setup

Captro now supports voice-only posts, photo posts with one voice attachment, and voice replies. A submitted recording stays private until the backend has validated the actual file, transcribed it, screened its transcript and associated text, and approved that exact content version.

## Required configuration

1. Apply `supabase/migrations/20260919150750_voice_recordings_moderation.sql`. It creates the private `captro-voice-private` bucket, private voice/job/review tables, RLS, indexes, and the version-checked publication function.
2. Configure the server-only variables shown in `backend-cf/.env.example`. `OPENAI_API_KEY` is required. The defaults are `gpt-transcribe` for transcription and `omni-moderation-latest` for transcript/text moderation.
3. Bind `MEDIA_MODERATION_QUEUE` as both the Worker queue producer and consumer. Voice jobs use the existing durable queue and the scheduled recovery pass; they are not detached request promises.
4. Give approved moderators `content:read` and `content:write`. Flagged, ambiguous, silent, appealed, and conflicting submissions remain private in Admin → Voice Review. Do not launch review-required submissions without staffed reviewer access.

`CAPTRO_VOICE_AUTO_REJECT` defaults to `false`. Leave it off during the initial evaluation. Clean, complete recordings can publish automatically; first-stage flags remain private for human review. Provider errors and unclear audio do not create policy strikes and never fail open.

## Security and privacy behavior

- The app requests microphone access only after the user taps Record.
- Audio is uploaded directly to private Supabase Storage through the authenticated backend. Filenames, client MIME type, duration, and approval claims are not trusted.
- Playback and transcript endpoints re-check the signed-in viewer, current publication state, and post/reply audience. There are no public storage URLs.
- The immutable storage key and SHA-256 bind moderation to the exact recording version. Caption changes require another screening pass. Delayed work cannot publish a deleted item or an old version.
- Ordinary logs exclude raw recordings, transcripts, signed links, and credentials.
- Deleting or removing content denies new playback and deletes the private storage object. A recording already downloaded to a device cannot be remotely erased.

Retention periods for abandoned, failed, rejected, and deleted submissions must be selected as an operating policy before launch. The schema records the relevant timestamps; configure and document the cleanup schedule for the deployment rather than presenting it as a legal guarantee.

## Verification

Run:

```powershell
cd backend-cf
npm install
npm test
npx tsc --noEmit

cd ../admin-web
npm install
npm run build
```

Automated coverage includes server-measured duration, corrupt input, silence/empty transcripts, safe approval, rollout holds, automatic-rejection gating, evidence grounding, private storage, and exact-version publication. Existing repository tests continue to cover authentication, feed visibility, reporting, blocking, admin permissions, and payment isolation.

An iPhone/device pass is still required for microphone denial, incoming-call interruption, backgrounding, route changes, seeking, Bluetooth behavior, and mixed-language recognition. Live-provider evaluation should use consented or synthetic English and French samples, accents, mixed language, counterspeech, quotations, threats, and instruction-injection phrases. Measure missed violations and incorrect flags separately; do not claim perfect detection.

Official integration references:

- https://developers.openai.com/api/docs/guides/speech-to-text
- https://developers.openai.com/api/docs/guides/moderation
- https://developers.openai.com/api/docs/guides/structured-outputs
