import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { validateCreatorEvent, creatorEventDetails, isEventPostType } from '../src/post-objects.ts';

const sample = { starts_at: '2026-09-12T19:00:00-04:00', ends_at: '2026-09-12T22:00:00-04:00',
  time_zone: 'America/New_York', venue_name: 'Public rooftop', address: '100 Main St', city: 'New York',
  price: '12.50', currency: 'usd', attendance_enabled: true };

test('creator event fields round trip with iOS snake-case and retain exact schedule and price', () => {
  const event = validateCreatorEvent(sample);
  assert.equal(event.startsAt, '2026-09-12T23:00:00.000Z');
  assert.equal(event.endsAt, '2026-09-13T02:00:00.000Z');
  assert.equal(event.price, '12.50');
  assert.equal(event.currency, 'USD');
  const details = creatorEventDetails({ creator_event: event }, 'meetup');
  assert.deepEqual(details.event, { ...event, creatorEditable: true });
  assert.deepEqual(validateCreatorEvent(event), event);
});

test('event editor never accepts ticket ownership, codes, counts or verification', () => {
  const event = validateCreatorEvent({ ...sample, ticket: 'fake', code: 'SECRET', verified: true,
    attendeesCount: 999, user_id: 'other', viewerGoing: true });
  assert.doesNotMatch(JSON.stringify(event), /SECRET|fake|999|other|verified|viewerGoing/);
  assert.equal(creatorEventDetails({ creator_event: event }, 'receipt'), undefined);
  assert.equal(isEventPostType('meetup'), true);
  assert.equal(isEventPostType('travel'), false);
});

test('invalid event prices and schedules fail before storage', () => {
  for (const patch of [{ price: '-1' }, { price: 'Infinity' }, { price: '2.123' }, { currency: 'XYZ' },
    { time_zone: 'Mars/City' }, { starts_at: 'tomorrow' }, { ends_at: '2026-09-10T00:00:00Z' },
    { starts_at: null }, { attendance_enabled: 'true' }, { venue_name: 'a'.repeat(181) }]) {
    assert.throws(() => validateCreatorEvent({ ...sample, ...patch }), JSON.stringify(patch));
  }
  assert.throws(() => validateCreatorEvent(null));
  assert.throws(() => validateCreatorEvent([]));
});

test('optional facts stay optional and a free event is different from a missing price', () => {
  assert.deepEqual(validateCreatorEvent({ attendance_enabled: false }), { attendanceEnabled: false });
  assert.equal(validateCreatorEvent({ price: '0', currency: 'USD' }).price, '0');
  assert.equal(validateCreatorEvent({}).price, undefined);
});

test('post edits check creator ownership, issuer management and concurrent updates', () => {
  const worker = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
  const route = worker.slice(worker.indexOf("api.put('/posts/:postId/event'"), worker.indexOf("api.get('/posts/:postId/object'"));
  assert.match(route, /supabaseOwnedAppPost/);
  assert.match(route, /owned.status !== 200/);
  assert.match(route, /owned.row.status !== 'active'/);
  assert.match(route, /validateCreatorEvent/);
  assert.match(route, /if \(linked.length\)/);
  assert.match(route, /url.searchParams.set\('updated_at'/);
  assert.match(route, /if \(!rows.length\)/);
  assert.match(route, /private, no-store/);
});

test('composer respects the keyboard and exposes editable stamps, not just hidden details', () => {
  const native = '../../ios_native/MIRA/Sources/MIRANative/';
  const source = path => readFileSync(new URL(native + path, import.meta.url), 'utf8');
  const home = source('Screens/MainFeedView.swift');
  const composer = source('Screens/NotificationLibrarySearchCreateViews.swift');
  assert.match(home, /\.fullScreenCover\(isPresented: \$isShowingCreatePost\)/);
  assert.doesNotMatch(home, /\.miraFullScreenOverlay\(isPresented: \$isShowingCreatePost/);
  assert.match(composer, /safeAreaInset\(edge: \.bottom, spacing: 0\) \{ composerToolBar/);
  assert.match(composer, /CaptroEventEditorFields\(draft: \$eventDraft\)/);
  assert.match(composer, /event: isEventStamp \? eventDraft.input : nil/);
  assert.match(composer, /CaptroPostStamp\(content: composerStampContent/);
  assert.match(source('Screens/PostDetailNativeView.swift'), /isMuted = false/);
});
