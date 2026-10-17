"""r3 (2026-10-05): as render_capture_hero.py, with the 8192-px NASA texture, the finer MLI texture (v1; v2 showed
contour artefacts), fewer stars, and an overlay in the poster's engineering style (readouts, phase strip, no icons).
GIF frames are written as PNGs to <out>_gifframes/ (assembled by make_gif.py).
Cinematic render of the MuJoCo capture prototype (det_r3, controller v3, ideal measurement) for the iPoster.
Step 1 (physics): runs the ORIGINAL model and controller with the same loop as stress_capture_v3 (nominal) and records
qpos after every control period (100 Hz).
Step 2 (render only): a DECORATED copy of capture_scene.xml (same kinematic tree; extra visual-only geoms; procedural
textures; NASA Earth texture; star field) replays the recorded qpos. Nothing in step 2 integrates dynamics.
Check: the replayed TCP-handle distance equals the physics run's distance at every rendered frame.
Outputs (never overwritten): <out>.mp4 (1280x720, 30 fps), <out>_grasp.png (1920x1080), <out>_preview.gif (560x315).
Usage: python render_capture_hero.py <out_basename>"""
import os
import re
import sys

import imageio.v2 as iio
import mujoco
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
CAP = os.path.join(os.path.dirname(HERE), "mujoco_capture")
sys.path.insert(0, CAP)
import capture_core as CC                                     # noqa: E402
import sim_capture as SC                                      # noqa: E402
import stress_capture_v2 as V2                                # noqa: E402
import stress_capture_v3 as V3                                # noqa: E402

out = sys.argv[1]
for ext in (".mp4", "_grasp.png", "_gifframes"):
    assert not os.path.exists(out + ext), out + ext
os.makedirs(out + "_gifframes")

# ------------------------------------------------------------------ step 1: physics with the original model
m0 = SC.m
scn = [s for s in SC.scenarios() if s["id"] == "det_r3"][0]
plant, ctl, flt = V3.PlantV3(scn), CC.Controller(), V2.MeasFilter()
rec_t, rec_q, rec_ph, rec_d = [0.0], [plant.d.qpos.copy()], ["SYNC"], [np.nan]
hold = None
for k in range(int(round(26.5 / SC.DT_CTRL))):
    t = k * SC.DT_CTRL
    cmd, dg = ctl.step(flt(plant.measure()), t)
    if ctl.phase == "HOLD":
        if hold is None:
            Mf = np.zeros((m0.nv, m0.nv)); mujoco.mj_fullM(m0, plant.d, Mf); Mjj = np.diag(Mf)[SC.ARM_V]
            Kp = 50.0 * Mjj; hold = (plant.d.qpos[SC.ARM_Q].copy(), Kp, 2.0 * np.sqrt(Kp * Mjj))
        cmd = dict(cmd, hold_q=hold[0], Kp=hold[1], Kd=hold[2])
    ph = ctl.phase
    ci = plant.apply(cmd)
    ctl.contact_update(ci["fl"], ci["fr"], t)
    d0 = plant.d
    hdl = d0.xpos[SC.BID["target"]] + SC.mat(d0.xquat[SC.BID["target"]]) @ SC.PB
    rec_t.append(t + SC.DT_CTRL); rec_q.append(d0.qpos.copy()); rec_ph.append(ph)
    rec_d.append(float(np.linalg.norm(d0.site_xpos[SC.TCP] - hdl)))
rec_t = np.array(rec_t); rec_q = np.array(rec_q); rec_d = np.array(rec_d)
t_close = next(t for t, p in zip(rec_t, rec_ph) if p == "CLOSE")
print("physics: %d samples; CLOSE at %.2f s; phases %s" % (len(rec_t), t_close, sorted(set(rec_ph))))

# ------------------------------------------------------------------ step 2: decorated render-only model
src = open(os.path.join(CAP, "capture_scene.xml"), encoding="utf-8").read()
HEAD = """<mujoco model="capture_scene">
  <statistic extent="4" center="-1 0 0"/>
  <visual>
    <global offwidth="1920" offheight="1080" fovy="36"/>
    <quality shadowsize="8192" offsamples="8"/>
    <headlight ambient="0.10 0.10 0.12" diffuse="0.22 0.22 0.22" specular="0.03 0.03 0.03"/>
    <map znear="0.01" zfar="2000"/>
  </visual>
  <asset>
    <texture name="sky" type="skybox" builtin="gradient" rgb1="0.025 0.03 0.07" rgb2="0 0 0" width="2000" height="2000"
             mark="random" random="0.0005" markrgb="0.85 0.86 0.9"/>
    <texture name="earthtex" type="2d" file="land_shallow_topo_8192.png"/>
    <material name="earth" texture="earthtex" specular="0.05" shininess="0.05" emission="0.15"/>
    <mesh name="uvsphere" file="uvsphere.obj" scale="400 400 400"/>
    <texture name="t_mli" type="cube" file="textures/tex_mli_gold.png"/>
    <material name="mli" texture="t_mli" specular="0.75" shininess="0.6" reflectance="0.05"/>
    <texture name="t_solar" type="cube" file="textures/tex_solar_cells_sq.png"/>
    <material name="solar" texture="t_solar" specular="0.9" shininess="0.95"/>
    <texture name="t_alu" type="cube" file="textures/tex_aluminium_panels.png"/>
    <material name="alu" texture="t_alu" specular="0.5" shininess="0.55"/>
    <texture name="t_rad" type="cube" file="textures/tex_radiator.png"/>
    <material name="rad" texture="t_rad" specular="0.3" shininess="0.3"/>
    <material name="arm" rgba="0.80 0.81 0.83 1" specular="0.45" shininess="0.5"/>
    <material name="joint" rgba="0.20 0.22 0.25 1" specular="0.3" shininess="0.4"/>
    <material name="dark" rgba="0.16 0.17 0.19 1" specular="0.2" shininess="0.3"/>
    <material name="steel" rgba="0.62 0.64 0.67 1" specular="0.8" shininess="0.8"/>
    <material name="whitemetal" rgba="0.92 0.92 0.90 1" specular="0.5" shininess="0.5"/>
    <material name="handle" rgba="0.25 0.45 0.75 1" specular="0.5" shininess="0.5"/>
  </asset>"""
dec = src.replace('<mujoco model="capture_scene">', HEAD, 1)
dec = dec.replace("<worldbody>", """<worldbody>
    <light name="sun" directional="true" pos="0 0 20" dir="-0.35 0.55 -0.76" diffuse="1.0 0.98 0.93" specular="0.4 0.4 0.4" castshadow="true"/>
    <geom name="earth" type="mesh" mesh="uvsphere" material="earth" pos="-300 -120 -520" euler="0.3 0.5 2.2" contype="0" conaffinity="0" mass="0"/>""", 1)


def restyle(s, gname, material):
    pat = re.compile(r'(<geom name="%s"[^>]*?)\s+rgba="[^"]*"' % re.escape(gname))
    s2, n = pat.subn(r'\1 material="%s"' % material, s)
    assert n == 1, gname
    return s2


for g, mat in (("g_bus", "mli"), ("g_target", "alu"), ("g_stalk", "steel"), ("g_handle", "handle"), ("g_palm", "dark"),
               ("g_finger_l", "steel"), ("g_finger_r", "steel")) + tuple(("g_link%d" % i, "arm") for i in range(1, 7)):
    dec = restyle(dec, g, mat)
VIS = ' contype="0" conaffinity="0" mass="0"'
bus_extra = "".join([
    '<geom type="capsule" fromto="0 0.5 0 0 0.80 0" size="0.022" material="steel"%s/>' % VIS,
    '<geom type="capsule" fromto="0 -0.5 0 0 -0.80 0" size="0.022" material="steel"%s/>' % VIS,
    '<geom type="box" pos="0 1.62 0" size="0.012 0.82 0.40" material="solar"%s/>' % VIS,
    '<geom type="box" pos="0 -1.62 0" size="0.012 0.82 0.40" material="solar"%s/>' % VIS,
    '<geom type="box" pos="-0.507 0 0" size="0.004 0.42 0.42" material="rad"%s/>' % VIS,
    '<geom type="capsule" fromto="0.22 0.22 0.5 0.22 0.22 0.72" size="0.012" material="steel"%s/>' % VIS,
    '<geom type="ellipsoid" pos="0.22 0.22 0.75" size="0.17 0.17 0.035" material="whitemetal"%s/>' % VIS,
    '<geom type="box" pos="-0.25 -0.3 0.53" size="0.06 0.05 0.03" material="dark"%s/>' % VIS] +
    ['<geom type="cylinder" pos="-0.52 %g %g" zaxis="-1 0 0" size="0.03 0.03" material="dark"%s/>' % (y, z, VIS)
     for y in (-0.4, 0.4) for z in (-0.4, 0.4)])
dec, n = re.subn(r'(<geom name="g_bus"[^>]*/>)', lambda mm: mm.group(1) + bus_extra, dec)
assert n == 1
for i in range(1, 7):                                          # joint housings at each hinge (local z axis)
    dec, n = re.subn(r'(<joint name="j%d"[^>]*/>)' % i,
                     lambda mm: mm.group(1) + '<geom type="cylinder" size="0.058 0.055" material="joint"%s/>' % VIS, dec)
    assert n == 1, i
xml_path = os.path.join(HERE, "capture_hero_scene_r3.xml")
if not os.path.exists(xml_path):
    open(xml_path, "x", encoding="utf-8").write(dec)
assert open(xml_path, encoding="utf-8").read() == dec, "capture_hero_scene.xml differs from this script's scene"
m = mujoco.MjModel.from_xml_path(xml_path)
d = mujoco.MjData(m)
assert m.nq == m0.nq, (m.nq, m0.nq)
tcp_id = mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_SITE, "tcp")
bt, bb = m.body("target").id, m.body("bus").id

# ------------------------------------------------------------------ camera choreography and time mapping
FPS = 30
taus = np.concatenate([np.linspace(0.0, 14.5, 420, endpoint=False),          # approach, ~1x
                       np.linspace(14.5, 17.5, 200, endpoint=False),         # grasp, slow motion
                       np.linspace(17.5, 26.5, 180)])                        # hold, faster
idx = np.clip(np.searchsorted(rec_t, taus), 0, len(rec_t) - 1)


# camera azimuth FIXED in the world frame (chosen from the grasp-time geometry), so the fixed Earth stays in view
kg0 = int(np.searchsorted(rec_t, t_close))
d.qpos[:] = rec_q[kg0]; mujoco.mj_forward(m, d)
ug = d.xpos[bb] - d.xpos[bt]; AZ = float(np.degrees(np.arctan2(ug[1], ug[0]))) + 70.0
d.qpos[:] = rec_q[0]; mujoco.mj_forward(m, d)
c0 = 0.5 * (d.xpos[bt] + d.xpos[bb]); el0 = np.radians(-20.0)
fwd = np.array([np.cos(el0) * np.cos(np.radians(AZ)), np.cos(el0) * np.sin(np.radians(AZ)), np.sin(el0)])
e_dir = fwd + np.array([0.0, 0.0, -0.62]); e_dir /= np.linalg.norm(e_dir)
m.geom_pos[mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_GEOM, "earth")] = c0 + 700.0 * e_dir   # rendering only
print("camera azimuth %.1f deg; Earth centre placed at %s" % (AZ, np.round(c0 + 700.0 * e_dir, 1)))


def camera_for(tau, cam):
    cT = d.xpos[bt]; pB = d.xpos[bb]; tcp = d.site_xpos[tcp_id]
    base_az = AZ - 70.0
    w = np.clip((tau - 2.0) / 12.0, 0, 1)
    look_wide = 0.5 * (cT + pB); look_close = tcp
    if tau < 17.5:
        cam.lookat[:] = (1 - w) * look_wide + w * look_close
        cam.distance = float(np.interp(tau, [0, 2, 14, 15.5, 17.5], [6.8, 6.8, 2.6, 1.7, 1.7]))
    else:
        v = np.clip((tau - 17.5) / 6.0, 0, 1)
        cam.lookat[:] = (1 - v) * look_close + v * (0.55 * cT + 0.45 * pB)
        cam.distance = float(np.interp(tau, [17.5, 23.5, 26.5], [1.7, 5.2, 5.2]))
    cam.azimuth = base_az + float(np.interp(tau, [0, 14, 17.5, 26.5], [62, 70, 74, 84]))
    cam.elevation = float(np.interp(tau, [0, 14, 17.5, 26.5], [-16, -22, -26, -20]))


F = r"C:\Windows\Fonts"


def font(size, var="Regular"):
    fo = ImageFont.truetype(F + "/bahnschrift.ttf", size)
    fo.set_variation_by_name(var)
    return fo


NOTE = {"SYNC": "the bus matches the tumbling target's motion", "APPROACH": "the gripper closes the last 15 cm",
        "CLOSE": "the fingers close on the handle", "HOLD": "post-grasp hold: arm joints held, thrusters off"}
PHASES = ["SYNC", "APPROACH", "CLOSE", "HOLD"]


def spaced(dr, xy, txt, fo, fill, sp):
    x, y = xy
    for ch in txt:
        dr.text((x, y), ch, font=fo, fill=fill)
        x += dr.textlength(ch, font=fo) + sp


def overlay(img, k, scale=1.0):
    im = Image.fromarray(img).convert("RGBA")
    lay = Image.new("RGBA", im.size, (0, 0, 0, 0)); dr = ImageDraw.Draw(lay)
    S = lambda v: int(round(v * scale)); w, h = im.size
    fk, ft, fl, fv, fs, fc, fp = (font(S(16), "SemiBold"), font(S(34), "SemiBold"), font(S(15)), font(S(30), "SemiBold"),
                                  font(S(17)), font(S(13)), font(S(15), "SemiBold"))
    title = "A 6-DOF arm grasps the handle"
    tw = dr.textlength(title, font=ft)
    kick = "BEYOND THE PAPER  ·  DEVELOPMENT PROTOTYPE, NOT VALIDATED"
    kw_ = sum(dr.textlength(ch, font=fk) + S(1.6) for ch in kick)
    bw = max(tw, kw_)
    dr.rectangle([S(24), S(22), S(24) + bw + S(36), S(112)], fill=(6, 9, 16, 150))
    spaced(dr, (S(42), S(34)), kick, fk, (225, 230, 240, 230), S(1.6))
    dr.line([S(42), S(60), S(42) + bw, S(60)], fill=(225, 230, 240, 120), width=max(1, S(1)))
    dr.text((S(42), S(66)), title, font=ft, fill=(255, 255, 255, 255))
    bx, by = S(24), h - S(128)
    dr.rectangle([bx, by, bx + S(560), h - S(22)], fill=(6, 9, 16, 160))
    dd = rec_d[k]
    for x0, lab, val in ((18, "TIME", "%4.1f s" % rec_t[k]), (170, "PHASE", rec_ph[k]),
                         (360, "GRIPPER TO HANDLE", ("%.1f cm" % (100 * dd)) if np.isfinite(dd) else "—")):
        dr.text((bx + S(x0), by + S(12)), lab, font=fl, fill=(170, 178, 190, 255))
        dr.text((bx + S(x0), by + S(30)), val, font=fv, fill=(255, 255, 255, 255))
    dr.text((bx + S(18), by + S(76)), NOTE[rec_ph[k]], font=fs, fill=(255, 214, 140, 255))
    # phase strip, bottom right
    px0, py0, pw, ph = w - S(24) - S(4 * 104 + 3 * 6 + 32), h - S(128), S(104), S(34)
    dr.rectangle([px0, py0, w - S(24), h - S(22)], fill=(6, 9, 16, 160))
    dr.text((px0 + S(16), py0 + S(12)), "CONTROLLER PHASE", font=fl, fill=(170, 178, 190, 255))
    cur = PHASES.index(rec_ph[k])
    for i, nm in enumerate(PHASES):
        x = px0 + S(16) + i * (pw + S(6)); y = py0 + S(40)
        if i == cur:
            dr.rectangle([x, y, x + pw, y + ph], fill=(255, 255, 255, 235))
            col = (10, 14, 22, 255)
        else:
            dr.rectangle([x, y, x + pw, y + ph], outline=(200, 205, 215, 200) if i < cur else (120, 126, 136, 200),
                         width=max(1, S(2)))
            col = (200, 205, 215, 255) if i < cur else (120, 126, 136, 255)
        dr.text((x + pw / 2, y + ph / 2), nm, font=fp, fill=col, anchor="mm")
    dr.text((w - S(24), S(22)), "Earth texture: NASA Visible Earth", font=fc, fill=(200, 205, 215, 190), anchor="ra")
    return np.asarray(Image.alpha_composite(im, lay).convert("RGB"))


W, H = 1280, 720
rend = mujoco.Renderer(m, height=H, width=W, max_geom=3000)
cam = mujoco.MjvCamera()
if "--test" in sys.argv:                     # one still only (layout check)
    kg = int(np.searchsorted(rec_t, t_close + 0.4))
    d.qpos[:] = rec_q[kg]; mujoco.mj_forward(m, d); camera_for(16.2, cam)
    rhd = mujoco.Renderer(m, height=1080, width=1920, max_geom=3000); rhd.update_scene(d, camera=cam)
    Image.fromarray(overlay(rhd.render(), kg, scale=1.5)).save(out + "_TEST_grasp.png")
    sys.exit("test still written: " + out + "_TEST_grasp.png")
mp4 = iio.get_writer(out + ".mp4", fps=FPS, codec="libx264", quality=8, pixelformat="yuv420p", macro_block_size=16)
ng, max_dev = 0, 0.0
for i, (k, tau) in enumerate(zip(idx, taus)):
    d.qpos[:] = rec_q[k]; mujoco.mj_forward(m, d)
    if np.isfinite(rec_d[k]):
        hdl = d.xpos[bt] + d.xmat[bt].reshape(3, 3) @ SC.PB
        max_dev = max(max_dev, abs(np.linalg.norm(d.site_xpos[tcp_id] - hdl) - rec_d[k]))
    camera_for(tau, cam)
    rend.update_scene(d, camera=cam)
    fr = overlay(rend.render(), k)
    mp4.append_data(fr)
    if i % 3 == 0:
        Image.fromarray(fr).save(os.path.join(out + "_gifframes", "f%04d.png" % ng)); ng += 1
for _ in range(40):
    mp4.append_data(fr)
mp4.close()
Image.fromarray(fr).save(os.path.join(out + "_gifframes", "f%04d.png" % ng))
kg = int(np.searchsorted(rec_t, t_close + 0.4))
d.qpos[:] = rec_q[kg]; mujoco.mj_forward(m, d); camera_for(16.2, cam)
rhd = mujoco.Renderer(m, height=1080, width=1920, max_geom=3000); rhd.update_scene(d, camera=cam)
Image.fromarray(overlay(rhd.render(), kg, scale=1.5)).save(out + "_grasp.png")
print("frames %d | max |replayed - recorded TCP-handle distance| = %.2e m | %s.mp4 %.1f MB" % (
    len(idx), max_dev, out, os.path.getsize(out + ".mp4") / 2**20))
