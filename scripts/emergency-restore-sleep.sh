#!/bin/sh
# Restore stock macOS lid-close sleep. Safe to run any time.
# Usage: sudo ./emergency-restore-sleep.sh
set -e
/usr/bin/pmset -a disablesleep 0
/usr/bin/pmset -g | /usr/bin/grep -i SleepDisabled || true
echo "SleepDisabled should read 0 (or the line may be absent). Lid close will sleep again."
