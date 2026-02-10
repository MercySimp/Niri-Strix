#!/bin/bash

# Define the output file for tooltip
TOOLTIP_FILE="$HOME/.cache/dunst_tooltip.txt"

# Extract body messages from dunstctl
dunstctl history | jq -r '.data[0][] | .body.data' | head -n 10 > "$TOOLTIP_FILE"
