from pathlib import Path
import xml.etree.ElementTree as ET
from PIL import Image
import json,hashlib
R=Path(__file__).resolve().parents[1]
report={'svg_directories':{},'png_directories':{},'font_files_included':[],'transparent_tag_hole':True}
for folder in ['svg','svg-compact','frames','frames-compact','outlined','outlined-compact']:
 files=sorted((R/'assets'/folder).glob('*.svg'));assert len(files)==15
 for p in files:
  text=p.read_text();root=ET.fromstring(text);assert '{{' not in text
  if folder.startswith(('frames','outlined')):assert not any(e.tag.endswith('}text') for e in root.iter())
  assert '<image' not in text and '@font-face' not in text and '<script' not in text
 report['svg_directories'][folder]={'count':len(files),'xml_valid':True}
for folder,expected in [('png-4x',(2560,1152)),('png-compact-4x',(2560,896))]:
 files=sorted((R/'assets'/folder).glob('*.png'));assert len(files)==15
 for p in files:
  im=Image.open(p);assert im.size==expected;assert im.mode=='RGBA';assert im.getpixel((0,0))[3]==0;assert im.getchannel('A').getextrema()==(0,255)
 report['png_directories'][folder]={'count':len(files),'dimensions':expected,'transparent_background':True}
for suffix,height in [('',288),('-compact',224)]:
 im=Image.open(R/f'assets/png{suffix}-4x/club-tag@4x.png');assert im.getpixel((45*4,int(height/2)*4))[3]==0
for ext in ['*.ttf','*.otf','*.woff','*.woff2']:
 report['font_files_included'].extend(str(p.relative_to(R)) for p in R.rglob(ext))
assert not report['font_files_included']
(R/'tests/asset-validation.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
