# Herbstluftwm State Save/Load Scripts

Scripts for saving and restoring herbstluftwm window layouts, including apps, frame positions, and monitor assignments.

## Usage

### Save current state
Arrange your workspace how you want it, then:
```bash
savestate.sh > mystate
```

### Restore state
At boot or after closing windows:
```bash
loadstate.sh mystate
```

### Dry run (preview without changes)
```bash
loadstate.sh --dry-run mystate
```

## What gets saved

- Tag layouts (frame splits and ratios)
- Window classes and their frame positions
- Tag-to-monitor assignments
- Frame layout modes (horizontal, vertical, max)

## What gets skipped

Tags 8 and 9 are skipped by default (configured as `SKIP_TAGS` in both scripts). These are float/scratchpad tags managed by your autostart.

## State file format

```
TAG 1
MONITOR 0
LAYOUT (clients vertical:0)
FRAME 0 qutebrowser

TAG 2
MONITOR 1
LAYOUT (split vertical:0.5:0 (split horizontal:0.5:0 (clients vertical:0) (clients horizontal:0)) (clients vertical:0))
FRAME 0 Alacritty
FRAME 1 Slack qutebrowser
FRAME 2 Code
```

- `TAG` - Tag name
- `MONITOR` - Monitor index to display the tag on
- `LAYOUT` - Herbstluftwm layout tree (from `hc dump`)
- `FRAME` - Frame index followed by window classes in that frame

## Customizing launch commands

Edit `get_launch_command()` in `loadstate.sh` to map window classes to launch commands:

```bash
get_launch_command() {
    local class="$1"
    local instance="${2:-1}"  # For multiple windows of same class

    case "$class" in
        qutebrowser)
            if [[ "$instance" == "1" ]]; then
                echo "qutebrowser"
            else
                echo "qutebrowser.matrix https://app.element.io/..."
            fi
            ;;
        Alacritty)
            echo "alacritty"
            ;;
        # Add more mappings here
        *)
            echo "${class,,}"  # Default: lowercase class name
            ;;
    esac
}
```

The `instance` parameter tracks multiple windows of the same class globally across the state file, allowing different launch commands for each (e.g., first qutebrowser = regular, second = Element).

## Files

- `savestate.sh` - Captures current herbstluftwm state
- `loadstate.sh` - Restores state and launches apps
- `mystate` - Example saved state file

## Notes

- Apps are launched via `herbstclient spawn` (same as autostart keybinds)
- Frame navigation uses `cycle_frame` to place windows correctly
- Monitor focus is set before tag switching to ensure correct placement
