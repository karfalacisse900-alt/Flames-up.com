# Aura Mobile TestFlight Public Beta Setup

Aura Mobile builds are uploaded to TestFlight by the GitHub Actions workflow `Aura iOS TestFlight` (`.github/workflows/native-ios-testflight.yml`), triggered manually or by pushing an `ios-v*` tag.

Apple still requires the first external TestFlight build to pass TestFlight App Review before a public link can be opened.

iOS bundle ID: `com.captro.app`. This is unchanged from Captro on purpose, so the build continues to attach to the existing App Store Connect app record instead of creating a new one.

## Recommended Public Beta Group

- Group name: `Captro Public Beta` (kept as-is; rename it in App Store Connect first if you want a different name, then update `BETA_GROUP` in the workflow to match)
- Public link access: `Open to Anyone`
- Starting tester limit: `300`
- Increase later if crashes and feedback look healthy.

## Beta App Description

> The copy below describes what Aura Mobile actually does today. As of this migration, Scan, Proofs, Reputation, and Wallet are honest not-yet-connected empty states pending an Aura Mobile Gateway/FFI bridge — update this section as those become real before advertising them to testers.

Aura Mobile is a native iOS app for scanning receipts and invoices, submitting them as verified proofs, building a portable Aura Reputation score from real verified purchases, and (eventually) holding an Aura wallet.

This beta is focused on testing the core Aura Mobile shell before the verification and wallet backends are connected:

- Creating an account and signing in
- Navigating Home, Scan, Proofs, Reputation, and Wallet
- Confirming that not-yet-connected features show a clear, honest empty state rather than fake data
- App stability, dark mode, and general navigation

Please report crashes, broken navigation, login issues, or any screen that shows data that looks invented rather than a genuine empty state.

Aura Mobile is early in this beta, so most functional screens will show empty states until the backend and wallet FFI bridge are connected.

## What To Test

Please focus on:

- Sign up, log in, and account flows
- Tab navigation across Home, Scan, Proofs, Reputation, and Wallet
- Empty-state screens are honest (no invented scores, balances, or history)
- App stability after closing/reopening the app
- Dark mode, Settings, and cache clearing

Please send feedback for:

- Crashes
- Any screen showing a fabricated Aura Score, AUR balance, transaction, proof, or reputation event
- Slow screens
- Broken buttons
- Login or signup issues
- Anything that feels unsafe or confusing

## Feedback Email

Use the production support email for TestFlight feedback.

Suggested value:

`karfalacisse900@gmail.com`

## Contact Info

Use the Captro owner/developer contact information from App Store Connect.

Suggested contact email:

`karfalacisse900@gmail.com`

## Sign-In / Test Account Info

Aura Mobile supports normal account creation and login. No special invite code is required for beta testers.

Suggested App Review note:

```
Testers can create a new Aura account inside the app using email/password or supported social sign-in.

No paid account is required.
No invite code is required.

If Apple needs an existing test account, use:
Email: [ADD TEST ACCOUNT EMAIL]
Password: [ADD TEST ACCOUNT PASSWORD]

Please do not use the production owner account for review testing.
```

Create a dedicated non-admin test account before submitting the first external beta build, then replace the placeholders above.

## App Store Connect Steps

1. Go to `My Apps -> Captro -> TestFlight` (the app record's App Store Connect display name can be renamed to Aura independently of the bundle ID; that does not affect this workflow).
2. Confirm the latest GitHub Actions build is processed and available.
3. Fill in `Test Information`:
   - Beta App Description: use the copy above.
   - Feedback Email: use the value above.
   - Contact Info: use owner/developer contact info.
   - Sign-in/test account info: use the review note above.
4. Create or verify an internal testing group.
5. Create an external testing group named `Captro Public Beta` (or your renamed equivalent, kept in sync with `BETA_GROUP` in the workflow).
6. Add the latest build to the group.
7. Paste the `What To Test` copy above.
8. Submit the build for TestFlight App Review.
9. After Apple approves it, open the external group.
10. Click `Create Public Link`.
11. Choose `Open to Anyone`.
12. Set the tester limit to `300` to start.
13. Copy the public link and share it once you're ready to promote it.

## Public Link Sharing Copy

Short version:

```
Aura Mobile beta is open on TestFlight. Join here:
[PASTE PUBLIC TESTFLIGHT LINK]

You need Apple's TestFlight app installed. Spots are limited.
```

## Notes

- Public-link testers do not need manual email invites.
- Testers still need Apple’s TestFlight app.
- Public-link testers may appear as anonymous in App Store Connect.
- You can still view install date, sessions, crash data, and feedback.
- Keep the tester limit small at first, then raise it after the beta is stable.
