#!/usr/bin/env bash

# loadstate.sh - Restore herbstluftwm window state
# Reads state file from stdin or argument, restores layouts and launches apps
#
# Usage: loadstate.sh < mystate
#    or: loadstate.sh mystate
#    or: loadstate.sh --dry-run mystate

DRY_RUN=false
if [[ "$1" == "--dry-run" || "$1" == "-n" ]]; then
    DRY_RUN=true
    shift
fi

hc() { "${herbstclient_command[@]:-herbstclient}" "$@" ;}

# get_window_token: the same token savestate.sh wrote for a window
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/window-token.sh"

# === LAUNCH COMMAND MAPPING ===
# Edit this function to customize how apps are launched
# Argument: $1 = window token from savestate.sh (usually the window class;
# see get_window_token in window-token.sh for the variants)
get_launch_command() {
    local class="$1"

    case "$class" in
        qutebrowser)
            echo "qutebrowser"
            ;;
        qutebrowser:matrix)
            echo "qutebrowser.matrix https://app.element.io"
            ;;
        qutebrowser:1)
            echo "qutebrowser.wrapper https://youtube.com"
            ;;
        qutebrowser:*)
            echo "qutebrowser.wrapper -r ${class#qutebrowser:}"
            ;;
        focus-dash)
            echo "focus-dash"
            ;;
        Alacritty)
            echo "alacritty"
            ;;
        Slack|slack)
            echo "slack"
            ;;
        Code|code)
            echo "code"
            ;;
        Google-chrome)
            echo "$HOME/scripts/utils/chrome-debug"
            ;;
        microsoft-edge)
            echo "microsoft-edge-stable"
            ;;
        dolphin)
            echo "dolphin --platformtheme qt6ct"
            ;;
        *)
            # Default: try lowercase class name as command
            echo "${class,,}"
            ;;
    esac
}

# Seconds to wait for a launched app's window before moving on. Waiting keeps
# the frame focused until the window lands in it.
WINDOW_TIMEOUT=20

# Seconds place_windows waits for late windows before placing what it has.
# focus-dash alone may wait up to 60s for its server.
PLACE_TIMEOUT=90

# Count all managed windows
client_count() {
    hc attr clients 2>/dev/null | grep -cE '0x[0-9a-fA-F]+'
}

# Wait until the number of windows exceeds $1
wait_for_window() {
    local before="$1"
    local class="$2"
    local waited=0

    while (( waited < WINDOW_TIMEOUT * 10 )); do
        if (( $(client_count) > before )); then
            return 0
        fi
        sleep 0.1
        ((waited++))
    done
    echo "    Warning: $class window did not appear within ${WINDOW_TIMEOUT}s"
    return 1
}

# Launch an app and wait for its window
launch_app() {
    local class="$1"
    local cmd=$(get_launch_command "$class")

    if [[ -n "$cmd" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo "    [DRY-RUN] Would launch: $cmd"
        else
            echo "  Launching: $cmd"
            local before=$(client_count)
            # Use herbstclient spawn like autostart does
            hc spawn $cmd
            wait_for_window "$before" "$class"
            sleep 0.5  # Let the window settle before focus moves on
        fi
    fi
}

# What the state file asked for, filled in by process_state and used by
# place_windows once everything is launched
declare -a PLACE_TAGS=()           # tags in file order
declare -A PLACE_LAYOUT=()         # tag -> layout without window IDs
declare -A PLACE_FRAMES=()         # "tag frame" -> tokens
declare -A PLACE_WANTED=()         # tag -> set when it has any windows

# Launching only puts a window in whichever frame has focus when it finally
# maps, and some apps (focus-dash waits for its server) map late. So once
# everything is launched, match each expected token to a real window and
# reload every layout with the window IDs filled in: hlwm then moves each
# window into its saved frame no matter where it landed.
place_windows() {
    local timeout="$PLACE_TIMEOUT"
    local -A pool=()               # token -> unclaimed window IDs
    local -A need=()               # token -> how many windows the file asks for
    local winid token tag layout frame out rest ids key missing

    for key in "${!PLACE_FRAMES[@]}"; do
        for token in ${PLACE_FRAMES[$key]}; do
            need[$token]=$(( ${need[$token]:-0} + 1 ))
        done
    done

    # Wait until every expected window exists (or give up and place the rest)
    while :; do
        pool=()
        for winid in $(hc attr clients 2>/dev/null | grep -oE '0x[0-9a-fA-F]+'); do
            token=$(get_window_token "$winid")
            [[ -n "$token" ]] && pool[$token]+=" $winid"
        done

        missing=0
        for token in "${!need[@]}"; do
            ids=(${pool[$token]})
            (( ${#ids[@]} < ${need[$token]} )) && missing=1
        done

        (( missing == 0 || timeout-- <= 0 )) && break
        sleep 1
    done

    for tag in "${PLACE_TAGS[@]}"; do
        [[ -z "${PLACE_WANTED[$tag]}" ]] && continue   # no windows saved here
        layout="${PLACE_LAYOUT[$tag]}"
        out=""
        frame=0
        # Walk the (clients ...) nodes in the same order savestate.sh numbered them
        while [[ "$layout" == *"(clients"* ]]; do
            rest="${layout#*(clients}"
            out+="${layout%%(clients*}(clients${rest%%)*}"
            rest="${rest#*)}"
            for token in ${PLACE_FRAMES["$tag $frame"]}; do
                ids=(${pool[$token]})
                if (( ${#ids[@]} > 0 )); then
                    out+=" ${ids[0]}"
                    pool[$token]="${ids[*]:1}"
                else
                    echo "  Warning: no $token window to place in tag $tag frame $frame"
                fi
            done
            out+=")"
            layout="$rest"
            ((frame++))
        done
        out+="$layout"
        hc load "$tag" "$out"
    done
    echo "Placed windows into their saved frames"
}

# Tags to skip (float/scratchpad tags managed by autostart)
SKIP_TAGS="8 9"

# Process state file
process_state() {
    local current_tag=""
    local current_layout=""
    local current_monitor=""
    local current_frame_pos=0  # Track which frame we're at within a tag
    local need_frame_reset=true  # Flag to reset to frame 0 when starting a new tag
    local skip_current_tag=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^TAG\ (.+)$ ]]; then
            # New tag section
            current_tag="${BASH_REMATCH[1]}"
            current_monitor=""  # Reset for new tag
            current_frame_pos=0
            need_frame_reset=true

            # Check if this tag should be skipped
            if [[ " $SKIP_TAGS " =~ " $current_tag " ]]; then
                skip_current_tag=true
                echo "Skipping tag: $current_tag (float/scratchpad)"
                continue
            fi
            skip_current_tag=false
            echo "Processing tag: $current_tag"

        elif [[ "$line" =~ ^MONITOR\ ([0-9]+)$ ]]; then
            [[ "$skip_current_tag" == true ]] && continue
            # Monitor assignment for this tag
            current_monitor="${BASH_REMATCH[1]}"
            if [[ "$DRY_RUN" == true ]]; then
                echo "  [DRY-RUN] Would assign to monitor $current_monitor"
            fi

        elif [[ "$line" =~ ^LAYOUT\ (.+)$ ]]; then
            [[ "$skip_current_tag" == true ]] && continue
            # Layout definition
            current_layout="${BASH_REMATCH[1]}"

            # Create the tag and load the empty layout
            if [[ "$DRY_RUN" == true ]]; then
                echo "  [DRY-RUN] Would load layout: $current_layout"
            else
                hc add "$current_tag" 2>/dev/null
                hc load "$current_tag" "$current_layout"
                PLACE_TAGS+=("$current_tag")
                PLACE_LAYOUT[$current_tag]="$current_layout"
                echo "  Loaded layout for tag $current_tag"
            fi

        elif [[ "$line" =~ ^FRAME\ ([0-9]+)\ (.+)$ ]]; then
            [[ "$skip_current_tag" == true ]] && continue
            # Frame with windows
            local frame_num="${BASH_REMATCH[1]}"
            local classes="${BASH_REMATCH[2]}"

            # Focus the correct monitor first, then switch to tag
            if [[ "$DRY_RUN" == true ]]; then
                if [[ -n "$current_monitor" ]]; then
                    echo "  [DRY-RUN] Would focus monitor $current_monitor"
                fi
                echo "  [DRY-RUN] Would use tag $current_tag, navigate to frame $frame_num"
            else
                if [[ -n "$current_monitor" ]]; then
                    hc focus_monitor "$current_monitor"
                fi
                hc use "$current_tag"

                # Reset to frame 0 on first frame of this tag
                if [[ "$need_frame_reset" == true ]]; then
                    hc cycle_frame -999  # Go to first frame
                    current_frame_pos=0
                    need_frame_reset=false
                fi

                # Cycle forward to reach the target frame
                local frames_to_advance=$((frame_num - current_frame_pos))
                if [[ $frames_to_advance -gt 0 ]]; then
                    hc cycle_frame "$frames_to_advance"
                fi
                current_frame_pos=$frame_num
            fi

            # Launch each app in this frame
            PLACE_FRAMES["$current_tag $frame_num"]="$classes"
            PLACE_WANTED[$current_tag]=1
            for class in $classes; do
                launch_app "$class"
            done

            # Small delay to let windows settle
            if [[ "$DRY_RUN" != true ]]; then
                sleep 1
            fi
        fi
    done
}

# Main
if [[ -n "$1" && -f "$1" ]]; then
    # Read from file argument
    process_state < "$1"
else
    # Read from stdin
    process_state
fi

if [[ "$DRY_RUN" != true ]]; then
    place_windows
fi

if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo "=== DRY-RUN COMPLETE (no changes made) ==="
else
    echo "State restoration complete!"
fi
