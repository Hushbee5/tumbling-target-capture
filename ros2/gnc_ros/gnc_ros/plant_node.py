"""Relative-motion plant: exact zero-order-hold Clohessy-Wiltshire step at Ts, advanced in lockstep with the controller.
At the end of the run it writes the state and command histories to the JSON file given by the out_file parameter."""
import json

import numpy as np
import rclpy
from geometry_msgs.msg import AccelStamped
from nav_msgs.msg import Odometry
from rclpy.node import Node

from gnc import cw_matrices, default_params
from gnc_ros import TS_NS, from_stamp, to_stamp


class Plant(Node):
    def __init__(self):
        super().__init__("plant")
        self.declare_parameter("x0", [0.0, -10.0, 0.0, 0.0, 0.0, 0.0])
        self.declare_parameter("duration", 200.0)
        self.declare_parameter("out_file", "")
        p = default_params()
        _, _, self.Ad, self.Bd = cw_matrices(p["n"], p["Ts"])
        self.x = np.array(self.get_parameter("x0").value, dtype=float)
        self.K = int(round(self.get_parameter("duration").value / p["Ts"]))
        self.out_file = self.get_parameter("out_file").value
        self.k = 0
        self.X = [self.x.tolist()]
        self.U = []
        self.stale = 0
        self.done = False
        self.pub = self.create_publisher(Odometry, "/approach/state", 10)
        self.create_subscription(AccelStamped, "/approach/accel_cmd", self.on_cmd, 10)
        self.create_timer(0.5, self.publish_state)          # re-sends the current state until the controller answers
        self.publish_state()

    def publish_state(self):
        if self.done:
            return
        o = Odometry()
        to_stamp(o.header, self.k * TS_NS)
        o.header.frame_id = "lvlh"
        o.child_frame_id = "servicer"
        o.pose.pose.position.x, o.pose.pose.position.y, o.pose.pose.position.z = map(float, self.x[:3])
        o.pose.pose.orientation.w = 1.0
        o.twist.twist.linear.x, o.twist.twist.linear.y, o.twist.twist.linear.z = map(float, self.x[3:])
        self.pub.publish(o)

    def on_cmd(self, msg):
        if self.done:
            return
        if from_stamp(msg.header) != self.k * TS_NS:
            self.stale += 1                                  # answer to a re-sent state: ignored
            return
        a = msg.accel.linear
        u = np.array([a.x, a.y, a.z])
        self.x = self.Ad @ self.x + self.Bd @ u
        self.U.append(u.tolist())
        self.X.append(self.x.tolist())
        self.k += 1
        if self.k >= self.K:
            self.finish()
        else:
            self.publish_state()

    def finish(self):
        self.done = True
        if self.out_file:
            with open(self.out_file, "w", encoding="utf-8") as fh:
                json.dump({"X": self.X, "U": self.U, "stale_commands": self.stale}, fh)
        self.get_logger().info("run complete: %d steps, final position %s, %d stale commands"
                               % (self.k, np.round(self.x[:3], 3).tolist(), self.stale))


def main():
    rclpy.init()
    node = Plant()
    while rclpy.ok() and not node.done:
        rclpy.spin_once(node, timeout_sec=0.1)
    node.destroy_node()
    rclpy.shutdown()


if __name__ == "__main__":
    main()
