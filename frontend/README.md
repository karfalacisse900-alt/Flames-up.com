# Flames-Up Frontend

Expo SDK 54 app for iOS, Android, and web.

## Run

```powershell
npm install
npm run start:go:tunnel
```

Expo Go is good for normal app testing. Google OAuth cannot complete inside Expo Go because Expo Go cannot use this app's custom redirect scheme. Use a development build when testing Google sign-in:

```powershell
npm run build:dev:android
npm run start:dev-client -- --tunnel
```

## Auth Configuration

The app defaults to the live Worker at `https://api.flames-up.com`.

Optional local environment values:

```text
EXPO_PUBLIC_API_URL=https://api.flames-up.com
EXPO_PUBLIC_SUPABASE_URL=https://your-project-ref.supabase.co
EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
EXPO_PUBLIC_SUPABASE_WEB_REDIRECT_URI=https://flames-up.com/auth/callback
EXPO_PUBLIC_SUPABASE_NATIVE_REDIRECT_URI=frontend://auth/callback
EXPO_PUBLIC_ENABLE_APPLE_SIGN_IN=1
EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID=your-web-client-id.apps.googleusercontent.com
EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID=your-ios-client-id.apps.googleusercontent.com
EXPO_PUBLIC_GOOGLE_ANDROID_CLIENT_ID=your-android-client-id.apps.googleusercontent.com
```

Do not put Supabase service-role keys, database passwords, OAuth client secrets, Stripe secret keys, or Worker secrets in `EXPO_PUBLIC_*`. Those must stay in Supabase/Cloudflare server-side secrets.

Google sign-in needs the matching client IDs added to the Worker `GOOGLE_OAUTH_CLIENT_IDS` secret:

```powershell
cd "..\backend-cf"
$ids = "your-web-client-id.apps.googleusercontent.com,your-ios-client-id.apps.googleusercontent.com,your-android-client-id.apps.googleusercontent.com"
$ids | npx wrangler secret put GOOGLE_OAUTH_CLIENT_IDS --env production
npx wrangler deploy --env production
```

Apple sign-in needs the app bundle/service audience added to `APPLE_OAUTH_AUDIENCES`.
Phone sign-in works with development codes until Twilio vars are configured on the Worker.
