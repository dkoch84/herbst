#!/usr/bin/env bash

# savestate.sh - Save herbstluftwm window state
# Outputs tag layouts and window positions for later restoration
#
# Usage: savestate.sh > mystate

hc() { "${herbstclient_command[@]:-herbstclient}" "$@" ;}

# Extract all window IDs (0x...) from a layout string
extract_window_ids() {
    echo "$1" | grep -oE '0x[0-9a-fA-F]+'
}

# Strip window IDs from layout, keeping structure
strip_window_ids() {
    echo "$1" | sed -E 's/0x[0-9a-fA-F]+//g' | sed -E 's/  +/ /g'
}

# Get window class for a window ID
get_window_class() {
    hc get_attr "clients.$1.class" 2>/dev/null
}

# Parse a layout tree and output frame contents in depth-first order
# This walks the tree structure and for each "clients" node, outputs the windows
parse_frames() {
    local layout="$1"
    local winid_to_class="$2"
    local frame_num=0

    # Extract each (clients ...) block using grep and process in order
    # The -o gives us each match, preserving depth-first order from the string
    echo "$layout" | grep -oE '\(clients [^)]+\)' | while read -r clients_block; do
        # Extract window IDs from this clients block
        local winids=$(echo "$clients_block" | grep -oE '0x[0-9a-fA-F]+')

        if [[ -n "$winids" ]]; then
            local classes=""
            for winid in $winids; do
                # Look up class from our mapping
                local class=$(grep "^$winid=" <<< "$winid_to_class" | cut -d= -f2)
                if [[ -n "$class" ]]; then
                    classes="$classes $class"
                fi
            done
            classes="${classes# }"  # trim leading space
            if [[ -n "$classes" ]]; then
                echo "FRAME $frame_num $classes"
            fi
        fi

        ((frame_num++))
    done
}

# Build a mapping of tag -> monitor index
declare -A tag_to_monitor
monitor_count=$(hc attr monitors.count)
for ((i=0; i<monitor_count; i++)); do
    mon_tag=$(hc attr monitors.$i.tag 2>/dev/null)
    if [[ -n "$mon_tag" ]]; then
        tag_to_monitor["$mon_tag"]=$i
    fi
done

# Tags to skip (float/scratchpad tags managed by autostart)
SKIP_TAGS="8 9"

# Main: iterate through all tags
hc complete 1 use | while read -r tag; do
    # Skip float/scratchpad tags
    if [[ " $SKIP_TAGS " =~ " $tag " ]]; then
        continue
    fi

    layout=$(hc dump "$tag" 2>/dev/null)

    # Skip empty layouts or tags with no windows
    [[ -z "$layout" ]] && continue

    # Build window ID to class mapping
    winid_to_class=""
    for winid in $(extract_window_ids "$layout"); do
        class=$(get_window_class "$winid")
        if [[ -n "$class" ]]; then
            winid_to_class+="$winid=$class"$'\n'
        fi
    done

    # Output tag header
    echo "TAG $tag"

    # Output which monitor this tag is on (if any)
    if [[ -n "${tag_to_monitor[$tag]}" ]]; then
        echo "MONITOR ${tag_to_monitor[$tag]}"
    fi

    # Output stripped layout (structure only)
    echo "LAYOUT $(strip_window_ids "$layout")"

    # Output frame contents
    parse_frames "$layout" "$winid_to_class"

    # Blank line between tags
    echo ""
done
