#!/bin/bash

# Modified from — https://github.com/jumpyvi/alchemist/build_files/packages/kernel.sh

set ${CI:+-x} -euo pipefail

# Add kernel repo
dnf5 copr enable -y bieszczaders/kernel-cachyos

# Remove previous kernels
readarray -t OLD_KERNELS < <(rpm -qa 'kernel-*')
if (( ${#OLD_KERNELS[@]} )); then
    rpm -e --justdb --nodeps "${OLD_KERNELS[@]}"
    dnf5 versionlock delete "${OLD_KERNELS[@]}" || true
    rm -rf /usr/lib/modules/*
    rm -rf /lib/modules/*
fi

# Install kernel packages
dnf5 install -y \
    --enablerepo="copr:copr.fedorainfracloud.org:bieszczaders:kernel-cachyos" \
    --allowerasing \
    --setopt=tsflags=noscripts \
    kernel-cachyos-lts \
    kernel-cachyos-lts-devel-matched \
    kernel-cachyos-lts-devel \
    kernel-cachyos-lts-modules \
    kernel-cachyos-lts-core

KERNEL_VERSION="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-cachyos-lts)"

# Install and patch akmods package for container compatibility. Thanks to Vergil.
dnf5 install -y \
    akmods
cp /usr/sbin/akmodsbuild /usr/sbin/akmodsbuild.backup
sed -i '/if \[\[ -w \/var \]\] ; then/,/fi/d' /usr/sbin/akmodsbuild

# Install zenergy. Modified from — https://github.com/ublue-os/akmods/blob/51ea18abf8439fb72eb92047aec7d43f73b555e7/build_files/extra/build-kmod-zenergy.sh
RELEASE="$(rpm -E '%fedora')"
curl -LsSf -o /etc/yum.repos.d/terra.repo \
    "https://raw.githubusercontent.com/terrapkg/packages/f${RELEASE}/anda/terra/release/terra.repo"
curl -LsSf -o /etc/pki/rpm-gpg/RPM-GPG-KEY-terra"${RELEASE}" \
    "https://raw.githubusercontent.com/terrapkg/packages/f${RELEASE}/anda/terra/gpg-keys/RPM-GPG-KEY-terra${RELEASE}"
rpmkeys --import /etc/pki/rpm-gpg/RPM-GPG-KEY-terra"${RELEASE}"

# Create directories to ensure build
mkdir -p /var/roothome
mkdir -p /var/tmp
chmod 1777 /var/tmp

dnf5 install -y \
    --enablerepo="terra" \
    akmod-zenergy
akmods --force --kmod zenergy
modinfo /usr/lib/modules/"${KERNEL_VERSION}"/extra/zenergy/zenergy.ko.xz > /dev/null \
|| (find /var/cache/akmods/zenergy/ -name \*.log -print -exec cat {} \; && exit 1)

# Generate module dependencies
depmod -a "${KERNEL_VERSION}"

# Handle vmlinuz placement
# Check if the files are physically different (-ef) before attempting a copy.
VMLINUZ_SOURCE="/lib/modules/${KERNEL_VERSION}/vmlinuz"
VMLINUZ_TARGET="/usr/lib/modules/${KERNEL_VERSION}/vmlinuz"

if [[ -f "${VMLINUZ_SOURCE}" ]]; then
    if ! [[ "${VMLINUZ_SOURCE}" -ef "${VMLINUZ_TARGET}" ]]; then
        mkdir -p "/usr/lib/modules/${KERNEL_VERSION}"
        cp "${VMLINUZ_SOURCE}" "${VMLINUZ_TARGET}"
    else
        echo "vmlinuz already exists at target via symlink, skipping copy."
    fi
fi

# Lock kernel packages
dnf5 versionlock add "kernel-cachyos-lts-${KERNEL_VERSION}" || true
dnf5 versionlock add "kernel-cachyos-lts-modules-${KERNEL_VERSION}" || true

# Thank you @renner03 for this part
export DRACUT_NO_XATTR=1
dracut --force \
  --no-hostonly \
  --kver "${KERNEL_VERSION}" \
  --zstd \
  --reproducible -v \
  --add ostree \
  -f "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"

chmod 0600 "/lib/modules/${KERNEL_VERSION}/initramfs.img"

rm -f /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:bieszczaders:kernel-cachyos-lto.repo
rm -f /etc/yum.repos.d/terra.repo
