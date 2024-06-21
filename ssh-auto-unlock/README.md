# Automatically import and unlock your SSH keys

This script will automatically import and unlock your SSH keys when you login to your computer. It is useful if you have SSH keys for various and you don't want to type the passphrase every time you login to your computer.

## Compatibility

This script is designed to work on KDE Neon, but it should work on any Linux distribution that uses the KDE Plasma desktop environment and the KDE Wallet Manager.

## Installation

1. Place the `ssh-agent-startup.sh` script under the `~/.config/plasma-workspace/env/` directory.
1. Place the `ssh-import-startup.sh` script under the `~/.config/autostart-scripts/` directory.
1. Place the `ssh-agent-shutdown.sh` script under the `~/.config/plasma-workspace/shutdown/` directory.
