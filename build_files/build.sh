#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
# (includes /etc/yum.repos.d/tuxedo.repo — the official TUXEDO Fedora repo)
cp -avf "/ctx/system_files"/. /

RELEASE="$(rpm -E %fedora)"
KERNEL_VERSION="$(rpm -q kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
echo "Building for Fedora ${RELEASE}, kernel ${KERNEL_VERSION}"

###############################################################################
# 1. TUXEDO kernel drivers (baked in as kmod, built at image build time)
#
# Uses the akmod packaging from the gladion136/tuxedo-drivers-kmod COPR
# (https://copr.fedorainfracloud.org/coprs/gladion136/tuxedo-drivers-kmod/)
# instead of the official DKMS package — DKMS does not fit ostree images,
# akmods lets us compile the modules here and ship them in the image.
###############################################################################

dnf5 -y copr enable gladion136/tuxedo-drivers-kmod

# kernel-devel must match the kernel shipped in the base image exactly,
# otherwise the modules get built for the wrong kernel.
dnf5 -y install \
    "kernel-devel-${KERNEL_VERSION}" \
    akmods \
    akmod-tuxedo-drivers

# Build the modules for the image kernel and install the resulting kmod RPM
akmods --force --kernels "${KERNEL_VERSION}" --kmod tuxedo-drivers

# Fail the build if the modules did not actually land in the image
if ! find "/usr/lib/modules/${KERNEL_VERSION}" -name 'tuxedo*.ko*' | grep -q .; then
    echo "ERROR: tuxedo kernel modules missing after akmods build" >&2
    # akmods hides the real rpmbuild error in its logs — surface them
    cat /var/cache/akmods/tuxedo-drivers/*.log >&2 || true
    exit 1
fi

depmod -a "${KERNEL_VERSION}"

dnf5 -y copr disable gladion136/tuxedo-drivers-kmod

###############################################################################
# 2. TUXEDO Control Center (+ hardware extras) from the official TUXEDO repo
#
# /opt is a real directory in this image (see Containerfile), so TCC's files
# in /opt/tuxedo-control-center are baked into the image.
###############################################################################

dnf5 -y install tuxedo-control-center

# Present in newer repo versions (F43+): firmware blobs for current devices.
# --skip-unavailable keeps F42 builds working where the package doesn't exist.
dnf5 -y install --skip-unavailable tuxedo-firmware-collection

systemctl enable tccd.service
systemctl enable tccd-sleep.service

###############################################################################
# 3. Cleanup: drop kernel build tooling from the final image
###############################################################################

dnf5 -y remove "kernel-devel-${KERNEL_VERSION}" akmods akmod-tuxedo-drivers || \
    echo "WARN: cleanup removal failed, continuing (image just carries extra packages)"
