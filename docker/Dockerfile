ARG ROS_DISTRO=${ROS_DISTRO}
ARG PACKAGE_NAME=mypkg
ENV ROS_DISTRO=${ROS_DISTRO}

ARG WORKDIR=/root/upstream_ws

# Tweak APT configuration
RUN \
    # Don't install recommended pkgs
    echo 'APT::Install-Recommends "0";\nAPT::Install-Suggests "0";' > \
        /etc/apt/apt.conf.d/01norecommend \
    # Assume `-y`
    && echo 'APT::Get::Assume-Yes "true";' > \
        /etc/apt/apt.conf.d/02assumeyes \
    # Keep APT package cache
    && echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' \
        > /etc/apt/apt.conf.d/03keep-cache \
    && echo 'APT::Clean-Installed "false";' \
        > /etc/apt/apt.conf.d/04clean-installed-off \
    && rm -f /etc/apt/apt.conf.d/docker-clean

# Add string to shell prompt to help identify Docker container shells
RUN echo ${PACKAGE_NAME} > /etc/debian_chroot

WORKDIR ${WORKDIR}

# Configure 3rd-party APT repos and rosdep keys
ADD docker/install_docker_deps.sh docker/install_funcs.sh src/${PACKAGE_NAME}/docker/
RUN --mount=type=cache,target=/var/cache/apt \
    ./src/${PACKAGE_NAME}/docker/install_docker_deps.sh

# Install & configure dev tools
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update \
    && apt-get install -y \
        ccache \
        clang \
        clang-tidy \
        clang-tools \
        gdb \
        git \
        openssh-client \
        python3-pip \
        ros-${ROS_DISTRO}-ament-lint-cmake \
        ros-${ROS_DISTRO}-ament-cmake \
        wget \
        xterm \
    && pip3 install black pre-commit \
    # Add missing ccache symlinks
    && test -f /usr/lib/ccache/c++ || ln -s ../../bin/ccache /usr/lib/ccache/c++ \
    && test -f /usr/lib/ccache/cc || ln -s ../../bin/ccache /usr/lib/ccache/cc

# Clone source deps
COPY ${PACKAGE_NAME}.repos src/${PACKAGE_NAME}/
RUN vcs import src/ < src/${PACKAGE_NAME}/${PACKAGE_NAME}.repos

###############
# Generate package dependencies in separate build stage
#
# The Docker image cache gets dirty at any random file change.  To
# compute source deps, `rosdep` only needs `package.xml` files.
# Keeping a `.dockerignore` file up to date when new packages are
# added is a headach.  Instead, run `rosdep` in an isolated build
# stage and copy over the resulting script.  The main image build
# cache will only dirty when that script changes.

FROM base AS pkg_deps

# Pull in everything; this will dirty the cache only of this dead-end
# build stage
ADD . src/${PACKAGE_NAME}/

# Generate rosdeps script
RUN \
    apt-get update \
    && rosdep install -y -s --rosdistro $ROS_DISTRO \
         --from-paths src --ignore-src \
        --skip-keys=rrbot_description --skip-keys=ros2_control_demo_bringup \
        --skip-keys=cmake_clang_tools --skip-keys=ocs2_frank_wolfe --skip-keys=cmake_modules \
      # Do some munging to make the result more deterministic
      | grep -v '^#' | sort \
      | tee /tmp/install_rosdeps.sh


###############
# Continue main build

FROM base AS mypkg

# Pull in rosdeps script from temporary pkg_deps build stage
COPY --from=pkg_deps /tmp/install_rosdeps.sh /tmp/install_rosdeps.sh
RUN --mount=type=cache,target=/var/cache/apt \
    bash -xe /tmp/install_rosdeps.sh

# Build and install ROS package source dependencies & perform final
# steps
RUN --mount=type=cache,target=/ccache/ \
    touch src/${PACKAGE_NAME}/COLCON_IGNORE \
    # Use ccache
    && export CCACHE_DIR=/ccache \
    && ccache -s \
    && ccache -z \
    && PATH=/usr/lib/ccache:$PATH \
    # Build & install workspace
    && source /opt/ros/$ROS_DISTRO/setup.bash \
    && CXXFLAGS=-g colcon build \
        --install-base /opt/ros/$ROS_DISTRO --merge-install \
        --cmake-args -DCMAKE_BUILD_TYPE=Release \
    # See how ccache did
    && ccache -s
