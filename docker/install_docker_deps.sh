#!/bin/bash -xe

# - Load functions for cloudsmith repo and set up APT over https
source $(dirname ${BASH_SOURCE[0]})/install_funcs.sh
install_apt_https
apt-get update

rm -f /etc/ros/rosdep/sources.list.d/20-default.list
rosdep init
rosdep update

# Install misc. dependencies
apt-get install -y libstb-dev
