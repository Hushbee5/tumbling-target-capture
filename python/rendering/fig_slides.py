# -*- coding: utf-8 -*-
"""Slideshow images 3 and 4 (1920 x 1080; the slideshow has no caption field, so each image carries its title).
S3: grasp robustness matrix, read from results/mujoco_capture/stress{1,2,3}_console.txt (asserted below).
S4: ROS 2 + MuJoCo lockstep: process diagram, one-cycle timing diagram, check table (TECHNICAL_REPORT_final F1-F3)."""
import re
import sys

from engfig import *

VER = sys.argv[1] if len(sys.argv) > 1 else "v1"
W, H = 1920, 1080
RES = r"results\mujoco_capture"


def frame(kicker, title, sub):
    return (text(70, 74, kicker, size=24, weight=600, fill=INK2, extra='letter-spacing="2"') +
            text(70, 138, title, size=56, weight=600) + text(70, 188, sub, size=30, fill=INK2))


# ------------------------------------------------------------------ S3 robustness
def outcomes(fn):
    d = {}
    for ln in open(RES + "\\" + fn, encoding="utf-8", errors="replace"):
        m = re.match(r"(\w+?)_(N1|N2|L1|L2|B1|NOM)\s+-> (\w+)", ln.strip())
        if m:
            d[(m.group(1), m.group(2))] = m.group(3)
    return d


V = {"v1": outcomes("stress1_console.txt"), "v2": outcomes("stress2_console.txt"), "v3": outcomes("stress3_console.txt")}
SC = [("det_r3", "r3"), ("w2_1", "w2"), ("w3_1", "w3")]
CASES = [("B1", "start offset", "10 cm, 1 cm/s"), ("L1", "latency", "50 ms"), ("L2", "latency", "200 ms"),
         ("N1", "noise N1", "0.5\u00b0, 5 mm (1\u03c3)"), ("N2", "noise N2", "3 \u00d7 N1")]
tot = {v: sum(V[v][(s, c)] == "CAPTURED" for s, _ in SC for c, _, _ in CASES) for v in V}
assert (tot["v1"], tot["v2"], tot["v3"]) == (8, 11, 12), tot
for v in ("v2", "v3"):
    assert sum(V[v][(k[0], "NOM")] == "CAPTURED" for k in V[v] if k[1] == "NOM") == 10

b = [defs()]
b.append(frame("CAPTURE PROTOTYPE  \u00b7  MuJoCo  \u00b7  DEVELOPMENT DATA, NOT VALIDATED",
               "Grasp robustness over three controller iterations",
               "15 stress runs: one stress factor at a time, three tumbling scenarios each. Same runs for every version."))
CW, G1, G2 = 58, 6, 30
MX, MY, RP = 470, 380, 92
gw = 3 * CW + 2 * G1
for gi, (c, t1, t2) in enumerate(CASES):
    gx = MX + gi * (gw + G2)
    b.append(text(gx, MY - 70, t1, size=27, weight=600))
    b.append(text(gx, MY - 36, t2, size=24, fill=INK2))
    for si, (_, lab) in enumerate(SC):
        b.append(text(gx + si * (CW + G1) + CW / 2, MY + 3 * RP + 18, lab, size=23, fill=INK2, anchor="middle"))
ROWS = [("v1", "first controller", ""), ("v2", "+ measurement filter", ""), ("v3", "+ filter, post-grasp hold", "")]
for ri, (v, d1, _) in enumerate(ROWS):
    y = MY + ri * RP
    b.append(text(70, y + 38, v, size=40, weight=700))
    b.append(text(140, y + 36, d1, size=25, fill=INK2))
    for gi, (c, _, _) in enumerate(CASES):
        gx = MX + gi * (gw + G2)
        for si, (s, _) in enumerate(SC):
            x = gx + si * (CW + G1)
            o = V[v][(s, c)]
            if o == "CAPTURED":
                b.append(rect(x, y, CW, CW, stroke=INK, sw=0, fill=INK))
            elif o == "NOT_REACHED":
                b.append(rect(x + 1.5, y + 1.5, CW - 3, CW - 3, stroke=INK3, sw=3, fill="url(#hatchl)"))
            else:
                assert o == "UNSAFE_CONTACT", o
                b.append(rect(x + 2, y + 2, CW - 4, CW - 4, stroke=KEEP, sw=4, fill=PAPER))
                b.append(line(x + 10, y + 10, x + CW - 10, y + CW - 10, stroke=KEEP, w=4))
                b.append(line(x + CW - 10, y + 10, x + 10, y + CW - 10, stroke=KEEP, w=4))
TX = MX + 5 * gw + 4 * G2 + 60
b.append(text(TX, MY - 70, "captured", size=27, weight=600))
b.append(text(TX, MY - 36, "of 15", size=24, fill=INK2))
b.append(text(TX + 180, MY - 70, "nominal", size=27, weight=600))
b.append(text(TX + 180, MY - 36, "ideal sensing", size=24, fill=INK2))
for ri, (v, _, _) in enumerate(ROWS):
    y = MY + ri * RP
    b.append(text(TX, y + 50, "%d" % tot[v], size=56, weight=700))
    b.append(text(TX + 72, y + 50, "/ 15", size=28, fill=INK2))
    b.append(text(TX + 180, y + 46, "10 / 10", size=32, weight=600))
# legend
ly = MY + 3 * RP + 96
b.append(rect(70, ly, 40, 40, stroke=INK, sw=0, fill=INK))
b.append(text(126, ly + 30, "captured", size=27))
b.append(rect(330, ly, 40, 40, stroke=INK3, sw=3, fill="url(#hatchl)"))
b.append(text(386, ly + 30, "no grasp: the synchronisation gate was never met", size=27))
b.append(rect(1060, ly, 40, 40, stroke=KEEP, sw=4, fill=PAPER))
b.append(line(1066, ly + 6, 1094, ly + 34, stroke=KEEP, w=4))
b.append(line(1094, ly + 6, 1066, ly + 34, stroke=KEEP, w=4))
b.append(text(1116, ly + 30, "unsafe: a forbidden contact after the gripper closed", size=27, fill=KEEP))
b.append(text(70, ly + 92, "What changed: the measurement filter of v2 turned two N1 runs into captures and removed the "
              "v1 unsafe contact;", size=27))
b.append(text(70, ly + 128, "the post-grasp hold of v3 removed the last unsafe contact.", size=27))
b.append(line(70, 930, W - 70, 930, stroke=HAIR, w=1.4))
b.append(text(70, 972, "At three times the nominal noise (N2) no version ever left synchronisation. Scenarios: r3 = det_r3 "
              "(3.9 deg/s), w2 = w2_1 (2 deg/s), w3 = w3_1 (3 deg/s).", size=24, fill=INK2))
b.append(text(70, 1008, "Nominal: ten scenarios with ideal measurement. Each run set was defined before it ran. Source: "
              "results/mujoco_capture/stress1-3.", size=24, fill=INK2))
name = "s3_robustness_%s" % VER
open(name + ".html", "w", encoding="utf-8").write(page(W, H, "".join(b), name))
render(name + ".html", "png/%s.png" % name, W, H)
print("written png/%s.png" % name, tot)

# ------------------------------------------------------------------ S4 ROS 2
b = [defs()]
b.append(frame("CAPTURE PROTOTYPE  \u00b7  ROS 2 + MuJoCo  \u00b7  DEVELOPMENT DATA, NOT VALIDATED",
               "Two processes, one deterministic lockstep",
               "The grasp runs as a ROS 2 plant node and a controller node that exchange standard messages every 10 ms."))
PX, PY, PW, PH = 70, 260, 400, 450
CX = 1030
b.append(rect(PX, PY, PW, PH, stroke=INK, sw=2.6, fill=PAPER))
b.append(rect(CX, PY, PW, PH, stroke=INK, sw=2.6, fill=PAPER))
b.append(text(PX + 22, PY + 50, "plant node", size=34, weight=600))
b.append(text(CX + 22, PY + 50, "controller node", size=34, weight=600))
pl = ["MuJoCo 3.14, RK4, 1 ms", "free-floating bus + 6-DOF arm", "tumbling target with handle", "Clohessy\u2013Wiltshire terms",
      "joint-velocity servo, 1 kHz", "contact monitor"]
cl = ["bus synchronisation", "arm resolved-rate control", "phases SYNC \u2192 APPROACH \u2192", "CLOSE \u2192 HOLD",
      "sees only the messages", "it receives"]
for i, s in enumerate(pl):
    b.append(text(PX + 22, PY + 104 + 44 * i, s, size=26, fill=INK2))
for i, s in enumerate(cl):
    b.append(text(CX + 22, PY + 104 + 44 * i, s, size=26, fill=INK2))
up = [("/capture/target/odom", "nav_msgs/Odometry"), ("/capture/bus/odom", "nav_msgs/Odometry"),
      ("/capture/joint_states", "sensor_msgs/JointState"),
      ("/capture/wrist_wrench", "geometry_msgs/WrenchStamped"), ("/capture/contact", "std_msgs/String")]
dn = [("/capture/bus_cmd", "geometry_msgs/WrenchStamped"), ("/capture/joint_cmd", "sensor_msgs/JointState"),
      ("/capture/status", "std_msgs/String")]
ax0, ax1 = PX + PW + 14, CX - 14
for i, (t, m) in enumerate(up):
    y = PY + 44 + 44 * i
    b.append(line(ax0, y, ax1, y, stroke=INK, w=2.2, marker_end="arr"))
    b.append(text(ax0 + 6, y - 9, t, size=19, cls="mono"))
    b.append(text(ax1 - 4, y - 9, m, size=19, fill=INK2, anchor="end", cls="mono"))
for i, (t, m) in enumerate(dn):
    y = PY + 330 + 44 * i
    b.append(line(ax1, y, ax0, y, stroke=INK, w=2.2, marker_end="arr"))
    b.append(text(ax0 + 6, y - 9, t, size=19, cls="mono"))
    b.append(text(ax1 - 4, y - 9, m, size=19, fill=INK2, anchor="end", cls="mono"))
TK = 't<tspan baseline-shift="sub" font-size="16">k</tspan>'


def e10(x):
    return '10<tspan baseline-shift="super" font-size="17">\u2212%s</tspan>' % x


b.append(text((ax0 + ax1) / 2, PY + 266, "measurements, stamped " + TK, size=22, weight=600, fill=INK2, anchor="middle"))
b.append(text((ax0 + ax1) / 2, PY + PH + 30, "commands, stamped " + TK, size=22, weight=600, fill=INK2, anchor="middle"))

# one-cycle timing diagram
TX0, TX1, TY = 1520, 1850, 300
b.append(text(TX0 - 10, TY - 10, "one 10 ms cycle", size=27, weight=600))
lanes = [("plant", TY + 70), ("controller", TY + 200)]
for nm, y in lanes:
    b.append(text(TX1, y - 32, nm, size=22, weight=600, fill=INK2, anchor="end"))
    b.append(line(TX0, y, TX1, y, stroke=HAIR, w=1.4))
X = lambda f: TX0 + (TX1 - TX0) * f
b.append(rect(X(0.0), lanes[0][1] - 22, X(0.10) - X(0.0), 44, stroke=INK, sw=2, fill=INK))
b.append(rect(X(0.12), lanes[1][1] - 22, X(0.38) - X(0.12), 44, stroke=INK, sw=2, fill="#EEF3F9"))
b.append(rect(X(0.42), lanes[0][1] - 22, X(0.92) - X(0.42), 44, stroke=INK, sw=2, fill="url(#hatchl)"))
b.append(rect(X(0.93), lanes[0][1] - 22, X(1.0) - X(0.93), 44, stroke=INK, sw=2, fill=INK))
b.append(line(X(0.06), lanes[0][1] + 22, X(0.14), lanes[1][1] - 24, stroke=INK, w=2, marker_end="arr"))
b.append(line(X(0.36), lanes[1][1] - 24, X(0.44), lanes[0][1] + 24, stroke=INK, w=2, marker_end="arr"))
b.append(text(X(0.67), lanes[0][1] + 8, "10 \u00d7 1 ms", size=20, weight=600, anchor="middle"))
b.append(text(X(0.25), lanes[1][1] + 8, "solve", size=20, weight=600, anchor="middle"))
b.append(line(X(0), lanes[1][1] + 50, X(1), lanes[1][1] + 50, stroke=INK2, w=1.4))
b.append(text(X(0), lanes[1][1] + 80, TK, size=24, fill=INK2, anchor="middle"))
b.append(text(X(1), lanes[1][1] + 80, TK + " + 10 ms", size=24, fill=INK2, anchor="end"))
tl = ["publish measurements", "controller solves, replies", "physics steps only after", "the matching command arrives"]
for i, s in enumerate(tl):
    b.append(text(TX0 - 10, lanes[1][1] + 130 + 34 * i, s, size=22, fill=INK2))

# check table
TY0 = 830
cols = [70, 470, 1150]
b.append(line(70, TY0 - 40, W - 70, TY0 - 40, stroke=INK, w=2))
for x, h in zip(cols, ["Check (set before the runs)", "Criterion", "Result"]):
    b.append(text(x, TY0 - 8, h, size=24, weight=700))
b.append(line(70, TY0 + 6, W - 70, TY0 + 6, stroke=INK, w=1.2))
rows = [("F2  stamps, frames, limits", "0 stamp or frame errors; commands inside limits", "PASS in 3 of 3 runs", INK),
        ("F3  determinism", "repeated runs identical in every history field", "PASS, bit-identical", INK),
        ("F1  agreement with one process", "relative difference \u2264 1\u00d7" + e10("9"),
         "PASS w2_1 (1.5\u00d7" + e10("10") + ');  <tspan fill="%s">FAIL det_r3 (1.06\u00d7' % KEEP + e10("9") +
         ")</tspan>", INK)]
for i, (a, c, r, col) in enumerate(rows):
    y = TY0 + 48 + 46 * i
    b.append(text(cols[0], y, a, size=25, weight=600))
    b.append(text(cols[1], y, c, size=25))
    b.append(text(cols[2], y, r, size=25, weight=600, fill=col))
b.append(line(70, TY0 + 48 + 46 * 2 + 20, W - 70, TY0 + 48 + 46 * 2 + 20, stroke=INK, w=2))
b.append(text(70, 1040, "ROS 2 Humble on Windows, localhost; frames per REP-105; integer-nanosecond stamps. Runs use "
              "controller v1 with ideal measurement; the approach controller is not in the ROS graph.", size=22, fill=INK2))
name = "s4_ros2_%s" % VER
open(name + ".html", "w", encoding="utf-8").write(page(W, H, "".join(b), name))
render(name + ".html", "png/%s.png" % name, W, H)
print("written png/%s.png" % name)
