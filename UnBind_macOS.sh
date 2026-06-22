#!/bin/bash

LOG_DIR="/var/log"
LOG_FILE="$LOG_DIR/unbind_ad_conversion.log"
SCRIPT_NAME="$(basename "$0")"
START_TIME=$(date +%Y-%m-%d\ %H:%M:%S)

log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_error() {
  log "ERROR" "$@"
}

log_info() {
  log "INFO" "$@"
}

log_success() {
  log "SUCCESS" "$@"
}

if [[ $(id -u) -ne 0 ]]; then
  log_error "This script must be run as root."
  exit 1
fi

if ! touch "$LOG_FILE" 2>/dev/null; then
  LOG_FILE="/tmp/unbind_ad_conversion.log"
  log_info "Unable to write to $LOG_DIR, using $LOG_FILE instead"
fi

log_info "=== Starting AD Unbind and Account Conversion ==="
log_info "Hostname: $(hostname)"
log_info "OS Version: $(sw_vers -productVersion)"

verify_local_auth() {
  local user="$1"
  local userRecord="/Users/$user"

  log_info "Verifying local authentication for $user"

  auth_method=$(dscl . -read "/Users/$user" AuthenticationAuthority 2>/dev/null)

  if echo "$auth_method" | grep -q "LocalCachedUser\|;local;" 2>/dev/null; then
    log_success "Authentication verified: $user is now using local authentication"
    return 0
  else
    log_error "Authentication verification failed for $user"
    log_error "Auth method: $auth_method"
    return 1
  fi
}

convert_mobile_account() {
  local user="$1"
  local userRecord="/Users/$user"
  local failed=0

  log_info "Processing mobile account: $user"

  if [[ ! -d "$userRecord" ]]; then
    log_error "Home directory does not exist for $user: $userRecord"
    return 1
  fi

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
      if dscl . -delete "/Users/$user" "$attribute" 2>/dev/null; then
        log_info "  Removed AD attribute: $attribute"
      else
        log_error "  Failed to remove AD attribute: $attribute"
        failed=1
      fi
    fi
  done

  if dscl . -read "/Users/$user" AuthenticationAuthority >/dev/null 2>&1; then
    dscl . -read "/Users/$user" AuthenticationAuthority | tail -n +2 | while IFS= read -r authValue; do
      if [[ "$authValue" == *"Active Directory"* || "$authValue" == *"Kerberosv5"* ]]; then
        if dscl . -delete "/Users/$user" AuthenticationAuthority "$authValue" 2>/dev/null; then
          log_info "  Removed AuthenticationAuthority: AD/Kerberos entry"
        else
          log_error "  Failed to remove AuthenticationAuthority entry"
          failed=1
        fi
      fi
    done
  fi

  if ! dscl . -create "/Users/$user" NFSHomeDirectory "$userRecord" 2>/dev/null; then
    log_error "  Failed to set NFSHomeDirectory for $user"
    failed=1
  fi

  if ! dscl . -create "/Users/$user" PrimaryGroupID 20 2>/dev/null; then
    log_error "  Failed to set PrimaryGroupID for $user"
    failed=1
  fi

  if ! dscl . -append "/Users/$user" AuthenticationAuthority ";ShadowHash;" 2>/dev/null; then
    log_error "  Failed to set local authentication authority for $user"
    failed=1
  fi

  if [[ -d "$userRecord" ]]; then
    if chown -R "$user":staff "$userRecord"; then
      log_info "  Reset home directory ownership for $user"
    else
      log_error "  Failed to reset home directory ownership for $user"
      failed=1
    fi

    if chmod -R 700 "$userRecord"; then
      log_info "  Set home directory permissions for $user"
    else
      log_error "  Failed to set home directory permissions for $user"
      failed=1
    fi
  fi

  if [[ $failed -eq 0 ]]; then
    if verify_local_auth "$user"; then
      log_success "Successfully converted $user to local account"
      return 0
    else
      log_error "Conversion incomplete: Authentication verification failed for $user"
      return 1
    fi
  else
    log_error "Conversion had errors for $user"
    return 1
  fi
}

convert_mobile_accounts() {
  log_info "Scanning for mobile accounts..."

  mobileUsers=$(dscl . -list /Users OriginalNodeName 2>/dev/null | awk '{print $1}')

  if [[ -z "$mobileUsers" ]]; then
    log_info "No mobile accounts found."
    return 0
  fi

  local conversion_count=0
  local conversion_failed=0

  while IFS= read -r user; do
    if [[ -n "$user" && "$user" != "root" && "$user" != "_"* ]]; then
      if convert_mobile_account "$user"; then
        ((conversion_count++))
      else
        ((conversion_failed++))
      fi
    fi
  done <<< "$mobileUsers"

  log_info "Account conversion complete: $conversion_count successful, $conversion_failed failed"

  if [[ $conversion_failed -gt 0 ]]; then
    return 1
  fi
  return 0
}

unbind_ad() {
  log_info "Checking for Active Directory binding..."

  if ! /usr/sbin/dsconfigad -show >/dev/null 2>&1; then
    log_info "No Active Directory binding detected."
    return 0
  fi

  log_info "Active Directory binding detected. Removing AD binding..."

  if /usr/sbin/dsconfigad -remove -force 2>/dev/null; then
    log_success "Active Directory unbind complete (forced)."
    return 0
  elif /usr/sbin/dsconfigad -remove 2>/dev/null; then
    log_success "Active Directory unbind complete."
    return 0
  else
    log_error "Failed to remove Active Directory binding."
    local ad_config=$(/usr/sbin/dsconfigad -show 2>&1)
    log_error "Current AD Configuration: $ad_config"
    return 1
  fi
}

main() {
  local overall_status=0

  if ! convert_mobile_accounts; then
    log_error "Mobile account conversion had errors"
    overall_status=1
  fi

  if ! unbind_ad; then
    log_error "Active Directory unbind failed"
    overall_status=1
  fi

  local end_time=$(date +%Y-%m-%d\ %H:%M:%S)
  log_info "=== AD Unbind and Account Conversion Complete ==="
  log_info "Start Time: $START_TIME"
  log_info "End Time: $end_time"
  log_info "Exit Status: $overall_status"
  log_info "Log file: $LOG_FILE"

  return $overall_status
}

main
exit $?