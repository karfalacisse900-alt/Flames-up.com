# Captro icon integration brief

Use the assets in this folder to install the selected Captro concept 01 app icon in my existing iOS project.

Use the primary file `app-icons/captro-app-icon-dark-1024.png` or the matching `AppIcon.appiconset`. The icon is a white two-curve symbol on a fully opaque black 1024 × 1024 square. Preserve the supplied geometry, scale, composition, colors, and square canvas. Do not redraw the logo or round the corners.

First inspect the repository, app target, Xcode version, existing asset catalog, and icon configuration. Integrate into the existing app-icon set where appropriate. Avoid duplicate icon sets. Preserve unrelated asset entries and support any legacy icon slots the project actually requires, generating those sizes from the 1024 master. The optional light image is only an alternative; do not add appearance behavior without asking.

Change only the icon asset files and the minimum configuration required for the target to use them. Do not redesign or otherwise change my app's UI, screens, colors, fonts, layout, navigation, features, entitlements, signing, or bundle identity. Do not install the wordmark throughout the app unless I separately ask.

Validate the PNG's 1024 × 1024 dimensions and opaque RGB mode, run the available asset/build checks, and report changed files and any blocker. If a simulator or device is available, inspect the resulting icon. Do not claim an unrun build passed.

Do not upload to App Store Connect, submit for review, release a build, change accounts, or publish anything. Ask me before any such action.
