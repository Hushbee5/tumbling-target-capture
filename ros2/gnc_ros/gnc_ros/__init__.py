"""ROS 2 nodes for the safe terminal approach. The controller code itself is python/gnc (put python/ on PYTHONPATH).

Lockstep protocol, one exchange per control period k (stamp = k * Ts, integer nanoseconds):
  plant_node      -> /approach/state      nav_msgs/Odometry, frame 'lvlh', child 'servicer' (position, velocity)
  controller_node -> /approach/accel_cmd  geometry_msgs/AccelStamped, frame 'lvlh', same stamp as the state
The plant advances only on a command whose stamp equals its current state stamp, so the run is deterministic and
does not depend on message timing."""
TS_NS = 100_000_000                     # Ts = 0.1 s


def to_stamp(h, ns):
    h.stamp.sec = ns // 1_000_000_000
    h.stamp.nanosec = ns % 1_000_000_000


def from_stamp(h):
    return h.stamp.sec * 1_000_000_000 + h.stamp.nanosec
