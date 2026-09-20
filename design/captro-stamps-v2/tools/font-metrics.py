"""Rebuild advance-width tables from locally installed fonts. No font files copied."""
from fontTools.ttLib import TTFont
from pathlib import Path
import subprocess,json
R=Path(__file__).resolve().parents[1]
fonts={}
for family in ('sans','serif'):
 for weight in (400,500,600,700):
  for italic in (False, True):
   if family=='sans' and italic:continue
   if family=='serif' and weight!=400:continue
   base='Inter' if family=='sans' else 'EB Garamond'
   style=('Regular' if weight==400 else 'Medium' if weight==500 else 'SemiBold' if weight==600 else 'Bold') if not italic else 'Italic'
   fpath=subprocess.check_output(['fc-match',base+':style='+style,'-f','%{file}'],text=True)
   f=TTFont(fpath);cmap=f.getBestCmap();scale=f['head'].unitsPerEm
   chars=''.join(chr(i) for i in range(32,383))+'…·—–’“”→✓'
   key=family+str(weight)+('italic' if italic else '')
   fonts[key]={c:round(f['hmtx'][cmap[ord(c)]][0]/scale,5) for c in chars if ord(c) in cmap}
(R/'src/metrics.ts').write_text('// Conservative reference widths; actual app font shaping still needs device QA.\nexport const METRICS: Record<string, Record<string, number>> = '+json.dumps(fonts,ensure_ascii=False)+';\n')
print('Built reference metrics without copying or embedding fonts.')
