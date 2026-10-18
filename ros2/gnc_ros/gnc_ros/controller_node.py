"""Controller: preview MPC towards a fixed set point, then the HOCBF-QP keep-out filter (python/gnc). Answers every
state message with a command carrying the same stamp."""
import numpy as np
import rclpy
from geometry_msgs.msg import AccelStamped
from nav_msgs.msg import Odometry
from rclpy.node import Node

from gnc import CondensedMPC, cbf_qp_filter, default_params


class Controller(Node):
    def __init__(self):
        super().__init__("controller")
        self.declare_parameter("r_ref", [0.0, 3.0, 0.0])
        self.declare_parameter("use_filter", True)
        self.p = default_params()
        self.mpc = CondensedMPC(self.p)
        r_ref = np.array(self.get_parameter("r_ref").value, dtype=float)
        self.Pref = np.tile(r_ref.reshape(3, 1), (1, self.mpc.N + 1))
        self.Vref = np.zeros_like(self.Pref)
        self.use_filter = self.get_parameter("use_filter").value
        self.pub = self.create_publisher(AccelStamped, "/approach/accel_cmd", 10)
        self.create_subscription(Odometry, "/approach/state", self.on_state, 10)

    def on_state(self, o):
        pp, tw = o.pose.pose.position, o.twist.twist.linear
        x = np.array([pp.x, pp.y, pp.z, tw.x, tw.y, tw.z])
        u, _ = self.mpc.step(x, self.Pref, self.Vref)
        if self.use_filter:
            u, info = cbf_qp_filter(x, u, self.p)
            if not info["feasible"]:
                self.get_logger().error("HOCBF-QP infeasible")
        msg = AccelStamped()
        msg.header.stamp = o.header.stamp
        msg.header.frame_id = "lvlh"
        msg.accel.linear.x, msg.accel.linear.y, msg.accel.linear.z = map(float, u)
        self.pub.publish(msg)


def main():
    rclpy.init()
    node = Controller()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
