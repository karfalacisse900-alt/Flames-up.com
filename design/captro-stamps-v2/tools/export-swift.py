"""Compile trusted kit geometry to native drawing commands; never runs on device.
Requires fonttools==4.59.2. Run build-designs.py first. No text is outlined.
"""
import json, re
from pathlib import Path
from xml.etree import ElementTree as ET
from fontTools.svgLib.path import parse_path
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.transformPen import TransformPen
from fontTools.misc.transform import Transform

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT.parents[1] / 'ios_native/MIRA/Sources/MIRANative/Resources/CaptroStampTemplates.json'

def geometry(node):
    a = node.attrib
    n = lambda k, default=0: float(a.get(k, default))
    if node.tag == 'path': return a['d']
    if node.tag in ('circle', 'ellipse'):
        x,y = n('cx'),n('cy'); rx,ry = n('rx',n('r')),n('ry',n('r'))
        return f'M{x-rx} {y}a{rx} {ry} 0 1 0 {2*rx} 0a{rx} {ry} 0 1 0 {-2*rx} 0Z'
    if node.tag == 'rect':
        x,y,w,h,r=n('x'),n('y'),n('width'),n('height'),n('rx')
        r=min(r,w/2,h/2)
        return f'M{x+r} {y}H{x+w-r}Q{x+w} {y} {x+w} {y+r}V{y+h-r}Q{x+w} {y+h} {x+w-r} {y+h}H{x+r}Q{x} {y+h} {x} {y+h-r}V{y+r}Q{x} {y} {x+r} {y}Z'
    raise ValueError(f'Unsupported trusted shape: {node.tag}')

def layers(node, inherited=None, transform=Transform(), opacity=1, texture=False):
    a = {**(inherited or {}), **node.attrib}
    opacity *= float(node.get('opacity','1'))
    texture = texture or node.get('data-texture') == 'paper'
    for name,raw in re.findall(r'(\w+)\(([^)]+)\)',node.get('transform','')):
        v=[float(s) for s in re.split(r'[ ,]+',raw)]
        if name=='translate': transform=transform.translate(v[0],v[1] if len(v)>1 else 0)
        elif name=='scale': transform=transform.scale(v[0],v[1] if len(v)>1 else v[0])
        else: raise ValueError(name)
    if node.tag in ('svg','g'):
        for child in node: yield from layers(child,a,transform,opacity,texture)
        return
    pen=RecordingPen(); parse_path(geometry(node),TransformPen(pen,transform))
    commands=[]
    for op,points in pen.value:
        if op=='endPath': continue
        code={'moveTo':0,'lineTo':1,'qCurveTo':2,'curveTo':3,'closePath':4}[op]
        commands.append([code]+[round(v,5) for p in points for v in p])
    fill=a.get('fill','black')
    yield dict(commands=commands,fill=fill,stroke=a.get('stroke','none'),
        width=float(a.get('stroke-width','1'))*abs(transform.xx),opacity=opacity,
        evenOdd=a.get('fill-rule')=='evenodd',round=a.get('stroke-linecap')=='round',
        dash=[float(v) for v in re.split(r'[ ,]+',a['stroke-dasharray'])] if 'stroke-dasharray' in a else [],
        texture=texture,paper=fill=='{{paper}}')

def build():
    source=json.loads((ROOT/'tools/template-data.json').read_text(encoding='utf-8'))
    for template in source.values():
        for density in ('compact','full'):
            layout=template[density]
            layout['layers']=list(layers(ET.fromstring('<svg>'+layout.pop('frame')+'</svg>')))
    OUTPUT.parent.mkdir(parents=True,exist_ok=True)
    OUTPUT.write_text(json.dumps(source,ensure_ascii=False,separators=(',',':'))+'\n',encoding='utf-8')
    print(f'Compiled {len(source)*2} native layouts into {OUTPUT.name}')

if __name__=='__main__': build()
