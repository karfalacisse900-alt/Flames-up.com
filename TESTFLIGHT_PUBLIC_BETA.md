# Captro TestFlight Public Beta Setup

Captro builds are uploaded to TestFlight by the GitHub Actions workflow `Native iOS TestFlight`.
Apple still requires the first external TestFlight build to pass TestFlight App Review before a public link can be opened.

Production Captro iOS bundle ID: `com.captro.app`.

Before running the first TestFlight upload for this new app record, create an App Store distribution provisioning profile for `com.captro.app` and update the GitHub Actions provisioning profile secret to match it.

## Recommended Public Beta Group

- Group name: `Captro Public Beta`
- Public link access: `Open to Anyone`
- Starting tester limit: `300`
- Increase later if crashes and feedback look healthy.

## Beta App Description

Captro is a social app for sharing real photo moments, short stories, Discover posts, comments, chat, and profile updates.

This beta is focused on testing the core Captro experience before public launch:

- Creating an account and choosing a username
- Posting photos and multi-photo carousels
- Viewing Home Feed and Discover
- Opening post details, liking, commenting, saving, and reporting
- Creating and viewing Stories
- Using chat and media messages
- Editing profile information
- Testing blocking, reporting, and safety flows

Please report crashes, broken media, slow loading, login issues, posting problems, chat problems, or anything that feels confusing.

Captro is still in beta, so some content, media loading, moderation, or notification behavior may change as we improve the app.

## What To Test

Please focus on:

- Sign up, log in, and username onboarding
- Creating photo posts and multi-photo posts
- Story recording, story upload, and story playback
- Feed scrolling, media loading, likes, comments, saves, and post menus
- Discover filters, Discover post opening, and post detail interactions
- Profile editing, profile posts, bookmarks, and pinned/private post states
- Chat text messages and photo/video media messages
- Report and block flows
- App stability after closing/reopening the app
- Dark mode, Settings, and cache clearing

Please send feedback for:

- Crashes
- Blank images or videos
- Videos stuck on processing
- Duplicate likes/comments/messages
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

Captro supports normal account creation and login. No special invite code is required for beta testers.

Suggested App Review note:

```
Testers can create a new Captro account inside the app using email/password or supported social sign-in.

No paid account is required.
No invite code is required.

If Apple needs an existing test account, use:
Email: [ADD TEST ACCOUNT EMAIL]
Password: [ADD TEST ACCOUNT PASSWORD]

Please do not use the production owner account for review testing.
```

Create a dedicated non-admin test account before submitting the first external beta build, then replace the placeholders above.

## App Store Connect Steps

1. Go to `My Apps -> Captro -> TestFlight`.
2. Confirm the latest GitHub Actions build is processed and available.
3. Fill in `Test Information`:
   - Beta App Description: use the copy above.
   - Feedback Email: use the value above.
   - Contact Info: use owner/developer contact info.
   - Sign-in/test account info: use the review note above.
4. Create or verify an internal testing group.
5. Create an external testing group named `Captro Public Beta`.
6. Add the latest build to `Captro Public Beta`.
7. Paste the `What To Test` copy above.
8. Submit the build for TestFlight App Review.
9. After Apple approves it, open the external group.
10. Click `Create Public Link`.
11. Choose `Open to Anyone`.
12. Set the tester limit to `300` to start.
13. Copy the public link and share it on TikTok, Instagram, SMS, Discord, and other channels.

## Public Link Sharing Copy

Short version:

```
Captro beta is open on TestFlight. Join here:
[PASTE PUBLIC TESTFLIGHT LINK]

You need Apple’s TestFlight app installed. Spots are limited.
```

Social version:

```
Captro beta is live on TestFlight.

Post real photo moments, try Stories, Discover, chat, profiles, and help shape the app before launch.

Join here:
[PASTE PUBLIC TESTFLIGHT LINK]

You need the TestFlight app from the App Store.
```

## Notes

- Public-link testers do not need manual email invites.
- Testers still need Apple’s TestFlight app.
- Public-link testers may appear as anonymous in App Store Connect.
- You can still view install date, sessions, crash data, and feedback.
- Keep the tester limit small at first, then raise it after the beta is stable.
