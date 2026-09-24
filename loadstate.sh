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

# === LAUNCH COMMAND MAPPING ===
# Edit this function to customize how apps are launched
# Argument: $1 = window token from savestate.sh (usually the window class;
# see get_window_class there for the variants)
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

if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo "=== DRY-RUN COMPLETE (no changes made) ==="
else
    echo "State restoration complete!"
fi
