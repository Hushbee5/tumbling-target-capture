"""Plant and controller in lockstep; the launch ends when the plant has completed the run.
  ros2 launch gnc_ros approach.launch.py duration:=200.0 out_file:=/tmp/approach.json use_filter:=true"""
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, EmitEvent, RegisterEventHandler
from launch.event_handlers import OnProcessExit
from launch.events import Shutdown
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node
from launch_ros.parameter_descriptions import ParameterValue


def generate_launch_description():
    duration = LaunchConfiguration("duration")
    out_file = LaunchConfiguration("out_file")
    use_filter = LaunchConfiguration("use_filter")
    plant = Node(package="gnc_ros", executable="plant_node", name="plant", output="screen",
                 parameters=[{"duration": ParameterValue(duration, value_type=float),
                              "out_file": ParameterValue(out_file, value_type=str)}])
    controller = Node(package="gnc_ros", executable="controller_node", name="controller", output="screen",
                      parameters=[{"use_filter": ParameterValue(use_filter, value_type=bool)}])
    return LaunchDescription([
        DeclareLaunchArgument("duration", default_value="200.0"),
        DeclareLaunchArgument("out_file", default_value=""),
        DeclareLaunchArgument("use_filter", default_value="true"),
        plant,
        controller,
        RegisterEventHandler(OnProcessExit(target_action=plant, on_exit=[EmitEvent(event=Shutdown())])),
    ])
