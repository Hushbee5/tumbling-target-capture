"""Animated GIF of the det_r3 capture (controller v3, ideal measurements) for the user's iPoster (development material).
Same simulation loop as render_visuals_r3.py / stress_capture_v3.py (nominal), so the run equals the stress-r3 NOM run.
Frames every 0.25 s, every 0.1 s around the grasp (14.5-17.5 s); time and phase are written on each frame.
Usage: python render_capture_gif.py <out.gif>    (never overwrites)"""
import os
import sys

import mujoco
import numpy as np
from PIL import Image, ImageDraw, ImageFont

import capture_core as CC
import sim_capture as SC
import stress_capture_v2 as V2
import stress_capture_v3 as V3

out = sys.argv[1]
assert not os.path.exists(out), "exists: " + out
m = SC.m
m.vis.headlight.ambient[:] = 0.32                          # rendering only; physics untouched
m.vis.headlight.diffuse[:] = 0.75
H, W = 420, 560
rend = mujoco.Renderer(m, height=H, width=W)
cam = mujoco.MjvCamera()
font = ImageFont.truetype(r"C:\Windows\Fonts\arial.ttf", 17)
font_s = ImageFont.truetype(r"C:\Windows\Fonts\arial.ttf", 14)
NOTE = {"SYNC": "SYNC: the bus follows the tumbling handle",
        "APPROACH": "APPROACH: the gripper closes the 15 cm standoff",
        "CLOSE": "CLOSE: the fingers close on the handle",
        "HOLD": "HOLD: arm joints held, bus thrusters off"}
times = [round(x, 2) for x in np.arange(0.0, 14.5, 0.25)] + [round(x, 2) for x in np.arange(14.5, 17.5, 0.1)] + \
        [round(x, 2) for x in np.arange(17.5, 26.01, 0.25)]
want = sorted(set(times))
scn = [s for s in SC.scenarios() if s["id"] == "det_r3"][0]
plant, ctl, flt = V3.PlantV3(scn), CC.Controller(), V2.MeasFilter()
frames, hold = [], None
for k in range(int(round(26.5 / SC.DT_CTRL))):
    t = round(k * SC.DT_CTRL, 2)
    cmd, dg = ctl.step(flt(plant.measure()), t)
    if ctl.phase == "HOLD":
        if hold is None:
            Mf = np.zeros((m.nv, m.nv)); mujoco.mj_fullM(m, plant.d, Mf); Mjj = np.diag(Mf)[SC.ARM_V]
            Kp = 50.0 * Mjj; hold = (plant.d.qpos[SC.ARM_Q].copy(), Kp, 2.0 * np.sqrt(Kp * Mjj))
        cmd = dict(cmd, hold_q=hold[0], Kp=hold[1], Kd=hold[2])
    phase_now = ctl.phase
    ci = plant.apply(cmd)
    ctl.contact_update(ci["fl"], ci["fr"], t)
    if want and t >= want[0] - 1e-9:
        d = plant.d
        cT = d.xpos[SC.BID["target"]]; pB = d.xpos[SC.BID["bus"]]; u = pB - cT
        tcp = d.site_xpos[SC.TCP]; hdl = cT + SC.mat(d.xquat[SC.BID["target"]]) @ SC.PB
        cam.lookat[:] = 0.5 * (cT + pB); cam.distance = 4.6
        cam.azimuth = np.degrees(np.arctan2(u[1], u[0])) + 90.0; cam.elevation = -25.0
        rend.update_scene(d, camera=cam)
        im = Image.fromarray(rend.render())
        dr = ImageDraw.Draw(im)
        dr.text((10, 8), "MuJoCo capture prototype (development, not validated)", font=font_s, fill="white",
                stroke_width=2, stroke_fill="black")
        dr.text((10, H - 52), "t = %4.1f s   TCP-handle %.1f cm" % (t, 100 * np.linalg.norm(tcp - hdl)), font=font,
                fill="white", stroke_width=2, stroke_fill="black")
        dr.text((10, H - 28), NOTE[phase_now], font=font, fill="white", stroke_width=2, stroke_fill="black")
        frames.append(im.convert("P", palette=Image.ADAPTIVE, colors=128))
        want.pop(0)
    if not want:
        break
dur = [100] * len(frames)
dur[-1] = 1800                                                   # hold the last frame before looping
frames[0].save(out, save_all=True, append_images=frames[1:], duration=dur, loop=0, optimize=True, disposal=2)
print("frames %d | %s | %.1f MB" % (len(frames), out, os.path.getsize(out) / 2**20))
