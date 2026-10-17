"""r5 (2026-10-05): same replay as render_approach.py, with the 8192-px NASA texture, fewer stars and an overlay in the
poster's engineering style (instrument readouts, line-swatch legend, no icons). GIF frames are written as PNGs to
<out>_gifframes/ so that the GIF can be assembled to a size budget afterwards (make_gif.py).
Approach animation of the paper's frozen 800 s run (r3 Section 5.5; alpha = 1e-3), for the presenter's iPoster.
READ-ONLY replay: every position and attitude comes from results/task4/final800/task4_final_800s_alpha1em3.mat
(frozen; read with h5py); nothing is simulated. MuJoCo is used only as a renderer (mocap bodies).
The script checks that the rendered servicer-to-capture-point distance equals the stored rho at every frame.
Outputs (never overwritten): <out>.mp4 (1280x720, 30 fps), <out>_preview.gif (640x360), <out>_handoff.png (1920x1080).
Usage: python render_approach.py <out_basename>"""
import os
import sys

import h5py
import imageio.v2 as iio
import mujoco
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FROZEN = r"results\task4\final800\task4_final_800s_alpha1em3.mat"
out = sys.argv[1]
for ext in (".mp4", "_handoff.png", "_gifframes"):
    assert not os.path.exists(out + ext), out + ext
os.makedirs(out + "_gifframes")

f = h5py.File(FROZEN, "r")
g = lambda p: np.array(f[p]).squeeze()
t = g("out/t"); X = np.array(f["out/X"]); qT = np.array(f["out/qT"]); act = g("out/active").astype(bool)
rho = g("out/rho"); n_orb = float(g("p_base/orbit/n")); pcb = g("p_base/target/p_cp_body")
r_safe = float(g("p_base/geom/r_safe")); r_tgt = float(g("p_base/geom/r_target")); s_cap = float(g("p_base/t4/s_cap"))
t_ho = float(g("out/handoff/t"))
k_ms = int(np.argmax(rho <= s_cap)); t_ms = float(t[k_ms])          # first sample within s_cap (milestone sample)
assert X.shape == (8001, 6) and qT.shape == (8001, 4)

XML = """
<mujoco model="approach_render">
  <statistic extent="5" center="0 0 0"/>
  <visual>
    <global offwidth="1920" offheight="1080" fovy="38"/>
    <quality shadowsize="4096" offsamples="8"/>
    <headlight ambient="0.16 0.16 0.18" diffuse="0.30 0.30 0.30" specular="0.05 0.05 0.05"/>
    <map znear="0.02" zfar="4000"/>
  </visual>
  <asset>
    <texture name="sky" type="skybox" builtin="gradient" rgb1="0.03 0.04 0.09" rgb2="0 0 0" width="1600" height="1600"
             mark="random" random="0.0006" markrgb="0.85 0.86 0.9"/>
    <texture name="earthtex" type="2d" file="land_shallow_topo_8192.png"/>
    <material name="earth" texture="earthtex" specular="0.05" shininess="0.05" emission="0.15"/>
    <mesh name="uvsphere" file="uvsphere.obj" scale="400 400 400"/>
    <texture name="tgt_tex" type="cube" file="tex_aluminium_panels.png"/>
    <material name="tgt" texture="tgt_tex" specular="0.45" shininess="0.5" rgba="0.9 0.9 0.92 1"/>
    <material name="gold" rgba="0.86 0.66 0.27 1" specular="0.7" shininess="0.7"/>
    <material name="panel" rgba="0.07 0.11 0.33 1" specular="0.9" shininess="0.95"/>
    <material name="keepout" rgba="1 0.25 0.2 0.12"/>
    <material name="commit" rgba="1 0.82 0.1 0.38"/>
  </asset>
  <worldbody>
    <light name="sun" directional="true" pos="0 0 20" dir="-0.45 0.55 -0.70" diffuse="1.0 0.98 0.92" specular="0.35 0.35 0.35" castshadow="true"/>
    <geom name="earth" type="mesh" mesh="uvsphere" material="earth" pos="-470 0 -430" euler="0.4 0.2 1.2" contype="0" conaffinity="0"/>
    <geom name="keepout" type="sphere" size="%(rs)g" material="keepout" contype="0" conaffinity="0"/>
    <body name="target" mocap="true">
      <geom type="sphere" size="%(rt)g" material="tgt" contype="0" conaffinity="0"/>
      <geom type="capsule" fromto="%(sx)g %(sy)g %(sz)g %(px)g %(py)g %(pz)g" size="0.014" rgba="0.82 0.84 0.88 1" contype="0" conaffinity="0"/>
      <geom type="sphere" pos="%(px)g %(py)g %(pz)g" size="0.028" rgba="0.1 0.62 1 1" contype="0" conaffinity="0"/>
      <geom name="commit" type="sphere" pos="%(px)g %(py)g %(pz)g" size="%(sc)g" material="commit" contype="0" conaffinity="0"/>
    </body>
    <body name="servicer" mocap="true">
      <geom type="box" size="0.12 0.12 0.12" material="gold" contype="0" conaffinity="0"/>
      <geom type="box" pos="0 0.27 0" size="0.008 0.14 0.085" material="panel" contype="0" conaffinity="0"/>
      <geom type="box" pos="0 -0.27 0" size="0.008 0.14 0.085" material="panel" contype="0" conaffinity="0"/>
      <geom type="capsule" fromto="0 0.12 0 0 0.14 0" size="0.01" rgba="0.8 0.8 0.8 1" contype="0" conaffinity="0"/>
    </body>
  </worldbody>
</mujoco>
"""
u = pcb / np.linalg.norm(pcb)
xml = XML % dict(rs=r_safe, rt=r_tgt, sc=s_cap, px=pcb[0], py=pcb[1], pz=pcb[2],
                 sx=0.95 * r_tgt * u[0], sy=0.95 * r_tgt * u[1], sz=0.95 * r_tgt * u[2])
xml_path = os.path.join(HERE, "approach_scene_r5.xml")
if not os.path.exists(xml_path):
    open(xml_path, "x", encoding="utf-8").write(xml)
assert open(xml_path, encoding="utf-8").read() == xml, "approach_scene.xml differs from this script's scene"
m = mujoco.MjModel.from_xml_path(xml_path)
d = mujoco.MjData(m)
mat_commit = mujoco.mj_name2id(m, mujoco.mjtObj.mjOBJ_MATERIAL, "commit")
bt, bs = m.body("target").mocapid[0], m.body("servicer").mocapid[0]


def qmul(a, b):
    w1, x1, y1, z1 = a; w2, x2, y2, z2 = b
    return np.array([w1*w2 - x1*x2 - y1*y2 - z1*z2, w1*x2 + x1*w2 + y1*z2 - z1*y2,
                     w1*y2 - x1*z2 + y1*w2 + z1*x2, w1*z2 + x1*y2 - y1*x2 + z1*w2])


def quat_target_L(k):                       # q_L = q_LI (x) q_T, R_LI = Rz(-n t), Hamilton scalar-first
    th = -n_orb * t[k]
    return qmul(np.array([np.cos(th / 2), 0, 0, np.sin(th / 2)]), qT[k] / np.linalg.norm(qT[k]))


# non-uniform video time: 0-560 s in 18 s, 560-660 s in 9 s, 660-800 s in 4 s (30 fps), then hold
FPS = 30
taus = np.concatenate([np.linspace(0, 560, 540, endpoint=False), np.linspace(560, 660, 270, endpoint=False),
                       np.linspace(660, 800, 121)])
ks = np.clip(np.round(taus / 0.1).astype(int), 0, 8000)
W, H = 1280, 720
rend = mujoco.Renderer(m, height=H, width=W, max_geom=6000)
rend_hd = mujoco.Renderer(m, height=1080, width=1920, max_geom=6000)
cam = mujoco.MjvCamera()
F = r"C:\Windows\Fonts"


def font(size, var="Regular"):
    fo = ImageFont.truetype(F + "/bahnschrift.ttf", size)
    fo.set_variation_by_name(var)
    return fo
trail_k = np.arange(0, 8001, 8)                                       # trail sample every 0.8 s
max_dev = 0.0


def setup(k, tau):
    global max_dev
    d.mocap_quat[bt] = quat_target_L(k)
    d.mocap_pos[bs] = X[k, :3]
    m.mat_rgba[mat_commit, 3] = 0.38 if t[k] < t_ho else 0.0           # commitment sphere vanishes at the handoff
    mujoco.mj_forward(m, d)
    pcp = d.xmat[m.body("target").id].reshape(3, 3) @ pcb
    max_dev = max(max_dev, abs(np.linalg.norm(X[k, :3] - pcp) - rho[k]))
    w = np.clip(tau / 420.0, 0, 1)
    rs = X[k, :3]
    cam.lookat[:] = (1 - w) * 0.5 * rs + w * 0.30 * rs
    cam.distance = float(np.interp(tau, [0, 300, 560, 640, 800], [16.0, 10.0, 5.2, 4.4, 4.4]))
    cam.azimuth = float(np.interp(tau, [0, 800], [196, 176]))
    cam.elevation = float(np.interp(tau, [0, 560, 800], [-12, -24, -28]))
    return pcp


def add_trail(scn, k):
    wid = 0.0022 * cam.distance
    js = np.arange(0, k + 1, 4)                                       # a segment every 0.4 s
    for a, b in zip(js[:-1], js[1:]):
        if scn.ngeom >= scn.maxgeom - 2:
            break
        c = [0.98, 0.55, 0.16, 1.0] if (a < 8000 and act[a]) else [0.45, 0.75, 1.0, 0.95]
        gm = scn.geoms[scn.ngeom]
        mujoco.mjv_initGeom(gm, mujoco.mjtGeom.mjGEOM_CAPSULE, np.zeros(3), np.zeros(3), np.eye(3).flatten(),
                            np.array(c, dtype=np.float32))
        mujoco.mjv_connector(gm, mujoco.mjtGeom.mjGEOM_CAPSULE, wid, X[a, :3], X[b, :3])
        scn.ngeom += 1


def spaced(dr, xy, txt, fo, fill, sp):
    x, y = xy
    for ch in txt:
        dr.text((x, y), ch, font=fo, fill=fill)
        x += dr.textlength(ch, font=fo) + sp


def overlay(img, k, tau, scale=1.0):
    im = Image.fromarray(img).convert("RGBA")
    lay = Image.new("RGBA", im.size, (0, 0, 0, 0)); dr = ImageDraw.Draw(lay)
    S = lambda v: int(round(v * scale)); w, h = im.size
    fk, ft, fl, fv, fs, fc = (font(S(16), "SemiBold"), font(S(34), "SemiBold"), font(S(15)), font(S(30), "SemiBold"),
                              font(S(17)), font(S(13)))
    title = "Terminal approach to a tumbling target"
    tw = dr.textlength(title, font=ft)
    dr.rectangle([S(24), S(22), S(24) + tw + S(36), S(112)], fill=(6, 9, 16, 150))
    spaced(dr, (S(42), S(34)), "WHAT THE PAPER EVALUATES  ·  FROZEN 800 s RUN, REPLAYED", fk, (225, 230, 240, 230), S(1.6))
    dr.line([S(42), S(60), S(42) + tw, S(60)], fill=(225, 230, 240, 120), width=max(1, S(1)))
    dr.text((S(42), S(66)), title, font=ft, fill=(255, 255, 255, 255))
    # instrument readouts, bottom left
    bx, by = S(24), h - S(128)
    dr.rectangle([bx, by, bx + S(580), h - S(22)], fill=(6, 9, 16, 160))
    dr.text((bx + S(18), by + S(12)), "TIME", font=fl, fill=(170, 178, 190, 255))
    dr.text((bx + S(18), by + S(30)), "%5.1f s" % t[k], font=fv, fill=(255, 255, 255, 255))
    dr.text((bx + S(190), by + S(12)), "RANGE TO CAPTURE POINT", font=fl, fill=(170, 178, 190, 255))
    dr.text((bx + S(190), by + S(30)), "%.3f m" % rho[k], font=fv, fill=(255, 255, 255, 255))
    if t[k] < t_ho:
        msg = "commitment sphere active; orange trail: the filter is acting"
    elif t[k] < t_ms:
        msg = "handoff at %.1f s: commitment sphere released" % t_ho
    else:
        msg = "proximity milestone at %.1f s: a controller event, not capture" % t_ms
    dr.text((bx + S(18), by + S(76)), msg, font=fs, fill=(255, 214, 140, 255))
    # legend with line swatches, bottom right
    lx, ly = w - S(392), h - S(128)
    dr.rectangle([lx, ly, w - S(24), h - S(22)], fill=(6, 9, 16, 160))
    items = (((236, 96, 72), "keep-out sphere, r = 0.70 m"), ((240, 200, 60), "commitment sphere, until the handoff"),
             ((250, 140, 40), "trail: filter modified the command"), ((115, 190, 255), "trail: MPC command unchanged"))
    for i, (c, lab) in enumerate(items):
        yy = ly + S(18) + S(22) * i
        dr.line([lx + S(16), yy + S(9), lx + S(44), yy + S(9)], fill=c + (255,), width=max(2, S(4)))
        dr.text((lx + S(56), yy), lab, font=fs, fill=(235, 238, 244, 255))
    dr.text((w - S(24), S(22)), "Earth texture: NASA Visible Earth", font=fc, fill=(200, 205, 215, 190), anchor="ra")
    return np.asarray(Image.alpha_composite(im, lay).convert("RGB"))


if "--test" in sys.argv:                     # one still only (layout check); the frame folder stays empty
    k = int(np.argmin(np.abs(t - (t_ho - 6.0)))); setup(k, 625.0)
    rend_hd.update_scene(d, camera=cam); add_trail(rend_hd.scene, k)
    Image.fromarray(overlay(rend_hd.render(), k, 625.0, scale=1.5)).save(out + "_TEST_handoff.png")
    sys.exit("test still written: " + out + "_TEST_handoff.png")
mp4 = iio.get_writer(out + ".mp4", fps=FPS, codec="libx264", quality=8, pixelformat="yuv420p", macro_block_size=16)
ng = 0
for i, (k, tau) in enumerate(zip(ks, taus)):
    setup(k, tau)
    rend.update_scene(d, camera=cam); add_trail(rend.scene, k)
    fr = overlay(rend.render(), k, tau)
    mp4.append_data(fr)
    if i % 3 == 0:
        Image.fromarray(fr).save(os.path.join(out + "_gifframes", "f%04d.png" % ng)); ng += 1
for _ in range(45):
    mp4.append_data(fr)
mp4.close()
Image.fromarray(fr).save(os.path.join(out + "_gifframes", "f%04d.png" % ng))
k = int(np.argmin(np.abs(t - (t_ho - 6.0))))
setup(k, 625.0)
rend_hd.update_scene(d, camera=cam); add_trail(rend_hd.scene, k)
Image.fromarray(overlay(rend_hd.render(), k, 625.0, scale=1.5)).save(out + "_handoff.png")
print("frames %d | max |rendered range - stored rho| = %.2e m | handoff %.1f s | milestone %.1f s | %s.mp4 %.1f MB" % (
    len(ks), max_dev, t_ho, t_ms, out, os.path.getsize(out + ".mp4") / 2**20))
