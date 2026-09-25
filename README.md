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
- `FRAME` - Frame index followed by window tokens in that frame

A window token is normally the window class. Windows that share a class but come from different launchers get their own token:

- `focus-dash` - the Focus dashboard qutebrowser (X11 instance `focus-dash`)
- `qutebrowser:NAME` - a qutebrowser started through a session wrapper (`--basedir .../qutebrowser/NAME`), e.g. `qutebrowser:matrix` for Element, `qutebrowser:1` for the YouTube window

## Customizing launch commands

Edit `get_launch_command()` in `loadstate.sh` to map window tokens to launch commands:

```bash
get_launch_command() {
    local class="$1"

    case "$class" in
        qutebrowser)
            echo "qutebrowser"
            ;;
        qutebrowser:matrix)
            echo "qutebrowser.matrix https://app.element.io/..."
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

Each launch waits (up to `WINDOW_TIMEOUT` seconds) for a new window to appear before moving to the next frame. Some apps map their window much later than that (focus-dash waits for its server), so once everything is launched `loadstate.sh` matches every saved token to a real window and reloads each layout with the window IDs filled in. herbstluftwm then moves each window into its saved frame no matter where it first landed.

The token logic lives in `window-token.sh`, which both scripts source, so saving and restoring always agree.

## Files

- `savestate.sh` - Captures current herbstluftwm state
- `loadstate.sh` - Restores state and launches apps
- `window-token.sh` - Shared window token logic
- `mystate` - Example saved state file

## Notes

- Apps are launched via `herbstclient spawn` (same as autostart keybinds)
- Frame navigation uses `cycle_frame` to place windows correctly
- Monitor focus is set before tag switching to ensure correct placement
