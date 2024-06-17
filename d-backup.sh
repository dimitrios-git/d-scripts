#!/bin/bash

# d-scripts
# Full system backup and upgrade script

# Global variables
LOG_FILE="/var/log/d-system.log"
BACKUP_ROOT_PATH="/mnt/backups/system"
BACKUP_ROOT_DEVICE="/dev/vgbackups/system"

# Colors
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
NC='\033[0m'

# Check if backup device is mounted at backup path and if not, mount it, else print a message and exit
# Convert the below insto a function that takes the device and path as arguments
check_mount_backup_device() {
    if [ ! -d $1 ]; then
        echo -e "$GREEN[SUCCESS]$NC Backup path not found, mounting the device..."
        sudo mkdir -p $1
        check_status "Creating backup path $1"
        sudo mount $2 $1
        check_status "Mounting backup device $2 at $1"
    else
        echo -e "$RED[ERROR]$NC Backup path already exists, skipping mounting the device at $1 and exiting..."
        exit 1
    fi
}

# Fuction to unmount the backup device and remove the backup path
unmount_backup_device() {
    echo "$(date --rfc-3339=seconds): Unmounting the backup device $1" | sudo tee -a $LOG_FILE
    sudo umount $1
    check_status "Unmounting backup device $1"
    echo "$(date --rfc-3339=seconds): Removing the backup path $1" | sudo tee -a $LOG_FILE
    sudo rm -rf $1
    check_status "Removing backup path $1"
}

# Function to check the exit status of the command and print a message
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "$GREEN[SUCCESS]$NC $1"
    else
        echo -e "$RED[ERROR]$NC $1 failed"
        exit 1
    fi
}

# Function for countdown
countdown() {
    local i
    for i in {5..1}; do
        echo -ne "$YELLOW\033[033mPress CTL+C to cancel - Sleeping for $i seconds...\033[0m\033[0K\r"
        sleep 1
    done
    echo -e "$YELLOW\033[033mPress CTL+C to cancel - Sleeping for 0 seconds...\033[0m\033[0K"
}

# Function to ensure the Backups directory is protected
protect_backups() {
    echo "$(date --rfc-3339=seconds): Reapplying immutable flag to the backup directories" | sudo tee -a $LOG_FILE
    sudo chattr +i $BACKUP_ROOT_PATH
}

# Check if the backup device is mounted at the backup path
check_mount_backup_device $BACKUP_ROOT_PATH $BACKUP_ROOT_DEVICE

# Set trap to protect the Backups directory and unmount backup_root on script exit
trap 'protect_backups; unmount_backup_device $BACKUP_ROOT_PATH' EXIT

# Start of the backup and upgrade process
echo "$(date --rfc-3339=seconds): Full system backup and upgrade started" | sudo tee -a $LOG_FILE

# Remove immutable flag to allow backup
echo "$(date --rfc-3339=seconds): Removing immutable flag from the backup directories" | sudo tee -a $LOG_FILE
sudo chattr -i $BACKUP_ROOT_PATH

# Backup operations...
## System backup
echo "$(date --rfc-3339=seconds): System backup starting" | sudo tee -a $LOG_FILE
countdown
echo "$(date --rfc-3339=seconds): Backup of root started" | sudo tee -a $LOG_FILE
sudo rsync -aAXHS --stats --info=progress2 --ignore-errors --no-compress --inplace --delete --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found","/snap/*","/var/lib/lxcfs/proc/*","/var/lib/lxcfs/sys/*"} / $BACKUP_ROOT_PATH
check_status "$(date --rfc-3339=seconds): Backup of root completed"
echo "$(date --rfc-3339=seconds): Backup of root completion logged" | sudo tee -a $LOG_FILE

