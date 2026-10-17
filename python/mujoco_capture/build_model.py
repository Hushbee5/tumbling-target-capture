"""Build the MuJoCo capture-phase model (gap D/E): free-floating servicer bus + 6-DOF arm + two-finger
gripper, and a free tumbling target with a capture handle. Writes capture_scene.xml and model_params.json
next to this file (refuses to overwrite). GENERIC RESEARCH MODEL, NOT FLIGHT HARDWARE.

Sources / modelling choices (all recorded in model_params.json):
  * Arm kinematics and link masses / centre-of-mass positions: Universal Robots UR5e published DH table
    (a, d, alpha; masses 3.761, 8.058, 2.846, 1.37, 1.3, 0.365 kg). Link inertia tensors are NOT published
    there; they are APPROXIMATED as solid cylinders of radius 0.045 m along each link segment (stated
    approximation). Joint torque limits 150/150/150/28/28/28 N m and speed limits 180 deg/s (UR5e data
    sheet values). The real UR5e is a terrestrial arm; it is used only as a sourced generic 6-DOF chain.
  * Servicer bus: generic 1 m cube, 300 kg, uniform-cube inertia 50 kg m^2 per axis (assumption).
    Thrust 3 N per axis = 0.01 m/s^2 for the 300 kg bus (the r3 actuator box), reaction-wheel torque
    0.2 N m per axis (assumption).
  * Target: as in r3 (Table 1): 100 kg, inertia diag(20, 25, 30) kg m^2, bounding sphere 0.50 m,
    capture point p_b = [0.8, 0.1, 0.0] m. The capture interface is modelled as a handle (cylinder,
    radius 0.02 m, half-length 0.06 m) centred at p_b with its axis along body z, on a stalk.
  * Gripper: two prismatic fingers (0.1 kg each, stroke 0-0.04 m, grip force limit 60 N), friction 0.8.
  * Environment: zero gravity; the Clohessy-Wiltshire terms are applied separately by the simulator
    (the world frame is the target-centred LVLH frame), see sim_capture.py.
Collision groups (contype / conaffinity bits): 1 target body+stalk, 2 handle, 4 bus+arm links, 8 fingers.
Allowed contact: fingers <-> handle. Any other contact pair involving the target, or arm/bus self contact,
is a VIOLATION counted by the simulator."""
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
XML = os.path.join(HERE, "capture_scene.xml")
PJS = os.path.join(HERE, "model_params.json")
for f in (XML, PJS):
    if os.path.exists(f):
        sys.exit("STOP: exists " + f)

# --- UR5e DH (standard convention) -------------------------------------------------------------
a = [0.0, -0.425, -0.3922, 0.0, 0.0, 0.0]
d = [0.1625, 0.0, 0.0, 0.1333, 0.0997, 0.0996]
alpha = [math.pi / 2, 0.0, 0.0, math.pi / 2, -math.pi / 2, 0.0]
mass = [3.761, 8.058, 2.846, 1.37, 1.3, 0.365]
com_dh = [[0.0, -0.02561, 0.00193], [0.2125, 0.0, 0.11336], [0.15, 0.0, 0.0265],
          [0.0, -0.0018, 0.01634], [0.0, 0.0018, 0.01634], [0.0, 0.0, -0.001159]]
tau_max = [150.0, 150.0, 150.0, 28.0, 28.0, 28.0]
qd_max = [math.pi] * 6
R_LINK = 0.045


def rx(t):
    c, s = math.cos(t), math.sin(t)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def quat_of(R):
    w = math.sqrt(max(0.0, 1 + R[0, 0] + R[1, 1] + R[2, 2])) / 2
    if w > 1e-8:
        return [w, (R[2, 1] - R[1, 2]) / (4 * w), (R[0, 2] - R[2, 0]) / (4 * w), (R[1, 0] - R[0, 1]) / (4 * w)]
    # 180-degree rotations (not used by this table except alpha = pi)
    x = math.sqrt(max(0.0, 1 + R[0, 0] - R[1, 1] - R[2, 2])) / 2
    return [0.0, x, R[0, 1] / (4 * x), R[0, 2] / (4 * x)]


def fmt(v):
    return " ".join("%.9g" % x for x in v)


def cyl_inertia(m, seg, r=R_LINK):
    L = float(np.linalg.norm(seg))
    u = seg / L if L > 1e-9 else np.array([0, 0, 1.0])
    It = m * (3 * r * r + L * L) / 12.0
    Ia = m * r * r / 2.0
    I = Ia * np.outer(u, u) + It * (np.eye(3) - np.outer(u, u))
    return [I[0, 0], I[1, 1], I[2, 2], I[0, 1], I[0, 2], I[1, 2]]


# --- arm chain XML -----------------------------------------------------------------------------
def arm_xml():
    out, close = [], []
    ind = "        "
    for i in range(6):
        # body i: joint i about local z; the DH fixed transform of row i leads to body i+1
        off = np.array([a[i], 0.0, d[i]])
        Rf = rx(alpha[i])
        com = off + Rf @ np.array(com_dh[i])
        seg = off if np.linalg.norm(off) > 1e-9 else Rf @ np.array([0, 0, 0.05])
        I = cyl_inertia(mass[i], seg)
        out.append('%s<body name="link%d">' % (ind, i + 1))
        out.append('%s  <joint name="j%d" type="hinge" axis="0 0 1" range="-6.2832 6.2832" damping="0.0"/>'
                   % (ind, i + 1))
        out.append('%s  <inertial pos="%s" mass="%.6g" fullinertia="%s"/>' % (ind, fmt(com), mass[i], fmt(I)))
        if np.linalg.norm(off) > 1e-9:
            out.append('%s  <geom name="g_link%d" type="capsule" fromto="0 0 0 %s" size="%.3f" contype="4" '
                       'conaffinity="13" rgba="0.6 0.6 0.65 1" mass="0"/>' % (ind, i + 1, fmt(off), R_LINK))
        else:
            out.append('%s  <geom name="g_link%d" type="sphere" size="%.3f" contype="4" conaffinity="13" '
                       'rgba="0.6 0.6 0.65 1" mass="0"/>' % (ind, i + 1, R_LINK))
        out.append('%s  <body name="frame%d" pos="%s" quat="%s">' % (ind, i + 1, fmt(off), fmt(quat_of(Rf))))
        close.append('%s  </body>' % ind)
        close.append('%s</body>' % ind)
        ind += "    "
    # gripper on the flange (frame 6): palm + two fingers along local y, TCP 0.12 m along z
    g = ind
    out += [
        '%s<body name="gripper">' % g,
        '%s  <inertial pos="0 0 0.03" mass="0.8" diaginertia="0.002 0.002 0.001"/>' % g,
        '%s  <geom name="g_palm" type="box" size="0.04 0.05 0.02" pos="0 0 0.02" contype="8" conaffinity="11" '
        'rgba="0.3 0.3 0.35 1" mass="0"/>' % g,
        '%s  <site name="wrist_ft" pos="0 0 0" size="0.01"/>' % g,
        '%s  <site name="tcp" pos="0 0 0.12" size="0.008" rgba="1 0 0 1"/>' % g,
        '%s  <body name="finger_l" pos="0 0.04 0.09">' % g,
        '%s    <joint name="jf_l" type="slide" axis="0 -1 0" range="0 0.04" damping="5"/>' % g,
        '%s    <inertial pos="0 0 0" mass="0.1" diaginertia="2e-5 2e-5 1e-5"/>' % g,
        '%s    <geom name="g_finger_l" type="box" size="0.012 0.006 0.035" contype="8" conaffinity="11" '
        'friction="0.8 0.005 0.0001" rgba="0.8 0.5 0.2 1" mass="0"/>' % g,
        '%s  </body>' % g,
        '%s  <body name="finger_r" pos="0 -0.04 0.09">' % g,
        '%s    <joint name="jf_r" type="slide" axis="0 1 0" range="0 0.04" damping="5"/>' % g,
        '%s    <inertial pos="0 0 0" mass="0.1" diaginertia="2e-5 2e-5 1e-5"/>' % g,
        '%s    <geom name="g_finger_r" type="box" size="0.012 0.006 0.035" contype="8" conaffinity="11" '
        'friction="0.8 0.005 0.0001" rgba="0.8 0.5 0.2 1" mass="0"/>' % g,
        '%s  </body>' % g,
        '%s</body>' % g,
    ]
    return "\n".join(out + close[::-1])


p_b = np.array([0.8, 0.1, 0.0])
u_r = p_b / np.linalg.norm(p_b)
stalk_from = 0.49 * u_r
stalk_to = (np.linalg.norm(p_b) - 0.02) * u_r

xml = """<mujoco model="capture_scene">
  <!-- GENERIC RESEARCH MODEL, NOT FLIGHT HARDWARE. Generated by build_model.py. -->
  <compiler angle="radian" autolimits="true"/>
  <option timestep="0.001" gravity="0 0 0" integrator="RK4" cone="elliptic" impratio="10">
    <flag energy="enable"/>
  </option>
  <default>
    <geom solref="0.004 1" solimp="0.95 0.99 0.001"/>
  </default>
  <worldbody>
    <body name="target" pos="0 0 0">
      <freejoint name="target_free"/>
      <inertial pos="0 0 0" mass="100" diaginertia="20 25 30"/>
      <geom name="g_target" type="sphere" size="0.5" contype="1" conaffinity="12" rgba="0.75 0.7 0.5 1" mass="0"/>
      <geom name="g_stalk" type="capsule" fromto="{sf} {st}" size="0.015" contype="1" conaffinity="12"
            rgba="0.6 0.6 0.5 1" mass="0"/>
      <geom name="g_handle" type="capsule" fromto="{h0} {h1}" size="0.02" contype="2" conaffinity="8"
            friction="0.8 0.005 0.0001" rgba="0.2 0.6 0.9 1" mass="0"/>
      <site name="capture_point" pos="{pb}" size="0.01" rgba="0 0 1 1"/>
    </body>
    <body name="bus" pos="-1.9 0 0">
      <freejoint name="bus_free"/>
      <inertial pos="0 0 0" mass="300" diaginertia="50 50 50"/>
      <geom name="g_bus" type="box" size="0.5 0.5 0.5" contype="4" conaffinity="13" rgba="0.4 0.45 0.5 1" mass="0"/>
      <site name="bus_cm" pos="0 0 0" size="0.02"/>
      <body name="arm_base" pos="0.5 0 0" euler="0 1.5707963267948966 0">
{arm}
      </body>
    </body>
  </worldbody>
  <contact>
    <exclude body1="bus" body2="link1"/>
  </contact>
  <actuator>
    <motor name="bus_fx" site="bus_cm" gear="1 0 0 0 0 0" ctrlrange="-3 3"/>
    <motor name="bus_fy" site="bus_cm" gear="0 1 0 0 0 0" ctrlrange="-3 3"/>
    <motor name="bus_fz" site="bus_cm" gear="0 0 1 0 0 0" ctrlrange="-3 3"/>
    <motor name="bus_tx" site="bus_cm" gear="0 0 0 1 0 0" ctrlrange="-0.2 0.2"/>
    <motor name="bus_ty" site="bus_cm" gear="0 0 0 0 1 0" ctrlrange="-0.2 0.2"/>
    <motor name="bus_tz" site="bus_cm" gear="0 0 0 0 0 1" ctrlrange="-0.2 0.2"/>
{joint_motors}
    <position name="grip_l" joint="jf_l" kp="400" ctrlrange="0 0.04" forcerange="-60 60"/>
    <position name="grip_r" joint="jf_r" kp="400" ctrlrange="0 0.04" forcerange="-60 60"/>
  </actuator>
  <sensor>
    <force name="wrist_force" site="wrist_ft"/>
    <torque name="wrist_torque" site="wrist_ft"/>
  </sensor>
</mujoco>
""".format(sf=fmt(stalk_from), st=fmt(stalk_to), h0=fmt(p_b - np.array([0, 0, 0.06])),
           h1=fmt(p_b + np.array([0, 0, 0.06])), pb=fmt(p_b), arm=arm_xml(),
           joint_motors="\n".join('    <motor name="tau%d" joint="j%d" ctrlrange="%g %g"/>' % (i + 1, i + 1, -tau_max[i],
                                                                                            tau_max[i]) for i in range(6)))

params = {
    "status": "GENERIC RESEARCH MODEL, NOT FLIGHT HARDWARE",
    "arm": {"source": "UR5e published DH table (kinematics, link masses, CoM); inertia: solid-cylinder "
                      "approximation r=0.045 m (assumption); limits: UR5e data sheet",
            "a": a, "d": d, "alpha": alpha, "mass": mass, "com_dh": com_dh, "tau_max": tau_max,
            "qd_max_rad_s": qd_max, "link_radius_m": R_LINK},
    "gripper": {"mass_kg": 1.0, "stroke_m": 0.04, "grip_force_limit_N": 60, "friction": 0.8,
                "tcp_offset_m": 0.12},
    "bus": {"mass_kg": 300, "inertia_kgm2": [50, 50, 50], "size_m": 1.0, "thrust_N_per_axis": 3.0,
            "wheel_torque_Nm_per_axis": 0.2, "source": "assumption (generic small servicer)"},
    "target": {"mass_kg": 100, "inertia_kgm2": [20, 25, 30], "radius_m": 0.5, "p_b_m": p_b.tolist(),
               "handle": {"radius_m": 0.02, "half_length_m": 0.06, "axis_body": [0, 0, 1]},
               "source": "r3 Table 1"},
    "sim": {"timestep_s": 0.001, "integrator": "RK4 (model check M2: momentum drift <= 1e-9 at 1 ms; implicitfast drifts)", "gravity": [0, 0, 0],
            "orbital_terms": "Clohessy-Wiltshire translational terms applied by sim_capture.py "
                             "(world = target-centred LVLH); rotating-frame torques neglected (n << |w|)"},
}
with open(XML, "x", encoding="utf-8", newline="\n") as fh:
    fh.write(xml)
with open(PJS, "x", encoding="utf-8", newline="\n") as fh:
    json.dump(params, fh, indent=2)
print("written", XML, "and", PJS)
