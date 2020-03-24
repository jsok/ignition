#!/bin/bash
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

depends() {
    echo qemu systemd url-lib network
}

install_ignition_unit() {
    local unit="$1"; shift
    local target="${1:-ignition-complete.target}"; shift
    local instantiated="${1:-$unit}"; shift
    inst_simple "$moddir/$unit" "$systemdsystemunitdir/$unit"
    mkdir -p "$initdir/$systemdsystemunitdir/$target.requires"
    ln_r "../$unit" "$systemdsystemunitdir/$target.requires/$instantiated"
}

install() {
    inst_multiple \
        lsblk

    # Not all features of the configuration may be available on all systems
    # (e.g. on embedded systems), so only add applications which are actually
    # present
    inst_multiple -o \
        groupadd \
        mkfs.btrfs \
        mkfs.ext4 \
        mkfs.vfat \
        mkfs.xfs \
        mkswap \
        sgdisk \
        useradd \
        usermod

    # Required by s390x's z/VM installation.
    # Supporting https://github.com/coreos/ignition/pull/865
    inst_multiple -o chccwdev vmur

    # Required on system using SELinux
    inst_multiple -o setfiles

    inst_script "$moddir/coreos-gpt-setup.sh" \
        "/usr/sbin/coreos-gpt-setup"

    inst_script "$moddir/ignition-setup-base.sh" \
        "/usr/sbin/ignition-setup-base"
    inst_script "$moddir/ignition-setup-user.sh" \
        "/usr/sbin/ignition-setup-user"

    # Distro packaging is expected to install the ignition binary into the
    # module directory.
    inst_simple "$moddir/ignition" \
        "/usr/bin/ignition"

    inst_simple "$moddir/ignition-generator" \
        "$systemdutildir/system-generators/ignition-generator"

    for x in "complete" "subsequent" "diskful" "diskful-subsequent"; do
        inst_simple "$moddir/ignition-$x.target" \
            "$systemdsystemunitdir/ignition-$x.target"
    done

    # For consistency tear down the network between the initramfs and
    # real root. See https://github.com/coreos/fedora-coreos-tracker/issues/394#issuecomment-599721763
    inst_script "$moddir/coreos-teardown-initramfs-network.sh" \
        "/usr/sbin/coreos-teardown-initramfs-network"
    install_ignition_unit coreos-teardown-initramfs-network.service

    install_ignition_unit ignition-setup-base.service
    install_ignition_unit ignition-setup-user.service
    install_ignition_unit ignition-fetch.service
    install_ignition_unit ignition-disks.service
    install_ignition_unit ignition-mount.service
    install_ignition_unit ignition-files.service

    # units only started when we have a boot disk
    # path generated by systemd-escape --path /dev/disk/by-label/root
    install_ignition_unit coreos-gpt-setup@.service        ignition-diskful.target 'coreos-gpt-setup@dev-disk-by\x2dlabel-root.service'
    install_ignition_unit ignition-remount-sysroot.service ignition-diskful.target

    # needed for openstack config drive support
    inst_rules 60-cdrom_id.rules
}

has_fw_cfg_module() {
    # this is like check_kernel_config() but it specifically checks for `m` and
    # also checks the OSTree-specific kernel location
    for path in /boot/config-$kernel \
                /usr/lib/modules/$kernel/config \
                /usr/lib/ostree-boot/config-$kernel; do
        if test -f $path; then
            rc=0
            grep -q CONFIG_FW_CFG_SYSFS=m $path || rc=$?
            return $rc
        fi
    done
    return 1
}

installkernel() {
    # We definitely need this one in the initrd to support Ignition cfgs on qemu
    # if available
    if has_fw_cfg_module; then
        instmods -c qemu_fw_cfg
    fi
}
