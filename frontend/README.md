# Flames-Up Frontend

Expo SDK 54 app for iOS, Android, and web.

## Run

```powershell
npm install
npx expo start --tunnel
```

## Auth Configuration

The app defaults to the live Worker at `https://api.flames-up.com`.

Optional local environment values:

```text
EXPO_PUBLIC_API_URL=https://api.flames-up.com
EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID=your-web-client-id.apps.googleusercontent.com
EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID=your-ios-client-id.apps.googleusercontent.com
EXPO_PUBLIC_GOOGLE_ANDROID_CLIENT_ID=your-android-client-id.apps.googleusercontent.com
```

Google sign-in needs the matching client IDs added to the Worker `GOOGLE_OAUTH_CLIENT_IDS` variable.
Apple sign-in needs the app bundle/service audience added to `APPLE_OAUTH_AUDIENCES`.
Phone sign-in works with development codes until Twilio vars are configured on the Worker.
