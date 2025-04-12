#!/bin/bash

# d-scripts
# Enables or disables the loopback module in PulseAudio to feed PS5 audio to the line-in port

# IDs for line-in and output
LINE_IN_ID=269
OUTPUT_ID=268
LOOPBACK_NAME="Loopback"

# Function to enable loopback module
enable_loopback() {
    # Load the loopback module and specify source, sink, and name
    pactl load-module module-loopback source=$LINE_IN_ID sink=$OUTPUT_ID latency_msec=50 adjust_time=0 source_output_properties=device.description="$LOOPBACK_NAME" sink_input_properties=device.description="$LOOPBACK_NAME"
    echo "module-loopback is now loaded"
}

# Function to disable loopback module
disable_loopback() {
    # Get the module ID of the loopback module with the specific name
    module_id=$(pactl list short modules | grep module-loopback | grep "$LOOPBACK_NAME" | awk '{print $1}')
    
    # Unload the module if it is found
    if [ -n "$module_id" ]; then
        pactl unload-module "$module_id"
        echo "module-loopback is now unloaded"
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

