import assert from 'node:assert/strict';

// Wiring contract only. Behavioral coverage lives in CaptroFeedStabilityTests.
// Filtering may move out of View.body, but must remain on every posts mutation
// and the actual ForEach must consume that filtered presentation.
export function homeMediaPresentation(source) {
  assert.match(source, /@Published var posts:[\s\S]*?didSet\s*\{[\s\S]*?homePosts = posts\.filter \{ \$0\.hasHomeMedia \}/);
  assert.match(source, /homePostIDs = homePosts\.map\(\\\.id\)/);
  assert.match(source, /private var displayedPosts:[^{]+\{\s*model\.homePosts\s*\}/);
  assert.match(source, /ForEach\(displayedPosts, id: \\\.id\)/);
}
