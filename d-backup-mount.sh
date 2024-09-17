#!/bin/bash

# d-scripts
# Backup device mount/unmount management script

# Global variables
LOG_FILE="/var/log/d-backup-mount.log"
BACKUP_ROOT_PATH="/mnt/backups/system"
BACKUP_ROOT_DEVICE="/dev/vgbackups/system"

# Colors
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
NC='\033[0m'

# Function to check the exit status of the command and print a message
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "$GREEN[SUCCESS]$NC $1"
    else
        echo -e "$RED[ERROR]$NC $1 failed"
        exit 1
    fi
}

# Function to unmount the backup device and remove the backup path
unmount_backup_device() {
    echo "$(date --rfc-3339=seconds): Unmounting the backup device $BACKUP_ROOT_PATH" | sudo tee -a $LOG_FILE
    sudo umount $BACKUP_ROOT_PATH
    check_status "Unmounting backup device $BACKUP_ROOT_PATH"
    echo "$(date --rfc-3339=seconds): Removing the backup path $BACKUP_ROOT_PATH" | sudo tee -a $LOG_FILE
    sudo rm -rf $BACKUP_ROOT_PATH
    check_status "Removing backup path $BACKUP_ROOT_PATH"
}

# Function to ask user for confirmation
ask_confirmation() {
    read -p "$1 (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to check if the backup device is mounted, and act accordingly
check_mount_backup_device() {
    if mountpoint -q $BACKUP_ROOT_PATH; then
        echo -e "$YELLOW[WARNING]$NC Backup device is already mounted at $BACKUP_ROOT_PATH."
        if ask_confirmation "Do you want to unmount it?"; then
            unmount_backup_device
        else
            echo -e "$GREEN[INFO]$NC Backup device remains mounted."
            exit 0
        fi
    else
        if [ -d $BACKUP_ROOT_PATH ]; then
            echo -e "$YELLOW[WARNING]$NC Backup path exists but is not mounted."
            if ask_confirmation "Do you want to mount the backup device?"; then
                sudo mount $BACKUP_ROOT_DEVICE $BACKUP_ROOT_PATH
                check_status "Mounting backup device $BACKUP_ROOT_DEVICE at $BACKUP_ROOT_PATH"
            else
                echo -e "$GREEN[INFO]$NC Skipping mounting of the backup device."
                exit 0
            fi
        else
            echo -e "$GREEN[SUCCESS]$NC Backup path not found, creating and mounting the device..."
            sudo mkdir -p $BACKUP_ROOT_PATH
            check_status "Creating backup path $BACKUP_ROOT_PATH"
            sudo mount $BACKUP_ROOT_DEVICE $BACKUP_ROOT_PATH
            check_status "Mounting backup device $BACKUP_ROOT_DEVICE at $BACKUP_ROOT_PATH"
        fi
    fi
}

# Run the function to check and manage the backup device
check_mount_backup_device

