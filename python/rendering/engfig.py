# -*- coding: utf-8 -*-
"""Shared drawing kit for the iPoster figures (engineering-drawing style, no icons, no gradients).
Each figure is an SVG inside a minimal HTML page, rendered to PNG by Edge headless at device scale 1.
Palette validated with the dataviz validator on 2026-10-05 (light mode, all checks PASS):
  V3 / proposed #1D5FA8, nominal MPC #C47500, APF #00896B. Keep-out / violation red is reserved: #B3392B."""
import math
import os
import subprocess

EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
INK, INK2, INK3 = "#1D232B", "#56606B", "#8A939C"
HAIR, GRID, PAPER = "#C9CED4", "#E6E9EC", "#FFFFFF"
V3, MPC, APF, KEEP = "#1D5FA8", "#C47500", "#00896B", "#B3392B"
FONT = "Bahnschrift, 'Segoe UI', sans-serif"
MONO = "Consolas, 'Cascadia Mono', monospace"

CSS = """
html,body{margin:0;padding:0;background:%(paper)s}
svg{display:block}
text{font-family:%(font)s}
.mono{font-family:%(mono)s}
""" % dict(paper=PAPER, font=FONT, ink=INK, mono=MONO)


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def text(x, y, s, size=32, weight=400, fill=INK, anchor="start", italic=False, cls="", extra=""):
    st = ' font-style="italic"' if italic else ""
    c = ' class="%s"' % cls if cls else ""
    return ('<text x="%.1f" y="%.1f" font-size="%s" font-weight="%d" fill="%s" text-anchor="%s"%s%s %s>%s</text>'
            % (x, y, size, weight, fill, anchor, st, c, extra, esc(s) if "<tspan" not in s else s))


def line(x1, y1, x2, y2, stroke=INK, w=2, dash=None, cap="butt", marker_end=None, marker_start=None, op=1.0):
    d = ' stroke-dasharray="%s"' % dash if dash else ""
    me = ' marker-end="url(#%s)"' % marker_end if marker_end else ""
    ms = ' marker-start="url(#%s)"' % marker_start if marker_start else ""
    return ('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="%s" stroke-linecap="%s"%s%s%s '
            'opacity="%s"/>' % (x1, y1, x2, y2, stroke, w, cap, d, me, ms, op))


def path(d, stroke=INK, w=2, fill="none", dash=None, marker_end=None, marker_start=None, op=1.0, join="miter"):
    da = ' stroke-dasharray="%s"' % dash if dash else ""
    me = ' marker-end="url(#%s)"' % marker_end if marker_end else ""
    ms = ' marker-start="url(#%s)"' % marker_start if marker_start else ""
    return ('<path d="%s" stroke="%s" stroke-width="%s" fill="%s" stroke-linejoin="%s"%s%s%s opacity="%s"/>'
            % (d, stroke, w, fill, join, da, me, ms, op))


def rect(x, y, w, h, stroke=INK, sw=2, fill="none", dash=None, rx=0):
    da = ' stroke-dasharray="%s"' % dash if dash else ""
    return ('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="%s" stroke="%s" stroke-width="%s" fill="%s"%s/>'
            % (x, y, w, h, rx, stroke, sw, fill, da))


def circle(cx, cy, r, stroke=INK, sw=2, fill="none", dash=None, op=1.0):
    da = ' stroke-dasharray="%s"' % dash if dash else ""
    return ('<circle cx="%.1f" cy="%.1f" r="%.1f" stroke="%s" stroke-width="%s" fill="%s"%s opacity="%s"/>'
            % (cx, cy, r, stroke, sw, fill, da, op))


def arc(cx, cy, r, a0, a1):
    """SVG path data for a circular arc from angle a0 to a1 (degrees, math convention, y up)."""
    x0, y0 = cx + r * math.cos(math.radians(a0)), cy - r * math.sin(math.radians(a0))
    x1, y1 = cx + r * math.cos(math.radians(a1)), cy - r * math.sin(math.radians(a1))
    large = 1 if abs(a1 - a0) > 180 else 0
    sweep = 0 if a1 > a0 else 1
    return "M %.1f %.1f A %.1f %.1f 0 %d %d %.1f %.1f" % (x0, y0, r, r, large, sweep, x1, y1)


def defs(extra=""):
    """Arrowheads (open technical style and filled), section hatching patterns."""
    out = ['<defs>']
    for name, col in (("arr", INK), ("arr2", INK2), ("arrv3", V3), ("arrk", KEEP), ("arrw", "#FFFFFF")):
        out.append('<marker id="%s" viewBox="0 0 12 12" refX="11" refY="6" markerWidth="12" markerHeight="12" '
                   'markerUnits="userSpaceOnUse" orient="auto-start-reverse"><path d="M0,1 L11,6 L0,11 z" fill="%s"/>'
                   '</marker>' % (name, col))
        out.append('<marker id="%s_l" viewBox="0 0 16 16" refX="15" refY="8" markerWidth="18" markerHeight="18" '
                   'markerUnits="userSpaceOnUse" orient="auto-start-reverse"><path d="M0,1.5 L15,8 L0,14.5 z" fill="%s"/>'
                   '</marker>' % (name, col))
    # dimension-line tick (architectural oblique stroke)
    out.append('<marker id="tick" viewBox="-6 -6 12 12" markerWidth="12" markerHeight="12" markerUnits="userSpaceOnUse" '
               'orient="auto"><path d="M-5,5 L5,-5" stroke="%s" stroke-width="2"/></marker>' % INK)
    for name, col, sp in (("hatch", INK3, 14), ("hatchk", KEEP, 12), ("hatchl", HAIR, 16)):
        out.append('<pattern id="%s" patternUnits="userSpaceOnUse" width="%d" height="%d" patternTransform="rotate(45)">'
                   '<line x1="0" y1="0" x2="0" y2="%d" stroke="%s" stroke-width="2"/></pattern>' % (name, sp, sp, sp, col))
    out.append(extra)
    out.append('</defs>')
    return "".join(out)


def page(w, h, body, title="figure"):
    return ('<!doctype html><html><head><meta charset="utf-8"><title>%s</title><style>%s</style></head><body>'
            '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
            '<rect width="%d" height="%d" fill="%s"/>%s</svg></body></html>'
            % (esc(title), CSS, w, h, w, h, w, h, PAPER, body))


def render(html_path, png_path, w, h):
    """Edge headless screenshot at device scale 1; refuses to overwrite an existing PNG."""
    if os.path.exists(png_path):
        raise SystemExit("exists " + png_path)
    url = "file:///" + os.path.abspath(html_path).replace("\\", "/")
    cmd = [EDGE, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
           "--window-size=%d,%d" % (w, h), "--screenshot=" + os.path.abspath(png_path), url]
    subprocess.run(cmd, check=True, capture_output=True, timeout=120)
    if not os.path.exists(png_path):
        raise SystemExit("no PNG from Edge: " + png_path)


def wilson(k, n, z=1.959963984540054):
    p = k / n
    den = 1 + z * z / n
    c = (p + z * z / (2 * n)) / den
    hw = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / den
    return 100 * (c - hw), 100 * (c + hw)
