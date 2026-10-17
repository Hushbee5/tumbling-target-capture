"""ROS 2 (Humble, RoboStack) co-simulation of the capture-phase prototype (gap F).

Two processes, one per role:
  python ros2_capture_nodes.py plant <scenario_id> <out_dir>   MuJoCo physics (capture_core.Plant): publishes the
                                                                measurement, applies commands, monitors contacts
  python ros2_capture_nodes.py controller <out_dir>            capture_core.Controller: computes the commands

Deterministic LOCKSTEP per control period k (t_k = k * 10 ms, header stamps in integer nanoseconds):
  plant      -> /capture/target/odom, /capture/bus/odom (nav_msgs/Odometry, frame 'lvlh', child 'target'/'bus',
                twist in the CHILD frame per REP-105), /capture/joint_states (sensor_msgs/JointState),
                /capture/wrist_wrench (geometry_msgs/WrenchStamped, frame 'wrist_ft')                 [stamp t_k]
  controller -> /capture/bus_cmd (WrenchStamped, frame 'bus'), /capture/joint_cmd (JointState: velocity = joint-rate
                command for j1..j6, position = finger target for jf_l, jf_r)                         [stamp t_k]
  plant      -> /capture/contact (std_msgs/String, JSON: window [t_k, t_k+1) contact flags)
  controller -> /capture/status (std_msgs/String, JSON: phase, timeline, diagnostics, done flag)
Units SI (m, m/s, rad, rad/s, N, N m). The plant refuses a command whose stamp differs from its measurement stamp.
Outputs (never overwritten): <out_dir>/<scenario>_ros2.json/.npz (plant side), <out_dir>/ros2_controller_log.json."""
import json
import os
import sys
import time

import numpy as np
import rclpy
from geometry_msgs.msg import WrenchStamped
from nav_msgs.msg import Odometry
from rclpy.executors import SingleThreadedExecutor
from rclpy.node import Node
from sensor_msgs.msg import JointState
from std_msgs.msg import String

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import capture_core as CC  # noqa: E402
import sim_capture as SC  # noqa: E402

JN = ["j1", "j2", "j3", "j4", "j5", "j6", "jf_l", "jf_r"]
m = SC.m
QADR = {n: SC.m.jnt_qposadr[SC.m.joint(n).id] for n in JN}
VADR = {n: SC.m.jnt_dofadr[SC.m.joint(n).id] for n in JN}
TIMEOUT = 60.0


def stamp_ns(k):
    return int(k) * 10_000_000


def set_stamp(h, ns, frame):
    h.stamp.sec = ns // 1_000_000_000
    h.stamp.nanosec = ns % 1_000_000_000
    h.frame_id = frame


def get_ns(h):
    return h.stamp.sec * 1_000_000_000 + h.stamp.nanosec


def odom_msg(ns, child, pos, quat_wxyz, R, v_world, w_body):
    o = Odometry()
    set_stamp(o.header, ns, "lvlh"); o.child_frame_id = child
    o.pose.pose.position.x, o.pose.pose.position.y, o.pose.pose.position.z = map(float, pos)
    o.pose.pose.orientation.w, o.pose.pose.orientation.x, o.pose.pose.orientation.y, o.pose.pose.orientation.z = \
        map(float, quat_wxyz)
    vl = R.T @ v_world                                     # REP-105: twist expressed in the child frame
    o.twist.twist.linear.x, o.twist.twist.linear.y, o.twist.twist.linear.z = map(float, vl)
    o.twist.twist.angular.x, o.twist.twist.angular.y, o.twist.twist.angular.z = map(float, w_body)
    return o


def odom_parse(o):
    p = np.array([o.pose.pose.position.x, o.pose.pose.position.y, o.pose.pose.position.z])
    q = np.array([o.pose.pose.orientation.w, o.pose.pose.orientation.x, o.pose.pose.orientation.y,
                  o.pose.pose.orientation.z])
    R = SC.mat(q)
    vl = np.array([o.twist.twist.linear.x, o.twist.twist.linear.y, o.twist.twist.linear.z])
    wb = np.array([o.twist.twist.angular.x, o.twist.twist.angular.y, o.twist.twist.angular.z])
    return p, q, R @ vl, wb


class Inbox(Node):
    def __init__(self, name, subs):
        super().__init__(name)
        self.box = {}
        for topic, typ in subs:
            self.create_subscription(typ, topic, lambda msg, t=topic: self.box.setdefault(t, []).append(msg), 50)

    def take(self, ex, topic, pred):
        t0 = time.time()
        while time.time() - t0 < TIMEOUT:
            for i, msg in enumerate(self.box.get(topic, [])):
                if pred(msg):
                    return self.box[topic].pop(i)
            ex.spin_once(timeout_sec=0.01)
        raise TimeoutError("timeout waiting for %s" % topic)


def plant_main(scn_id, out_dir):
    scn = [s for s in SC.scenarios() if s["id"] == scn_id][0]
    fj = os.path.join(out_dir, scn_id + "_ros2.json"); fz = os.path.join(out_dir, scn_id + "_ros2.npz")
    assert not os.path.exists(fj) and not os.path.exists(fz), "exists"
    rclpy.init()
    node = Inbox("capture_plant", [("/capture/bus_cmd", WrenchStamped), ("/capture/joint_cmd", JointState),
                                   ("/capture/status", String)])
    pubs = {t: node.create_publisher(T, t, 50) for t, T in (("/capture/target/odom", Odometry),
                                                            ("/capture/bus/odom", Odometry),
                                                            ("/capture/joint_states", JointState),
                                                            ("/capture/wrist_wrench", WrenchStamped),
                                                            ("/capture/contact", String))}
    ex = SingleThreadedExecutor(); ex.add_node(node)
    t0w = time.time()
    plant = CC.Plant(scn)
    time.sleep(2.0)                                         # discovery
    H = {k: [] for k in ("t", "phase", "e_p", "e_o", "v_rel", "s", "bus_e", "bus_sat", "tau_sat", "fl", "fr",
                         "f_pad", "wrist_f", "wrist_t", "clear_tcp", "forbidden")}
    checks = {"stamp_mismatch": 0, "frame_errors": 0, "max_thrust_N": 0.0, "max_wheel_Nm": 0.0, "max_qd_cmd": 0.0,
              "steps": 0}
    forbidden_all, peak_pad, hold_n, hold_both = [], 0.0, 0, 0
    tl, status = {}, None
    for k in range(int(round(SC.T_MAX / SC.DT_CTRL))):
        ns = stamp_ns(k); t = k * SC.DT_CTRL
        d = plant.d
        for name, bid, adr in (("target", SC.BID["target"], SC.QT), ("bus", SC.BID["bus"], SC.QB)):
            vadr = SC.VT if name == "target" else SC.VB
            R = SC.mat(d.qpos[adr + 3:adr + 7])
            pubs["/capture/%s/odom" % name].publish(odom_msg(ns, name, d.qpos[adr:adr + 3], d.qpos[adr + 3:adr + 7], R,
                                                             d.qvel[vadr:vadr + 3], d.qvel[vadr + 3:vadr + 6]))
        js = JointState(); set_stamp(js.header, ns, "servicer")
        js.name = JN
        js.position = [float(d.qpos[QADR[n]]) for n in JN]; js.velocity = [float(d.qvel[VADR[n]]) for n in JN]
        pubs["/capture/joint_states"].publish(js)
        w = WrenchStamped(); set_stamp(w.header, ns, "wrist_ft")
        w.wrench.force.x, w.wrench.force.y, w.wrench.force.z = map(float, d.sensordata[0:3])
        w.wrench.torque.x, w.wrench.torque.y, w.wrench.torque.z = map(float, d.sensordata[3:6])
        pubs["/capture/wrist_wrench"].publish(w)
        bc = node.take(ex, "/capture/bus_cmd", lambda msg: get_ns(msg.header) == ns)
        jc = node.take(ex, "/capture/joint_cmd", lambda msg: get_ns(msg.header) == ns)
        checks["frame_errors"] += int(bc.header.frame_id != "bus") + int(jc.header.frame_id != "servicer")
        u_bus = np.array([bc.wrench.force.x, bc.wrench.force.y, bc.wrench.force.z,
                          bc.wrench.torque.x, bc.wrench.torque.y, bc.wrench.torque.z])
        qd = np.array(jc.velocity[:6]); grip = float(jc.position[6])
        checks["max_thrust_N"] = max(checks["max_thrust_N"], float(np.max(np.abs(u_bus[:3]))))
        checks["max_wheel_Nm"] = max(checks["max_wheel_Nm"], float(np.max(np.abs(u_bus[3:]))))
        checks["max_qd_cmd"] = max(checks["max_qd_cmd"], float(np.max(np.abs(qd))))
        ci = plant.apply({"u_bus": u_bus, "qd_cmd": qd, "grip": grip})
        if ci["forbidden"]:
            forbidden_all += [(round(t, 3), x) for x in ci["forbidden"]]
        peak_pad = max(peak_pad, ci["f_pad"])
        pubs["/capture/contact"].publish(String(data=json.dumps({"ns": ns, "fl": ci["fl"], "fr": ci["fr"]})))
        st = node.take(ex, "/capture/status", lambda msg: json.loads(msg.data)["ns"] == ns)
        status = json.loads(st.data)
        tl = status["tl"]
        if status["phase"] == "HOLD":
            hold_n += 1; hold_both += int(ci["fl"] and ci["fr"])
        dg = status["diag"]; sd = plant.d.sensordata
        for key, val in (("t", t), ("phase", status["phase"]), ("e_p", dg["e_p"]), ("e_o", dg["e_o"]),
                         ("v_rel", dg["v_rel"]), ("s", dg["s"]), ("bus_e", dg["bus_e"]), ("bus_sat", dg["bus_sat"]),
                         ("tau_sat", ci["tau_sat"]), ("fl", ci["fl"]), ("fr", ci["fr"]), ("f_pad", ci["f_pad"]),
                         ("wrist_f", np.linalg.norm(sd[0:3])), ("wrist_t", np.linalg.norm(sd[3:6])),
                         ("clear_tcp", dg["clear_tcp"]), ("forbidden", bool(ci["forbidden"]))):
            H[key].append(val)
        checks["steps"] += 1
        if status["done"]:
            break

    class _Ctl:                                              # timeline carrier for CC.evaluate
        pass
    c = _Ctl(); c.tl = tl
    S = CC.evaluate(scn, plant, c, H, peak_pad, forbidden_all, hold_n, hold_both, time.time() - t0w,
                    extra={"transport": "ROS 2 Humble (RoboStack) lockstep, ROS_LOCALHOST_ONLY=1", "ros2_checks": checks})
    with open(fj, "x", encoding="utf-8") as fh:
        json.dump(S, fh, indent=1)
    np.savez_compressed(fz, **{kk: np.array(v) for kk, v in H.items()})
    print("PLANT %s -> %s  steps %d  checks %s  wall %.0f s" % (scn_id, S["outcome"], checks["steps"], checks, S["wall_s"]),
          flush=True)
    rclpy.shutdown()


def controller_main(out_dir):
    rclpy.init()
    node = Inbox("capture_controller", [("/capture/target/odom", Odometry), ("/capture/bus/odom", Odometry),
                                        ("/capture/joint_states", JointState), ("/capture/wrist_wrench", WrenchStamped),
                                        ("/capture/contact", String)])
    pb = node.create_publisher(WrenchStamped, "/capture/bus_cmd", 50)
    pj = node.create_publisher(JointState, "/capture/joint_cmd", 50)
    ps = node.create_publisher(String, "/capture/status", 50)
    ex = SingleThreadedExecutor(); ex.add_node(node)
    ctl = CC.Controller()
    log = {"frames_seen": set(), "steps": 0}
    k = 0
    while True:
        ns = stamp_ns(k); t = k * SC.DT_CTRL
        try:
            ot = node.take(ex, "/capture/target/odom", lambda msg: get_ns(msg.header) == ns)
        except TimeoutError:
            break
        ob = node.take(ex, "/capture/bus/odom", lambda msg: get_ns(msg.header) == ns)
        js = node.take(ex, "/capture/joint_states", lambda msg: get_ns(msg.header) == ns)
        ww = node.take(ex, "/capture/wrist_wrench", lambda msg: get_ns(msg.header) == ns)
        for msg in (ot, ob):
            log["frames_seen"].add("%s->%s" % (msg.header.frame_id, msg.child_frame_id))
        log["frames_seen"].add(js.header.frame_id); log["frames_seen"].add(ww.header.frame_id)
        qpos = np.zeros(m.nq); qvel = np.zeros(m.nv)
        for o, qa, va in ((ot, SC.QT, SC.VT), (ob, SC.QB, SC.VB)):
            p, q, v_w, w_b = odom_parse(o)
            qpos[qa:qa + 3] = p; qpos[qa + 3:qa + 7] = q; qvel[va:va + 3] = v_w; qvel[va + 3:va + 6] = w_b
        for i, n in enumerate(js.name):
            qpos[QADR[n]] = js.position[i]; qvel[VADR[n]] = js.velocity[i]
        sens = np.array([ww.wrench.force.x, ww.wrench.force.y, ww.wrench.force.z,
                         ww.wrench.torque.x, ww.wrench.torque.y, ww.wrench.torque.z])
        cmd, dg = ctl.step({"qpos": qpos, "qvel": qvel, "sensordata": sens}, t)
        b = WrenchStamped(); set_stamp(b.header, ns, "bus")
        b.wrench.force.x, b.wrench.force.y, b.wrench.force.z = map(float, cmd["u_bus"][:3])
        b.wrench.torque.x, b.wrench.torque.y, b.wrench.torque.z = map(float, cmd["u_bus"][3:])
        pb.publish(b)
        j = JointState(); set_stamp(j.header, ns, "servicer")
        j.name = JN
        j.velocity = [float(x) for x in cmd["qd_cmd"]] + [0.0, 0.0]
        j.position = [0.0] * 6 + [float(cmd["grip"])] * 2
        pj.publish(j)
        c = node.take(ex, "/capture/contact", lambda msg: json.loads(msg.data)["ns"] == ns)
        ci = json.loads(c.data)
        ctl.contact_update(ci["fl"], ci["fr"], t)
        done = ctl.phase == "HOLD" and t - ctl.tl["HOLD"] >= SC.T_HOLD
        ps.publish(String(data=json.dumps({"ns": ns, "phase": ctl.phase, "tl": ctl.tl, "done": bool(done),
                                           "diag": {kk: (bool(v) if isinstance(v, (bool, np.bool_)) else float(v))
                                                    for kk, v in dg.items()}})))
        log["steps"] += 1
        k += 1
        if done:
            break
    log["frames_seen"] = sorted(log["frames_seen"])
    with open(os.path.join(out_dir, "ros2_controller_log.json"), "x", encoding="utf-8") as fh:
        json.dump(log, fh, indent=1)
    print("CONTROLLER steps %d frames %s" % (log["steps"], log["frames_seen"]), flush=True)
    rclpy.shutdown()


if __name__ == "__main__":
    if sys.argv[1] == "plant":
        plant_main(sys.argv[2], sys.argv[3])
    else:
        controller_main(sys.argv[2])
