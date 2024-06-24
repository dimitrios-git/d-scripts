#!/bin/sh

# ssh-auto-unlock

# Copy scripts
echo "Copying ssh-agent-startup.sh to ~/.config/plasma-workspace/env"
cp ssh-agent-startup.sh ~/.config/plasma-workspace/env
chmod +x ~/.config/plasma-workspace/env/ssh-agent-startup.sh
echo "Copying ssh-agent-shutdown.sh to ~/.config/plasma-workspace/shutdown"
cp ssh-agent-shutdown.sh ~/.config/plasma-workspace/shutdown
chmod +x ~/.config/plasma-workspace/shutdown/ssh-agent-shutdown.sh
echo "Copying ssh-import-startup.sh to ~/.config/autostart"
cp ssh-import-startup.sh ~/.config/autostart
cp ssh-import-startup.sh.desktop ~/.config/autostart
chmod +x ~/.config/autostart/ssh-import-startup.sh
echo "Installation completed. Importing keys..."
bash ~/.config/autostart/ssh-import-startup.sh
echo "Configuration completed."
