#!/bin/bash

# d-scripts
# Turn down the brightness of the side monitors when watching a movie.

# Check if an argument was supplied
if [ -z "$1" ]; then
	echo "No argument supplied. Please use 'on' or 'off' as an argument."
	exit 1
fi

# Check for Wayland session
if [ -n "$WAYLAND_DISPLAY" ]; then
  echo "This script does not support Wayland. Please switch to an X11 session."
  exit 1
fi

# Check for X11 session
if [ -n "$DISPLAY" ]; then
  # Use xrandr to check which monitors are connected
  # xrandr | grep " connected" | awk '{ print$1 }'

  # Set max brightness when cinema mode is off
  if [ "$1" == "off" ]; then
	  xrandr --output DVI-D-0 --brightness 1
	  xrandr --output HDMI-A-0 --brightness 1
	  exit 0
  fi

  # Set min brightness when cinema mode is on
  if [ "$1" == "on" ]; then
	  xrandr --output DVI-D-0 --brightness 0
	  xrandr --output HDMI-A-0 --brightness 0
	  exit 0
  fi

else
  echo "No graphical session detected."
  exit 1
fi

