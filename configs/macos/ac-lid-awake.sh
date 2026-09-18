#!/bin/bash
# ac-lid-awake - keep a MacBook awake with the lid closed, but only on AC power.
#
# Run as root by the dev.jiun.ac-lid-awake LaunchDaemon (modules/macos.sh copies
# this file to /usr/local/libexec and never runs it from the repo).
#
# `pmset sleep 0` only stops idle sleep; closing the lid still sleeps the Mac
# unless SleepDisabled is set, and SleepDisabled has no per-power-source form.
# So this loop follows the power source: SleepDisabled on while on AC, off on
# battery. Unplugging with the lid already closed puts the Mac to sleep right
# away instead of leaving it running in a bag.
set -u

readonly POLL_SECONDS=5

on_ac() {
    pmset -g ps | head -n 1 | grep -q "'AC Power'"
}

lid_closed() {
    ioreg -r -k AppleClamshellState -d 4 | grep -q '"AppleClamshellState" = Yes'
}

sleep_disabled() {
    pmset -g | awk '/SleepDisabled/ { print $2; found = 1 } END { if (!found) print 0 }'
}

while true; do
    if on_ac; then
        want=1
    else
        want=0
    fi

    if [[ "$(sleep_disabled)" != "$want" ]]; then
        pmset -a disablesleep "$want"
        # Only on the AC -> battery transition, so this never fights a sleep
        # macOS itself decided against.
        if [[ "$want" == 0 ]] && lid_closed; then
            pmset sleepnow
        fi
    fi

    sleep "$POLL_SECONDS"
done
