#!/usr/bin/env bash

# window-token.sh - sourced by savestate.sh and loadstate.sh
# Expects an hc() function to be defined by the caller.

# Get the token loadstate.sh uses to relaunch a window. Usually the window
# class, but windows sharing a class are told apart where it matters:
#   focus-dash          the Focus dashboard (its own X11 instance name)
#   qutebrowser:NAME    a qutebrowser session wrapper (--basedir .../qutebrowser/NAME)
get_window_token() {
    local winid="$1"
    local class instance pid basedir
    class=$(hc get_attr "clients.$winid.class" 2>/dev/null) || return
    instance=$(hc get_attr "clients.$winid.instance" 2>/dev/null)

    if [[ "$instance" == "focus-dash" ]]; then
        echo "focus-dash"
        return
    fi

    if [[ "$class" == "qutebrowser" ]]; then
        pid=$(hc get_attr "clients.$winid.pid" 2>/dev/null)
        basedir=$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | grep -A1 -x -- '--basedir' | tail -n1)
        if [[ "$basedir" =~ /qutebrowser/([^/]+)$ ]]; then
            echo "qutebrowser:${BASH_REMATCH[1]}"
            return
        fi
    fi

    echo "$class"
}
