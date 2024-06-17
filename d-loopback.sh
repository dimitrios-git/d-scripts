#!/bin/bash

# d-scripts
# Enables or disables the loopback module in PulseAudio to feed PS5 audio to the line-in port

# Function to enable loopback module
enable_loopback() {
    pactl load-module module-loopback
    echo "module-loopback is now loaded"
}

# Function to disable loopback module
disable_loopback() {
    # Get the module ID of the loopback module
    module_id=$(pactl list short modules | grep module-loopback | awk '{print $1}')
    
    # Unload the module if it is found
    if [ -n "$module_id" ]; then
        pactl unload-module "$module_id"
    else
        echo "module-loopback is not loaded"
    fi
}

# Check the argument
if [ "$1" == "enable" ]; then
    enable_loopback
elif [ "$1" == "disable" ]; then
    disable_loopback
else
    echo "Usage: $0 {enable|disable}"
    exit 1
fi

