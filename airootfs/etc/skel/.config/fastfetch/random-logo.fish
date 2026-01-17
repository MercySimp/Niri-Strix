#!/usr/bin/env fish

# Define logo paths
set logos \
    ~/.config/fastfetch/cat.txt \
    ~/.config/fastfetch/pumpkincat.txt \
    ~/.config/fastfetch/arch.txt

# Pick one at random
set chosen_logo (random choice $logos)

# Run Fastfetch with that logo
fastfetch --logo-type file --logo "$chosen_logo"
