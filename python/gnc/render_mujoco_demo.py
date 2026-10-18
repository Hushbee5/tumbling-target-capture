"""Animation of the MuJoCo closed loop: two servicers start 10 m behind the target and are sent to a set point 3 m in
front of it, one with the HOCBF-QP safety filter (blue) and one with the MPC alone (grey). Both trajectories are first
simulated with mujoco_loop.run and then replayed for rendering; nothing is integrated during rendering.

Usage (from the repository root): python python/gnc/render_mujoco_demo.py <out.gif>"""
import os
import sys

import imageio.v2 as imageio
import mujoco
import numpy as np
from matplotlib import font_manager
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from gnc.mujoco_loop import run  # noqa: E402
from gnc.params import default_params  # noqa: E402

W, H = 880, 360
XML = """
<mujoco model="replay">
  <visual><global offwidth="{W}" offheight="{H}"/><headlight ambient="0.35 0.35 0.35" diffuse="0.6 0.6 0.6"/></visual>
  <worldbody>
    <camera name="top" pos="0 -3.6 -8.2" xyaxes="0 1 0 1 0 0" fovy="45"/>
    <geom type="sphere" size="{r_safe}" rgba="0.9 0.2 0.2 0.28" contype="0" conaffinity="0"/>
    <geom type="box" size="0.4 0.4 0.4" rgba="0.85 0.68 0.25 1" contype="0" conaffinity="0"/>
    <geom type="sphere" size="0.06" pos="0 3 0" rgba="1 1 1 1" contype="0" conaffinity="0"/>
    <body name="filtered" mocap="true"><geom type="sphere" size="0.15" rgba="0.25 0.55 1 1" contype="0" conaffinity="0"/></body>
    <body name="mpc_only" mocap="true"><geom type="sphere" size="0.15" rgba="0.65 0.65 0.65 1" contype="0" conaffinity="0"/></body>
  </worldbody>
</mujoco>
"""


def add_dot(scene, pos, rgba, size=0.03):
    if scene.ngeom >= scene.maxgeom:
        return
    mujoco.mjv_initGeom(scene.geoms[scene.ngeom], mujoco.mjtGeom.mjGEOM_SPHERE, np.array([size, 0, 0]),
                        np.asarray(pos, float), np.eye(3).reshape(-1), np.asarray(rgba, np.float32))
    scene.ngeom += 1


def main(out_gif, T=600.0, every=30):
    p = default_params()
    x0 = np.array([0.0, -10.0, 0.0, 0.0, 0.0, 0.0])
    r_ref = [0.0, 3.0, 0.0]
    A = run(p, x0, r_ref, T, use_filter=True)["X"]
    B = run(p, x0, r_ref, T, use_filter=False)["X"]
    m = mujoco.MjModel.from_xml_string(XML.format(W=W, H=H, r_safe=p["r_safe"]))
    d = mujoco.MjData(m)
    ren = mujoco.Renderer(m, H, W, max_geom=4000)
    font = ImageFont.truetype(font_manager.findfont("DejaVu Sans"), 14)
    small = ImageFont.truetype(font_manager.findfont("DejaVu Sans"), 12)
    frames = []
    for k in range(0, len(A), every):
        d.mocap_pos[0], d.mocap_pos[1] = A[k, :3], B[k, :3]
        mujoco.mj_forward(m, d)
        ren.update_scene(d, camera="top")
        for j in range(0, k + 1, 10):
            add_dot(ren.scene, A[j, :3], (0.25, 0.55, 1, 0.9))
            add_dot(ren.scene, B[j, :3], (0.65, 0.65, 0.65, 0.7))
        img = Image.fromarray(ren.render())
        dr = ImageDraw.Draw(img)
        dr.text((14, 10), "t = %3.0f s" % (k * p["Ts"]), fill=(235, 235, 235), font=font)
        dr.text((14, 30), "blue: MPC + HOCBF-QP safety filter    grey: MPC only    red: keep-out sphere",
                fill=(200, 200, 200), font=small)
        dr.text((14, H - 22), "MuJoCo free body, Clohessy-Wiltshire terms at every RK4 stage; LVLH frame, top view",
                fill=(150, 150, 150), font=small)
        frames.append(np.asarray(img))
    frames += [frames[-1]] * 20
    imageio.mimsave(out_gif, frames, duration=0.06, loop=0)
    print("written", out_gif, len(frames), "frames")


if __name__ == "__main__":
    main(sys.argv[1])
