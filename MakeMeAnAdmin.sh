#!/bin/bash

###############################################################################
# Temporary Admin via Jamf Self Service
#
# - Detects the current console user
# - Grants that user admin rights
# - Writes a LaunchDaemon that triggers after 30 minutes
# - LaunchDaemon runs a removal script that:
#     * Removes the user from the admin group
#     * Collects a 30-minute system log archive for auditing
#     * Cleans up its own files
#
# The LaunchDaemon continues to count down even across logouts/reboots.
###############################################################################

set -euo pipefail

#========================
# Configurable variables
#========================

ADMIN_DURATION_SECONDS=1800                 # 30 minutes
LABEL="com.company.removeAdmin"            # Change to your org's reverse-DNS
LAUNCH_DAEMON_PLIST="/Library/LaunchDaemons/removeAdmin.plist"
JAMF_SUPPORT_DIR="/Library/Application Support/JAMF"
REMOVAL_SCRIPT="${JAMF_SUPPORT_DIR}/removeAdminRights.sh"
USER_STATE_DIR="/private/var/userToRemove"
USER_FILE="${USER_STATE_DIR}/user"

#========================
# Helper: console user
#========================

# More reliable than `who | awk '/console/...'` on macOS
currentUser=$(/usr/bin/stat -f%Su /dev/console)

if [[ -z "${currentUser}" || "${currentUser}" == "root" ]]; then
    echo "ERROR: Could not determine a valid console user."
    exit 1
fi

echo "Current console user: ${currentUser}"

#=====================================
# Inform the user via a dialog (GUI)
#=====================================

/usr/bin/osascript <<EOF
display dialog "You now have administrative rights for 30 minutes.

DO NOT ABUSE THIS PRIVILEGE.

Your admin access will be automatically removed after the timer expires." \
    buttons {"OK"} default button 1 with title "Temporary Admin Granted"
EOF

#===================================
# Prepare storage for user tracking
#===================================

/bin/mkdir -p "${USER_STATE_DIR}"
/bin/echo "${currentUser}" > "${USER_FILE}"

#===========================================================
# Give the user admin privileges (if they don't have them)
#===========================================================

if /usr/sbin/dseditgroup -o checkmember -m "${currentUser}" admin >/dev/null 2>&1; then
    echo "User ${currentUser} is already in the admin group. Skipping add."
else
    echo "Adding ${currentUser} to the admin group..."
    /usr/sbin/dseditgroup -o edit -a "${currentUser}" -t user admin
fi

#=====================================================
# Ensure the JAMF support directory and removal script
#=====================================================

/bin/mkdir -p "${JAMF_SUPPORT_DIR}"

cat << 'EOF' > "${REMOVAL_SCRIPT}"
#!/bin/bash
set -euo pipefail

USER_STATE_DIR="/private/var/userToRemove"
USER_FILE="${USER_STATE_DIR}/user"
LAUNCH_DAEMON_PLIST="/Library/LaunchDaemons/removeAdmin.plist"
LABEL="com.company.removeAdmin"

if [[ -f "${USER_FILE}" ]]; then
    userToRemove=$(cat "${USER_FILE}")
    echo "Removing ${userToRemove}'s admin privileges..."

    # Remove from admin group if still present
    if /usr/sbin/dseditgroup -o checkmember -m "${userToRemove}" admin >/dev/null 2>&1; then
        /usr/sbin/dseditgroup -o edit -d "${userToRemove}" -t user admin
    else
        echo "User ${userToRemove} is not in the admin group; nothing to remove."
    fi

    # Collect logs for the last 30 minutes for auditing
    /usr/bin/log collect --last 30m --output "${USER_STATE_DIR}/${userToRemove}.logarchive" || \
        echo "WARNING: log collect failed."

    # Cleanup
    /bin/rm -f "${USER_FILE}"
    /bin/rm -f "${LAUNCH_DAEMON_PLIST}"

    # Unload/stop the LaunchDaemon
    /bin/launchctl remove "${LABEL}" 2>/dev/null || true
fi

exit 0
EOF

/bin/chmod 755 "${REMOVAL_SCRIPT}"
/usr/sbin/chown root:wheel "${REMOVAL_SCRIPT}"

#==========================================
# Create the LaunchDaemon plist (XML file)
#==========================================

cat <<EOF > "${LAUNCH_DAEMON_PLIST}"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${REMOVAL_SCRIPT}</string>
    </array>
    <!-- Run once, 30 minutes after load -->
    <key>StartInterval</key>
    <integer>${ADMIN_DURATION_SECONDS}</integer>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF

/usr/sbin/chown root:wheel "${LAUNCH_DAEMON_PLIST}"
/bin/chmod 644 "${LAUNCH_DAEMON_PLIST}"

#========================================
# Load the LaunchDaemon (starts timer)
#========================================

/bin/launchctl load "${LAUNCH_DAEMON_PLIST}"

echo "Temporary admin granted to ${currentUser} for $((ADMIN_DURATION_SECONDS / 60)) minutes."
echo "LaunchDaemon ${LABEL} loaded; removal script will run after the interval."

exit 0
