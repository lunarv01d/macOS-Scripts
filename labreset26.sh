#!/bin/bash

# WARNING: Erases the Mac and installs the selected macOS full installer.
# Jamf Parameters:
#   4: Secure Token admin username
#   5: Secure Token admin password
#   6: Optional macOS installer version to download (major like 26, or full like 26.0)

set -e

ADMIN_USER="$4"
ADMIN_PASS="$5"
TARGET_VERSION="$6"
TARGET_INSTALLER_NAME="Install macOS Tahoe.app"
VOLUME_NAME="Macintosh HD"
LOG="/var/log/lisd-erase-install.log"
SCRIPT_VERSION="2026-07-08-tahoe-version-resolution"

exec > >(tee -a "$LOG") 2>&1

echo "Param 1: $1"
echo "Param 2: $2"
echo "Param 3: $3"
echo "Param 4: $4"
echo "Param 5 length: ${#5}"
echo "Param 6: ${TARGET_VERSION:-not set}"

echo "===== LISD Erase Install Started ====="
echo "Script version: $SCRIPT_VERSION"
date

if [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASS" ]; then
    echo "ERROR: Missing Jamf parameters."
    echo "Parameter 4: Secure Token admin username."
    echo "Parameter 5: Secure Token admin password."
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
BOOTSTRAP_TOKEN_STATUS=$(/usr/bin/profiles status -type bootstraptoken 2>&1 || true)
echo "$BOOTSTRAP_TOKEN_STATUS"
BOOTSTRAP_TOKEN_ESCROWED="false"
if echo "$BOOTSTRAP_TOKEN_STATUS" | /usr/bin/grep -qi "Bootstrap Token escrowed to server: YES"; then
    BOOTSTRAP_TOKEN_ESCROWED="true"
fi

if [ -n "$TARGET_VERSION" ]; then
    REQUESTED_VERSION="$TARGET_VERSION"
    if [[ "$TARGET_VERSION" =~ ^[0-9]+$ ]]; then
        echo "Jamf parameter 6 is a major version ($TARGET_VERSION); resolving the newest available $TARGET_VERSION.x full installer..."
        FULL_INSTALLER_LIST=$(/usr/sbin/softwareupdate --list-full-installers 2>&1 || true)
        echo "$FULL_INSTALLER_LIST"
        RESOLVED_VERSION=$(echo "$FULL_INSTALLER_LIST" | /usr/bin/awk -v major="$TARGET_VERSION" '
            /Version: / {
                version=$0
                sub(/^.*Version: /, "", version)
                sub(/,.*$/, "", version)
                if (version == major || index(version, major ".") == 1) {
                    print version
                    exit
                }
            }
        ')

        if [ -z "$RESOLVED_VERSION" ]; then
            echo "ERROR: Could not find an available macOS $TARGET_VERSION full installer."
            echo "Use a full version shown by softwareupdate --list-full-installers, or leave Jamf parameter 6 blank to fetch the newest available installer."
            exit 1
        fi

        REQUESTED_VERSION="$RESOLVED_VERSION"
        echo "Resolved macOS $TARGET_VERSION to full installer version $REQUESTED_VERSION."
    fi

    echo "Downloading macOS full installer version $REQUESTED_VERSION..."
    if ! /usr/sbin/softwareupdate --fetch-full-installer --full-installer-version "$REQUESTED_VERSION"; then
        echo "ERROR: softwareupdate could not fetch macOS full installer version $REQUESTED_VERSION."
        echo "Run softwareupdate --list-full-installers on a target Mac and set Jamf parameter 6 to an exact listed Tahoe version."
        exit 1
    fi
else
    echo "No target installer version supplied in Jamf parameter 6."
    echo "Downloading newest available macOS full installer; this policy will only continue if it resolves to $TARGET_INSTALLER_NAME."
    /usr/sbin/softwareupdate --fetch-full-installer
fi

echo "Finding installer..."
if [ -d "/Applications/$TARGET_INSTALLER_NAME" ]; then
    INSTALLER="/Applications/$TARGET_INSTALLER_NAME"
else
    INSTALLER=$(/bin/ls -dt /Applications/Install\ macOS*.app 2>/dev/null | /usr/bin/head -n 1 || true)
fi

if [ -z "$INSTALLER" ]; then
    echo "ERROR: No macOS installer found in /Applications."
    echo "Cache $TARGET_INSTALLER_NAME first, or set Jamf parameter 6 to a specific Tahoe full installer version."
    exit 1
fi

INSTALLER_BASENAME=$(/usr/bin/basename "$INSTALLER")
if [ "$INSTALLER_BASENAME" != "$TARGET_INSTALLER_NAME" ]; then
    echo "ERROR: Found $INSTALLER_BASENAME, but this lab reset is intended to install $TARGET_INSTALLER_NAME."
    echo "Set Jamf parameter 6 to a Tahoe version or cache /Applications/$TARGET_INSTALLER_NAME."
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

if [ "$BOOTSTRAP_TOKEN_ESCROWED" = "true" ]; then
    echo "Bootstrap Token is escrowed; startosinstall will use MDM authorization instead of stdin credentials."
else
    echo "Validating admin password before startosinstall..."
    if ! /usr/bin/dscl /Local/Default -authonly "$ADMIN_USER" "$ADMIN_PASS"; then
        echo "ERROR: Password validation failed for $ADMIN_USER."
        echo "Apple Silicon erase installs require valid credentials for a Secure Token/volume-owner admin."
        exit 1
    fi

    USER_GUID=$(/usr/bin/dscl . -read "/Users/$ADMIN_USER" GeneratedUID 2>/dev/null | /usr/bin/awk '{print $2}')
    if [ -n "$USER_GUID" ]; then
        echo "Checking APFS volume ownership for $ADMIN_USER ($USER_GUID)..."
        VOLUME_OWNER_STATUS=$(/usr/sbin/diskutil apfs listUsers / 2>/dev/null | /usr/bin/awk -v guid="$USER_GUID" '
            $0 ~ guid { in_user=1; owner="" }
            in_user && /Volume Owner:/ { owner=$0 }
            in_user && owner != "" { print owner; exit }
        ')

        if [ -z "$VOLUME_OWNER_STATUS" ]; then
            echo "WARNING: Could not confirm APFS volume-owner status for $ADMIN_USER."
            echo "startosinstall on Apple Silicon requires the supplied account to be a volume owner."
        elif echo "$VOLUME_OWNER_STATUS" | /usr/bin/grep -qi "Yes"; then
            echo "APFS volume-owner status: $VOLUME_OWNER_STATUS"
        else
            echo "ERROR: $ADMIN_USER is not an APFS volume owner: $VOLUME_OWNER_STATUS"
            echo "Use the password for a volume-owner account, or issue the Jamf MDM EraseDevice command instead of startosinstall."
            exit 1
        fi
    else
        echo "WARNING: Could not read GeneratedUID for $ADMIN_USER; unable to verify APFS volume-owner status."
    fi

fi

echo "Starting erase install..."
echo "This Mac will reboot and erase itself."

set +e
if [ "$BOOTSTRAP_TOKEN_ESCROWED" = "true" ]; then
    "$STARTOSINSTALL" \
        --eraseinstall \
        --newvolumename "$VOLUME_NAME" \
        --agreetolicense \
        --forcequitapps \
        --allowremoval \
        --nointeraction
    RESULT=$?
else
    printf '%s\n' "$ADMIN_PASS" | "$STARTOSINSTALL" \
        --eraseinstall \
        --newvolumename "$VOLUME_NAME" \
        --agreetolicense \
        --forcequitapps \
        --allowremoval \
        --nointeraction \
        --user "$ADMIN_USER" \
        --stdinpass
    RESULT=$?
fi
set -e

echo "startosinstall exited with code: $RESULT"

if [ "$RESULT" -ne 0 ]; then
    echo "===== startosinstall diagnostics ====="
    echo "Recent install.log entries:"
    /usr/bin/tail -n 120 /var/log/install.log 2>/dev/null || true

    echo "Recent startosinstall/osinstallersetupd unified log entries:"
    /usr/bin/log show \
        --style syslog \
        --last 15m \
        --predicate 'process == "startosinstall" || process == "osinstallersetupd" || eventMessage CONTAINS[c] "OSISClient" || eventMessage CONTAINS[c] "LACredential" || eventMessage CONTAINS[c] "OSInstallerSetup"' \
        2>/dev/null || true

    echo "If the unified log mentions password rejection or LocalAuthentication failures, verify Jamf parameter 5 and use a volume-owner account password."
    echo "If it mentions package, personalization, or compatibility failures, rebuild/redownload the Tahoe installer and rerun the policy."
fi

exit "$RESULT"
