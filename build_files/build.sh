#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
# (includes /etc/yum.repos.d/tuxedo.repo — the official TUXEDO Fedora repo)
cp -avf "/ctx/system_files"/. /

RELEASE="$(rpm -E %fedora)"
KERNEL_VERSION="$(rpm -q kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"
echo "Building for Fedora ${RELEASE}, kernel ${KERNEL_VERSION}"

###############################################################################
# 1. TUXEDO kernel drivers (baked in, built at image build time)
#
# Built from the OFFICIAL tuxedo-drivers dkms package — the only packaging
# TUXEDO keeps current (the community akmod COPR lags behind and its 4.17.0
# does not compile against kernel 7.x). dkms is only used as a build tool
# here: the resulting .ko files are shipped in the image, nothing rebuilds
# at runtime.
###############################################################################

# kernel-devel must match the kernel shipped in the base image exactly,
# otherwise the modules get built for the wrong kernel.
dnf5 -y install "kernel-devel-${KERNEL_VERSION}"

# tuxedo-drivers' %post runs a dkms build for `uname -r` (the BUILD HOST
# kernel — wrong in a container). Install it and its missing deps (dkms,
# udev-hid-bpf) without scriptlets, then build explicitly for the image
# kernel below.
dnf5 -y download --destdir=/tmp/td-rpms --resolve tuxedo-drivers
rpm -ivh --noscripts /tmp/td-rpms/*.rpm

TD_VERSION="$(rpm -q tuxedo-drivers --queryformat '%{VERSION}')"
echo "Building tuxedo-drivers ${TD_VERSION} for kernel ${KERNEL_VERSION}"

dkms install -m tuxedo-drivers -v "${TD_VERSION}" -k "${KERNEL_VERSION}" || {
    echo "ERROR: dkms build/install of tuxedo-drivers failed" >&2
    cat "/var/lib/dkms/tuxedo-drivers/${TD_VERSION}/build/make.log" >&2 || true
    exit 1
}

# Strict verification: tuxedo_io is part of the out-of-tree set only (newer
# kernels ship SOME in-tree tuxedo_* modules, which must not mask a failed
# driver build — this bit us with the akmod approach).
echo "tuxedo modules now present in the image:"
find "/usr/lib/modules/${KERNEL_VERSION}" -name '*tuxedo*'
if ! find "/usr/lib/modules/${KERNEL_VERSION}" -name 'tuxedo_io.ko*' | grep -q .; then
    echo "ERROR: tuxedo_io module missing — out-of-tree driver set did not install" >&2
    exit 1
fi

depmod -a "${KERNEL_VERSION}"

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

# TCC's %post copies polkit policies out of its /opt payload and is flaky in
# container builds (observed: a missing tomte.policy tripped up the copy).
# Make sure every policy that shipped actually lands, then verify.
TCC_DIST="/opt/tuxedo-control-center/resources/dist/tuxedo-control-center/data/dist-data"
if [ -d "${TCC_DIST}" ]; then
    for p in "${TCC_DIST}"/*.policy; do
        [ -e "${p}" ] || continue
        install -Dm644 "${p}" "/usr/share/polkit-1/actions/$(basename "${p}")"
    done
fi
echo "TUXEDO polkit policies installed:"
ls /usr/share/polkit-1/actions/ | grep -i tuxedo || true
if ! ls /usr/share/polkit-1/actions/*tuxedo* >/dev/null 2>&1; then
    echo "ERROR: no TUXEDO polkit policy installed — TCC GUI could not authenticate" >&2
    exit 1
fi

systemctl enable tccd.service
systemctl enable tccd-sleep.service

###############################################################################
# 3. Cleanup: build-time residue only
#
# Deliberately NO `dnf5 remove kernel-devel` here: dnf5's unused-dependency
# autoremoval cascades into base-image packages (observed: it ripped out
# v4l2loopback, the libguestfs stack, dhcpcd, ...). Keeping the build
# tooling (~100 MB) is the safer trade on a ~5 GB image.
###############################################################################

# bootc lint flags content in runtime-only and machine-local directories:
# dnf state, and dkms bookkeeping (incl. an ephemeral auto-generated MOK
# key). The built modules live in /usr/lib/modules and are unaffected.
rm -rf /run/* /var/lib/dkms /var/lib/dnf || true
