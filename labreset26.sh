#!/bin/bash

# WARNING: Erases the Mac and installs the newest available macOS full installer.
# Jamf Parameters:

set -e

ADMIN_USER="$4"
ADMIN_PASS="$5"
VOLUME_NAME="Macintosh HD"
LOG="/var/log/lisd-erase-install.log"

exec > >(tee -a "$LOG") 2>&1

echo "Param 1: $1"
echo "Param 2: $2"
echo "Param 3: $3"
echo "Param 4: $4"
echo "Param 5 length: ${#5}"

echo "===== LISD Erase Install Started ====="
date

if [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASS" ]; then
    echo "ERROR: Missing Jamf parameters."
    echo "Parameter 4."
    echo "Parameter 5."
    exit 1
fi

echo "Admin user: $ADMIN_USER"
echo "Volume name: $VOLUME_NAME"

ARCH=$(/usr/bin/arch)
if [ "$ARCH" != "arm64" ]; then
    echo "ERROR: This script is intended for Apple Silicon Macs only."
    exit 1
fi

echo "Checking Bootstrap Token status..."
/usr/bin/profiles status -type bootstraptoken || true

echo "Downloading newest macOS full installer..."
/usr/sbin/softwareupdate --fetch-full-installer

echo "Finding newest installer..."
INSTALLER=$(/bin/ls -dt /Applications/Install\ macOS*.app 2>/dev/null | /usr/bin/head -n 1)

if [ -z "$INSTALLER" ]; then
    echo "ERROR: No macOS installer found in /Applications."
    exit 1
fi

STARTOSINSTALL="$INSTALLER/Contents/Resources/startosinstall"

if [ ! -x "$STARTOSINSTALL" ]; then
    echo "ERROR: startosinstall not found in $INSTALLER."
    exit 1
fi

echo "Using installer: $INSTALLER"

if ! /usr/bin/dscl . -read "/Users/$ADMIN_USER" >/dev/null 2>&1; then
    echo "ERROR: Admin user does not exist locally: $ADMIN_USER"
    exit 1
fi

echo "Checking Secure Token status..."
/usr/sbin/sysadminctl -secureTokenStatus "$ADMIN_USER" 2>&1 || true

echo "Starting erase install..."
echo "This Mac will reboot and erase itself."

echo "$ADMIN_PASS" | "$STARTOSINSTALL" \
    --eraseinstall \
    --newvolumename "$VOLUME_NAME" \
    --agreetolicense \
    --forcequitapps \
    --nointeraction \
    --user "$ADMIN_USER" \
    --stdinpass

RESULT=$?
echo "startosinstall exited with code: $RESULT"

exit "$RESULT"
