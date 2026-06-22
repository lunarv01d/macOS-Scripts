#!/bin/bash

# GUI wrapper for AD unbind using SwiftDialog
# Requires: swiftDialog (https://github.com/swiftDialog/swiftDialog)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNBIND_SCRIPT="$SCRIPT_DIR/UnBind_macOS.sh"
DIALOG_ICON="/System/Library/CoreServices/Finder.app/Contents/Resources/Finder.icns"
LOG_FILE="/var/log/unbind_ad_conversion.log"

# Check if running as root
if [[ $(id -u) -ne 0 ]]; then
  /usr/local/bin/dialog \
    --title "Error" \
    --message "This application must be run as root (via sudo or from Jamf)." \
    --icon caution \
    --button1text "OK" \
    --alignment center
  exit 1
fi

# Check if swiftDialog is installed
if ! command -v /usr/local/bin/dialog &> /dev/null; then
  osascript -e 'tell app "System Events" to display dialog "SwiftDialog is not installed.\n\nPlease install from: https://github.com/swiftDialog/swiftDialog" buttons {"OK"} default button 1 with icon caution'
  exit 1
fi

# Show confirmation dialog
CONFIRMATION=$(/usr/local/bin/dialog \
  --title "Unbind from Active Directory" \
  --message "This will:\n\n• Convert mobile accounts to local accounts\n• Unbind this Mac from Active Directory\n• Preserve all user files\n\nAfter completion, you can enroll with Jamf Connect and Entra ID.\n\nThis process cannot be undone. Continue?" \
  --icon "$DIALOG_ICON" \
  --button1text "Continue" \
  --button2text "Cancel" \
  --alignment center)

if [[ $? -ne 0 ]]; then
  exit 0
fi

# Show progress dialog
/usr/local/bin/dialog \
  --title "Processing" \
  --message "Starting AD unbind process...\n\nPlease wait, this may take a few minutes." \
  --icon "$DIALOG_ICON" \
  --progress \
  --button1text "Waiting..." \
  --button1disabled \
  --alignment center &

DIALOG_PID=$!

# Run the unbind script silently
export SILENT_MODE="true"
if bash "$UNBIND_SCRIPT" 2>&1; then
  SCRIPT_EXIT=0
  RESULT_MESSAGE="Successfully completed!\n\nYour Mac has been unbound from Active Directory.\nLocal accounts have been converted.\n\nYou can now enroll with Jamf Connect."
  RESULT_ICON="$DIALOG_ICON"
  BUTTON_TEXT="Done"
else
  SCRIPT_EXIT=$?
  RESULT_MESSAGE="Errors occurred during processing.\n\nPlease check the log file for details:\n$LOG_FILE"
  RESULT_ICON="caution"
  BUTTON_TEXT="View Log"
fi

# Kill the progress dialog
kill $DIALOG_PID 2>/dev/null
wait $DIALOG_PID 2>/dev/null

# Show results dialog
RESULT=$(/usr/local/bin/dialog \
  --title "AD Unbind Complete" \
  --message "$RESULT_MESSAGE" \
  --icon "$RESULT_ICON" \
  --button1text "$BUTTON_TEXT" \
  --alignment center)

if [[ "$BUTTON_TEXT" == "View Log" ]]; then
  open -a "Console" "$LOG_FILE"
fi

exit $SCRIPT_EXIT
