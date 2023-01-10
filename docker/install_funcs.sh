# Install packages for APT over https
install_apt_https() {
    ${SUDO} apt-get update
    ${SUDO} apt-get install -y \
        apt-transport-https \
        curl
}
