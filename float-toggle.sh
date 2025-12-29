#!/usr/bin/env bash

# float-toggle.sh - Toggle current window to/from float2 (tag 9)
# Moves window to floating scratchpad and back to original tag

hc() { herbstclient "$@"; }

FLOAT_TAG="9"
FLOAT_MONITOR="float2"

# Get the focused window ID
winid=$(hc get_attr clients.focus.winid 2>/dev/null)

if [[ -z "$winid" ]]; then
    # No focused window
    exit 0
fi

# Get the current tag of the focused window
current_tag=$(hc get_attr clients.focus.tag 2>/dev/null)

if [[ "$current_tag" == "$FLOAT_TAG" ]]; then
    # Window is on float tag - move it back to original tag
    original_tag=$(hc get_attr clients.focus.my_original_tag 2>/dev/null)

    if [[ -n "$original_tag" ]]; then
        # Move window back without following it
        hc move "$original_tag"
        # Clean up the attribute
        hc remove_attr clients.focus.my_original_tag 2>/dev/null
    fi
else
    # Window is on a regular tag - save tag and move to float
    # Create attribute to store original tag
    hc new_attr string clients.focus.my_original_tag 2>/dev/null
    hc set_attr clients.focus.my_original_tag "$current_tag"

    # Move to float tag
    hc move "$FLOAT_TAG"
    # Focus then raise the float monitor to keep it on top
    hc focus_monitor "$FLOAT_MONITOR"
    hc raise_monitor "$FLOAT_MONITOR"
fi
