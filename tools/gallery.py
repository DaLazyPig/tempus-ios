#!/usr/bin/env python3
"""Shoot every screen off the booted simulator and build a single self-contained page.

    python3 tools/gallery.py                 # → build/screens.html
    python3 tools/gallery.py --only ob0,home

The page embeds its own fonts and every frame as a data URI, so it works from anywhere with
no server and no network — which is the point: the simulator only exists on this Mac.

Each screen is launched through the seams CLAUDE.md documents, so the board doubles as the
reference for reaching any of them by hand.
"""
import argparse
import base64
import io
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUNDLE = "com.dalazypig.tempus"
SETTLE = 2.8  # the splash runs to ~1.4s and every screen plays an entrance after it

# code, title, note, launch args. Order is the order they appear on the board.
SCREENS = [
    ("ob0", "Boarding pass", "Onboarding", ["-tempusStep", "0"]),
    ("ob1", "Flying earns miles", "Onboarding", ["-tempusStep", "1"]),
    ("ob2", "Miles buy screen time", "Onboarding", ["-tempusStep", "2"]),
    ("ob3", "What costs miles", "Onboarding", ["-tempusStep", "3"]),
    ("ob4", "Home airport", "Onboarding", ["-tempusStep", "4"]),
    ("ob5", "Permissions", "Onboarding", ["-tempusStep", "5"]),
    ("ob6", "Account", "Onboarding", ["-tempusStep", "6"]),
    ("ob7", "Status Club", "Onboarding", ["-tempusStep", "7"]),
    ("ob8", "Business Class", "Onboarding", ["-tempusStep", "8"]),
    ("home", "The deck", "Flight", ["-tempusPhase", "home"]),
    ("preflight", "Preflight", "Flight", ["-tempusPhase", "preflight"]),
    ("gate", "Consent gate", "Flight", ["-tempusPhase", "preflight", "-tempusPlus", "-tempusGate"]),
    ("pass", "Boarding pass", "Flight", ["-tempusPhase", "pass"]),
    ("flying", "In flight", "Flight", ["-tempusPhase", "flying", "-tempusMinutes", "30"]),
    ("landed", "Landed", "Flight", ["-tempusPhase", "landed", "-tempusMinutes", "30"]),
    ("diverted", "Diverted", "Flight", ["-tempusPhase", "diverted"]),
    ("exited", "Emergency exit", "Flight", ["-tempusPhase", "exited"]),
    ("tierup", "Status earned", "Flight", ["-tempusPhase", "tierup"]),
    ("redeem", "Redeem", "Screens", ["-tempusPhase", "redeem"]),
    ("passes", "Passes", "Screens", ["-tempusPhase", "passes", "-tempusPasses", "14"]),
    ("status", "Status Club", "Screens", ["-tempusPhase", "status", "-tempusTier", "2"]),
    ("log", "Flight log", "Screens", ["-tempusPhase", "log", "-tempusPlus"]),
    ("blocking", "Blocking", "Screens", ["-tempusPhase", "blocking"]),
    ("settings", "Settings", "Screens", ["-tempusPhase", "settings"]),
    ("dev", "Dev tools", "Screens", ["-tempusPhase", "home", "-tempusDev"]),
]

FONTS = [
    ("Outfit", 400, "Outfit-Regular.ttf"),
    ("Outfit", 600, "Outfit-SemiBold.ttf"),
    ("Outfit", 700, "Outfit-Bold.ttf"),
    ("DM Mono", 500, "DMMono-Medium.ttf"),
]


def simctl(args):
    return subprocess.run(["xcrun", "simctl", *args], capture_output=True, text=True)


def shoot(args, out: Path, width: int, quality: int) -> str:
    """Launch the app on `args`, wait for it to settle, return a JPEG data URI."""
    import time
    from PIL import Image

    simctl(["terminate", "booted", BUNDLE])
    simctl(["launch", "booted", BUNDLE, *args])
    time.sleep(SETTLE)
    simctl(["io", "booted", "screenshot", str(out)])
    im = Image.open(out).convert("RGB")
    im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=quality, optimize=True, progressive=True)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()


def font_face(family, weight, filename) -> str:
    data = base64.b64encode((ROOT / "Tempus" / "Fonts" / filename).read_bytes()).decode()
    return (f"@font-face{{font-family:'{family}';font-weight:{weight};font-style:normal;"
            f"font-display:block;src:url(data:font/ttf;base64,{data}) format('truetype')}}")


def build(shots, out_path: Path, stamp: str):
    faces = "".join(font_face(*f) for f in FONTS)
    payload = json.dumps(shots, separators=(",", ":"))
    html = TEMPLATE.replace("/*FACES*/", faces).replace("/*DATA*/", payload).replace("__STAMP__", stamp)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(html, encoding="utf-8")
    return out_path


TEMPLATE = r"""<title>Tempus — screens</title>
<style>
/*FACES*/

/* Tempus's own tokens (Tempus/Theme/Colors.swift). Light is the bare :root, so the
   un-stamped "system" state resolves before any media query runs. */
:root{
  --ground:#f2f5fa; --card:#ffffff; --sunken:#e4ebf5;
  --ink:#23395b; --ink-2:#5d7496; --ink-3:#8ea2bf;
  --rule:#d0dbeb; --rule-soft:#e2e9f3;
  --accent:#b86f52; --accent-soft:#f5e6df;
  --shadow:rgba(16,29,49,.20);
}
@media (prefers-color-scheme:dark){
  :root:not([data-theme="light"]){
    --ground:#101d31; --card:#182a45; --sunken:#23395b;
    --ink:#f2f5fa; --ink-2:#9fb3d1; --ink-3:#7389aa;
    --rule:#33507c; --rule-soft:#23395b;
    --accent:#cb8a71; --accent-soft:#2f4b76;
    --shadow:rgba(0,0,0,.55);
  }
}
:root[data-theme="dark"]{
  --ground:#101d31; --card:#182a45; --sunken:#23395b;
  --ink:#f2f5fa; --ink-2:#9fb3d1; --ink-3:#7389aa;
  --rule:#33507c; --rule-soft:#23395b;
  --accent:#cb8a71; --accent-soft:#2f4b76;
  --shadow:rgba(0,0,0,.55);
}

*{box-sizing:border-box}
body{
  margin:0; background:var(--ground); color:var(--ink);
  font:400 16px/1.5 'Outfit',ui-sans-serif,system-ui,sans-serif;
  -webkit-font-smoothing:antialiased;
}
.lbl{
  font:500 11px/1 'DM Mono',ui-monospace,monospace;
  letter-spacing:.16em; text-transform:uppercase; color:var(--ink-3);
}

.wrap{max-width:1240px; margin:0 auto; padding:34px 24px 64px;
  display:grid; grid-template-columns:minmax(280px,360px) 1fr; gap:44px; align-items:start}

header{grid-column:1/-1; display:flex; align-items:baseline; justify-content:space-between;
  gap:20px; flex-wrap:wrap; padding-bottom:20px; border-bottom:1px solid var(--rule)}
h1{margin:0; font:700 38px/1 'Outfit',sans-serif; letter-spacing:-.045em; text-wrap:balance}
header p{margin:8px 0 0; color:var(--ink-2); font-size:15px; max-width:56ch}

/* The index reads as a departures board: mono codes, ruled rows, the seam in the last
   column so the page is also the reference for reaching a screen by hand. */
nav{position:sticky; top:24px}
nav h2{margin:22px 0 6px; padding-bottom:6px; border-bottom:1px solid var(--rule-soft)}
nav h2:first-child{margin-top:0}
.rows{display:flex; flex-direction:column}
.row{display:grid; grid-template-columns:74px 1fr; gap:12px; align-items:baseline;
  width:100%; text-align:left; padding:11px 10px; border:0; border-radius:10px;
  background:transparent; color:inherit; cursor:pointer; font:inherit;
  border-bottom:1px solid var(--rule-soft)}
.row:hover{background:var(--sunken)}
.row[aria-current="true"]{background:var(--accent-soft)}
.row[aria-current="true"] .code{color:var(--accent)}
.row:focus-visible{outline:2px solid var(--accent); outline-offset:2px}
.code{font:500 12px/1.35 'DM Mono',ui-monospace,monospace; letter-spacing:.08em;
  color:var(--ink-3); font-variant-numeric:tabular-nums}
.name{font:600 15px/1.3 'Outfit',sans-serif; letter-spacing:-.01em}

main{display:flex; flex-direction:column; align-items:center; gap:18px}
.frame{width:100%; max-width:392px; border-radius:34px; overflow:hidden;
  background:var(--card); box-shadow:0 26px 60px -26px var(--shadow);
  border:1px solid var(--rule-soft)}
.frame img{display:block; width:100%; height:auto}
.meta{width:100%; max-width:392px; display:flex; flex-direction:column; gap:8px}
.meta h3{margin:0; font:600 21px/1.2 'Outfit',sans-serif; letter-spacing:-.02em}
.seam{overflow-x:auto; padding:11px 13px; border-radius:12px; background:var(--card);
  border:1px solid var(--rule-soft);
  font:500 12px/1.5 'DM Mono',ui-monospace,monospace; color:var(--ink-2); white-space:pre}
.pager{display:flex; gap:8px; align-items:center; color:var(--ink-3); font-size:13px}
.pager button{height:34px; min-width:38px; padding:0 12px; border-radius:999px;
  border:1px solid var(--rule); background:var(--card); color:var(--ink);
  font:600 13px/1 'Outfit',sans-serif; cursor:pointer}
.pager button:hover{border-color:var(--accent); color:var(--accent)}
.pager button:focus-visible{outline:2px solid var(--accent); outline-offset:2px}

@media (max-width:900px){
  .wrap{grid-template-columns:1fr; gap:28px}
  nav{position:static; order:2}
  main{order:1}
}
@media (prefers-reduced-motion:no-preference){
  .frame img{transition:opacity .18s ease}
}
</style>

<div class="wrap">
  <header>
    <div>
      <h1>Tempus — screens</h1>
      <p>Every screen off the booted simulator, shot through the launch seams. The command
         under each frame is how to reach it by hand.</p>
    </div>
    <span class="lbl">__STAMP__</span>
  </header>

  <nav id="board"></nav>

  <main>
    <div class="frame"><img id="shot" alt=""></div>
    <div class="meta">
      <h3 id="title"></h3>
      <div class="seam" id="seam"></div>
      <div class="pager">
        <button id="prev" aria-label="Previous screen">&larr;</button>
        <button id="next" aria-label="Next screen">&rarr;</button>
        <span id="count"></span>
      </div>
    </div>
  </main>
</div>

<script>
const SHOTS = /*DATA*/;
const board = document.getElementById('board');
const shot = document.getElementById('shot'), title = document.getElementById('title');
const seam = document.getElementById('seam'), count = document.getElementById('count');
let at = 0;

let group = null;
SHOTS.forEach((s, i) => {
  if (s.group !== group) {
    group = s.group;
    const h = document.createElement('h2');
    h.className = 'lbl'; h.textContent = group;
    board.append(h);
    const rows = document.createElement('div');
    rows.className = 'rows'; rows.dataset.group = group;
    board.append(rows);
  }
  const b = document.createElement('button');
  b.className = 'row'; b.type = 'button'; b.dataset.i = i;
  b.innerHTML = '<span class="code"></span><span class="name"></span>';
  b.querySelector('.code').textContent = s.code;
  b.querySelector('.name').textContent = s.title;
  b.onclick = () => show(i);
  board.lastElementChild.append(b);
});

function show(i) {
  at = (i + SHOTS.length) % SHOTS.length;
  const s = SHOTS[at];
  shot.src = s.src;
  shot.alt = s.group + ' — ' + s.title;
  title.textContent = s.title;
  seam.textContent = s.cmd;
  count.textContent = (at + 1) + ' of ' + SHOTS.length;
  document.querySelectorAll('.row').forEach(r =>
    r.setAttribute('aria-current', String(Number(r.dataset.i) === at)));
  document.querySelector('.row[aria-current="true"]')
    ?.scrollIntoView({block: 'nearest'});
}

document.getElementById('prev').onclick = () => show(at - 1);
document.getElementById('next').onclick = () => show(at + 1);
addEventListener('keydown', e => {
  if (e.key === 'ArrowLeft') show(at - 1);
  if (e.key === 'ArrowRight') show(at + 1);
});
show(0);
</script>
"""


def main():
    import datetime

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", default=str(ROOT / "build" / "screens.html"))
    ap.add_argument("--width", type=int, default=620)
    ap.add_argument("--quality", type=int, default=78)
    ap.add_argument("--only", help="comma-separated screen codes")
    a = ap.parse_args()

    wanted = set(a.only.split(",")) if a.only else None
    picked = [s for s in SCREENS if wanted is None or s[0] in wanted]

    shots = []
    with tempfile.TemporaryDirectory() as d:
        for code, title, group, args in picked:
            print(f"  {code}", flush=True)
            src = shoot(args, Path(d) / f"{code}.png", a.width, a.quality)
            shots.append({"code": code, "title": title, "group": group, "src": src,
                          "cmd": f"xcrun simctl launch booted {BUNDLE} " + " ".join(args)})

    stamp = datetime.datetime.now().strftime("%d %b %Y · %H:%M")
    out = build(shots, Path(a.out), stamp)
    print(f"{out}  ({out.stat().st_size / 1e6:.1f} MB, {len(shots)} screens)")


if __name__ == "__main__":
    main()
