# Captro App Review Resubmission Notes

## Rejection Items Addressed

### Guideline 5.1.1(ii): permission purpose strings

The iOS `Info.plist` now explains why Captro requests each permission with concrete examples:

- Camera: taking photos and videos for posts, stories, and profile pictures.
- Photo Library: choosing photos and videos for posts, stories, and profile pictures.
- Microphone: recording audio when creating videos for posts or stories.
- Location: tagging nearby places and showing local content, with a post place-tag example.

### Guideline 1.2: user-generated content safety

Captro now requires users to accept the Terms and Community Rules before email/password, Apple, or Google authentication can continue. The auth screen states that Captro is 16+ and has zero tolerance for objectionable content or abusive users.

The acceptance is sent to the backend and recorded with:

- `terms_version`
- `terms_accepted_at`
- user id
- auth source

The Terms of Service now explicitly state: "Captro has zero tolerance for objectionable content or abusive users."

## Safety Controls Available In App

- Report posts.
- Report comments.
- Report profiles.
- Report messages.
- Report stories.
- Block users.
- Review and unblock users in Settings > Privacy & Safety > Blocked accounts.
- Delete account in Settings > Account.
- Safety & Reporting page in Settings.

Report reasons include:

- Nudity or sexual content
- Harassment
- Hate speech
- Threats or violence
- Spam or scam
- Doxxing or private information
- Impersonation
- Child safety concern
- Illegal or dangerous activity
- Other

Blocking a user now also creates a backend moderation report record so developer/moderation staff can review block-only abuse signals.

## App Review Reply Draft

Hello App Review,

Thank you for the review. We addressed the issues raised for Captro.

For Guideline 5.1.1(ii), the camera, photo library, microphone, and location purpose strings now clearly explain why each permission is requested and include examples of how the permission is used in Captro.

For Guideline 1.2, Captro now requires users to accept the Terms and Community Rules before signing up or logging in with email/password, Apple, or Google. The Terms state that Captro has zero tolerance for objectionable content or abusive users. Captro includes in-app reporting for posts, comments, profiles, messages, and stories, in-app user blocking, a blocked users management screen, account deletion, and backend moderation records for reports and block events.

We also verified that the iOS build does not declare VoIP background mode and does not include active CallKit, PushKit, or VoIP calling functionality.

Please review the updated build.

## Reviewer Notes

Captro is a social app for users 16 and older. Users can report content or users from post menus, comment menus, profile/chat menus, story/report flows, and message menus. Users can block and unblock accounts from Settings. Account deletion is available in Settings > Account.

If a reviewer account is required, provide a valid test account in App Store Connect under App Review Information.

## Verification Performed

- `backend-cf`: `npx.cmd tsc --noEmit`
- `admin-web`: `npm.cmd --prefix admin-web run build`
- `backend-cf`: `npm.cmd run test:moderation`
- `git diff --check`
- Repository scan for `voip`, `CallKit`, `PushKit`, `CXProvider`, `CXCallController`, `WebRTC`, `Agora`, and related calling libraries.

## Remaining Manual Verification

- Run the iOS GitHub Actions/TestFlight workflow because local Xcode/Swift is not available on this Windows machine.
- Attach a short physical-device screen recording for App Review showing:
  - Terms acceptance before login/signup.
  - Report a post.
  - Block a user.
  - Blocked users page.
  - Safety & Reporting page.
  - Delete Account page.
