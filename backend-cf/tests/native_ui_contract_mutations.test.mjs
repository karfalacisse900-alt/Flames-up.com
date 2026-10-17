import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {favoritePlacement,guestRoute,videoControls,detailFavorites} from './helpers/native-ui-contract.mjs';
const read=p=>readFileSync(new URL('../../ios_native/MIRA/Sources/MIRANative/'+p,import.meta.url),'utf8');
test('updated wiring coverage rejects a broken guest route, inert playback, disconnected save and moved favorite',()=>{
 const pager=read('Screens/CaptroFeedMediaPager.swift'),controls=read('Components/CaptroVideoControls.swift');
 const details=read('Screens/PostDetailNativeView.swift'),favorites=read('Components/CaptroFavoriteButton.swift');
 const auth=read('Screens/AuthNativeView.swift'),welcome=read('Screens/CaptroWelcomeView.swift'),session=read('Services/MIRAAuthSession.swift');
 favoritePlacement(pager);guestRoute(auth,welcome,session);videoControls(pager,controls);detailFavorites(details,favorites);
 assert.throws(()=>favoritePlacement(pager.replace('? 0 : 38','? 0 : 160')));
 assert.throws(()=>guestRoute(auth.replace('onGuest: { session.continueAsGuest() }','onGuest: {}'),welcome,session));
 assert.throws(()=>guestRoute(auth,welcome,session.replace(/clearSessionState\(\)\s+setGuestMode\(true\)/,'setGuestMode(true)')));
 assert.throws(()=>videoControls(pager,controls.replace('isPaused.toggle()','_ = isPaused')));
 assert.throws(()=>detailFavorites(details,favorites.replace('Button { Task { await store.toggle(post) } } label:', 'Button {} label:')));
});
