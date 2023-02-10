#!/bin/bash
set -eu -o pipefail
#
# Script to join host to domain
#
#################################################################
PROGNAME="$( basename "${0}" )"
JOIN_DOMAIN="${JOIN_DOMAIN:-UNDEF}"
JOIN_OU="${JOIN_OU:-}"
JOIN_USER="${JOIN_USER:-Administrator}"
JOIN_CNAME="${JOIN_CNAME:-UNDEF}"
PWCRYPT="${ENCRYPT_PASS:-UNDEF}"
PWSTRNG="${PWSTRING:-}"
PWUNLOCK="${ENCRYPT_KEY:-UNDEF}"
CLIENT_OSNAME="$(
  awk -F "=" '/^NAME/{ print $2}' /etc/os-release |
  sed 's/"//g'
)"
CLIENT_OSVERS="$(
  awk -F "=" '/^VERSION_ID/{ print $2 }' /etc/os-release |
  sed 's/"//g'
)"

# Print a usage-message
function UsageMsg {

  (
      echo "Usage: ${0} [GNU long option] [option] ..."
      echo "  Options:"
      printf "\t-c <ENCRYPTED_PASSWORD>  \n"
      printf "\t-d <AD_FQDN> \n"
      printf "\t-h print this message  \n"
      printf "\t-k <DECRYPTION_KEY>  \n"
      printf "\t-o <OU_PATH>  \n"
      printf "\t-p <CLEARTEXT_PASSWORD>  \n"
      printf "\t-u <USERNAME> \n"
      echo "  GNU long options:"
      printf "\t--domain-fqdn    see -d  \n"
      printf "\t--help           see -h  \n"
      printf "\t--join-crypt     see -c  \n"
      printf "\t--join-key       see -k \n"
      printf "\t--join-password  see -p \n"
      printf "\t--join-user      see -u \n"
      printf "\t--ou-path        see -o \n"
  )
  return 0
}

# Get clear-text password from crypt
function PWdecrypt {
  local PWCLEAR

  # Get cleartext password-string
  if PWCLEAR=$(
    echo "${PWCRYPT}" | \
    openssl enc -aes-256-cbc -md sha256 -a -d -salt -pass pass:"${PWUNLOCK}"
  )
  then
    echo "${PWCLEAR}"
    return 0
  else
    echo "Decryption FAILED!"
    return 1
  fi
}

# Make sure domain is discoverable
function IsDiscoverable {
  if [[ $( realm discover "${JOIN_DOMAIN}" > /dev/null 2>&1 )$? -eq 0 ]]
  then
    printf "The %s domain is discoverable\n" "${JOIN_DOMAIN}"
    return 0
  else
    printf "The %s domain is not discoverable. Aborting...\n" "${JOIN_DOMAIN}"
    return 1
  fi
}

# Try to join host to domain
function JoinDomain {

  # Toggle SELinux if necessary
  if [[ $( getenforce ) == "Enforcing" ]]
  then
    SEL_TARG="1"
    printf "Toggling SELinux mode... "
    setenforce 0 || (echo "FAILED" ; exit 1 )
    echo SUCCESS
  else
    SEL_TARG=0
  fi

  if [[ -z ${JOIN_OU} ]]
  then
    printf "Joining to %s... " "${JOIN_DOMAIN}"
    # shellcheck disable=SC2005
    echo "$( PWdecrypt )" | \
    realm join -U "${JOIN_USER}" \
      --unattended \
      --os-name="${CLIENT_OSNAME}" \
      --os-version="${CLIENT_OSVERS}" "${JOIN_DOMAIN}" > /dev/null 2>&1 || \
    ( echo "FAILED" ; exit 1)
    echo "Success"

  elif [[ -n ${JOIN_OU} ]]
  then
    printf "Joining to %s under %s OU... " "${JOIN_DOMAIN}" "${JOIN_OU}"
    # shellcheck disable=SC2005
    echo "$( PWdecrypt )" | \
    realm join -U "${JOIN_USER}" \
      --unattended \
      --computer-ou="${JOIN_OU}" \
      --os-name="${CLIENT_OSNAME}" \
      --os-version="${CLIENT_OSVERS}" "${JOIN_DOMAIN}" > /dev/null 2>&1 || \
    ( echo "FAILED" ; exit 1)
    echo "Success"
  else
    echo "Unsupported configuration-options"
    return 1
  fi

  # Revert SEL as necessary
  if [[ ${SEL_TARG} -eq 1 ]]
  then
    printf "Resetting SELinux mode... "
    setenforce "${SEL_TARG}" || ( echo "FAILED" ; exit 1 )
    echo "Success"
  fi

  return 0
}

#########################
## Main program flow...
#########################

# Define flags to look for...
OPTIONBUFR=$(
   getopt -o c:d:hk:o:p:u: \
   --long help,domain-fqdn:,join-crypt:,join-key:,join-password:,join-user:,ou-path: \
   -n "${PROGNAME}" -- "$@"
)

# Check for mutually-exclusive arguments
if [[ ${OPTIONBUFR} =~ p\ |join-password && ${OPTIONBUFR} =~ c\ |join-crypt ]] ||
  [[ ${OPTIONBUFR} =~ p\ |join-password && ${OPTIONBUFR} =~ c\ |join-key ]]
then
  EXCLUSIVEARGS=TRUE
  UsageMsg
fi

eval set -- "${OPTIONBUFR}"

###################################
# Parse contents of ${OPTIONBUFR}
###################################
while true
do
  case "$1" in
      -h|--help)
        UsageMsg
        exit
        ;;
      -d|--domain-fqdn)
        case "$2" in
            "")
              logIt "Error: option required but not specified" 1
              shift 2;
              exit 1
              ;;
            *)
              JOIN_DOMAIN="${2}"
              shift 2;
              ;;
        esac
        ;;
      -u|--join-user)
        case "$2" in
            "")
              logIt "Error: option required but not specified" 1
              shift 2;
              exit 1
              ;;
            *)
              JOIN_USER="${2}"
              shift 2;
              ;;
        esac
        ;;
      -c|--join-crypt)
        case "$2" in
            "")
              logIt "Error: option required but not specified" 1
              shift 2;
              exit 1
              ;;
            *)
              PWCRYPT="${2}"
              PWSTRNG="TOBESET"
              shift 2;
              ;;
        esac
        ;;
      -k|--join-key)
        case "$2" in
            "")
              logIt "Error: option required but not specified" 1
              shift 2;
              exit 1
              ;;
            *)
              PWUNLOCK="${2}"
              shift 2;
              ;;
        esac
        ;;
      -p|--join-password)
        case "$2" in
            "")
              logIt "Error: option required but not specified" 1
              shift 2;
              exit 1
              ;;
            *)
              PWSTRNG="${2}"
              shift 2;
              ;;
        esac
        ;;
      -o|--ou-path)
        case "$2" in
            "")
              JOINOU="UNDEF"
              shift 2;
              ;;
            *)
              JOINOU="${2}"
              JOINOU=${JOINOU// /\ }
              shift 2;
              ;;
        esac
        ;;
      --)
        shift
        break
        ;;
      *)
        logIt "Missing value" 1
        exit 1
        ;;
  esac
done


IsDiscoverable
JoinDomain
