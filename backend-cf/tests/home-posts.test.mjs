import test from 'node:test';
import assert from 'node:assert/strict';
import { PGlite } from '@electric-sql/pglite';
import { activityPostTypes, homePostFilters, homePostRelations, isRegularHomePost } from '../src/home-posts.ts';

test('record identity excludes every supported listing, never words in an ordinary post', () => {
  for (const type of activityPostTypes) {
    for (const images of [['photo.jpg'], ['video.mp4'], ['one.jpg', 'two.jpg']])
      assert.equal(isRegularHomePost({ post_type: type, images }), false, type);
  }
  for (const type of ['general', 'photo', 'video', 'carousel', 'check_in', null]) {
    assert.equal(isRegularHomePost({ post_type: type, title: 'Club event', caption: 'Meetup deal at our club' }), true);
    for (const relation of ['commerce', 'event', 'travel', 'document', 'collection'])
      assert.equal(isRegularHomePost({ post_type: type, detail: { [relation]: { id: 'existing' } } }), false);
  }
});

// Execute the query predicates against PostgreSQL, including JSONB, NULLs,
// relationship anti-joins and LIMIT/OFFSET. This is isolated; no hosted writes.
function split(text) {
  let depth = 0, start = 0;
  const parts = [];
  for (let i = 0; i < text.length; i++) {
    if (text[i] === '(') depth++;
    if (text[i] === ')') depth--;
    if (text[i] === ',' && !depth) { parts.push(text.slice(start, i)); start = i + 1; }
  }
  return [...parts, text.slice(start)];
}
function compile(expression, values) {
  for (const op of ['and', 'or']) if (expression.startsWith(op + '('))
    return '(' + split(expression.slice(op.length + 1, -1)).map(part => compile(part, values)).join(' ' + op + ' ') + ')';
  const [, field, negation, op, value] = expression.match(/^([^.]+)\.(not\.)?(is|in|neq)\.(.*)$/) ?? [];
  assert.ok(['post_type', 'media', 'metadata->>image'].includes(field), expression);
  const column = field === 'metadata->>image' ? "p.metadata->>'image'" : 'p.' + field;
  if (op === 'is') { assert.equal(value, 'null'); return column + (negation ? ' is not null' : ' is null'); }
  if (op === 'in') {
    const params = split(value.slice(1, -1)).map(value => { values.push(value); return '$' + values.length; });
    return column + (negation ? ' not in (' : ' in (') + params.join(',') + ')';
  }
  assert.equal(op, 'neq'); values.push(value);
  return column + ' <> $' + values.length + (field === 'media' ? '::jsonb' : '');
}

test('Home queries remove cover listings before pagination and keep video/carousels and legacy photos', async () => {
  const db = new PGlite();
  try {
    await db.exec(`create table posts(id int primary key, post_type text, media jsonb, metadata jsonb default '{}');
      create table app_purchasables(post_id int references posts(id));
      create table app_post_objects(post_id int references posts(id));`);
    for (let i = 1; i <= 90; i++)
      await db.query('insert into posts(id,post_type,media) values($1,$2,$3)', [i, activityPostTypes[i % activityPostTypes.length], '["cover.jpg"]']);
    for (const [id, type, media, metadata] of [
      [91, 'general', '["photo.jpg"]', '{}'], [92, 'video', '["video.mp4"]', '{}'],
      [93, 'carousel', '["a.jpg","b.jpg"]', '{}'], [94, null, '[]', '{"image":"legacy.jpg"}'],
      [95, 'general', '["listing.jpg"]', '{}'], [96, 'general', '["event.jpg"]', '{}'],
      [97, 'general', '[]', '{}'], [98, 'general', '[]', '{"image":""}'],
    ]) await db.query('insert into posts values($1,$2,$3,$4)', [id,type,media,metadata]);
    await db.exec('insert into app_purchasables values(95); insert into app_post_objects values(96)');
    const filters = homePostFilters();
    assert.equal(filters.home_listing, 'is.null'); assert.equal(filters.home_object, 'is.null');
    assert.ok(homePostRelations.includes('home_listing:app_purchasables()'));
    assert.ok(homePostRelations.includes('home_object:app_post_objects()'));
    const values = [];
    const where = compile('and' + filters.and, values)
      + ' and not exists(select 1 from app_purchasables l where l.post_id=p.id)'
      + ' and not exists(select 1 from app_post_objects o where o.post_id=p.id)';
    const page = async offset => (await db.query(`select p.id from posts p where ${where} order by p.id limit 2 offset ${offset}`, values)).rows.map(row => row.id);
    assert.deepEqual(await page(0), [91,92]); assert.deepEqual(await page(2), [93,94]); assert.deepEqual(await page(4), []);
    assert.equal((await db.query('select count(*)::int as total from posts')).rows[0].total, 98);
  } finally { await db.close(); }
});
