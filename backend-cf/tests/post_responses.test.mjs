import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { PGlite } from '@electric-sql/pglite';

const worker = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
const composer = readFileSync(new URL('../../ios_native/MIRA/Sources/MIRANative/Screens/NotificationLibrarySearchCreateViews.swift', import.meta.url), 'utf8');
const feed = readFileSync(new URL('../../ios_native/MIRA/Sources/MIRANative/Screens/CaptroFeedPostView.swift', import.meta.url), 'utf8');
const migration = readFileSync(new URL('../../supabase/migrations/20260929001010_captro_post_responses.sql', import.meta.url), 'utf8');

test('one response per account, changing choice reverses the old count, and deleting a post cascades', async () => {
  const db = new PGlite();
  try {
    await db.exec('create role anon; create role authenticated; create role service_role; create table public.app_posts(id uuid primary key);');
    await db.exec(migration);
    const post = (await db.query('insert into public.app_posts values (gen_random_uuid()) returning id')).rows[0].id;
    const vote = (choice) => db.query(`insert into public.app_post_responses(post_id,app_user_id,actor_key,selected_option)
      values($1,'buyer','auth:buyer',$2)
      on conflict(post_id,actor_key) do update set selected_option=excluded.selected_option,updated_at=now()`, [post, choice]);
    await vote('Yes');
    await vote('Yes');
    assert.equal((await db.query('select response_count from public.app_post_response_counts where post_id=$1 and selected_option=$2', [post, 'Yes'])).rows[0].response_count, 1);
    await vote('No');
    assert.deepEqual((await db.query('select selected_option,response_count from public.app_post_response_counts where post_id=$1', [post])).rows.map(row => row.selected_option), ['No']);
    await db.exec('set role authenticated');
    await assert.rejects(db.query('select * from public.app_post_responses'), /permission denied/);
    await assert.rejects(db.query('select * from public.app_post_response_counts'), /permission denied/);
    await db.exec('reset role');
    await db.query('delete from public.app_posts where id=$1', [post]);
    assert.equal((await db.query('select count(*)::int as n from public.app_post_responses')).rows[0].n, 0);
  } finally {
    await db.close();
  }
});

test('creator chooses zero or one mode; votes require visible posts and the selected option', () => {
  assert.match(composer, /postResponse: postResponse/);
  assert.match(composer, /hasSelectedStamp && !title\.trimmingCharacters/);
  assert.match(feed, /if post\.response != nil/);
  assert.match(feed, /CaptroPostResponseView\(post: post/);
  assert.match(worker, /const postResponse = normalizePostResponseConfig\(rawPostResponse\)/);
  assert.match(worker, /post_response: input\.postResponse \|\| null/);
  assert.match(worker, /postResponse\?\.type === 'going' && \(commerceConfig \|\| creatorEvent\?\.attendanceEnabled === true\)/);
  assert.match(worker, /supabaseHydratePostResponses\(c, ordered, viewerId\)/);
  const route = worker.slice(worker.indexOf("api.post('/posts/:postId/responses'"), worker.indexOf("api.get('/posts/:postId/responses/people'"));
  assert.match(route, /supabaseReadVisiblePosts\(c, userId, \{ postId, limit: 1 \}\)/);
  assert.match(route, /config\.options\.includes\(selectedOption\)/);
  assert.match(route, /'post_id,actor_key'/);
  assert.match(route, /supabaseAdminDeleteRows\(c, 'app_post_responses'/);
});
