from glob import glob

from setuptools import setup

package_name = "gnc_ros"

setup(
    name=package_name,
    version="0.1.0",
    packages=[package_name],
    data_files=[
        ("share/ament_index/resource_index/packages", ["resource/" + package_name]),
        ("share/" + package_name, ["package.xml"]),
        ("share/" + package_name + "/launch", glob("launch/*.launch.py")),
    ],
    install_requires=["setuptools"],
    zip_safe=True,
    maintainer="Hasan Baran Gurbuz",
    maintainer_email="hasanbarangurbuz58@gmail.com",
    description="ROS 2 nodes for the safe terminal approach (plant, MPC + HOCBF-QP controller).",
    license="All rights reserved",
    entry_points={
        "console_scripts": [
            "plant_node = gnc_ros.plant_node:main",
            "controller_node = gnc_ros.controller_node:main",
        ],
    },
)
