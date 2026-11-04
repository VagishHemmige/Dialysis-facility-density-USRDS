"""Render the compact ESRD classification diagram using only Python standard libraries.

See README.md for regeneration, provenance, and known visual limitations.
"""
from pathlib import Path
from html import escape
import base64
ASSET_DIR = Path(__file__).resolve().parent / 'assets'
p = []

def box(x, y, w, h, fill='#fff', stroke='#c5d3e2', r=14):
    p.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{stroke}" stroke-width="2"/>')

def t(x, y, s, size=20, b=False, c='#18334e'):
    p.append(f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{(700 if b else 400)}" fill="{c}">{escape(s)}</text>')

def a(d, ret=False):
    c = '#168577' if ret else '#316bbb'
    p.append(f'''<path d="{d}" fill="none" stroke="{c}" stroke-width="3" marker-end="url(#{('ret' if ret else 'send')})"/>''')

def logo(n, x, y, w=48, h=48):
    ext = 'png' if n == 'ellmer' else 'svg'
    raw = (ASSET_DIR / (n + '.' + ext)).read_bytes()
    mime = 'image/png' if ext == 'png' else 'image/svg+xml'
    p.append(f'<image x="{x}" y="{y}" width="{w}" height="{h}" href="data:{mime};base64,{base64.b64encode(raw).decode()}"/>')

def main():
    box(0, 0, 1600, 980, '#fff', '#fff', 0)
    t(40, 55, 'Classifying ICD codes with R and ellmer', 36, True)
    t(40, 91, 'R groups public codes into batches; model classifications return to the same R session.', 21)
    box(310, 130, 940, 700, '#f1f6fc', '#7c9bbb', 24)
    t(340, 170, 'ANALYST’S COMPUTER', 25, True)
    box(20, 290, 260, 255, '#fff8e4', '#e3d5af')
    t(38, 325, 'Public code list', 23, True)
    t(38, 356, '445 USRDS cause codes', 17)
    t(38, 394, 'Code', 15, True)
    t(118, 394, 'Description', 15, True)
    for y, c, d in [(428, '4464Z', 'Wegener’s'), (463, 'B20', 'HIV disease'), (498, 'I50.9', 'Heart failure')]:
        t(38, y, c, 15)
        t(118, y, d, 15)
    t(38, 526, 'No patient data', 17, True)
    a('M 280 410 H 330')
    box(340, 200, 420, 585, '#fff', '#9db9d5')
    logo('r', 365, 219, 70, 55)
    t(450, 257, 'R session', 27, True)
    t(365, 305, 'Input dataset', 21, True)
    box(360, 322, 380, 167, '#f4f8fc')
    t(375, 350, 'Code', 16, True)
    t(460, 350, 'Description', 16, True)
    for y, c, d in [(389, '4464Z', 'Wegener’s granulomatosis'), (427, 'B20', 'HIV disease'), (465, 'I50.9', 'Heart failure')]:
        t(375, y, c, 16)
        t(460, y, d, 16)
    t(365, 566, 'Classified dataset', 21, True)
    box(360, 586, 380, 160, '#eef8f4', '#a0cebf')
    t(375, 614, 'Code', 16, True)
    t(460, 614, 'Category*', 16, True)
    for y, c, d in [(651, '4464Z', 'Glomerulonephritis'), (687, 'B20', 'Glomerulonephritis'), (723, 'I50.9', 'Hypertension / cardiac')]:
        t(375, y, c, 16)
        t(460, y, d, 16)
    t(365, 770, '*Illustrative rows', 15)
    for x, y in [(797, 388), (791, 382), (785, 376)]:
        box(x, y, 125, 133, '#fff8e4', '#dcc88e', 7)
    t(799, 404, 'BATCH', 17, True)
    for y, c in [(433, '4464Z'), (460, 'B20'), (487, 'I50.9')]:
        t(802, y, c, 16)
    a('M 760 440 H 777')
    t(783, 542, 'Shared prompt', 16, True)
    t(783, 565, 'Six categories', 16)
    box(950, 390, 230, 180, '#fff8e4', '#dbc483')
    logo('ellmer', 1015, 405, 95, 105)
    t(1019, 547, 'ellmer', 25, True)
    a('M 922 440 H 940')
    a('M 950 530 H 930 V 671 H 750', True)
    t(790, 699, 'Classifications + reasons', 17, c='#168577')
    box(905, 200, 305, 130, '#f2edfa', '#c4b3dc')
    logo('ollama', 920, 212, 37, 46)
    t(971, 244, 'Ollama · local models', 19, True)
    logo('qwen', 923, 267, 30, 30)
    t(962, 290, 'Qwen', 18)
    logo('meta', 1045, 267, 30, 30)
    t(1083, 290, 'Llama', 18)
    t(924, 318, 'Comparison only · no vote', 16, True)
    a('M 990 390 V 340')
    a('M 1120 330 V 380', True)
    t(931, 363, 'send', 15, c='#316bbb')
    t(1138, 363, 'return', 15, c='#168577')
    box(1290, 200, 290, 490, '#eef8f3', '#a2cdb9')
    t(1310, 240, 'CLOUD SERVICES', 23, True)
    for y, n, title in [(270, 'openai', 'OpenAI · GPT'), (395, 'claude', 'Claude'), (520, 'gemini', 'Gemini')]:
        box(1310, y, 250, 90)
        logo(n, 1323, y + 20, 42, 42)
        t(1380, y + 51, title, 20, True)
    t(1310, 665, 'Three voting models', 20, True)
    p.append('<path d="M1220 300 V550" fill="none" stroke="#316bbb" stroke-width="3"/>')
    a('M 1180 440 H 1220')
    for y in [300, 425, 550]:
        a(f'M 1220 {y} H 1300')
    for y in [335, 460, 585]:
        a(f'M 1310 {y} H 1265', True)
    p.append('<path d="M1265 335 V735" fill="none" stroke="#168577" stroke-width="3"/>')
    a('M 1265 735 H 1080 V 580', True)
    t(1110, 764, 'Cloud replies', 17, c='#168577')
    box(20, 855, 1560, 100, '#f8fafc', '#d7e0e9')
    a('M 40 881 H 86')
    t(100, 888, 'Code batches + prompt', 17)
    a('M 40 921 H 86', True)
    t(100, 928, 'Returned classifications', 17)
    t(410, 885, 'R validates cloud replies and accepts a category when at least 2 of 3 cloud models agree.', 18)
    t(410, 916, 'No majority → human decision. Local replies are retained for comparison, including invalid or missing answers.', 17)
    t(410, 941, 'Batch sizes: GPT / Claude 100 · Gemini / Qwen 25 · Llama 5. Requested output: code, category and reason.', 16)
    svg = '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1600" height="980" viewBox="0 0 1600 980"><defs>'
    for n, c in [('send', '#316bbb'), ('ret', '#168577')]:
        svg += f'<marker id="{n}" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0 0 L8 4 L0 8" fill="{c}"/></marker>'
    svg += '</defs><g font-family="DejaVu Sans, sans-serif">' + ''.join(p) + '</g></svg>'
    Path(__file__).resolve().parent.parent.joinpath('esrd-cause-classification-placeholder.svg').write_text(svg, encoding='utf-8')
if __name__ == '__main__':
    main()
