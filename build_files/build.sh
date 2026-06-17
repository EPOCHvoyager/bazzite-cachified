#!/bin/bash

# Modified from — https://github.com/jumpyvi/alchemist/build_files/packages/kernel.sh

set -ouex pipefail

# Adds the longterm kernel repo
dnf5 copr enable -y bieszczaders/kernel-cachyos-lto

# Remove previous kernels
readarray -t OLD_KERNELS < <(rpm -qa 'kernel-*')
if (( ${#OLD_KERNELS[@]} )); then
    rpm -e --justdb --nodeps "${OLD_KERNELS[@]}"
    dnf5 versionlock delete "${OLD_KERNELS[@]}" || true
    rm -rf /usr/lib/modules/*
    rm -rf /lib/modules/*
fi

# Install kernel packages (noscripts required for 43+)
dnf5 install -y \
    --enablerepo="copr:copr.fedorainfracloud.org:bieszczaders:kernel-cachyos-lto" \
    --allowerasing \
    --setopt=tsflags=noscripts \
    kernel-cachyos-lts-lto \
    kernel-cachyos-lts-lto-devel-matched \
    kernel-cachyos-lts-lto-devel \
    kernel-cachyos-lts-lto-modules \
    kernel-cachyos-lts-lto-core

KERNEL_VERSION="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-cachyos-lts-lto)"

# Generate module dependencies
depmod -a "${KERNEL_VERSION}"

# Handle vmlinuz placement
# We check if the files are physically different (-ef) before attempting a copy
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
dnf5 versionlock add "kernel-cachyos-lts-lto-${KERNEL_VERSION}" || true
dnf5 versionlock add "kernel-cachyos-lts-lto-modules-${KERNEL_VERSION}" || true

# Thank you @renner03 for this part
dracut --force \
  --no-hostonly \
  --kver "${KERNEL_VERSION}" \
  --reproducible -v --add ostree \
  -f "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"

chmod 0600 "/lib/modules/${KERNEL_VERSION}/initramfs.img"
