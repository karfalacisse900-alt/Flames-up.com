"""Export example text as curves, preserving appearance without distributing fonts.
Requires local fonts plus fontTools, CairoSVG and Pillow. The editable originals remain.
"""
from pathlib import Path
from functools import lru_cache
import subprocess,xml.etree.ElementTree as ET,re,json
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
import cairosvg
R=Path(__file__).resolve().parents[1]
NS='http://www.w3.org/2000/svg'
ET.register_namespace('',NS)
@lru_cache(None)
def font_for(family,weight,italic):
    family=family.split(',')[0].strip().strip("'\"")
    style='Italic' if italic else 'Bold' if weight>=700 else 'SemiBold' if weight>=600 else 'Medium' if weight>=500 else 'Regular'
    filename=subprocess.check_output(['fc-match',f'{family}:style={style}','-f','%{file}'],text=True)
    return TTFont(filename)
def n(v):
    s=f'{v:.3f}'.rstrip('0').rstrip('.')
    return s or '0'
def outline(file,dest):
    root=ET.parse(file).getroot()
    for parent in root.iter():
        for index,el in enumerate(list(parent)):
            if el.tag!=f'{{{NS}}}text':continue
            a=el.attrib;txt=el.text or '';font=font_for(a.get('font-family','Inter'),int(a.get('font-weight','400')),a.get('font-style')=='italic')
            size=float(a['font-size']);unit=size/font['head'].unitsPerEm;cmap=font.getBestCmap();gs=font.getGlyphSet();track=float(a.get('letter-spacing','0'))
            names=[cmap.get(ord(c),'.notdef') for c in txt]
            advances=[font['hmtx'][g][0]*unit for g in names];total=sum(advances)+max(0,len(names)-1)*track
            anchor=a.get('text-anchor','start');x=float(a['x'])-(total/2 if anchor=='middle' else total if anchor=='end' else 0);y=float(a['y'])
            pen=SVGPathPen(gs,ntos=n)
            for glyph,advance in zip(names,advances):
                gs[glyph].draw(TransformPen(pen,(unit,0,0,-unit,x,y)));x+=advance+track
            repl=ET.Element(f'{{{NS}}}path',{'d':pen.getCommands(),'fill':a.get('fill','#000000')})
            if 'data-field' in a:repl.set('data-field',a['data-field'])
            parent.remove(el);parent.insert(index,repl)
    ET.ElementTree(root).write(dest,encoding='unicode',xml_declaration=False)
for compact in (False,True):
    suffix='-compact' if compact else ''
    for source in (R/f'assets/svg{suffix}').glob('*.svg'):
        target=R/f'assets/outlined{suffix}'/source.name
        outline(source,target)
        png=R/f'assets/png{suffix}-4x'/f'{source.stem}@4x.png'
        cairosvg.svg2png(url=str(target),write_to=str(png),output_width=2560,output_height=896 if compact else 1152)
    examples=json.loads((R/'examples.json').read_text())
    ht=224 if compact else 288;W=2180;H=60+5*(ht+70)
    parts=[f'<svg xmlns="{NS}" width="{W}" height="{H}" viewBox="0 0 {W} {H}"><rect width="100%" height="100%" fill="#F4F1EA"/>']
    for i,e in enumerate(examples):
        svg=(R/f'assets/outlined{suffix}'/f'{e["variant"]}.svg').read_text();body=re.sub(r'^<svg[^>]*>','',svg).removesuffix('</svg>')
        x=70+(i%3)*710;y=65+(i//3)*(ht+70);parts.append(f'<g transform="translate({x} {y})">{body}</g>')
    parts.append('</svg>');dest=R/'preview'/f'all-15{"-compact" if compact else "-stamps"}.svg';dest.write_text(''.join(parts))
    cairosvg.svg2png(url=str(dest),write_to=str(dest.with_suffix('.png')))
print('Exported 30 outlined reference SVGs, 30 transparent PNGs at 4×, and two stamp-only boards.')
