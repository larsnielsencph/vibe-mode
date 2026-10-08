#!/bin/sh
# One-time helper for Lars: passwordless SleepDisabled toggle + boot safety net.
# Review the script, then: sudo ./install-passwordless-pmset.sh
set -euo pipefail

SUDOERS=/etc/sudoers.d/vibemode
PLIST=/Library/LaunchDaemons/dk.lars.vibemode.safetynet.plist

cat > /tmp/vibemode.sudoers <<'EOF'
# VibeMode — passwordless toggle of the SleepDisabled flag only.
%admin ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0
%admin ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1
EOF
chown root:wheel /tmp/vibemode.sudoers
chmod 440 /tmp/vibemode.sudoers
visudo -cf /tmp/vibemode.sudoers
mv /tmp/vibemode.sudoers "$SUDOERS"
chown root:wheel "$SUDOERS"
chmod 440 "$SUDOERS"

cat > "$PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>dk.lars.vibemode.safetynet</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/pmset</string>
        <string>-a</string>
        <string>disablesleep</string>
        <string>0</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>LaunchOnlyOnce</key>
    <true/>
</dict>
</plist>
PLIST
chown root:wheel "$PLIST"
chmod 644 "$PLIST"
launchctl bootout system "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap system "$PLIST" >/dev/null 2>&1 || launchctl load "$PLIST"

echo "Installed $SUDOERS and $PLIST"
echo "Test: sudo -n pmset -a disablesleep 0 && echo OK"
