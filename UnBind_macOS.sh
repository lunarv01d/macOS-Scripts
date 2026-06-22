#!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root."
  exit 1
fi

convert_mobile_account() {
  local user="$1"
  local userRecord="/Users/$user"

  echo "Processing mobile account: $user"

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
    if dscl . -read "/Users/$user" "$attribute" >/dev/null 2>&1; then
      dscl . -delete "/Users/$user" "$attribute" 2>/dev/null
      echo "  Removed $attribute"
    fi
  done

  if dscl . -read "/Users/$user" AuthenticationAuthority >/dev/null 2>&1; then
    dscl . -read "/Users/$user" AuthenticationAuthority | tail -n +2 | while IFS= read -r authValue; do
      if [[ "$authValue" == *"Active Directory"* || "$authValue" == *"Kerberosv5"* || "$authValue" == *"LocalCachedUser"* ]]; then
        dscl . -delete "/Users/$user" AuthenticationAuthority "$authValue" 2>/dev/null && echo "  Removed AuthenticationAuthority entry"
      fi
    done
  fi

  dscl . -create "/Users/$user" NFSHomeDirectory "$userRecord" 2>/dev/null
  dscl . -create "/Users/$user" PrimaryGroupID 20 2>/dev/null

  if [[ -d "$userRecord" ]]; then
    chown -R "$user":staff "$userRecord"
    echo "  Reset ownership for home directory."
  fi

  echo "  Converted $user to local account."
}

mobileUsers=$(dscl . -list /Users OriginalNodeName 2>/dev/null | awk '{print $1}')

if [[ -z "$mobileUsers" ]]; then
  echo "No mobile accounts found."
else
  while IFS= read -r user; do
    if [[ -n "$user" ]]; then
      convert_mobile_account "$user"
    fi
  done <<< "$mobileUsers"
fi

unbind_ad() {
  echo "Checking for Active Directory binding..."
  if /usr/sbin/dsconfigad -show >/dev/null 2>&1; then
    echo "Active Directory binding detected. Removing AD binding..."
    if /usr/sbin/dsconfigad -remove -force >/dev/null 2>&1; then
      echo "Active Directory unbind complete."
    elif /usr/sbin/dsconfigad -remove >/dev/null 2>&1; then
      echo "Active Directory unbind complete."
    else
      echo "Failed to remove Active Directory binding."
      /usr/sbin/dsconfigad -show
      exit 1
    fi
  else
    echo "No Active Directory binding found."
  fi
}

unbind_ad

exit 0