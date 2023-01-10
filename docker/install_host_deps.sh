#!/usr/bin/bash

# Called as script, or sourced?
test $0 = $BASH_SOURCE && CALLED_AS_SCRIPT=true || CALLED_AS_SCRIPT=false

# Abort on any error
set -e

###########################
# Common variables
###########################

OS_VENDOR=$(. /etc/os-release && echo $ID)  # debian, ubuntu, linuxmint
OS_CODENAME=$(. /etc/os-release && echo $VERSION_CODENAME)  # bullseye, focal, ulyssa

DEFAULT_HOST_OS_CODENAME=bullseye

test "$DEBUG" = true || DEBUG=false
$DEBUG && DO=echo || DO=
test $(id -u) = 0 && SUDO="$DO" || SUDO="$DO sudo -H"
APT_GET="${SUDO} env DEBIAN_FRONTEND=noninteractive apt-get"

###########################
# Misc. utility functions
###########################

# Determine RT CPUs and GPU info
check_cpu() {
    # Processor model
    CPU="$(awk '/^model name/ {split($0, F, /: /); print(F[2]); exit}' \
               /proc/cpuinfo)"

    case "$CPU" in
        "Intel(R) Celeron(R) CPU  N3160  @ 1.60GHz")
            RT_CPUS=${RT_CPUS:-2,3}
            GRUB_CMDLINE="isolcpus=${RT_CPUS}"
            ;;
        "Intel(R) Core(TM) i5-8259U CPU @ 2.30GHz")
            RT_CPUS=${RT_CPUS:-3,7}
            GRUB_CMDLINE="isolcpus=${RT_CPUS}"
            ;;
        "Intel(R) Atom(TM) Processor E3950 @ 1.60GHz")
            RT_CPUS=${RT_CPUS:-3}
            GRUB_CMDLINE="isolcpus=${RT_CPUS}"
            ;;
    esac

    # Motherboard information
    DMI_DATA="$(cat /sys/devices/virtual/dmi/id/modalias)"

    # Non-free firmware
    NEED_NON_FREE_FW=false
    # IWL firmware
    NEED_IWLWIFI_FIRMWARE=false

    # IWL firmware needs non-free repos
    ! $NEED_IWLWIFI_FIRMWARE || NEED_NON_FREE_FW=true
}

confirm_changes() {
    # Ask confirmation for we're about to do
    {
        echo "This script will:"
        echo "- Install some utility packages"
        echo "- Uninstall any Docker from Debian packages and install Docker CE"
        echo "  - Add your user to the 'docker' group"
        test -z "${GRUB_CMDLINE}" ||
            echo "- Configure kernel cmdline args '${GRUB_CMDLINE}'"
        echo "- Install the RT kernel"
        echo "- Install non-free hardware drivers (maybe)"
        echo
        echo -n "WARNING:  Do you want this script to make these changes?  (y/N) "
    } >&2
    read REALLY
    if test ! "$REALLY" = y; then
        echo "Aborting script at user request" >&2
        exit 1
    fi
}

# add_user_to_group group_name [user_name]
add_user_to_group() {
    local GROUP=$1
    local USER=${2:-$(id -un)}
    test $USER != 0 -a $USER != root || return
    ${SUDO} adduser $USER $GROUP
}

###########################
# Install script deps
###########################

install_script_deps() {
    ${APT_GET} install -y curl gnupg git
}

###########################
# Install RT kernel
# Configure isolated CPUs
###########################

install_rt_kernel() {
    ${SUDO} apt-get install -y linux-image-rt-amd64 linux-headers-rt-amd64

    GRUB_CMDLINE_CUR="$(source /etc/default/grub &&
                           echo $GRUB_CMDLINE_LINUX_DEFAULT)"
    if test -n "${GRUB_CMDLINE}" -a "$GRUB_CMDLINE_CUR" != "$GRUB_CMDLINE"; then
        # Configure kernel cmdline args
        ${SUDO} sed -i /etc/default/grub \
            -e "s/.*\(GRUB_CMDLINE_LINUX_DEFAULT\).*/\1=\"${GRUB_CMDLINE}\"/"
        ${SUDO} update-grub
    fi
}

###########################
# Install hardware drivers
###########################

install_hw_drivers() {
    # Add contrib and non-free repos (once!)
    ${SUDO} sed -i /etc/apt/sources.list -e 's/ main$/ main contrib non-free/'
    ${APT_GET} update
    if $NEED_NON_FREE_FW; then
        # Solves e.g.
        #   W: Possible missing firmware /lib/firmware/i915/[...] for module i915
        ${APT_GET} install -y firmware-misc-nonfree
    fi
    if $NEED_IWLWIFI_FIRMWARE; then
        ${APT_GET} install -y firmware-iwlwifi
    fi
}

###########################
# Docker CE
###########################

# https://docs.docker.com/install/linux/docker-ce/ubuntu/
# https://docs.docker.com/install/linux/docker-ce/debian/

install_docker_ce() {
    # Remove other Docker packages and add repo
    DOCKER_CE_STATUS="$(dpkg-query -Wf='${db:Status-Status}' docker-ce
                            2>/dev/null || true)"
    if test "$DOCKER_CE_STATUS" != installed; then
        # Remove old packages
        ${APT_GET} remove -y \
            docker docker-engine docker.io || true
        # Add official Docker GPG key
        curl -fsSL https://download.docker.com/linux/${OS_VENDOR}/gpg |
            ${SUDO} apt-key add -

        echo "deb [arch=amd64] https://download.docker.com/linux/${OS_VENDOR} \
            ${OS_CODENAME} stable" |
            ${SUDO} tee /etc/apt/sources.list.d/docker.list
        ${APT_GET} update
    fi

    # Install or update docker-ce package
    ${APT_GET} install -y docker-ce

    # docker user group
    add_user_to_group docker
}

###########################
# Finish up
###########################

finalize() {
    cat >&2 <<-EOF

		*** Install complete!
		*** You will probably have to reboot your machine
		***   in order for changes to take effect.
	EOF
    exit 0
}



###########################
# Install everything
###########################

install_everything() {
    check_cpu
    confirm_changes

    # At this point we're committed; show what we're doing
    set -x
    install_script_deps
    install_rt_kernel
    install_hw_drivers
    install_docker_ce
    finalize
}

# Install everything if called as a script
! $CALLED_AS_SCRIPT || install_everything "$@"

