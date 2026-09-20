# Recorded voice setup

Captro now supports voice-only posts, photo posts with one voice attachment, and voice replies. A submitted recording stays private until the backend has validated the actual file, transcribed it, screened its transcript and associated text, and approved that exact content version.

## Required configuration

1. Apply `supabase/migrations/20260919150750_voice_recordings_moderation.sql`. It creates the private voice/job/review metadata tables, RLS, indexes, and the version-checked publication function. Audio bytes are not written to Supabase Storage.
2. Bind the private Cloudflare R2 bucket as `VOICE_RECORDINGS`. Production currently uses the existing `flames-up-media-backup` bucket with immutable per-user voice object keys; the bucket must not have public access enabled.
3. Configure the server-only variables shown in `backend-cf/.env.example`. `OPENAI_API_KEY` is required. The defaults are `gpt-transcribe` for transcription and `omni-moderation-latest` for transcript/text moderation.
4. Bind `MEDIA_MODERATION_QUEUE` as both the Worker queue producer and consumer. Voice jobs use the existing durable queue and the scheduled recovery pass; they are not detached request promises.
5. Give approved moderators `content:read` and `content:write`. Flagged, ambiguous, silent, appealed, and conflicting submissions remain private in Admin → Voice Review. Do not launch review-required submissions without staffed reviewer access.

`CAPTRO_VOICE_AUTO_REJECT` defaults to `false`. Leave it off during the initial evaluation. Clean, complete recordings can publish automatically; first-stage flags remain private for human review. Provider errors and unclear audio do not create policy strikes and never fail open.

## Security and privacy behavior

- The app requests microphone access only after the user taps Record.
- Audio is uploaded through the authenticated Worker and stored as a private Cloudflare R2 object. Filenames, client MIME type, duration, and approval claims are not trusted.
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

## Release status — 2026-09-20

- Captro **1.0.1 (461.1)** was signed, archived, exported, and uploaded to TestFlight in [release run 35540928436](https://github.com/karfalacisse900-alt/Flames-up.com/actions/runs/35540928436) from commit `9deeb570a56862412bb5af768aaa5cd568dfc32c`. The simulator capture job was skipped.
- The iOS release fixes the recorder route-change race, preserves the measured duration before stopping, removes failed temporary captures, and prevents empty recordings from being submitted.
- Production Worker release [35540928409](https://github.com/karfalacisse900-alt/Flames-up.com/actions/runs/35540928409) stopped at the dependency gate because the configured Cloudflare API token cannot access R2 (`Authentication error 10000`). `OPENAI_API_KEY` is also not configured as a GitHub Actions secret. The Worker and database migration were therefore not deployed; voice uploads remain unavailable in production until both credentials are corrected and the deploy is rerun.
