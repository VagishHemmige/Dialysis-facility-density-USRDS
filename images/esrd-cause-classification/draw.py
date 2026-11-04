"""Render the ESRD cause-code classification diagram with Python standard libraries only.

Five models are each called separately through ellmer and each returns its own
dataset; R checks the three cloud datasets and takes a 2-of-3 vote, and compares
the two local ones. Every value shown is read from public files in the
repository (references/, including each local model's answers as returned, and R/setup.R), so the diagram follows the committed
mapping. See README.md for regeneration and provenance.
"""
from pathlib import Path
from html import escape
import base64
import csv
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
ASSET_DIR = HERE / 'assets'
OUTPUT = HERE.parent / 'esrd-cause-classification-placeholder.svg'

# Codes shown in every dataset card, with a short description for the code list.
# The highlighted code should be one on which the cloud models split.
EXAMPLES = [
    ('4464Z', 'Wegener’s syndrome'),
    ('I509', 'Heart failure'),
    ('2718Z', 'Oxalosis'),
]
HIGHLIGHT = '2718Z'

# Category names as the figure shows them (the full names are in R/setup.R).
SHORT_CATEGORY = {
    'Diabetes': 'Diabetes',
    'Hypertension and cardiac disease': 'Hypertension / cardiac',
    'Glomerulonephritis': 'Glomerulonephritis',
    'Hereditary or polycystic kidney disease': 'Hereditary / polycystic',
    'Transplant failure or complications': 'Transplant',
    'Other': 'Other',
}

# Model order, logo, label and the column names used in the public files.
CLOUD = [
    ('openai', 'openai', 'OpenAI · GPT'),
    ('anthropic', 'claude', 'Anthropic · Claude'),
    ('google', 'gemini', 'Google · Gemini'),
]
LOCAL = [
    ('ollama_qwen', 'qwen', 'Alibaba · Qwen'),
    ('ollama_llama', 'meta', 'Meta · Llama'),
]

INK = '#18334e'
MUTED = '#5b6b7d'
SEND = '#316bbb'
RETURN = '#168577'
FLAG = '#c0392b'
BEZEL = '#2b3e52'
PORT = '#d9e4ef'
BAND = '#fff1cc'

# Layout: one row per model, from the top of the first row.
ROW_TOP, ROW_STEP, ROW_H = 305, 132, 118
W, H = 1600, 1175
FOOTER_Y = 1060  # top of the legend box, below the monitor's stand

p = []


# ---- data -------------------------------------------------------------------

def read_csv(name):
    with open(ROOT / 'references' / name, newline='', encoding='utf-8') as f:
        return list(csv.DictReader(f))


def batch_sizes():
    """Batch size per model, from esrd_classifier_batch_sizes in R/setup.R."""
    setup = (ROOT / 'R' / 'setup.R').read_text(encoding='utf-8')
    block = re.search(r'esrd_classifier_batch_sizes\s*<-\s*list\((.*?)\)', setup, re.S)
    if block is None:
        raise SystemExit('esrd_classifier_batch_sizes not found in R/setup.R')
    return {k: int(v) for k, v in re.findall(r'(\w+)\s*=\s*(\d+)', block.group(1))}


def load():
    mapping = {r['code']: r for r in read_csv('esrd-cause-categories.csv')}
    missing = [c for c, _ in EXAMPLES if c not in mapping]
    if missing:
        raise SystemExit(f'Example codes not in the mapping: {missing}')
    row = mapping[HIGHLIGHT]
    if row['unanimous'] == 'TRUE':
        raise SystemExit(f'{HIGHLIGHT} is unanimous; choose a code the models split on')
    cloud_ids = [m.strip() for m in row['models'].split(';')]
    local = {r['provider']: r for r in read_csv('esrd-cause-local-models.csv')}
    for r in read_csv('esrd-cause-local-answers.csv'):
        local[r['provider']].setdefault('answers', []).append(r)
    agreement = read_csv('esrd-cause-agreement.csv')[0]
    return mapping, cloud_ids, local, agreement, batch_sizes()


def local_answer(answers, code):
    """What a local model returned for one code, as the figure shows it.

    Returns (text, ok): the shortened category when the code was answered exactly
    once; otherwise a note saying what went wrong, as the local-model report counts it.
    """
    exact = [a for a in answers if a['code'] == code]
    if len(exact) == 1:
        return SHORT_CATEGORY.get(exact[0]['category'], exact[0]['category']), True
    if len(exact) > 1:
        return f'answered {len(exact)} times', False
    loose = [a for a in answers if code in a['code']]
    if loose:
        return f'returned as {loose[0]["code"]}', False
    return 'no answer', False


# ---- drawing helpers --------------------------------------------------------

def box(x, y, w, h, fill='#fff', stroke='#c5d3e2', r=14, sw=2):
    p.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" '
             f'fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>')


def t(x, y, s, size=16, b=False, c=INK, anchor='start', mono=False, italic=False):
    family = ' font-family="DejaVu Sans Mono, monospace"' if mono else ''
    style = ' font-style="italic"' if italic else ''
    p.append(f'<text x="{x}" y="{y}" font-size="{size}" font-weight="{700 if b else 400}" '
             f'fill="{c}" text-anchor="{anchor}"{family}{style}>{escape(s)}</text>')


def arrow(d, ret=False):
    c = RETURN if ret else SEND
    p.append(f'<path d="{d}" fill="none" stroke="{c}" stroke-width="3" '
             f'marker-end="url(#{"ret" if ret else "send"})"/>')


def line(d, c=MUTED):
    p.append(f'<path d="{d}" fill="none" stroke="{c}" stroke-width="2.5"/>')


def logo(name, x, y, w=40, h=40):
    ext = 'png' if name == 'ellmer' else 'svg'
    raw = (ASSET_DIR / f'{name}.{ext}').read_bytes()
    mime = 'image/png' if ext == 'png' else 'image/svg+xml'
    p.append(f'<image x="{x}" y="{y}" width="{w}" height="{h}" '
             f'href="data:{mime};base64,{base64.b64encode(raw).decode()}"/>')


def row_top(i):
    return ROW_TOP + i * ROW_STEP


def row_mid(i):
    return row_top(i) + ROW_H // 2


# ---- parts of the figure ----------------------------------------------------

def inputs(mapping):
    box(20, 170, 262, 205, '#fff8e4', '#e3d5af')
    t(38, 204, 'Public code list', 21, True)
    t(38, 230, f'{len(mapping)} USRDS cause codes', 15)
    for i, (code, desc) in enumerate(EXAMPLES):
        t(38, 262 + i * 26, code, 14, mono=True)
        t(108, 262 + i * 26, desc, 14)
    t(38, 356, 'No patient data', 15, True)

    box(20, 395, 262, 245, '#fff8e4', '#e3d5af')
    t(38, 429, 'Shared prompt', 21, True)
    t(38, 455, 'The same for every model:', 15)
    for i, name in enumerate(SHORT_CATEGORY.values()):
        t(48, 484 + i * 22, f'· {name}', 14)
    t(38, 626, 'one category + reason per code', 13, c=MUTED)

    arrow('M 282 240 H 336')
    arrow('M 282 470 H 290 V 270 H 336')


def frames():
    # The analyst's computer, drawn as a monitor: bezel, screen, camera, stand and base.
    box(298, 108, 979, 884, BEZEL, BEZEL, 22)
    box(310, 120, 955, 860, '#f1f6fc', '#f1f6fc', 8)
    p.append(f'<circle cx="787" cy="114" r="3" fill="{MUTED}"/>')
    p.append(f'<path d="M 742 992 L 832 992 L 852 1032 L 722 1032 Z" fill="{BEZEL}"/>')
    box(652, 1030, 270, 14, BEZEL, BEZEL, 7)
    # Openings in the bezel where arrows leave or enter the computer, so they
    # pass through the frame rather than across it.
    for x, y, h in [(298, 226, 58), (1265, 336, 316)]:
        box(x, y, 12, h, PORT, PORT, 3, 0)
    t(1135, 333, 'over the internet', 12, c=MUTED, anchor='middle')
    t(335, 157, 'ANALYST’S COMPUTER', 22, True)
    box(325, 170, 560, 795, '#fff', '#9db9d5')
    logo('r', 340, 178, 44, 34)
    t(394, 205, 'R session', 22, True)
    box(1290, 265, 295, 434, '#eef8f3', '#a2cdb9')
    t(1306, 292, 'CLOUD · THESE THREE VOTE', 16, True)
    box(1060, 661, 192, 300, '#f2edfa', '#c4b3dc')
    logo('ollama', 1072, 668, 22, 27)
    t(1100, 688, 'OLLAMA · NO VOTE', 13, True)


def batch_and_ellmer():
    box(340, 225, 525, 60, '#fff8e4', '#dcc88e', 8)
    t(356, 251, 'Batch of codes and descriptions', 16, True)
    t(356, 273, 'with the shared prompt, sent to each model in turn', 14)
    arrow('M 865 255 H 896')

    box(900, 225, 105, 740, '#fff8e4', '#dbc483', 14)
    # Logo, name and note centred vertically in the column (225 to 965).
    logo('ellmer', 911, 510, 83, 92)
    t(952, 625, 'ellmer', 21, True, anchor='middle')
    for i, s in enumerate(['one call', 'per model', 'per batch']):
        t(952, 650 + i * 19, s, 13, c=MUTED, anchor='middle')


def model_box(i, x, w, name, label, model_id, batch):
    top = row_top(i) + 14
    box(x, top, w, 90)
    logo(name, x + 12, top + 25, 40, 40)
    t(x + 62, top + 32, label, 16, True)
    t(x + 62, top + 56, model_id, 13, mono=True)
    t(x + 62, top + 77, f'batches of {batch}', 13, c=MUTED)


def calls(cloud_ids, local, sizes):
    for i, ((key, name, label), model_id) in enumerate(zip(CLOUD, cloud_ids)):
        model_box(i, 1306, 266, name, label, model_id, sizes[key])
        arrow(f'M 1005 {row_mid(i) - 12} H 1302')
        arrow(f'M 1306 {row_mid(i) + 12} H 1009', ret=True)
    for j, (key, name, label) in enumerate(LOCAL):
        i = len(CLOUD) + j
        model_box(i, 1072, 168, name, label.split(' · ')[1], local[key]['model'], sizes[key])
        arrow(f'M 1005 {row_mid(i) - 12} H 1068')
        arrow(f'M 1072 {row_mid(i) + 12} H 1009', ret=True)
    # Each reply continues on the same line from ellmer into its model's dataset.
    for i in range(len(CLOUD) + len(LOCAL)):
        arrow(f'M 900 {row_mid(i) + 12} H 869', ret=True)


def cloud_card(i, key, label, mapping):
    x, top, w = 600, row_top(i), 265
    box(x, top, w, ROW_H, '#fff', '#a0cebf', 10)
    t(x + 14, top + 24, f'{label} dataset', 15, True)
    t(x + 14, top + 45, 'Code', 12, True, MUTED)
    t(x + 82, top + 45, 'Category', 12, True, MUTED)
    for k, (code, _) in enumerate(EXAMPLES):
        y = top + 67 + k * 20
        row = mapping[code]
        category = row[f'category_{key}']
        dissent = category != row['final_category']
        if code == HIGHLIGHT:
            box(x + 6, y - 15, w - 12, 21, BAND, FLAG if dissent else BAND, 4, 1.6 if dissent else 0)
        t(x + 14, y, code, 13, code == HIGHLIGHT, mono=True)
        t(x + 82, y, SHORT_CATEGORY[category], 13, dissent, FLAG if dissent else INK)


def local_card(i, label, r):
    x, top, w = 600, row_top(i), 265
    box(x, top, w, ROW_H, '#fff', '#c4b3dc', 10)
    t(x + 14, top + 24, f'{label} dataset', 15, True)
    t(x + 14, top + 45, 'Code', 12, True, MUTED)
    t(x + 82, top + 45, 'Category', 12, True, MUTED)
    for k, (code, _) in enumerate(EXAMPLES):
        y = top + 67 + k * 20
        if code == HIGHLIGHT:
            box(x + 6, y - 15, w - 12, 21, BAND, BAND, 4, 0)
        text, ok = local_answer(r['answers'], code)
        t(x + 14, y, code, 13, code == HIGHLIGHT, mono=True)
        t(x + 82, y, text, 13, c=INK if ok else MUTED, italic=not ok)


def datasets(mapping, local):
    for i, (key, _, label) in enumerate(CLOUD):
        cloud_card(i, key, label.split(' · ')[1], mapping)
    for j, (key, _, label) in enumerate(LOCAL):
        local_card(len(CLOUD) + j, label.split(' · ')[1], local[key])


def vote_and_comparison(mapping, agreement, local):
    # The three cloud datasets join into the vote.
    for i in range(3):
        line(f'M 600 {row_mid(i)} H 585')
    line(f'M 585 {row_mid(0)} V {row_mid(2)}')
    p.append(f'<path d="M 585 405 H 574" fill="none" stroke="{MUTED}" '
             f'stroke-width="2.5" marker-end="url(#flow)"/>')

    box(340, 330, 230, 150, '#eef8f4', '#a0cebf', 10)
    t(355, 358, 'Check, then vote', 17, True)
    for k, s in enumerate(['Each code answered once,', 'only the six names.',
                           '2 of 3 cloud models', 'must agree; otherwise',
                           'the deciders choose.']):
        t(355, 382 + k * 19, s, 13)
    p.append(f'<path d="M 455 480 V 506" fill="none" stroke="{MUTED}" '
             f'stroke-width="2.5" marker-end="url(#flow)"/>')

    row = mapping[HIGHLIGHT]
    box(340, 512, 230, 168, '#fff', INK, 10)
    t(355, 540, 'Mapping file', 17, True)
    t(355, 560, 'esrd-cause-categories.csv', 11, c=MUTED, mono=True)
    for k, (n, s) in enumerate([(agreement['unanimous'], 'unanimous'),
                                (agreement['majority_only'], 'by 2 of 3'),
                                (agreement['no_majority'], 'for review')]):
        t(395, 586 + k * 20, n, 15, True, anchor='end')
        t(403, 586 + k * 20, s, 13)
    box(348, 642, 214, 26, BAND, BAND, 4, 0)
    t(356, 660, HIGHLIGHT, 13, True, mono=True)
    t(410, 660, f'→ {SHORT_CATEGORY[row["final_category"]]} ({row["agreement"].replace(" models", "")})', 13)

    # The two local datasets join into the comparison.
    for i in (3, 4):
        line(f'M 600 {row_mid(i)} H 585')
    line(f'M 585 {row_mid(3)} V {row_mid(4)}')
    mid = (row_mid(3) + row_mid(4)) // 2
    p.append(f'<path d="M 585 {mid} H 574" fill="none" stroke="{MUTED}" '
             f'stroke-width="2.5" marker-end="url(#flow)"/>')
    box(340, mid - 75, 230, 150, '#f2edfa', '#c4b3dc', 10)
    t(355, mid - 47, 'Local-model report', 17, True)
    for k, s in enumerate(['Compared with the', 'accepted category;', 'they do not vote.']):
        t(355, mid - 24 + k * 18, s, 13)
    for k, (key, _, label) in enumerate(LOCAL):
        r = local[key]
        t(355, mid + 34 + k * 20,
          f'{label.split(" · ")[1]}: {r["agrees_with_accepted"]} of {r["codes_answered"]} match', 13, True)
    p.append(f'<path d="M 455 680 V {mid - 82}" fill="none" stroke="{MUTED}" '
             f'stroke-width="2" stroke-dasharray="5 4" marker-end="url(#flow)"/>')


def footer(sizes):
    box(20, FOOTER_Y, 1560, 100, '#f8fafc', '#d7e0e9')
    arrow(f'M 40 {FOOTER_Y + 29} H 86')
    t(100, FOOTER_Y + 35, 'Request: codes + prompt', 15)
    arrow(f'M 40 {FOOTER_Y + 67} H 86', ret=True)
    t(100, FOOTER_Y + 73, 'Reply, as a dataset', 15)
    box(330, FOOTER_Y + 17, 40, 22, BAND, FLAG, 4, 1.6)
    t(380, FOOTER_Y + 34, 'A code the cloud models split on; the outvoted answer in red', 15)
    t(330, FOOTER_Y + 73, 'Three of the 445 codes shown; category names shortened. In grey: no valid answer '
      '(the code was not answered, or was returned in a form that does not match it).', 13, c=MUTED)
    t(330, FOOTER_Y + 92, 'Values are read from the esrd-cause-*.csv files in references/ '
      '(including each local model’s answers, as returned) and from R/setup.R.', 13, c=MUTED)


def main():
    mapping, cloud_ids, local, agreement, sizes = load()
    box(0, 0, W, H, '#fff', '#fff', 0)
    t(40, 55, 'Classifying cause codes with R and ellmer', 34, True)
    t(40, 90, 'Five models are called separately and return five datasets; '
      'R checks the three cloud datasets and takes a 2-of-3 vote.', 19)
    frames()
    inputs(mapping)
    batch_and_ellmer()
    calls(cloud_ids, local, sizes)
    datasets(mapping, local)
    vote_and_comparison(mapping, agreement, local)
    footer(sizes)

    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
           f'width="{W}" height="{H}" viewBox="0 0 {W} {H}"><defs>')
    for n, c in [('send', SEND), ('ret', RETURN), ('flow', MUTED)]:
        svg += (f'<marker id="{n}" markerWidth="8" markerHeight="8" refX="7" refY="4" '
                f'orient="auto"><path d="M0 0 L8 4 L0 8" fill="{c}"/></marker>')
    svg += '</defs><g font-family="DejaVu Sans, sans-serif">' + ''.join(p) + '</g></svg>'
    OUTPUT.write_text(svg, encoding='utf-8')


if __name__ == '__main__':
    main()
