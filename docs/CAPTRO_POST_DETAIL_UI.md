# Captro Post Details

## Shared Screen

All existing `DiscoverPostDetailNativeView` entry points now delegate to
`PostDetailNativeView`. Home navigation, Home gestures, Home stamps, and the
Home cover-only preview are unchanged.

The detail screen owns a full-width image pager, fixed Post header with back /
share / save, inline comments, and a bottom comment composer. The tab bar is
hidden. The four content variants are Place / Review, Regular, Meetup / Event,
and Collection / List. Captions are displayed in full.

## Existing Live Operations

- Post reads: `GET /posts/:id`
- Comments, replies, comment moderation: existing post/comment endpoints
- Like: `POST /posts/:id/like`
- Save and unsave: existing `/library/save/:id` endpoints
- Share: existing `MIRAProductionBackend.siteURL`
- Location: Apple Maps URL constructed only from actual tagged-place data

## Backend Work Still Required

The current backend does **not** expose event attendance or public collection
contents. No backend or database changes are included in this UI change.

The client supports the following optional `detail` field on the existing post
response. Omit unavailable values; never infer them from caption text, tagged
people, likes, or image count.

```text
detail.visited_count: nonnegative integer, only if independently recorded
detail.creator_visited: boolean, only if recorded
detail.event.starts_at / ends_at: ISO-8601 timestamps
detail.event.time_zone: IANA timezone
detail.event.venue_name / address: strings
detail.event.latitude / longitude: optional coordinates
detail.event.attendees_count: nonnegative integer
detail.event.attendees: permitted public user summaries
detail.event.viewer_going: authenticated viewer's server-owned RSVP state
detail.event.attendance_enabled: true only when the RSVP endpoint is available
detail.collection.items: ordered, visible MIRAPost objects
```

When attendance is absent or disabled, the UI displays `RSVP unavailable` and
does not send a mutation. The proposed client contract is:

```text
POST /posts/:id/attendance
Body: { "going": true | false }
Response: { "event": <updated event detail including viewer_going> }
```

The server must authenticate the caller, enforce post visibility, validate event
eligibility, and persist an idempotent set/unset operation with a unique
post/user constraint. The client updates GOING only after a successful response
confirms the requested state. This route is not yet implemented server-side.

Collection responses must filter inaccessible/deleted child posts and avoid
recursive nested collection payloads. They must not expose another account's
private saved-library contents. Collection rows use each child's real post ID
for navigation and saving. Missing collection data displays an empty state.

## Verification

`CaptroPostDetailsTests` covers variant routing, complete captions, missing data,
metadata preservation during engagement/cache updates, unique collection rows,
map URL encoding, and date parsing. These XCTest tests require Xcode/iOS and
have not been executed on the Windows workstation. No simulator was run.

Before release, verify all four layouts with real post data; image swiping,
video playback, keyboard/comment submission, save rollback, profile navigation,
Dynamic Type, and returning to the same Home page need device verification.
