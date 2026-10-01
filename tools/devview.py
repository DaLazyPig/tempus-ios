#!/usr/bin/env python3
"""Live view of the booted simulator in a browser, plus the launch seams as buttons.

    python3 tools/devview.py            # http://localhost:8765
    python3 tools/devview.py --port 9000 --fps 3

The simulator only exists on this Mac, so this serves its frames instead: one JPEG per
request, an <img> that re-requests on a timer, and a row of buttons that relaunch the app
through the same `-tempusPhase` seams CLAUDE.md documents.

To reach it from somewhere else, put a tunnel in front of it — `cloudflared tunnel --url
http://localhost:8765` or `ngrok http 8765`. Nothing here is authenticated, so only do that
for as long as you need it.

Frames only: a simulator takes no synthetic touches, which is why the seams are buttons.
"""
import argparse
import html
import json
import shutil
import subprocess
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

BUNDLE = "com.dalazypig.tempus"

# Allowlisted, because this handler can end up behind a tunnel. A request names a preset;
# it never supplies argv. Anything not in here is a 400.
PRESETS = {
    "home":       ["-tempusPhase", "home"],
    "preflight":  ["-tempusPhase", "preflight"],
    "pass":       ["-tempusPhase", "pass"],
    "flying":     ["-tempusPhase", "flying", "-tempusMinutes", "5"],
    "landed":     ["-tempusPhase", "landed", "-tempusMinutes", "30"],
    "diverted":   ["-tempusPhase", "diverted"],
    "exited":     ["-tempusPhase", "exited"],
    "tierup":     ["-tempusPhase", "tierup"],
    "redeem":     ["-tempusPhase", "redeem"],
    "passes":     ["-tempusPhase", "passes", "-tempusPasses", "14"],
    "status":     ["-tempusPhase", "status", "-tempusTier", "2"],
    "log":        ["-tempusPhase", "log", "-tempusPlus"],
    "blocking":   ["-tempusPhase", "blocking"],
    "settings":   ["-tempusPhase", "settings"],
    "gate":       ["-tempusPhase", "preflight", "-tempusPlus", "-tempusGate"],
    "biz":        ["-tempusPhase", "flying", "-tempusMinutes", "1", "-tempusBiz"],
    "interrupted": ["-tempusPhase", "flying", "-tempusInterrupted"],
    "dev":        ["-tempusPhase", "home", "-tempusDev"],
}
PRESETS.update({f"ob{i}": ["-tempusStep", str(i)] for i in range(9)})

GROUPS = [
    ("Flight", ["home", "preflight", "pass", "flying", "landed", "diverted", "exited", "tierup"]),
    ("Screens", ["redeem", "passes", "status", "log", "blocking", "settings", "gate"]),
    ("Guarded", ["biz", "interrupted", "dev"]),
    ("Onboarding", [f"ob{i}" for i in range(9)]),
]

PAGE = """<!doctype html><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>Tempus — live</title>
<style>
:root{color-scheme:light dark;--bg:#f2f5fa;--ink:#23395b;--mut:#5d7496;--card:#fff;--line:#d0dbeb}
@media (prefers-color-scheme:dark){:root{--bg:#101d31;--ink:#f2f5fa;--mut:#9fb3d1;--card:#182a45;--line:#33507c}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);
 font:400 15px/1.5 ui-sans-serif,-apple-system,system-ui,sans-serif;
 display:flex;gap:28px;padding:20px;align-items:flex-start;flex-wrap:wrap}
#shot{width:min(360px,92vw);border-radius:30px;display:block;background:var(--card);
 box-shadow:0 24px 60px -24px rgba(16,29,49,.5)}
aside{flex:1;min-width:260px;max-width:520px}
h1{font-size:20px;letter-spacing:-.02em;margin:0 0 4px}
p.sub{margin:0 0 18px;color:var(--mut);font-size:13px}
h2{font-size:10px;letter-spacing:.16em;text-transform:uppercase;color:var(--mut);
 margin:20px 0 8px;font-weight:600}
.row{display:flex;flex-wrap:wrap;gap:6px}
button{height:34px;padding:0 13px;border-radius:999px;border:1px solid var(--line);
 background:var(--card);color:var(--ink);font:600 13px/1 inherit;cursor:pointer}
button:hover{border-color:var(--ink)}
button.on{background:#b86f52;border-color:#b86f52;color:#fff}
#status{margin-top:18px;font-size:12px;color:var(--mut);min-height:1.4em}
</style>
<img id=shot alt="booted simulator">
<aside>
<h1>Tempus — live</h1>
<p class=sub>Frames from the booted simulator, __FPS__&times; a second. Buttons relaunch the app
through its own test seams; the simulator takes no touches, so this is look-don't-poke.</p>
__GROUPS__
<div id=status></div>
</aside>
<script>
const img=document.getElementById('shot'),st=document.getElementById('status');
let miss=0;
function frame(){
  const u='/frame.jpg?t='+Date.now();
  const n=new Image();
  n.onload=()=>{img.src=u;miss=0;};
  n.onerror=()=>{miss++;if(miss>2)st.textContent='No booted simulator. Start one and it reappears.';};
  n.src=u;
}
setInterval(frame,Math.round(1000/__FPS__));frame();
document.querySelectorAll('button[data-p]').forEach(b=>b.onclick=async()=>{
  document.querySelectorAll('button[data-p]').forEach(x=>x.classList.remove('on'));
  b.classList.add('on');
  st.textContent='launching '+b.dataset.p+'\\u2026';
  const r=await fetch('/launch?preset='+encodeURIComponent(b.dataset.p),{method:'POST'});
  st.textContent=(await r.json()).message;
});
</script>
"""


def simctl(args, **kw):
    return subprocess.run(["xcrun", "simctl", *args], capture_output=True, text=True, **kw)


class Handler(BaseHTTPRequestHandler):
    fps = 2

    def log_message(self, *_):
        pass

    def _send(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/":
            groups = "\n".join(
                f"<h2>{html.escape(name)}</h2><div class=row>"
                + "".join(f'<button data-p="{k}">{html.escape(k)}</button>' for k in keys)
                + "</div>"
                for name, keys in GROUPS
            )
            page = PAGE.replace("__GROUPS__", groups).replace("__FPS__", str(self.fps))
            self._send(200, page.encode(), "text/html; charset=utf-8")
        elif path == "/frame.jpg":
            with tempfile.TemporaryDirectory() as d:
                out = Path(d) / "f.jpg"
                r = simctl(["io", "booted", "screenshot", "--type", "jpeg", str(out)])
                if r.returncode != 0 or not out.exists():
                    self._send(503, b"no booted simulator", "text/plain")
                    return
                self._send(200, out.read_bytes(), "image/jpeg")
        else:
            self._send(404, b"", "text/plain")

    def do_POST(self):
        u = urlparse(self.path)
        if u.path != "/launch":
            self._send(404, b"", "text/plain")
            return
        preset = (parse_qs(u.query).get("preset") or [""])[0]
        args = PRESETS.get(preset)
        if args is None:
            self._send(400, json.dumps({"message": f"unknown preset {preset!r}"}).encode(),
                       "application/json")
            return
        simctl(["terminate", "booted", BUNDLE])
        r = simctl(["launch", "booted", BUNDLE, *args])
        ok = r.returncode == 0
        self._send(200 if ok else 500,
                   json.dumps({"message": preset if ok else (r.stderr.strip() or "launch failed")}).encode(),
                   "application/json")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--fps", type=float, default=2)
    ap.add_argument("--host", default="0.0.0.0")
    a = ap.parse_args()
    if not shutil.which("xcrun"):
        raise SystemExit("xcrun not found — this needs Xcode's command line tools.")
    Handler.fps = a.fps
    print(f"Tempus live view → http://localhost:{a.port}   ({a.fps}fps)")
    print("Tunnel it with:  cloudflared tunnel --url http://localhost:%d" % a.port)
    ThreadingHTTPServer((a.host, a.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
