"""Build Captro's original vector layouts. No downloaded or generated imagery.
Typography stays editable; reference outlines are exported separately.
"""
from pathlib import Path
import json, math, random
R = Path(__file__).resolve().parents[1]
T = {}
P = {
'moment-paper':dict(paper='#F7F1E4',ink='#282E29',line='#ABA693',accent='#8D4E32'),
'moment-postal':dict(paper='#8D4937',ink='#FFF1DB',line='#C39379',accent='#FFF1DB'),
'moment-voice':dict(paper='#E5EAE9',ink='#213E4A',line='#9DACAD',accent='#213E4A'),
'club-oval':dict(paper='#244D3E',ink='#FFF1D6',line='#92A487',accent='#FFF1D6'),
'club-member':dict(paper='#E1E7EF',ink='#263E63',line='#A0AEC4',accent='#263E63'),
'club-tag':dict(paper='#EBDACE',ink='#6F383A',line='#BA9B90',accent='#6F383A'),
'event-ticket':dict(paper='#E3DDEC',ink='#4B355E',line='#A495B2',accent='#4B355E'),
'event-screening':dict(paper='#333D35',ink='#F2E4B9',line='#818875',accent='#F2E4B9'),
'event-postal':dict(paper='#F4EBDD',ink='#90432F',line='#C19479',accent='#90432F'),
'meetup-note':dict(paper='#F0DEA1',ink='#4A4325',line='#B5A368',accent='#4A4325'),
'meetup-fold':dict(paper='#E5E7D8',ink='#384A33',line='#A4AC91',accent='#384A33'),
'meetup-route':dict(paper='#D8E6DC',ink='#27564C',line='#98B6A6',accent='#27564C'),
'deal-coupon':dict(paper='#964B38',ink='#FFF0D6',line='#C58E70',accent='#FFF0D6'),
'deal-cashback':dict(paper='#DCE8CF',ink='#31513B',line='#9AB088',accent='#31513B'),
'deal-drop':dict(paper='#D8E2EC',ink='#294668',line='#9AADBF',accent='#294668'),
}

def path(d,fill='none',stroke='{{line}}',sw=1.5,extra=''):
    return f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" {extra}/>'
def line(x1,y1,x2,y2,color='line',sw=1.5,dash=None,opacity=None):
    extra=(f'stroke-dasharray="{dash}" ' if dash else '')+(f'opacity="{opacity}"' if opacity else '')
    return path(f'M{x1} {y1}H{x2}' if y1==y2 else f'M{x1} {y1}L{x2} {y2}',stroke='{{'+color+'}}',sw=sw,extra=extra)
def rect(x,y,w,h,fill='none',stroke='{{line}}',sw=1.5,r=0,extra=''):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" {extra}/>'
def circle(x,y,r,fill='none',stroke='{{ink}}',sw=1.8,extra=''):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" {extra}/>'
def star(x,y,r=11,color='ink'):
    return path(f'M{x} {y-r}Q{x+2} {y-2} {x+r} {y}Q{x+2} {y+2} {x} {y+r}Q{x-2} {y+2} {x-r} {y}Q{x-2} {y-2} {x} {y-r}Z',fill='{{'+color+'}}',stroke='none',sw=0)
def arrow(x,y,w=30):
    return path(f'M{x} {y}h{w}m{-10} -10 10 10-10 10',stroke='{{ink}}',sw=2.4,extra='stroke-linecap="round" stroke-linejoin="round"')
def sun(x,y,r=13):
    s=circle(x,y,r,sw=1.8)
    for a in range(0,360,45):
        ca,sa=math.cos(math.radians(a)),math.sin(math.radians(a))
        s+=path(f'M{x+ca*(r+5):.2f} {y+sa*(r+5):.2f}L{x+ca*(r+11):.2f} {y+sa*(r+11):.2f}',stroke='{{ink}}',sw=1.7,extra='stroke-linecap="round"')
    return s

def people(x,y,scale=1):
    s='<g transform="translate(%s %s) scale(%s)" fill="none" stroke="{{ink}}" stroke-width="2.1" stroke-linecap="round">'%(x,y,scale)
    s+='<circle cx="13" cy="12" r="6"/><circle cx="32" cy="14" r="5"/><path d="M2 36v-5c0-13 23-13 23 0v5M29 24c9-1 15 3 15 11"/></g>'
    return s

def fiber(id,h,inside):
    rng=random.Random(id+str(h)); s=[]
    for _ in range(135):
        x=rng.uniform(14,626);y=rng.uniform(14,h-14)
        if inside(x,y):
            dx=rng.uniform(.6,2.5);dy=rng.uniform(-.4,.4)
            s.append(f'M{x:.1f} {y:.1f}l{dx:.1f} {dy:.1f}')
    return '<g data-texture="paper" opacity="0.035">'+path(' '.join(s),stroke='{{ink}}',sw=.6,extra='stroke-linecap="round"')+'</g>'

def shape(id,h):
    """Only genuine contours/holes: no masking paint that assumes a background."""
    y=h-10; inner=lambda x,z:22<x<618 and 22<z<h-22
    if id=='club-oval':
        cx,cy,rx,ry=320,h/2,307,(h-24)/2
        base=f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{{{{paper}}}}" stroke="{{{{ink}}}}" stroke-width="1.6"/>'
        base+=f'<ellipse cx="320" cy="{cy}" rx="295" ry="{ry-10}" fill="none" stroke="{{{{line}}}}" stroke-width="2"/>'
        base+=f'<ellipse cx="320" cy="{cy}" rx="285" ry="{ry-18}" fill="none" stroke="{{{{ink}}}}" stroke-width=".8" opacity=".45"/>'
        inner=lambda x,z:((x-320)/278)**2+((z-h/2)/(ry-20))**2<1
    elif id in ('moment-postal','event-postal'):
        # 20px scallops are purpose-drawn in the outline, not filled circles.
        d='M20 10'
        for x in range(20,620,20): d+=f'H{x+4}q6 9 12 0H{x+20}'
        d+='H630V14'
        for z in range(14,int(y-14),20):d+=f'V{z+4}q-9 6 0 12V{z+20}'
        d+=f'V{y}H620'
        for x in range(620,20,-20):d+=f'H{x-4}q-6-9-12 0H{x-20}'
        d+='H10V'+str(y-4)
        for z in range(int(y-4),24,-20):d+=f'V{z-4}q9-6 0-12V{z-20}'
        d+='V10Z'
        base=path(d,fill='{{paper}}',sw=1.25)+rect(26,26,588,h-52,sw=1.2)
        inner=lambda x,z:30<x<610 and 30<z<h-30
    elif id in ('event-ticket','event-screening','deal-coupon','deal-drop'):
        cy=h/2
        d=f'M22 10H618Q630 10 630 22V{cy-14}a14 14 0 0 0 0 28V{y-12}Q630 {y} 618 {y}H22Q10 {y} 10 {y-12}V{cy+14}a14 14 0 0 0 0-28V22Q10 10 22 10Z'
        base=path(d,fill='{{paper}}',sw=1.5)
        inner=lambda x,z:28<x<612 and 22<z<h-22
    elif id=='club-tag':
        # Even-odd subpath cuts a transparent hole through the tag.
        cy=h/2
        d=f'M48 10H618Q630 10 630 22V{y-12}Q630 {y} 618 {y}H48L10 {cy+56}V{cy-56}Z M45 {cy}m-9 0a9 9 0 1 0 18 0a9 9 0 1 0-18 0Z'
        base=path(d,fill='{{paper}}',sw=1.5,extra='fill-rule="evenodd"')
        inner=lambda x,z:70<x<614 and 24<z<h-24
    elif id=='meetup-route':
        d=f'M16 10H574L630 {h/2} 574 {y}H16Q10 {y} 10 {y-6}V16Q10 10 16 10Z'
        base=path(d,fill='{{paper}}',sw=1.5)
        inner=lambda x,z:24<x<566 and 24<z<h-24
    elif id=='meetup-fold':
        d=f'M18 10H585L630 55V{y}H10V18Q10 10 18 10Z'
        base=path(d,fill='{{paper}}',sw=1.5)
        base+=path('M585 10V55H630Z',fill='{{line}}',stroke='none',sw=0)
        base+=path('M585 55l-7 7H630v-7Z',fill='{{ink}}',stroke='none',sw=0,extra='opacity=".07"')
        inner=lambda x,z:26<x<611 and 28<z<h-26 and not(x>576 and z<70)
    elif id=='deal-cashback':
        d='M16 10H624V'+str(y-8)
        for x in range(624,16,-16):d+=f'l-8 7-8-7'
        d+='H16Z'
        base=path(d,fill='{{paper}}',sw=1.5)+rect(28,22,584,h-53,sw=.8)
        inner=lambda x,z:32<x<608 and 26<z<h-34
    elif id in ('moment-paper','meetup-note'):
        d=f'M14 13Q69 8 122 12T245 11T367 12T489 11T625 13L628 {h-18}Q571 {h-12} 514 {h-14}T395 {h-12}T271 {h-15}T145 {h-12}T12 {h-15}Q17 {h/2} 14 13Z'
        base=path(d,fill='{{paper}}',sw=1.4)
        inner=lambda x,z:28<x<607 and 30<z<h-30
    else:
        base=rect(12,12,616,h-24,'{{paper}}',r=8)
        inner=lambda x,z:28<x<611 and 28<z<h-28
    # Two faint offset contour layers lend the paper a thin, tangible edge.
    import re
    first = re.match(r'<(?:path|rect|ellipse)[^>]*?/>', base).group(0)
    shadow = first.replace('{{paper}}','#191B17').replace('{{ink}}','#191B17').replace('{{line}}','#191B17')
    shadows = '<g opacity=".045" transform="translate(0 3)">'+shadow+'</g><g opacity=".04" transform="translate(0 1.5)">'+shadow+'</g>'
    return shadows+base+fiber(id,h,inner)

def field(key,x,y,w,size=30,font='sans',weight=500,tracking=0,minSize=None,overflow=None,anchor='start',color='ink',italic=False):
    if overflow is None:overflow='ellipsis' if key in ('title','label','meta') else 'details'
    return dict(key=key,x=x,y=y,maxWidth=w,size=size,minSize=minSize if minSize is not None else size,font=font,weight=weight,tracking=tracking,overflow=overflow,anchor=anchor,color=color,italic=italic)

def design(id,compact=False):
    h=224 if compact else 288
    f=shape(id,h);fields=[]
    # Body positions keep titles separated from footer rules at both densities.
    head=58 if compact else 64
    title=123 if compact else 145
    bottom=h-39
    fs=54 if compact else 65
    if id in ('deal-coupon','deal-cashback'):head=44 if compact else 56
    elif id=='deal-drop' and compact:head=48
    if id=='moment-paper':
        f+=rect(25,25,590,h-50,sw=.9)+line(40,head+14,600,head+14)+sun(581,head-12,9)
        f+=line(40,bottom-33,600,bottom-33,sw=.95)
        fields=[field('label',42,head,475,30,weight=700,tracking=2.5),field('title',40,title,553,fs,'serif',400,minSize=50),field('compactText' if compact else 'footer',42,bottom,553,32 if compact else 28,tracking=.3)]
        if not compact:fields.append(field('meta',42,193,553,30))
    elif id=='moment-postal':
        # Large line-drawn sun impression, not a tiny generic icon.
        f+=line(151,38,151,h-38,color='ink',sw=1.3)
        f+=sun(88,h/2-12,22)+path(f'M55 {h/2+41}q16-10 32 0t32 0m-64 12q16-10 32 0t32 0',stroke='{{ink}}',sw=1.4)
        fields=[field('label',173,head,416,30,weight=700,tracking=2),field('title',170,title,414,fs,'serif',400,minSize=49),field('compactText' if compact else 'footer',174,bottom,413,30 if compact else 27,overflow='details')]
        if not compact:fields.append(field('meta',174,194,412,28))
    elif id=='moment-voice':
        # Opens details, not playback: a sound mark instead of a misleading play button.
        f+=line(34,head+15,606,head+15)+path(f'M578 {head-17}v10m8-17v24m8-17v10',stroke='{{ink}}',sw=2.2)
        fields=[field('label',36,head,505,30,weight=700,tracking=1.6),field('title',34,title,570,fs,'serif',400,minSize=49),field('sideMain',604,bottom,113,36,weight=600,anchor='end',overflow='details')]
        if not compact:fields.append(field('meta',37,191,490,28,tracking=.5))
    elif id=='club-oval':
        bottom=h-55
        # Horizontal register marks, a club mark with no decorative microtext.
        f+=star(209,head-10,5)+star(431,head-10,5)
        f+=line(167,bottom-30,473,bottom-30,color='line',sw=1)
        fields=[field('label',320,head,270,30,weight=600,tracking=3,anchor='middle'),field('title',320,title+2,510,fs,'serif',400,minSize=49,anchor='middle'),field('compactText' if compact else 'footer',320,bottom,444,30,anchor='middle',overflow='details')]
        if not compact:fields.append(field('meta',320,191,440,26,anchor='middle'))
    elif id=='club-member':
        f+=rect(23,23,86,h-46,'{{ink}}',stroke='none',sw=0,r=3)
        f+=circle(66,head+4,18,stroke='{{paper}}',sw=1.6)+circle(66,head+4,12,stroke='{{paper}}',sw=.8)
        f+=path(f'M57 {head+19}l-4 19 13-7 13 7-4-19',stroke='{{paper}}',sw=1.3)
        f+=rect(120,23,497,h-46,sw=.9)+line(137,head+14,599,head+14)
        fields=[field('label',139,head,446,30,weight=700,tracking=2.1),field('title',135,title,462,fs,'serif',400,minSize=47),field('compactText' if compact else 'footer',139,bottom,455,31,overflow='details')]
        if not compact:fields.append(field('meta',139,193,452,28))
    elif id=='club-tag':
        f+=circle(45,h/2,13,sw=.75,stroke='{{line}}')+line(78,32,78,h-32)
        f+=circle(585,head-10,14,sw=1.3)+circle(585,head-10,9,sw=.8)+line(98,bottom-33,601,bottom-33)
        fields=[field('label',101,head,433,30,weight=700,tracking=2.1),field('title',97,title,502,fs,'serif',400,minSize=49),field('compactText' if compact else 'footer',101,bottom,491,31,overflow='details')]
        if not compact:fields.append(field('meta',101,193,485,28))
    elif id=='event-ticket':
        split=142
        f+=line(split,25,split,h-25,dash='3 6',color='ink',sw=1.2)
        f+=line(164,head+14,604,head+14)+rect(571,head-22,31,19,stroke='{{ink}}',sw=1.4,r=2)
        fields=[field('sideTop',76,head+8,104,31,weight=600,anchor='middle',overflow='details'),field('sideMain',76,title+24,110,72 if compact else 83,weight=600,anchor='middle',overflow='details'),field('label',164,head,368,29,weight=700,tracking=2.2),field('title',162,title,440,fs,'serif',400,minSize=52),field('compactText' if compact else 'footer',165,bottom,436,30,overflow='details')]
        if not compact:fields.append(field('meta',165,196,438,27))
    elif id=='event-screening':
        # Rounded ticket with a print block / date stub. Still one tap target.
        f+=rect(508,25,105,h-50,'{{ink}}',stroke='none',sw=0,r=2)
        f+=line(488,26,488,h-26,color='ink',sw=1,dash='3 5')
        f+=line(36,head+14,468,head+14)
        for x in [43,61,79,97]:f+=rect(x,h-29,7,7,'{{ink}}',stroke='none',sw=0,r=1)
        fields=[field('label',38,head,426,30,weight=700,tracking=2.1),field('title',34,title,441,fs,'serif',400,minSize=47),field('sideTop',560,head+12,90,28,weight=500,anchor='middle',color='paper',overflow='details'),field('sideMain',560,title+24,93,68,weight=600,minSize=60,anchor='middle',color='paper',overflow='details'),field('compactText' if compact else 'footer',38,bottom,429,30,overflow='details')]
        if not compact:fields.append(field('meta',38,195,428,28))
    elif id=='event-postal':
        f+=line(41,head+14,599,head+14)
        for i in range(3): f+=path(f'M529 {head-22+i*8}q14-7 28 0t30 0',stroke='{{ink}}',sw=1.3)
        fields=[field('label',43,head,452,30,weight=700,tracking=2.3),field('title',40,title,560,fs,'serif',400,minSize=49),field('compactText' if compact else 'footer',44,bottom,549,31,overflow='details')]
        if not compact:fields.append(field('meta',44,193,550,28))
    elif id=='meetup-note':
        f+=line(36,head+15,605,head+15)+people(566,head-28,.8)+line(36,bottom-31,605,bottom-31)
        f+=arrow(567,bottom-9,30)
        fields=[field('label',39,head,500,30,weight=700,tracking=2.2),field('title',36,title,561,fs+3,'serif',400,minSize=51,italic=True),field('compactText' if compact else 'footer',40,bottom,513,30,overflow='details')]
        if not compact:fields.append(field('meta',40,193,548,28))
    elif id=='meetup-fold':
        f+=line(34,head+14,568,head+14)+line(35,bottom-32,603,bottom-32)+arrow(568,bottom-9,28)
        fields=[field('label',38,head,503,30,weight=700,tracking=2),field('title',35,title,566,fs,'serif',400,minSize=50),field('compactText' if compact else 'footer',39,bottom,514,30,overflow='details')]
        if not compact:fields.append(field('meta',39,193,520,28))
    elif id=='meetup-route':
        f+=line(104,31,104,h-31)
        f+=circle(59,head-9,5,fill='{{ink}}',stroke='none',sw=0)+line(59,head+2,59,title-6,dash='2 5',color='ink',sw=1.5)
        f+=path(f'M59 {title+35}C32 {title+6} 44 {title-11} 59 {title-11}S85 {title+6} 59 {title+35}Z',stroke='{{ink}}',sw=1.7)+circle(59,title+3,5,sw=1.5)
        fields=[field('label',128,head,425,30,weight=700,tracking=2),field('title',124,title,446,fs,'serif',400,minSize=47),field('compactText' if compact else 'footer',129,bottom,432,30,overflow='details')]
        if not compact:fields.append(field('meta',129,193,435,28))
    elif id=='deal-coupon':
        f+=line(497,26,497,h-26,dash='3 6',color='ink',sw=1.1)+line(36,bottom-33,478,bottom-33)
        f+=circle(557,head-5,21,sw=1.2)+path(f'M547 {head+5}l20-20m-15 1h0m10 19h0',stroke='{{ink}}',sw=2,extra='stroke-linecap="round"')+circle(549,head-13,3,sw=1.5)+circle(565,head+3,3,sw=1.5)+arrow(542,bottom-8,30)
        fields=[field('label',37,head,440,30,weight=700,tracking=2),field('title',31,title+6,446,70 if compact else 80,weight=700,minSize=64 if compact else 70,overflow='offer',tracking=-2),field('sideMain',557,title+10,111,27,weight=700,anchor='middle',overflow='details'),field('compactText' if compact else 'footer',37,bottom,439,30 if compact else 28,overflow='details')]
        if not compact:fields.extend([field('meta',37,203,435,31,weight=600),field('sideBottom',557,199,112,21,anchor='middle',overflow='details')])
    elif id=='deal-cashback':
        f+=line(40,bottom-33,600,bottom-33,dash='4 5',sw=1)
        f+=circle(577,title-15,28,stroke='{{line}}',sw=1.1)+path(f'M591 {title-12}a15 15 0 1 1-11-17m0-6v11h11',stroke='{{ink}}',sw=2,extra='stroke-linecap="round" stroke-linejoin="round"')
        fields=[field('label',42,head,550,29,weight=700,tracking=1.2),field('title',37,title+(10 if compact else 5),493,72 if compact else 80,weight=700,minSize=70,tracking=-1.6,overflow='offer'),field('compactText' if compact else 'footer',43,bottom,551,30 if compact else 28,overflow='details')]
        if not compact:fields.append(field('meta',43,204,515,31,weight=600))
    elif id=='deal-drop':
        f+=line(502,26,502,h-26,dash='3 6',color='ink',sw=1.1)+line(36,bottom-33,481,bottom-33)
        f+=circle(563,head+9,27,sw=1.2)+path(f'M563 {head-5}v27m-9-9 9 9 9-9',stroke='{{ink}}',sw=2,extra='stroke-linecap="round" stroke-linejoin="round"')+arrow(548,bottom-9,30)
        fields=[field('label',38,head,443,29,weight=700,tracking=1.1),field('title',32,title+3,450,65 if compact else 72,weight=700,minSize=58,tracking=-1.9,overflow='offer'),field('sideMain',563,title+20,106,26,weight=700,anchor='middle',overflow='details'),field('compactText' if compact else 'footer',38,bottom,443,29 if compact else 27,overflow='details')]
        if not compact:fields.append(field('meta',38,201,443,31,weight=600))
    return dict(width=640,height=h,frame=f,fields=fields)

labels={'moment-voice':'MOMENT / VOICE','deal-cashback':'DEAL / CASH BACK','deal-drop':'DEAL / DROP'}
for id in P:
    T[id]=dict(id=id,type=id.split('-')[0],label=labels.get(id,id.split('-')[0].upper()),colors=P[id],full=design(id),compact=design(id,True))
(R/'src/templates.ts').write_text('import type { StampTemplate, StampVariant } from "./types";\n\n/** Original Captro geometry; no external image or font dependencies. */\nexport const TEMPLATES: Record<StampVariant, StampTemplate> = '+json.dumps(T,ensure_ascii=False,indent=2)+';\n')
(R/'tools/template-data.json').write_text(json.dumps(T,ensure_ascii=False,indent=2))
# Sample copy is intentionally short enough to read at feed size. All offers are fictional.
S=[
 dict(type='moment',variant='moment-paper',title='A little of today',meta='WEST VILLAGE · NYC',footer='SEP 20, 2026',compactText='WEST VILLAGE · NYC'),
 dict(type='moment',variant='moment-postal',title='Slow Sunday',meta='CENTRAL PARK',footer='SEP 20 · NEW YORK',compactText='CENTRAL PARK · NYC'),
 dict(type='moment',variant='moment-voice',title='On my way home',meta='A NOTE FROM TODAY',footer='',sideMain='0:42',waveform=[.12,.28,.21,.49,.35,.78,.64,.93,.48,.65,.39,.87,.51,.99,.56,.42,.77,.59,.26,.46,.32,.54,.35,.18,.43,.28,.14,.21]),
 dict(type='club',variant='club-oval',title='NYC Photo Club',meta='127 MEMBERS',footer='$8 / MONTH · JOIN',compactText='$8 / MONTH · JOIN'),
 dict(type='club',variant='club-member',title='Sunday Readers',meta='A PLACE FOR GOOD BOOKS',footer='FREE · 32 MEMBERS',compactText='FREE · 32 MEMBERS'),
 dict(type='club',variant='club-tag',title='Studio Circle',meta='MAKE SOMETHING TOGETHER',footer='$12 / MONTH · JOIN',compactText='$12 / MONTH · JOIN'),
 dict(type='event',variant='event-ticket',title='After Hours',meta='BROOKLYN · LIVE MUSIC',footer='7 PM · $12 ENTRY',sideTop='SEP',sideMain='26',compactText='7 PM · $12 ENTRY'),
 dict(type='event',variant='event-screening',title='Sunday Cinema',meta='ONE FILM. GOOD COMPANY.',footer='7 PM · $10 ENTRY',sideTop='OCT',sideMain='02',compactText='7 PM · $10 ENTRY'),
 dict(type='event',variant='event-postal',title='Neighborhood Fest',meta='FOOD · MUSIC · LOCAL PEOPLE',footer='OCT 03 · 12 PM · FREE',compactText='OCT 03 · 12 PM · FREE'),
 dict(type='meetup',variant='meetup-note',title='Photo Walk',meta='DUMBO · 8 / 12 GOING',footer='SEP 27 · 2 PM · FREE',compactText='SEP 27 · 2 PM · DUMBO'),
 dict(type='meetup',variant='meetup-fold',title='Coffee & Company',meta='EAST VILLAGE · NEW YORK',footer='SAT · 11 AM · 6 SPOTS',compactText='SAT · 11 AM · 6 SPOTS'),
 dict(type='meetup',variant='meetup-route',title='Study Together',meta='BRING YOUR NOTEBOOK',footer='SEP 30 · 4 PM · BRONX',compactText='SEP 30 · 4 PM · BRONX'),
 dict(type='deal',variant='deal-coupon',title='15% OFF',meta='CAFÉ LUNA',footer='MIN. SPEND $20',sideMain='VIEW',sideBottom='OFFER',compactText='CAFÉ LUNA · $20 MIN.'),
 dict(type='deal',variant='deal-cashback',title='$4 BACK',meta='JOE’S PIZZA',footer='SPEND $20+ · SCAN RECEIPT',compactText='JOE’S PIZZA · $20 MIN.'),
 dict(type='deal',variant='deal-drop',title='FREE DRINK',meta='CAFÉ LUNA',footer='WITH A $15+ PURCHASE',sideMain='VIEW',compactText='CAFÉ LUNA · $15 MIN.'),
]
(R/'src/examples.ts').write_text('import type { StampData } from "./types";\n/** Demo records only. No active offers, dates or memberships. */\nexport const EXAMPLES: StampData[] = '+json.dumps(S,ensure_ascii=False,indent=2)+';\n')
(R/'examples.json').write_text(json.dumps(S,ensure_ascii=False,indent=2))
(R/'tokens.json').write_text(json.dumps(dict(version='2.0.0',palettes=P,layout={'full':{'viewBox':[0,0,640,288],'recommendedWidth':320},'compact':{'viewBox':[0,0,640,224],'recommendedWidth':232},'mediaInset':12,'oneStampPerPost':True},typography={'sans':'Inter with Arial fallback','serif':'EB Garamond with Georgia fallback','fontFilesIncluded':False}),indent=2))
print('Built 15 full layouts and 15 purpose-reflowed compact layouts.')
