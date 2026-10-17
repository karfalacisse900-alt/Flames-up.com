import assert from 'node:assert/strict';
// Wiring contracts supplement (not replace) native gesture/render tests. Follow
// the active shared component instead of requiring an obsolete inline button.
export function favoritePlacement(pager) {
 const overlay=pager.slice(pager.indexOf('CaptroFavoriteButton(post:'),pager.indexOf('private var mediaContent'));
 assert.match(overlay,/\.padding\(\.bottom,\s*dynamicTypeSize\.isAccessibilitySize\s*\?\s*0\s*:\s*38\)/);
 assert.match(overlay,/alignment:\s*dynamicTypeSize\.isAccessibilitySize\s*\?\s*\.topTrailing\s*:\s*\.bottomTrailing/);
}
export function guestRoute(auth,welcome,session) {
 assert.match(auth,/CaptroWelcomeView\([\s\S]*?onGuest:\s*\{\s*session\.continueAsGuest\(\)/);
 assert.match(welcome,/Button\("Continue as guest",\s*action:\s*onGuest\)/);
 const body=session.slice(session.indexOf('public func continueAsGuest()'),session.indexOf('public func exitGuestMode()'));
 assert.match(body,/clearSessionState\(\)/);assert.match(body,/setGuestMode\(true\)/);
}
export function videoControls(pager,controls) {
 assert.match(pager,/CaptroVideoControls\([\s\S]*?isPaused:\s*Binding\(get:\s*\{\s*isVideoPaused\s*\},\s*set:\s*\{\s*isVideoPaused = \$0\s*\}\)/);
 assert.match(pager,/shouldPlay: isVideoActive && !isVideoPaused/);
 assert.match(controls,/id: "play"\)\s*\{\s*isPaused\.toggle\(\)\s*\}/);
 assert.match(controls,/id: "mute"\)\s*\{\s*isMuted\.toggle\(\)\s*\}/);
 assert.match(controls,/\.frame\(width: 44, height: 44\)/);
}
export function detailFavorites(details,favorites) {
 assert.match(details,/CaptroFavoriteMenuAction\(post: model\.post, store: model\.api\.favorites\)/);
 const menu=favorites.slice(favorites.indexOf('struct CaptroFavoriteMenuAction'),favorites.indexOf('private struct FavoritePressControl'));
 assert.match(menu,/await store\.toggle\(post\)/);assert.match(menu,/store\.isSaved\(post\)/);
 assert.match(menu,/\.disabled\(store\.busy\.contains\(post\.id\)\)/);
}
