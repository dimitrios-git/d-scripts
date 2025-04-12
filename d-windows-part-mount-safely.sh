#!/bin/bash

set -e

### Function definitions

# Check if running on Ubuntu or Ubuntu-based distro
check_distro() {
    if ! grep -qi "ubuntu" /etc/os-release; then
        echo "❌ This script only supports Ubuntu or Ubuntu-based distributions."
        exit 1
    fi
}

# Check if ntfs-3g is installed
check_ntfs3g() {
    if ! dpkg -s ntfs-3g &> /dev/null; then
        echo "📦 'ntfs-3g' is not installed. You need it to safely mount NTFS partitions."
        read -rp "Do you want to install ntfs-3g now? [y/N]: " install_ntfs
        if [[ "$install_ntfs" =~ ^[Yy]$ ]]; then
            sudo apt update && sudo apt install -y ntfs-3g
        else
            echo "Aborting. You must install ntfs-3g first."
            exit 1
        fi
    fi
}

# Ask user for mount directory
get_mount_point() {
    read -rp "Enter mount point directory [default: /mnt/windows]: " mount_point
    mount_point="${mount_point:-/mnt/windows}"

    if [[ ! -d "$mount_point" ]]; then
        echo "❌ Directory '$mount_point' does not exist."
        exit 1
    fi

    if [[ "$(ls -A "$mount_point")" ]]; then
        echo "❌ Directory '$mount_point' is not empty."
        exit 1
    fi
}

# Confirm before continuing
confirm() {
    read -rp "$1 [y/N]: " response
    [[ "$response" =~ ^[Yy]$ ]]
}

# Detect and confirm target NTFS partition
get_ntfs_partition() {
    echo "📦 Detected NTFS partitions:"
    lsblk -f | grep -i ntfs
    echo
    read -rp "Enter the device name of the Windows partition (e.g. /dev/nvme0n1p5): " part

    if [[ ! -b "$part" ]]; then
        echo "❌ '$part' is not a valid block device."
        exit 1
    fi
}

# Check if the partition is dirty
check_dirty_bit() {
    echo "🔍 Checking if partition is marked dirty..."
    if sudo ntfsfix -n "$part" | grep -q "Volume is dirty"; then
        echo "⚠️  The Windows partition is dirty (Fast Startup or hibernation is active)."
        echo "Mounting it read/write can lead to data corruption."
        echo "Please boot into Windows and perform a full shutdown (not reboot)."
        echo
        if confirm "Do you want to mount the partition as READ-ONLY anyway?"; then
            readonly_mount=true
        else
            echo "Aborting to keep your data safe."
            exit 1
        fi
    fi
}

# Perform the mount
mount_partition() {
    uid=$(id -u)
    gid=$(id -g)

    echo "🛠️  Making sure $mount_point is not already mounted..."
    sudo umount "$mount_point" 2>/dev/null || true

    if [[ "$readonly_mount" == true ]]; then
        echo "🔒 Mounting as read-only..."
        sudo mount -t ntfs-3g -o ro,uid=$uid,gid=$gid "$part" "$mount_point"
    else
        echo "✅ Mounting as read/write..."
        sudo mount -t ntfs-3g -o uid=$uid,gid=$gid "$part" "$mount_point"
    fi

    echo "🎉 Done! Mounted '$part' to '$mount_point'"
}

### Main execution flow

check_distro
check_ntfs3g
get_mount_point
get_ntfs_partition

echo
if ! confirm "About to mount $part to $mount_point. Proceed?"; then
    echo "Aborted."
    exit 1
fi

check_dirty_bit
mount_partition

