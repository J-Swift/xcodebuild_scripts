#!/usr/bin/env bash

set -e


################################################################################
# Config
################################################################################

### General settings

# Set this to true if you want to skip y/n dialogs
AUTO_ACCEPT=false
# The number of recent archives we should list to ask user for selection
NUM_ARCHIVES_TO_SHOW=5

### Path settings

# Set this to explicitly declare which xcarchive you want to operate on rather
# than having to select from a list
ARCHIVE_PATH_OVERRIDE=
# Where your .xcarchives get exported to
ARCHIVES_BASE_PATH="${HOME}/Library/Developer/Xcode/Archives"
# Where your .mobileprovision files get installed to
PROFILES_BASE_PATH="${HOME}/Library/MobileDevice/Provisioning Profiles"
# Where you want the resulting .ipa to be exported to
EXPORT_BASE_PATH="${HOME}/Desktop"

### Output customization

SPACER='    '
HL_INFO_COLOR='\e[01;37m' # White
INFO_COLOR='\e[00;37m' # Gray
WARN_COLOR='\e[00;33m' # Yellowish gold
ERROR_COLOR='\e[00;31m' # Red
RESET_COLOR='\e[00m' # ANSI code to reset color settings. Probably shouldn't change this


################################################################################
# Setup
################################################################################

# TODO(jpr): command line flags

# $1 the message to output; newline is automatically added
# $2 the ANSI color code to print the message with
# @return nothing
function colored_msg()
{
  local MSG=$1
  local COLOR_CODE=$2

  printf "${COLOR_CODE}${MSG}${RESET_COLOR}\n"
}

# $1 the message to output; newline is automatically added
# @return nothing
function msg_hl_info()
{
  local MSG=$1

  colored_msg "[INFO]${SPACER}${MSG}" "${HL_INFO_COLOR}"
}

# $1 the message to output; newline is automatically added
# @return nothing
function msg_info()
{
  local MSG=$1

  colored_msg "[INFO]${SPACER}${MSG}" "${INFO_COLOR}"
}

# $1 the message to output; newline is automatically added
# @return nothing
function msg_warn()
{
  local MSG=$1

  colored_msg "[WARN]${SPACER}${MSG}" "${WARN_COLOR}"
}

# $1 the message to output; newline is automatically added
# @return nothing
function msg_error()
{
  local MSG=$1

  colored_msg "[ERROR]${SPACER}${MSG}" "${ERROR_COLOR}"
}

# $1 the prompt to display to the user
# $2 the default value to use on empty input
# @return USR_INPUT
function get_user_input()
{
  local PROMPT=$1
  local DEFAULT=$2
  
  echo
  read -r -p "${PROMPT}: " USR_INPUT
  if [ -z "${USR_INPUT}" ]; then
    USR_INPUT="${DEFAULT}"
  fi
}

# $1 the prompt to display to the user
# $2 the default value to use on empty input
# @return USR_INPUT of either 'y' or 'n'
function yes_no_prompt()
{
  if [ true = "${AUTO_ACCEPT}" ]; then
    USR_INPUT="y"
    return
  fi

  local PROMPT=$1
  local DEFAULT=$2

  get_user_input "${PROMPT}" "${DEFAULT}"

  while [[ ! $USR_INPUT =~ ^[YyNn]$ ]]; do
    msg_warn "Invalid input"
    get_user_input "${PROMPT}" "${DEFAULT}"
  done
  
  if [ $USR_INPUT == "Y" ]; then
    USR_INPUT="y"
  fi
  if [ $USR_INPUT == "N" ]; then
    USR_INPUT="n"
  fi
}

# @return ARCHIVE set to the absolute path of the .xcarchive chosen by user
function choose_archive()
{
  unset ARCHIVES i
  local ARCHIVES
  while IFS= read -r -d $'\n' filename; do
    ARCHIVES[i++]="${filename}"
  done < <(find "${ARCHIVES_BASE_PATH}" -depth 2 -name "*.xcarchive" | sort -r | head -${NUM_ARCHIVES_TO_SHOW})
  local NUM_ARCHIVES="${#ARCHIVES[@]}"

  for ((i = 0; i < ${#ARCHIVES[@]}; i++)); do
    let local num=i+1
    local LINE="${ARCHIVES[$i]}"
    msg_info "${SPACER}${num}: ${LINE}"
  done
  get_user_input "Which of the above archives do you want to export/sign [1-${NUM_ARCHIVES}]"
  while [ -z "${USR_INPUT}" ] || [ "${USR_INPUT}" -lt 1 ]  || [ "${USR_INPUT}" -gt "${NUM_ARCHIVES}" ]; do
    msg_warn "Invalid input"
    get_user_input "Which of the above archives do you want to export/sign [1-${NUM_ARCHIVES}]"
  done

  ARCHIVE="${ARCHIVES[$USR_INPUT-1]}"
}

# $1 the absolute path to the .xcarchive
# @return UUID set to the detected provisioning profiles UUID
function get_profile_uuid_from_archive()
{
  local ARCHIVE_PATH=$1

  local SEARCH_PATH="${ARCHIVE_PATH}/Products/Applications"
  local UUID_PATTERN='.{8}-.{4}-.{4}-.{4}-.{12}'
  UUID=`find "${SEARCH_PATH}" -name "embedded.mobileprovision" -exec grep -oaE "${UUID_PATTERN}" {} \;`
}

# $1 the absolute path to the .mobileprovision
# @return PROVISIONING_PROFILE_NAME set to the detected provisioning profiles name
# TODO(jpr): combine this with the uuid call
function get_profile_english_name_from_profile()
{
  local PROFILE_PATH=$1

  local RAW_PROVISIONING_PROFILE_NAME=`grep -Ea -1 "<key>Name</key>" "${PROFILE_PATH}" | tail -1 | sed 's/<string>//' | sed 's/<\/string>//'`
  # Trim whitespace
  PROVISIONING_PROFILE_NAME=`echo "${RAW_PROVISIONING_PROFILE_NAME}" | grep -Eo '\w.+\w'`
}


################################################################################
# DO WORK SON
################################################################################

# TODO(jpr): add build capability??
# http://stackoverflow.com/a/19856005/1273175

msg_info
msg_info "[Step 1 of 4] - ARCHIVE"
msg_info

if [ ! -z "${ARCHIVE_PATH_OVERRIDE}" ]; then
  ARCHIVE="${ARCHIVE_PATH_OVERRIDE}"
else
  choose_archive ${ARCHIVES}
fi

msg_hl_info "${SPACER}Archive selected [${ARCHIVE}]"
msg_info "${SPACER}Verifying archive exists"
if [ -z "${ARCHIVE}" ] || [ ! -d "${ARCHIVE}" ]; then
  msg_error "Archive doesn't exist"
  exit 1
fi
msg_info "${SPACER}Archive located"


msg_info
msg_info "[Step 2 of 4] - PROVISIONING PROFILE"
msg_info

msg_info "${SPACER}Detecting which provisioning profile was used to build the archive"
get_profile_uuid_from_archive "${ARCHIVE}"
msg_hl_info "${SPACER}Detected profile with UUID [${UUID}]"
PROFILE_PATH="${PROFILES_BASE_PATH}/${UUID}.mobileprovision"
msg_info "${SPACER}Searching for installed profile at [${PROFILE_PATH}]"
if [ ! -f "${PROFILE_PATH}" ]; then
  msg_error "No provisioning profile found"
  msg_error "You probably need to install it"
  exit 1
fi
msg_info "${SPACER}Profile located"

msg_info "${SPACER}Detecting provisioning profile name"
get_profile_english_name_from_profile "${PROFILE_PATH}"
msg_hl_info "${SPACER}Detected provisioning profile name [${PROVISIONING_PROFILE_NAME}]"


msg_info
msg_info "[Step 3 of 4] - EXPORT PATH"
msg_info

# TODO(jpr): better name detection, currently it is just parsing the first
# 'word' from the .xcarchive filename
ARCHIVE_BASE_NAME=`basename "${ARCHIVE}" .xcarchive | awk '{print $1;}'`
EXPORT_PATH="${EXPORT_BASE_PATH}/${ARCHIVE_BASE_NAME}.ipa"
if [[ -e "${EXPORT_PATH}" ]]; then
  msg_warn "${SPACER}Export path [${EXPORT_PATH}] exists"
  yes_no_prompt "Should I delete the file that is at the current export path [y/n]"
  if [ "y" != "${USR_INPUT}" ]; then
    msg_error "Export path needs to be changed, or current file moved. Exiting..."
    exit 1
  fi
  msg_warn "${SPACER}Deleting [${EXPORT_PATH}]"
  rm -rf "${EXPORT_PATH}"
fi
msg_info "${SPACER}Export path [${EXPORT_PATH}] is clear"


msg_info
msg_info "[Step 4 of 4] - SIGNING/EXPORTING"
msg_info

msg_info "${SPACER}Building and moving to [${EXPORT_PATH}] using [${PROVISIONING_PROFILE_NAME}]"
yes_no_prompt "Shall I proceed [y/n]"
if [ "y" != "${USR_INPUT}" ]; then
  msg_warn "Aborting..."
  exit 1
fi

msg_hl_info "${SPACER}Exporting signed archive..."
xcodebuild -exportArchive -archivePath "${ARCHIVE}" -exportPath "${EXPORT_PATH}" -exportFormat ipa -exportProvisioningProfile "${PROVISIONING_PROFILE_NAME}" 1>/dev/null && msg_hl_info "${SPACER}Done"

