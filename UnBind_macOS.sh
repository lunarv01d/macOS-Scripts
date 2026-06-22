#!/bin/bash

loggedInUser=$(stat -f%Su /dev/console)

if [[ "$loggedInUser" == "root" || -z "$loggedInUser" ]]; then

echo "No user logged in."

exit 1

fi

echo "Processing user: $loggedInUser"

if dscl . -read /Users/$loggedInUser OriginalNodeName >/dev/null 2>&1; then

echo "Mobile account detected."

attributes=(

OriginalNodeName

SMBPrimaryGroupSID

SMBGroupRID

SMBUserRID

SMBUserSID

cached_groups

cached_auth_policy

CopyTimestamp

AltSecurityIdentities

)

for attribute in "${attributes[@]}"; do

dscl . -delete /Users/$loggedInUser "$attribute" 2>/dev/null

done

chown -R "$loggedInUser":staff "/Users/$loggedInUser"

echo "Successfully converted $loggedInUser to local account."

else

echo "Account is already local."

fi

exit 0