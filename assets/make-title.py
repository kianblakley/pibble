#!/usr/bin/env python3
"""Regenerates assets/title.svg - the animated banner at the top of README.md.

The banner is one run of the launcher's own text scramble, baked into an SVG:
characters resolve left to right and everything that hasn't landed yet stands
in as a random glyph, rerolled every 45ms, over a 575ms span. Everything below
the SVG section is a straight port of services/Anim.qml, so the picks are the
same ones the shell draws rather than a lookalike - change the effect there and
re-run this to bring the banner back in step.

Glyphs are emitted as outlines rather than as text, so the banner needs no font
installed on the machine viewing it. Needs fontTools and a JetBrains Mono TTF:

    python3 assets/make-title.py [--font PATH] [--seed N] [-o assets/title.svg]
"""
import argparse
import subprocess
import sys

# ---------------------------------------------------------------- Anim.qml

SPAN = 575          # Anim.scrambleSpan - how long any label spends resolving
HOLD = 45           # Anim.scrambleHold - how long one noise glyph holds
TICK = 32           # Anim's scrambleClock interval, i.e. how often it repaints

CORE = "~=+*#%?!^"  # Anim.scrambleCore
# Anim.scrambleCandidates, less its last line (the outsized shapes): those are
# the ones a browser is liable to give emoji presentation, which no amount of
# measuring here would catch.
CANDIDATES = ("■□▪▫◆◇◈●○◉▲▼◀▶"
              "¤£°±×÷¬•~=+*#%?!^"
              "░▒▓█▌▐▄▀"
              "▣▤▥▦▧▨▩◧◨◩◪"
              "◐◑◒◓◢◣◤◥"
              "¶§@µ$¢/\\|†‡◊")

M32 = 0xffffffff

def imul(a, b):
    return (a * b) & M32

def scramble_hash(seed, i, frame):
    h = imul(seed ^ 0x9e3779b9, 0x85ebca6b)
    h = imul(h ^ i, 0xc2b2ae35)
    h = imul(h ^ frame, 0x27d4eb2f)
    return (h ^ (h >> 15)) & 0x3fffffff

def scramble_index(h, n, ban_a, ban_b):
    lo, hi = min(ban_a, ban_b), max(ban_a, ban_b)
    first = lo if lo >= 0 else hi
    second = hi if (lo >= 0 and hi > lo) else -1
    idx = h % (n - (1 if first >= 0 else 0) - (1 if second >= 0 else 0))
    if first >= 0 and idx >= first:
        idx += 1
    if second >= 0 and idx >= second:
        idx += 1
    return idx

def scramble_glyph(alphabet, seed, i, frame, avoid):
    idx = -1
    for f in range(frame + 1):
        idx = scramble_index(scramble_hash(seed, i, f), len(alphabet),
                             idx, avoid if f == frame else -1)
    return alphabet[idx]

def scrambled(alphabet, source, elapsed, seed):
    n = len(source)
    if n == 0 or elapsed >= SPAN:
        return source
    frame = max(0, elapsed) // HOLD
    out = ""
    for i, ch in enumerate(source):
        if ch in " \n\t" or elapsed >= (i + 1) / n * SPAN:
            out += ch
            continue
        last = (frame + 1) * HOLD >= (i + 1) / n * SPAN
        out += scramble_glyph(alphabet, seed, i, frame,
                              alphabet.find(ch) if last else -1)
    return out

def runs(alphabet, text, seed):
    """One window per distinct string the run puts on screen.

    The clock repaints every 32ms but a noise glyph holds for 45, so most ticks
    show what the one before it did; merged, they are the same picture out of
    half as many elements. Each window is (first tick, last tick + 1, string).
    """
    out, t = [], 0
    while True:
        s = scrambled(alphabet, text, t, seed)
        if out and out[-1][2] == s:
            out[-1][1] = t // TICK + 1
        else:
            out.append([t // TICK, t // TICK + 1, s])
        if t >= SPAN:
            return out
        t += TICK

# -------------------------------------------------------------------- SVG

class Face:
    def __init__(self, path):
        from fontTools.ttLib import TTFont
        self.font = TTFont(path)
        self.cmap = self.font.getBestCmap()
        self.glyphs = self.font.getGlyphSet()
        self.upem = self.font["head"].unitsPerEm

    def advance(self, ch):
        g = self.cmap.get(ord(ch))
        return self.font["hmtx"][g][0] if g else None

    def alphabet(self):
        """Anim.rebuildScrambleAlphabet(), against this face's real metrics.

        The app drops a candidate for either of two reasons - it comes back
        wider than a cell and a half, or it moves the line's baseline - and
        both are what a glyph reached by *substitution* does. Here there is
        only ever the one face, so nothing can shift a baseline, and a
        candidate the face doesn't have has no outline to draw at all: that is
        the drop, and it lands on the same glyphs.
        """
        cell = max(self.advance(c) for c in "MW@%0") * 1.5
        out = CORE
        for ch in CANDIDATES:
            adv = self.advance(ch)
            if ch not in out and adv is not None and adv <= cell:
                out += ch
        return out

    def path(self, ch, scale):
        from fontTools.pens.svgPathPen import SVGPathPen
        from fontTools.pens.transformPen import TransformPen
        pen = SVGPathPen(self.glyphs, ntos=lambda v: repr(round(v, 2)))
        # font units run y-up, SVG y-down
        self.glyphs[self.cmap[ord(ch)]].draw(TransformPen(pen, (scale, 0, 0, -scale, 0, 0)))
        return pen.getCommands()

    def bounds(self, ch, scale):
        from fontTools.pens.boundsPen import BoundsPen
        pen = BoundsPen(self.glyphs)
        self.glyphs[self.cmap[ord(ch)]].draw(pen)
        x0, y0, x1, y1 = pen.bounds
        return (x0 * scale, -y1 * scale, x1 * scale, -y0 * scale)


def build(face, text, seed, weight, size=104, cycle=4200,
          color="#875DC4", pad_x=34, pad_y=12):
    alphabet = face.alphabet()
    scale = size / face.upem
    cell = face.advance("M") * scale
    windows = runs(alphabet, text, seed)
    assert windows[-1][2] == text

    used = sorted({ch for _, _, s in windows for ch in s})
    ids = {ch: "g%d" % n for n, ch in enumerate(used)}
    # Sized to the ink the run actually puts on screen rather than to the type:
    # a full block paints the whole line box, well past where a letter reaches,
    # and the viewBox would crop it.
    top = min(face.bounds(ch, scale)[1] for ch in used)
    bot = max(face.bounds(ch, scale)[3] for ch in used)
    base = round(pad_y - top, 2)
    w = round(cell * len(text) + pad_x * 2)
    h = round(bot - top + pad_y * 2)

    def row(s, cls):
        return '<g class="%s">%s</g>' % (cls, "".join(
            '<use href="#%s" x="%g" y="%g"/>' % (ids[ch], round(pad_x + cell * i, 2), base)
            for i, ch in enumerate(s)))

    pct = lambda ms: round(ms / cycle * 100, 4)
    body, css = [], []
    for n, (a, b, s) in enumerate(windows[:-1]):
        body.append(row(s, "f%d" % n))
        # step-end holds each keyframe's value until the next one, so a window
        # is its two boundaries and nothing in between is interpolated.
        css.append("@keyframes f%d{%s%g%%{opacity:1}%g%%{opacity:0}}"
                   % (n, "" if a == 0 else "0%{opacity:0}", pct(a * TICK), pct(b * TICK)))
        css.append(".f%d{animation-name:f%d}" % (n, n))
    body.append(row(text, "rest"))
    css.append("@keyframes rest{0%%{opacity:0}%g%%{opacity:1}}" % pct(windows[-1][0] * TICK))

    defs = "\n".join('<path id="%s" d="%s"/>' % (ids[ch], face.path(ch, scale))
                     for ch in used)
    return """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" role="img" aria-label="{t}">
<title>{t}</title>
<!--
  The launcher's own text scramble, baked into one run: characters resolve left
  to right and everything not yet landed stands in as a random glyph, rerolled
  every {hold}ms, over a {span}ms span - the same numbers, the same alphabet and the
  same picks the shell draws (services/Anim.qml, ui/ScrambleText.qml), sampled
  on its {tick}ms clock. Seed {seed}.

  Generated by assets/make-title.py, and glyph outlines rather than text so it
  needs no font installed to render - regenerate it rather than editing the
  frames by hand. Outlines are JetBrains Mono {weight} (SIL Open Font License 1.1).
-->
<style>
g{{opacity:0;animation-duration:{cyc}s;animation-timing-function:step-end;animation-iteration-count:infinite}}
use{{fill:{color}}}
.rest{{animation-name:rest}}
{css}
@media (prefers-reduced-motion:reduce){{g{{animation:none}}.rest{{opacity:1}}}}
</style>
<defs>
{defs}
</defs>
{body}
</svg>
""".format(w=w, h=h, t=text, span=SPAN, hold=HOLD, tick=TICK, seed=seed,
           weight=weight, cyc=cycle / 1000, color=color,
           css="\n".join(css), defs=defs, body="\n".join(body))


def find_font(weight):
    try:
        out = subprocess.run(["fc-match", "--format=%{file}", "JetBrains Mono:style=" + weight],
                             capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        out = ""
    if not out or weight.lower() not in out.lower():
        sys.exit("no JetBrains Mono %s found - pass --font PATH" % weight)
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--text", default="pibble")
    ap.add_argument("--seed", type=int, default=3, help="which run of the effect to bake")
    ap.add_argument("--weight", default="Bold")
    ap.add_argument("--font", help="TTF to take outlines from (default: fc-match)")
    ap.add_argument("-o", "--out", default="assets/title.svg")
    args = ap.parse_args()

    face = Face(args.font or find_font(args.weight))
    with open(args.out, "w") as f:
        f.write(build(face, args.text, args.seed, args.weight))
    print("wrote %s (alphabet: %s)" % (args.out, face.alphabet()))
