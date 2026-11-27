"""
Generates the persona avatars (flat vector, adult proportions) as SVG files.

Each persona is built from layers: hair/hijab back, torso + outfit, neck,
face, features (eyes, brows, nose, mouth per expression), facial hair,
hair/hijab front, accessories. Output, per persona and expression:
  apps/mobile/assets/personas/<id>_<expr>_full.svg   (head and shoulders)
  apps/mobile/assets/personas/<id>_<expr>_head.svg   (face crop for badges)

Run: python3 design/personas/gen_personas.py
"""
import os

OUT = os.path.join(os.path.dirname(__file__), 'svg')
EXPRESSIONS = ['happy', 'neutral', 'sad', 'surprised']

SKIN = {
    'light': ('#F6D2B4', '#E5B08E'),
    'medium': ('#E2AD80', '#C98E62'),
    'tan': ('#C68A5C', '#A8703F'),
    'brown': ('#8E5B3C', '#73462B'),
}

CX, CY = 120, 112  # face centre in the 240x300 canvas


def shade(hex_color, f):
    h = hex_color.lstrip('#')
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    if f < 0:
        r, g, b = [int(c * (1 + f)) for c in (r, g, b)]
    else:
        r, g, b = [int(c + (255 - c) * f) for c in (r, g, b)]
    return '#%02X%02X%02X' % (r, g, b)


def face_path(w=94, h=116, jaw=0.72, chin=0.16):
    """Rounded face with a jaw; jaw 1 = square, 0.5 = narrow."""
    l, r, t, b = CX - w / 2, CX + w / 2, CY - h / 2, CY + h / 2
    jx = w / 2 * jaw
    return (f'M{CX},{t} C{CX + w * 0.36},{t} {r},{t + h * 0.14} {r},{CY - h * 0.06} '
            f'C{r},{CY + h * 0.18} {CX + jx + 6},{CY + h * 0.3} {CX + jx},{CY + h * 0.36} '
            f'C{CX + w * chin},{b - 4} {CX + w * 0.1},{b} {CX},{b} '
            f'C{CX - w * 0.1},{b} {CX - w * chin},{b - 4} {CX - jx},{CY + h * 0.36} '
            f'C{CX - jx - 6},{CY + h * 0.3} {l},{CY + h * 0.18} {l},{CY - h * 0.06} '
            f'C{l},{t + h * 0.14} {CX - w * 0.36},{t} {CX},{t} Z')


# ----------------------------------------------------------------- torso

def torso(p):
    o = p['outfit']
    c = p['outfit_color']
    d = shade(c, -0.18)
    base = f'<path d="M22,300 C22,236 52,206 96,196 L144,196 C188,206 218,236 218,300 Z" fill="{c}"/>'
    out = [base]
    if o == 'hoodie':
        out.append(f'<path d="M80,198 C88,226 152,226 160,198 C150,214 90,214 80,198 Z" fill="{d}"/>')
        out.append(f'<path d="M78,200 C70,208 70,222 84,228 C96,236 144,236 156,228 C170,222 170,208 162,200" fill="none" stroke="{d}" stroke-width="10" stroke-linecap="round"/>')
        out.append('<path d="M108,232 L106,262 M132,232 L134,262" stroke="#FFFFFF" stroke-width="3.5" stroke-linecap="round"/>')
        out.append('<circle cx="106" cy="264" r="3" fill="#FFFFFF"/><circle cx="134" cy="264" r="3" fill="#FFFFFF"/>')
        out.append(f'<path d="M70,300 L76,262 M170,300 L164,262" stroke="{d}" stroke-width="4" stroke-linecap="round"/>')
    elif o == 'tshirt':
        out.append(f'<path d="M98,196 C104,214 136,214 142,196" fill="none" stroke="{d}" stroke-width="6"/>')
        out.append(f'<path d="M62,300 L68,250 M178,300 L172,250" stroke="{d}" stroke-width="4" stroke-linecap="round"/>')
    elif o == 'shirt':
        out.append(f'<path d="M104,196 L120,222 L136,196 Z" fill="{p["skin"][0]}"/>')
        out.append(f'<path d="M96,194 L120,222 L102,232 L88,204 Z M144,194 L120,222 L138,232 L152,204 Z" fill="#FFFFFF"/>')
        out.append(f'<path d="M120,222 L120,300" stroke="{d}" stroke-width="3"/>')
        for y in (240, 262, 284):
            out.append(f'<circle cx="126" cy="{y}" r="2.6" fill="{d}"/>')
    elif o == 'jacket':
        inner = p.get('inner', '#F4F1EA')
        out.append(f'<path d="M98,198 C104,220 136,220 142,198 L136,300 L104,300 Z" fill="{inner}"/>')
        out.append(f'<path d="M96,196 L104,300 M144,196 L136,300" stroke="{d}" stroke-width="5"/>')
        out.append(f'<path d="M92,198 L110,246 L100,250 L84,206 Z M148,198 L130,246 L140,250 L156,206 Z" fill="{d}"/>')
    elif o == 'thobe':
        out.append(f'<path d="M106,196 L120,212 L134,196" fill="none" stroke="{d}" stroke-width="4"/>')
        out.append(f'<path d="M120,212 L120,262" stroke="{d}" stroke-width="3"/>')
        for y in (226, 244):
            out.append(f'<circle cx="120" cy="{y}" r="2.4" fill="{d}"/>')
    elif o == 'sport':
        out.append(f'<path d="M100,196 L120,214 L140,196" fill="none" stroke="#FFFFFF" stroke-width="5"/>')
        out.append('<path d="M120,214 L120,300" stroke="#FFFFFF" stroke-width="3.5"/>')
        out.append('<path d="M40,262 L84,230 M200,262 L156,230" stroke="#FFFFFF" stroke-width="7" stroke-linecap="round" opacity="0.9"/>')
    return ''.join(out)


# ------------------------------------------------------------------- hair

def hair_back(p):
    s = p['hair_style']
    c = p['hair']
    if s == 'long_wavy':
        return (f'<path d="M66,96 C60,40 180,40 174,96 C182,150 190,196 176,236 C160,250 150,226 150,210 '
                f'L90,210 C90,226 80,250 64,236 C50,196 58,150 66,96 Z" fill="{shade(c, -0.15)}"/>')
    if s == 'bob':
        return f'<path d="M64,104 C58,44 182,44 176,104 L182,170 C170,184 150,180 148,168 L92,168 C90,180 70,184 58,170 Z" fill="{shade(c, -0.15)}"/>'
    if s == 'afro':
        circles = [(120, 52, 44), (78, 72, 32), (162, 72, 32), (66, 108, 26), (174, 108, 26), (96, 46, 30), (144, 46, 30), (70, 140, 20), (170, 140, 20)]
        return ''.join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{c}"/>' for x, y, r in circles)
    if s == 'curly':
        circles = [(96, 64, 20), (120, 56, 22), (144, 64, 20), (80, 82, 16), (160, 82, 16)]
        return ''.join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{shade(c, -0.1)}"/>' for x, y, r in circles)
    return ''


def hair_front(p):
    s = p['hair_style']
    c = p['hair']
    hi = shade(c, 0.18)
    if s == 'fade':
        return (f'<path d="M72,100 C66,56 92,40 122,40 C152,40 176,54 168,100 C164,88 158,76 150,72 '
                f'C134,80 102,80 86,70 C80,78 76,88 72,100 Z" fill="{c}"/>'
                f'<path d="M72,100 L72,118 L76,118 L78,96 Z M168,100 L168,118 L164,118 L162,96 Z" fill="{c}" opacity="0.55"/>'
                f'<path d="M96,52 C110,46 132,46 146,52" stroke="{hi}" stroke-width="4" fill="none" stroke-linecap="round" opacity="0.7"/>')
    if s == 'side_part':
        return (f'<path d="M70,106 C62,50 96,36 124,38 C156,40 178,56 170,106 C166,90 160,78 152,72 '
                f'C130,62 104,64 92,74 C84,82 76,94 70,106 Z" fill="{c}"/>'
                f'<path d="M100,46 C92,56 90,66 92,74" stroke="{shade(c, -0.3)}" stroke-width="2.5" fill="none"/>'
                f'<path d="M112,48 C134,44 154,52 164,64" stroke="{hi}" stroke-width="4" fill="none" stroke-linecap="round" opacity="0.6"/>')
    if s == 'curly':
        circles = [(84, 76, 14), (100, 64, 16), (120, 60, 17), (140, 64, 16), (156, 76, 14), (110, 72, 12), (132, 72, 12)]
        return ''.join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{c}"/>' for x, y, r in circles) + \
            ''.join(f'<circle cx="{x - 3}" cy="{y - 4}" r="{r * 0.35}" fill="{hi}" opacity="0.5"/>' for x, y, r in circles[:5])
    if s == 'long_wavy':
        return (f'<path d="M70,112 C60,50 100,38 124,40 C160,42 182,66 172,118 C164,96 150,78 128,72 '
                f'C116,90 92,102 70,112 Z" fill="{c}"/>'
                f'<path d="M120,48 C146,48 164,62 170,84" stroke="{hi}" stroke-width="4" fill="none" stroke-linecap="round" opacity="0.6"/>')
    if s == 'bob':
        return (f'<path d="M68,110 C60,50 96,40 120,40 C146,40 180,50 172,110 C168,96 164,88 160,84 '
                f'L80,84 C76,90 72,98 68,110 Z" fill="{c}"/>'
                f'<path d="M80,84 C92,92 108,94 120,86 C132,94 148,92 160,84" fill="{c}"/>'
                f'<path d="M96,52 C112,46 132,46 148,52" stroke="{hi}" stroke-width="4" fill="none" stroke-linecap="round" opacity="0.6"/>')
    if s == 'afro':
        return ''
    if s == 'grey_receding':
        return (f'<path d="M70,112 C68,84 74,72 84,66 C82,80 80,96 78,116 Z M170,112 C172,84 166,72 156,66 '
                f'C158,80 160,96 162,116 Z" fill="{c}"/>'
                f'<path d="M92,58 C108,50 132,50 148,58" stroke="{c}" stroke-width="5" fill="none" stroke-linecap="round" opacity="0.8"/>')
    if s == 'buzz':
        return (f'<path d="M72,104 C66,52 96,42 120,42 C146,42 176,52 168,104 C162,86 150,74 120,72 '
                f'C92,74 78,86 72,104 Z" fill="{c}" opacity="0.9"/>')
    return ''


# --------------------------------------------------------------- headwear

def hijab_back(p):
    c = p['hijab']
    return (f'<path d="M58,120 C52,50 90,34 120,34 C150,34 188,50 182,120 C184,160 196,190 206,214 '
            f'C176,226 64,226 34,214 C44,190 56,160 58,120 Z" fill="{c}"/>')


def hijab_front(p):
    c = p['hijab']
    d = shade(c, -0.14)
    return (f'<path d="M66,118 C62,60 94,46 120,46 C146,46 178,60 174,118 C172,92 160,66 120,64 '
            f'C80,66 68,92 66,118 Z" fill="{c}"/>'
            f'<path d="M66,118 C66,150 82,176 104,186 C92,186 72,176 62,150 Z M174,118 C174,150 158,176 136,186 '
            f'C148,186 168,176 178,150 Z" fill="{d}" opacity="0.7"/>'
            f'<path d="M78,72 C98,58 142,58 162,72" stroke="{shade(c, 0.25)}" stroke-width="3" fill="none" opacity="0.7" stroke-linecap="round"/>')


def ghutra(p, front):
    c = '#FBFBFB'
    if not front:
        return (f'<path d="M56,116 C50,52 88,36 120,36 C152,36 190,52 184,116 C188,160 200,196 210,222 '
                f'C182,230 160,214 152,200 L88,200 C80,214 58,230 30,222 C40,196 52,160 56,116 Z" fill="{c}"/>'
                f'<path d="M56,116 C50,52 88,36 120,36 C152,36 190,52 184,116" fill="none" stroke="#E4E4E4" stroke-width="2"/>')
    return (f'<path d="M66,112 C64,62 92,48 120,48 C148,48 176,62 174,112 C170,86 156,68 120,66 C84,68 70,86 66,112 Z" fill="{c}"/>'
            f'<ellipse cx="120" cy="50" rx="50" ry="10" fill="none" stroke="#1D1B22" stroke-width="6"/>'
            f'<ellipse cx="120" cy="44" rx="46" ry="8" fill="none" stroke="#1D1B22" stroke-width="5"/>')


def cap(p):
    c = p['cap']
    d = shade(c, -0.2)
    return (f'<path d="M68,98 C64,46 96,34 120,34 C144,34 176,46 172,98 C150,86 90,86 68,98 Z" fill="{c}"/>'
            f'<path d="M68,98 C90,86 150,86 172,98 L172,104 C150,92 90,92 68,104 Z" fill="{d}"/>'
            f'<rect x="110" y="86" width="20" height="8" rx="3" fill="{d}"/>'
            f'<circle cx="120" cy="36" r="4" fill="{d}"/>')


def headband(p):
    return f'<path d="M70,90 C92,74 148,74 170,90 L170,100 C148,84 92,84 70,100 Z" fill="{p["band"]}"/>'


# ------------------------------------------------------------------- face

def eyes(p, e):
    out = []
    lid = '#2A1C17'
    for sx in (-1, 1):
        x = CX + sx * 19
        y = CY + 4
        if e == 'happy':
            out.append(f'<path d="M{x - 8},{y + 1} C{x - 4},{y - 7} {x + 4},{y - 7} {x + 8},{y + 1}" stroke="{lid}" stroke-width="3.6" fill="none" stroke-linecap="round"/>')
            continue
        ry = 7 if e == 'surprised' else 5.6
        out.append(f'<ellipse cx="{x}" cy="{y}" rx="7.5" ry="{ry + 0.8}" fill="#FFFFFF"/>')
        out.append(f'<circle cx="{x}" cy="{y + 0.6}" r="{4.6 if e != "surprised" else 4.2}" fill="{p.get("eye", "#4A2E20")}"/>')
        out.append(f'<circle cx="{x}" cy="{y + 0.6}" r="2.2" fill="#1A120E"/>')
        out.append(f'<circle cx="{x + 1.6}" cy="{y - 1.2}" r="1.4" fill="#FFFFFF"/>')
        top = y - ry - 0.4
        out.append(f'<path d="M{x - 8},{y - 1} C{x - 5},{top - 1} {x + 5},{top - 1} {x + 8.5},{y - 1}" stroke="{lid}" stroke-width="2.6" fill="none" stroke-linecap="round"/>')
        if p.get('lashes'):
            out.append(f'<path d="M{x + sx * 8.5},{y - 1} L{x + sx * 11.5},{y - 3.5}" stroke="{lid}" stroke-width="2.2" stroke-linecap="round"/>')
    return ''.join(out)


def brows(p, e):
    c = shade(p.get('brow', p.get('hair', '#2B1A12')), -0.1)
    w = p.get('brow_w', 4.2)
    out = []
    for sx in (-1, 1):
        x = CX + sx * 19
        y = CY - 12 - (4 if e == 'surprised' else 0)
        inner, outer = (y, y) if e == 'neutral' else (y - 1.5, y + 0.5)
        if e == 'sad':
            inner, outer = y - 4, y + 2
        if e == 'happy':
            inner, outer = y - 1, y
        xi, xo = x - sx * 9, x + sx * 9
        mid = min(inner, outer) - 3
        out.append(f'<path d="M{xi},{inner} Q{x},{mid} {xo},{outer}" stroke="{c}" stroke-width="{w}" fill="none" stroke-linecap="round"/>')
    return ''.join(out)


def nose(p):
    d = p['skin'][1]
    return f'<path d="M{CX - 2},{CY + 10} C{CX - 4},{CY + 18} {CX - 7},{CY + 22} {CX - 3},{CY + 25} C{CX},{CY + 26} {CX + 4},{CY + 25} {CX + 6},{CY + 23}" stroke="{d}" stroke-width="2.6" fill="none" stroke-linecap="round"/>'


def mouth(p, e):
    y = CY + 36
    lip = p.get('lip', '#B5555A')
    if e == 'happy':
        return (f'<path d="M{CX - 15},{y - 3} C{CX - 10},{y + 13} {CX + 10},{y + 13} {CX + 15},{y - 3} C{CX + 5},{y} {CX - 5},{y} {CX - 15},{y - 3} Z" fill="#7A2E33"/>'
                f'<path d="M{CX - 12},{y - 1.5} C{CX - 4},{y + 1.5} {CX + 4},{y + 1.5} {CX + 12},{y - 1.5} L{CX + 10},{y + 3} C{CX + 3},{y + 5} {CX - 3},{y + 5} {CX - 10},{y + 3} Z" fill="#FFFFFF"/>'
                f'<path d="M{CX - 7},{y + 8} C{CX - 2},{y + 10} {CX + 2},{y + 10} {CX + 7},{y + 8}" stroke="{lip}" stroke-width="2.2" fill="none" stroke-linecap="round" opacity="0.7"/>')
    if e == 'neutral':
        return f'<path d="M{CX - 10},{y + 1} C{CX - 4},{y + 4} {CX + 4},{y + 4} {CX + 10},{y + 1}" stroke="{lip}" stroke-width="3.4" fill="none" stroke-linecap="round"/>'
    if e == 'sad':
        return f'<path d="M{CX - 10},{y + 5} C{CX - 4},{y - 1} {CX + 4},{y - 1} {CX + 10},{y + 5}" stroke="{lip}" stroke-width="3.4" fill="none" stroke-linecap="round"/>'
    return f'<ellipse cx="{CX}" cy="{y + 3}" rx="6" ry="8" fill="#7A2E33"/>'


def facial_hair(p):
    s = p.get('facial')
    if not s:
        return ''
    c = p['hair'] if p['hair_style'] != 'grey_receding' else p['hair']
    if s in ('beard', 'stubble'):
        op = '1' if s == 'beard' else '0.28'
        return (f'<path d="M73,116 C74,150 92,176 120,176 C148,176 166,150 167,116 C164,132 158,140 150,144 '
                f'C142,146 136,140 120,140 C104,140 98,146 90,144 C82,140 76,132 73,116 Z" fill="{c}" opacity="{op}"/>'
                f'<path d="M{CX - 16},{CY + 30} C{CX - 8},{CY + 25} {CX + 8},{CY + 25} {CX + 16},{CY + 30} C{CX + 8},{CY + 29} {CX - 8},{CY + 29} {CX - 16},{CY + 30} Z" fill="{c}" opacity="{op}"/>')
    if s == 'mustache':
        return f'<path d="M{CX - 18},{CY + 32} C{CX - 12},{CY + 22} {CX - 3},{CY + 25} {CX},{CY + 28} C{CX + 3},{CY + 25} {CX + 12},{CY + 22} {CX + 18},{CY + 32} C{CX + 8},{CY + 30} {CX - 8},{CY + 30} {CX - 18},{CY + 32} Z" fill="{c}"/>'
    return ''


def glasses(p):
    c = p['glasses']
    out = []
    for sx in (-1, 1):
        x = CX + sx * 19
        out.append(f'<rect x="{x - 13}" y="{CY - 6}" width="26" height="20" rx="7" fill="#FFFFFF" fill-opacity="0.12" stroke="{c}" stroke-width="3"/>')
    out.append(f'<path d="M{CX - 6},{CY + 1} C{CX - 2},{CY - 2} {CX + 2},{CY - 2} {CX + 6},{CY + 1}" stroke="{c}" stroke-width="3" fill="none"/>')
    out.append(f'<path d="M{CX - 32},{CY + 0} L{CX - 46},{CY - 3} M{CX + 32},{CY + 0} L{CX + 46},{CY - 3}" stroke="{c}" stroke-width="3"/>')
    return ''.join(out)


def earrings(p):
    return f'<circle cx="{CX - 47}" cy="{CY + 16}" r="3.6" fill="#F5C24C"/><circle cx="{CX + 47}" cy="{CY + 16}" r="3.6" fill="#F5C24C"/>'


# ------------------------------------------------------------------ build

def persona_svg(p, e, view):
    skin, skin_d = p['skin']
    head = p.get('head', {})
    parts = []
    if p.get('hijab'):
        parts.append(hijab_back(p))
    elif p.get('ghutra'):
        parts.append(ghutra(p, False))
    else:
        parts.append(hair_back(p))
    parts.append(torso(p))
    if p.get('hijab'):
        # the scarf wraps under the chin and covers the neck
        c = p['hijab']
        parts.append(f'<path d="M64,120 L176,120 L186,222 C150,238 90,238 54,222 Z" fill="{c}"/>')
        parts.append(f'<path d="M84,176 C98,196 142,196 156,176 C150,206 90,206 84,176 Z" fill="{shade(c, -0.12)}" opacity="0.8"/>')
    else:
        # neck with a shadow under the chin
        parts.append(f'<path d="M100,150 L100,200 C108,210 132,210 140,200 L140,150 Z" fill="{skin_d}"/>')
        parts.append(f'<path d="M100,176 C110,188 130,188 140,176 L140,150 L100,150 Z" fill="{shade(skin_d, -0.08)}"/>')
    if not p.get('hijab') and not p.get('ghutra'):
        for sx in (-1, 1):
            parts.append(f'<ellipse cx="{CX + sx * 47}" cy="{CY + 4}" rx="8" ry="12" fill="{skin}"/>')
            parts.append(f'<ellipse cx="{CX + sx * 48}" cy="{CY + 4}" rx="3.5" ry="6" fill="{skin_d}"/>')
    parts.append(f'<path d="{face_path(**head)}" fill="{skin}"/>')
    # soft cheek blush
    parts.append(f'<ellipse cx="{CX - 28}" cy="{CY + 22}" rx="9" ry="5.5" fill="#F07C7C" opacity="{p.get("blush", 0.18)}"/>')
    parts.append(f'<ellipse cx="{CX + 28}" cy="{CY + 22}" rx="9" ry="5.5" fill="#F07C7C" opacity="{p.get("blush", 0.18)}"/>')
    parts.append(facial_hair(p))
    parts.append(eyes(p, e))
    parts.append(brows(p, e))
    parts.append(nose(p))
    parts.append(mouth(p, e))
    if p.get('hijab'):
        parts.append(hijab_front(p))
    elif p.get('ghutra'):
        parts.append(ghutra(p, True))
    else:
        parts.append(hair_front(p))
    if p.get('band'):
        parts.append(headband(p))
    if p.get('cap'):
        parts.append(cap(p))
    if p.get('glasses'):
        parts.append(glasses(p))
    if p.get('earrings'):
        parts.append(earrings(p))
    vb = '0 0 240 300' if view == 'full' else '46 34 148 148'
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb}">{"".join(parts)}</svg>'


PERSONAS = [
    dict(id='youssef', name='يوسف', skin=SKIN['medium'], hair='#1E1612', hair_style='fade', facial='beard',
         outfit='hoodie', outfit_color='#3D6BE0', head=dict(jaw=0.8)),
    dict(id='nour', name='نور', skin=SKIN['light'], hijab='#E8739A', outfit='jacket', outfit_color='#5A4FCF',
         inner='#FFF3E6', lashes=True, blush=0.28, lip='#C2566A', brow='#3A2418', brow_w=3.4, head=dict(w=90, jaw=0.62)),
    dict(id='karim', name='كريم', skin=SKIN['tan'], hair='#2A1A10', hair_style='curly', glasses='#1F1F2A',
         facial='stubble', outfit='shirt', outfit_color='#2BA68A', head=dict(jaw=0.76)),
    dict(id='layla', name='ليلى', skin=SKIN['light'], hair='#5A2E1C', hair_style='long_wavy', earrings=True,
         lashes=True, blush=0.3, lip='#C2566A', brow_w=3.4, outfit='tshirt', outfit_color='#F2A93B', head=dict(w=90, jaw=0.6)),
    dict(id='omar', name='عمر', skin=SKIN['brown'], hair='#141014', hair_style='buzz', cap='#E2483D',
         facial='stubble', outfit='sport', outfit_color='#1F2433', head=dict(jaw=0.82)),
    dict(id='salma', name='سلمى', skin=SKIN['medium'], hair='#17121A', hair_style='bob', lashes=True, blush=0.28,
         lip='#B44A5E', brow_w=3.4, outfit='jacket', outfit_color='#2E2A3D', inner='#E84F6B', earrings=True, head=dict(w=90, jaw=0.62)),
    dict(id='saber', name='عم صابر', skin=SKIN['tan'], hair='#C9C6C2', hair_style='grey_receding', facial='mustache',
         brow='#B8B3AE', outfit='shirt', outfit_color='#7A5A3A', head=dict(w=98, jaw=0.84)),
    dict(id='fatma', name='فاطمة', skin=SKIN['medium'], hijab='#2D3A6B', glasses='#7A3B2E', lashes=True, blush=0.25,
         lip='#B5555A', brow='#2B1A12', brow_w=3.4, outfit='tshirt', outfit_color='#4FB3C9', head=dict(w=90, jaw=0.64)),
    dict(id='khaled', name='خالد', skin=SKIN['tan'], hair='#1A1412', hair_style='buzz', ghutra=True, facial='beard',
         outfit='thobe', outfit_color='#F6F4EF', head=dict(jaw=0.8)),
    dict(id='reem', name='ريم', skin=SKIN['brown'], hair='#1B1214', hair_style='afro', band='#F2C94C', lashes=True,
         blush=0.25, lip='#9E3F4E', brow_w=3.4, earrings=True, outfit='sport', outfit_color='#8E5BFF', head=dict(w=90, jaw=0.62)),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    for p in PERSONAS:
        for e in EXPRESSIONS:
            for view in ('full', 'head'):
                with open(os.path.join(OUT, f"{p['id']}_{e}_{view}.svg"), 'w') as f:
                    f.write(persona_svg(p, e, view))
    print(f'wrote {len(PERSONAS) * len(EXPRESSIONS) * 2} files to {os.path.normpath(OUT)}')


if __name__ == '__main__':
    main()
