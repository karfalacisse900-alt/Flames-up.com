import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {homeMediaPresentation} from './helpers/home-media-presentation.mjs';
const source = readFileSync(new URL('../../ios_native/MIRA/Sources/MIRANative/Screens/MainFeedView.swift', import.meta.url), 'utf8');
test('Home wiring guard catches removal of filtering or a renderer that bypasses it', () => {
  homeMediaPresentation(source);
  for (const broken of [
    source.replace('posts.filter { $0.hasHomeMedia }', 'posts'),
    source.replace('    model.homePosts', '    model.posts'),
    source.replace('ForEach(displayedPosts,', 'ForEach(model.posts,'),
  ]) {
    assert.notEqual(broken, source);
    assert.throws(() => homeMediaPresentation(broken));
  }
});
