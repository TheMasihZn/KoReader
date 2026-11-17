#!/usr/bin/env python3
"""Builds one HTML report from doc/osItems.md and kos/VERSION.
People open it in a browser (colours, bars, a layer diagram). LLMs read the same file: real headings,
real tables, and the whole ledger again as JSON in <script id="ledger" type="application/json">.
Usage: make_report.py [output.html]"""
import html, json, os, re, sys, datetime

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "dist", "report.html")
version = open(os.path.join(ROOT, "kos/VERSION")).read().strip()
md = open(os.path.join(ROOT, "doc/osItems.md"), encoding="utf-8").read()

def klass(status):
    s = status.lower()
    if s.startswith("built"):
        return "builtOpen" if ("open" in s or "unconfirmed" in s or "not yet" in s or "device test" in s) else "built"
    if s.startswith("declared"): return "declared"
    return "open"

LABEL = {"built": "Built (tested here where it could be)", "builtOpen": "Built, not proven on the phone", "declared": "Declared in the documents", "open": "Open / question"}
COLOR = {"built": "#2e7d32", "builtOpen": "#f9a825", "declared": "#1565c0", "open": "#9e9e9e"}
FROM = {"you": "you asked", "me": "I added it", "?": "unclear, a question"}

items = []
for m in re.finditer(r"^\| (\d+) \| (.*?) \| (you|me|\?) \| (.*?) \|\s*$", md, re.M):
    n, title, src, status = m.groups()
    items.append({"id": int(n), "item": title.strip(), "from": src, "status": status.strip(), "class": klass(status)})

counts = {k: sum(1 for i in items if i["class"] == k) for k in LABEL}
total = len(items)
questions = re.findall(r"^\d+\. (.+(?:\n   .+)*)", md.split("## Questions")[-1], re.M) if "## Questions" in md else []

layers = [
    ("Apps", "Home chat, Settings, Canvas, Debugger, 3D viewer, Versions, Studio, Sheets, Icons", "built"),
    ("Shell (KOReader fork)", "windows, title bar, search, input layer, pipelines, registry", "builtOpen"),
    ("Bridge (laptop, Python)", "registry with permissions, files, audio, chat", "built"),
    ("OS layer (AOSP base, Lua engine, adbd, drivers, voice with tools)", "not started; declared in osEmbedding.md", "declared"),
]

def bar():
    w, x = 760, 0
    out = ['<svg viewBox="0 0 760 44" role="img" aria-label="Share of items by status" width="100%">']
    for k in LABEL:
        seg = w * counts[k] / total if total else 0
        out.append(f'<rect x="{x:.1f}" y="0" width="{seg:.1f}" height="44" fill="{COLOR[k]}"><title>{LABEL[k]}: {counts[k]}</title></rect>')
        if seg > 36: out.append(f'<text x="{x + seg/2:.1f}" y="28" text-anchor="middle" fill="#fff" font-size="16">{counts[k]}</text>')
        x += seg
    out.append("</svg>")
    return "".join(out)

def stack():
    out = ['<svg viewBox="0 0 760 300" role="img" aria-label="Layers of the OS, top to bottom" width="100%">']
    for i, (name, note, k) in enumerate(layers):
        y = i * 74
        out.append(f'<rect x="0" y="{y}" width="760" height="66" rx="8" fill="{COLOR[k]}" opacity="0.92"/>')
        out.append(f'<text x="16" y="{y+28}" fill="#fff" font-size="18" font-weight="700">{html.escape(name)}</text>')
        out.append(f'<text x="16" y="{y+52}" fill="#fff" font-size="14">{html.escape(note)}</text>')
    out.append("</svg>")
    return "".join(out)

rows = "\n".join(
    f'<tr class="{i["class"]}"><td>{i["id"]}</td><td>{html.escape(i["item"])}</td><td>{FROM[i["from"]]}</td>'
    f'<td><span class="dot" style="background:{COLOR[i["class"]]}"></span>{html.escape(i["status"])}</td></tr>'
    for i in items)

legend = "".join(f'<li><span class="dot" style="background:{COLOR[k]}"></span><b>{LABEL[k]}</b>: {counts[k]}</li>' for k in LABEL)
qs = "".join(f"<li>{html.escape(q)}</li>" for q in questions)
needs_device = [i for i in items if i["class"] == "builtOpen"]
nd = "".join(f'<li>#{i["id"]} {html.escape(i["item"])}</li>' for i in needs_device)

doc = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>KOReader OS {version} report</title>
<style>
body{{font:16px/1.55 system-ui,sans-serif;margin:0;background:#fafaf7;color:#1b1b1b}}
main{{max-width:880px;margin:auto;padding:20px}}
h1{{font-size:28px;margin:.2em 0}} h2{{margin-top:1.8em;border-bottom:2px solid #ddd;padding-bottom:4px}}
.card{{background:#fff;border:1px solid #e2e2dc;border-radius:12px;padding:14px 16px;margin:12px 0}}
.dot{{display:inline-block;width:12px;height:12px;border-radius:50%;margin-right:8px;vertical-align:-1px}}
table{{border-collapse:collapse;width:100%;font-size:14px;background:#fff}} th,td{{border-bottom:1px solid #e6e6e0;padding:6px 8px;text-align:left;vertical-align:top}}
th{{background:#f0efe8}} ul.legend{{list-style:none;padding:0}} ul.legend li{{margin:4px 0}}
.big{{font-size:40px;font-weight:700}} .row{{display:flex;gap:12px;flex-wrap:wrap}} .row .card{{flex:1;min-width:180px}}
@media (prefers-color-scheme:dark){{body{{background:#161616;color:#eee}}.card,table{{background:#1f1f1f;border-color:#333}}th{{background:#2a2a2a}}td,th{{border-color:#333}}}}
</style></head><body><main>
<h1>KOReader OS {version}: what is built and what is not</h1>
<p>Made {datetime.date.today().isoformat()} from the ledger <code>doc/osItems.md</code>. Colours: green is built (tested here where a test was possible, without a screen); yellow is built but not yet seen working on your phone; blue is written down only; grey is open or a question.</p>
<div class="row">
<div class="card"><div class="big">{total}</div>items in the ledger</div>
<div class="card"><div class="big" style="color:{COLOR['built']}">{counts['built']}</div>built</div>
<div class="card"><div class="big" style="color:{COLOR['builtOpen']}">{counts['builtOpen']}</div>need your phone to prove</div>
<div class="card"><div class="big" style="color:{COLOR['declared']}">{counts['declared']}</div>declared only</div>
</div>
<h2>Share by status</h2><div class="card">{bar()}<ul class="legend">{legend}</ul></div>
<h2>Layers</h2><div class="card">{stack()}<p>The app and shell layers are Lua inside the KOReader fork. The OS layer is a separate piece of work.</p></div>
<h2>Needs a test on your phone</h2><div class="card"><ul>{nd}</ul></div>
<h2>Open questions to you</h2><div class="card"><ol>{qs}</ol></div>
<h2>Whole ledger</h2>
<table><thead><tr><th>#</th><th>Item</th><th>From</th><th>Status</th></tr></thead><tbody>
{rows}
</tbody></table>
<h2>For an AI reading this</h2>
<div class="card"><p>This file is one page. The ledger above is the full list; the same data is in the JSON block below (fields: id, item, from, status, class). <code>class</code> is one of built, builtOpen, declared, open. Nothing here has run on the user's Galaxy Z Fold 5 unless the status says so. Naming rule: camelCase. Common library: nothing goes in without the owner's say-so.</p></div>
<script id="ledger" type="application/json">{json.dumps({"version": version, "counts": counts, "items": items}, ensure_ascii=False)}</script>
</main></body></html>"""
os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, "w", encoding="utf-8").write(doc)
print("wrote", OUT, len(doc), "bytes;", counts)
