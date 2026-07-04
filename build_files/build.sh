#!/bin/bash

set ${CI:+-x} -euo pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

# Adapted from — https://github.com/jumpyvi/alchemist/blob/main/build_files/build.sh

ARCH="$(rpm -E '%_arch')"
RELEASE="$(rpm -E '%fedora')"

# Add kernel repo
dnf5 copr enable -y crono/kernel-cachyos

# Remove previous kernels
readarray -t OLD_KERNELS < <(rpm -qa 'kernel-*')
if (( ${#OLD_KERNELS[@]} )); then
    rpm -e --justdb --nodeps "${OLD_KERNELS[@]}"
    dnf5 versionlock delete "${OLD_KERNELS[@]}" || true
    rm -rf /usr/lib/modules/*
    rm -rf /lib/modules/*
fi

KERNEL_NAME="kernel-cachyos-lts"
KERNEL_VERSION="6.12.73-cachylts1.fc${RELEASE}.${ARCH}"

# Install kernel packages
dnf5 install -y \
    --enablerepo="copr:copr.fedorainfracloud.org:crono:kernel-cachyos" \
    --allowerasing \
    --setopt=tsflags=noscripts \
    "${KERNEL_NAME}"-"${KERNEL_VERSION}" \
    "${KERNEL_NAME}"-devel-matched-"${KERNEL_VERSION}" \
    "${KERNEL_NAME}"-devel-"${KERNEL_VERSION}" \
    "${KERNEL_NAME}"-modules-"${KERNEL_VERSION}" \
    "${KERNEL_NAME}"-core-"${KERNEL_VERSION}"

KERNEL="$(rpm -q "${KERNEL_NAME}" --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}')"

# Install and patch akmods package for container compatibility. Thanks to Vergil.
dnf5 install -y \
    akmods
cp /usr/sbin/akmodsbuild /usr/sbin/akmodsbuild.backup
sed -i '/if \[\[ -w \/var \]\] ; then/,/fi/d' /usr/sbin/akmodsbuild

# Install zenergy. Modified from — https://github.com/ublue-os/akmods/blob/51ea18abf8439fb72eb92047aec7d43f73b555e7/build_files/extra/build-kmod-zenergy.sh

## Create directories to ensure build
mkdir -p /var/roothome
mkdir -p /var/tmp
chmod 1777 /var/tmp

dnf5 install -y \
    --enablerepo="terra" \
    akmod-zenergy-*.fc"${RELEASE}"."${ARCH}"
akmods --force --kmod zenergy
modinfo /usr/lib/modules/"${KERNEL}"/extra/zenergy/zenergy.ko.xz > /dev/null \
|| (find /var/cache/akmods/zenergy/ -name \*.log -print -exec cat {} \; && exit 1)

# Generate module dependencies
depmod -a "${KERNEL}"

# Handle vmlinuz placement
# Check if the files are physically different (-ef) before attempting a copy.
VMLINUZ_SOURCE="/lib/modules/${KERNEL}/vmlinuz"
VMLINUZ_TARGET="/usr/lib/modules/${KERNEL}/vmlinuz"

if [[ -f "${VMLINUZ_SOURCE}" ]]; then
    if ! [[ "${VMLINUZ_SOURCE}" -ef "${VMLINUZ_TARGET}" ]]; then
        mkdir -p "/usr/lib/modules/${KERNEL}"
        cp "${VMLINUZ_SOURCE}" "${VMLINUZ_TARGET}"
    else
        echo "vmlinuz already exists at target via symlink, skipping copy."
    fi
fi

# Lock kernel packages
dnf5 versionlock add "kernel-cachyos-lts-${KERNEL}" || true
dnf5 versionlock add "kernel-cachyos-lts-modules-${KERNEL}" || true

# Thank you @renner03 for this part
export DRACUT_NO_XATTR=1
dracut --force \
  --no-hostonly \
  --kver "${KERNEL}" \
  --zstd \
  --reproducible -v \
  --add ostree \
  -f "/usr/lib/modules/${KERNEL}/initramfs.img"

chmod 0600 "/lib/modules/${KERNEL}/initramfs.img"

rm -f /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:crono:kernel-cachyos.repo
