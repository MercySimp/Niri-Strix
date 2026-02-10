#!/bin/bash

# Dependencies: pactl + rofi or wofi/dmenu

# Use rofi, wofi, or dmenu. Customize this line:
MENU="rofi -dmenu -i -p 'Select Output'"

# Get available sinks
mapfile -t sinks < <(pactl list short sinks | awk '{print $2}')

# Ask user to choose
choice=$(printf '%s\n' "${sinks[@]}" | $MENU)

# Exit if no choice made
[ -z "$choice" ] && exit

# Get the sink index from the name
sink_index=$(pactl list short sinks | grep "$choice" | awk '{print $1}')

# Set default sink
pactl set-default-sink "$sink_index"

# Move all current audio streams to the new sink
for input in $(pactl list short sink-inputs | awk '{print $1}'); do
    pactl move-sink-input "$input" "$sink_index"
done
