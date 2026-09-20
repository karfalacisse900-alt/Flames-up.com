from pathlib import Path
from playwright.sync_api import sync_playwright
import json, shutil, itertools
R=Path(__file__).resolve().parents[1]
report={}
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path=shutil.which('chromium'),headless=True,args=['--no-sandbox'])
 page=browser.new_page(viewport={'width':1440,'height':1000},device_scale_factor=1)
 errors=[];requests=[]
 page.on('pageerror',lambda e:errors.append(str(e)))
 page.on('request',lambda r:requests.append(r.url))
 page.set_content((R/'studio.html').read_text(),wait_until='load');page.wait_for_function('window.CaptroKit && document.fonts.status === "loaded"')
 report['initial_gallery_count']=page.locator('.cell').count();assert report['initial_gallery_count']==15
 report['layout_bounds']=page.evaluate('''() => {const K=window.CaptroKit;const host=document.createElement('div');document.body.append(host);const result=[];for(const density of ['full','compact'])for(const s of K.samples){host.innerHTML=K.renderStamp(s,{density});const errors=[];const boxes=[];for(const text of host.querySelectorAll('text')){const b=text.getBBox(),max=+text.dataset.maxWidth;const entry={field:text.dataset.field,text:text.textContent,x:b.x,y:b.y,w:b.width,h:b.height,max};boxes.push(entry);if(b.width>max+1.5||b.x<5||b.x+b.width>635||b.y<5||b.y+b.height>(density==='full'?285:221))errors.push(entry)}result.push({variant:s.variant,density,errors,boxes})}host.remove();return result}''')
 violations=[x for x in report['layout_bounds'] if x['errors']]
 report['text_bounds_pass']=not violations
 overlap=[]
 for layout in report['layout_bounds']:
  for a,b in itertools.combinations(layout['boxes'],2):
   dx=min(a['x']+a['w'],b['x']+b['w'])-max(a['x'],b['x'])
   dy=min(a['y']+a['h'],b['y']+b['h'])-max(a['y'],b['y'])
   if dx>1 and dy>1:overlap.append([layout['variant'],layout['density'],a['field'],b['field']])
 report['text_overlaps']=overlap
 assert not overlap
 page.screenshot(path=str(R/'preview/studio-desktop.png'),full_page=True)
 page.locator('[data-filter="deal"]').click();assert page.locator('.cell').count()==3;report['filters']=True
 page.locator('.stamp-button').first.click();assert page.locator('#editor').is_visible()
 page.locator('#fields input[data-field="title"]').fill('20% OFF')
 assert '20% OFF' in page.locator('#live').inner_text();report['live_editing']=True
 page.locator('#edit-density').select_option('compact');assert '224' in page.locator('#live svg').get_attribute('viewBox');report['compact_switch']=True
 page.locator('[data-surface="dark"]').last.click();assert page.locator('#stage').get_attribute('data-surface')=='dark'
 with page.expect_download() as dl:page.locator('#svg-export').click()
 report['svg_download']=dl.value.suggested_filename
 with page.expect_download() as dl:page.locator('#png-export').click()
 report['png_download']=dl.value.suggested_filename
 page.locator('#fields input[data-field="title"]').fill('<img src=x onerror="window.hacked=true">')
 assert page.evaluate('window.hacked===undefined');assert page.locator('#live img').count()==0;report['injection_check']=True
 page.keyboard.press('Escape');assert not page.locator('#editor').is_visible();report['escape_close']=True
 page.locator('[data-filter="all"]').click()
 page.set_viewport_size({'width':390,'height':844});page.screenshot(path=str(R/'preview/studio-mobile.png'),full_page=True)
 report['mobile_no_horizontal_overflow']=page.evaluate('document.documentElement.scrollWidth <= innerWidth')
 assert report['mobile_no_horizontal_overflow']
 page.locator('#gallery-density').select_option('compact');page.locator('#feed-size').click();page.screenshot(path=str(R/'preview/studio-mobile-feed.png'),full_page=True)
 report['errors']=errors;report['external_requests']=[u for u in requests if not u.startswith(('file:','blob:','data:'))]
 assert not errors;assert not report['external_requests']
 browser.close()
(R/'tests/browser-validation.json').write_text(json.dumps(report,indent=2))
print(json.dumps({k:v for k,v in report.items() if k!='layout_bounds'},indent=2))
if violations:
 print('TEXT VIOLATIONS:',json.dumps(violations,indent=2));raise SystemExit(1)
