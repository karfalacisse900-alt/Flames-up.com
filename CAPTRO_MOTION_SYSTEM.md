# Captro Motion Design System

Captro motion should make the app feel stable, fast, and intentional. Motion is not decoration. It should explain where a surface came from, keep the previous screen visible during transitions, and hide network/media loading without flashing blank states.

## Principles

- Native first: use standard iOS push/pop navigation when possible.
- Stability before animation: reserve layout before loading media or text.
- One motion language: sheets, menus, overlays, media, and buttons use shared tokens.
- No blink: never remove a modal, sheet, overlay, or media placeholder before its closing/loading transition finishes.
- Fast feedback: taps respond immediately with subtle scale and haptic feedback where useful.
- Cache first: show cached content, thumbnails, posters, or skeletons before fetching fresh data.
- Respect accessibility: Reduce Motion switches large scale/slide movement to short fades.

## Motion Tokens

| Surface | Duration | Shape |
| --- | ---: | --- |
| Button press | 80ms-120ms | Ease out, scale 0.97 |
| Small menu open | 160ms-220ms | Ease out, fade and slight scale |
| Small menu close | 140ms-200ms | Ease out |
| Bottom sheet open | 250ms-350ms | Spring, gentle damping |
| Bottom sheet close | 220ms-300ms | Spring/ease out, delayed unmount |
| Full screen overlay open | 260ms-320ms | Fade and tiny scale |
| Full screen overlay close | 220ms-280ms | Fade, delayed unmount |
| Media fade-in | 120ms-200ms | Fade from thumbnail/poster |
| Tab/header chrome | 140ms-200ms | Ease out |

Reduce Motion uses short fades around 80ms and disables meaningful scale/slide.

## Shared Implementation

The source of truth is the Swift shared motion layer:

- `CaptroMotion`: durations, scales, and animation factories.
- `CaptroHaptics`: safe light, medium, success, warning, and error feedback.
- `miraBottomSheet`: bottom sheet lifecycle that keeps content mounted until close finishes.
- `miraFadeScaleOverlay`: small menus and centered overlays.
- `miraFullScreenOverlay`: viewers, creation flows, and immersive overlays.
- `miraScreenEnter`: screen entrance polish for push, modal, and tab content.

New surfaces should use these helpers instead of local one-off `withAnimation` timing literals.

## Sheet Behavior

Correct dismissal lifecycle:

1. User taps close, backdrop, or drags down.
2. Surface enters `closing` by setting visible state to false.
3. Close animation runs.
4. After the token close duration, the view is removed from hierarchy.
5. Previous screen remains mounted and stable behind the sheet.

Sheets should be safe-area aware, keyboard-safe, and use a gentle scrim. Destructive sheets require confirmation and reason where moderation/security applies.

## Menus and Popups

Menus should open in a predictable place, never behind the feed, and never as a hard pop. Use the shared fade-scale overlay or bottom sheet depending on screen size and importance.

Non-interactive decorative overlays must use `allowsHitTesting(false)` so they do not block buttons.

## Button Feedback

Buttons use:

- Minimum tap target: 44 x 44 pt.
- Press scale: about 0.97.
- Press duration: around 100ms.
- Haptic: light for ordinary actions, success for completed save/post/send, warning/error for failed destructive actions.

Do not haptic every tiny UI movement.

## Feed Motion

Feed smoothness depends on stable layout more than animation:

- Stable post ids.
- No full feed rebuild after like, comment, save, follow, or menu actions.
- Preserve scroll position.
- Keep media containers sized before media loads.
- Support only Captro portrait display ratios: 3:4, 4:5, and 2:3.
- Do not stretch media.
- Do not decode large media on the main thread.
- Do not create too many video players.

Action counts should update without moving the entire row.

## Media Loading

Media loading order:

1. Reserved aspect-ratio container with non-white placeholder.
2. Thumbnail/poster appears.
3. Full feed media fades in.
4. Thumbnail/poster remains underneath until full media is visible.

Rules:

- No white placeholder.
- No layout jump.
- No thumbnail as final full media.
- Prefetch nearby thumbnails/posters and visible/next feed media.
- Cancel far-away media requests.

## Carousel Behavior

Carousels should preload all thumbnails/posters, the current full item, and the next two full items where network/memory allow. Swiping must not reveal an empty slide. Video slides keep poster visible until playback is ready.

## Page Transitions

Use native iOS push/pop where possible. Avoid hard root replacement during normal navigation. Creation, settings, story creation, chat rooms, and detail pages should hide the main tab bar with `miraHideTabBarOnAppear`.

## Haptics

Recommended use:

- Light: open important sheet, tap like/save.
- Medium: confirm follow/save change where useful.
- Success: post published, comment/message sent.
- Warning/error: upload failed, destructive action failed, permission denied.

Never rely on haptics as the only feedback.

## Accessibility

When Reduce Motion is enabled:

- Replace large slide/scale motion with short fades.
- Keep all flows usable.
- Do not hide loading/error/success state behind animation-only cues.
- Avoid repeated pulsing effects.

## Performance Budget

Common flows should avoid major main-thread blocking:

- Feed scroll: no image decoding or video setup on main thread.
- Media fade: 120ms-200ms after cached/full media is ready.
- Modal open/close: no network fetch before showing the shell.
- Tab switch: cached content appears immediately.
- Chat open: local cache appears first, backend sync follows.

Use Instruments, MetricKit, and OSLog signposts for:

- app launch
- feed render
- post media load
- media cache hit/miss
- video prewarm ready
- tab switch
- modal open/close
- comments open/close

Do not log tokens, private messages, secrets, full API responses, or sensitive media URLs.

## Implementation Checklist

- Use `CaptroMotion` for new animation timing.
- Use shared overlay/sheet modifiers for modal surfaces.
- Keep views mounted through close animation.
- Respect Reduce Motion.
- Reserve media sizes before load.
- Show thumbnail/poster before full media.
- Keep feed updates item-scoped.
- Keep tab content cached.
- Use `CaptroHaptics` sparingly for important actions.
- Verify with TestFlight and real device Instruments before release.
