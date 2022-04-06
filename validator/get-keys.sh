#!/bin/bash
#
# This script must fetch and compare the public keys returned from the web3signer api
# with the public keys in the public_keys.txt file used to start the validator

ERROR="[ ERROR-cronjob ]"
WARN="[ WARN-cronjob ]"
INFO="[ INFO-cronjob ]"

CLIENT="prysm"
NETWORK="prater"

# This var must be set here and must be equal to the var defined in the compose file
PUBLIC_KEYS_FILE="/public_keys.txt"
HTTP_WEB3SIGNER="http://web3signer.web3signer-prater.dappnode:9000"

# Validator service status: http://supervisord.org/subprocess.html
VALIDATOR_STATUS=$(supervisorctl -u dummy -p dummy status validator | awk '{print $2}')

# Get public keys from web3signer API
function get_public_keys() {
    # Try for 30 seconds
    if WEB3SIGNER_RESPONSE=$(curl -s -w "%{http_code}" -X GET -H "Content-Type: application/json" -H "Host: validator.${CLIENT}-${NETWORK}.dappnode" \
    --retry 10 --retry-delay 3 --retry-connrefused "${HTTP_WEB3SIGNER}/eth/v1/keystores"); then

        HTTP_CODE=${WEB3SIGNER_RESPONSE: -3}
        CONTENT=$(echo ${WEB3SIGNER_RESPONSE} | head -c-4)

        case ${HTTP_CODE} in
            200)
                PUBLIC_KEYS_API=$(echo ${CONTENT} | jq -r 'try .data[].validating_pubkey')
                if [ -z "${PUBLIC_KEYS_API}" ]; then
                    echo "${INFO} no public keys found in web3signer api"
                    if [ "$VALIDATOR_STATUS" != "STOPPED" ]; then
                        echo "${INFO} stopping validator"
                        supervisorctl -u dummy -p dummy stop validator || { echo "${ERROR} could not stop validator"; exit 1; }
                    fi
                    exit 0
                else
                    echo "${INFO} found public keys: $PUBLIC_KEYS_API"
                fi
                ;;
            403)
                if [[ "${CONTENT}" == *"Host not authorized"* ]]; then
                    echo "${WARN} client not authorized to access the web3signer api"
                    if [ "$VALIDATOR_STATUS" != "STOPPED" ]; then
                        echo "${INFO} stopping validator"
                        supervisorctl -u dummy -p dummy stop validator || { echo "${ERROR} could not stop validator"; exit 1; }
                    fi
                    exit 0
                fi
                { echo "${ERROR} ${CONTENT} HTTP code ${HTTP_CODE} from ${HTTP_WEB3SIGNER}"; exit 1; }
                ;;
            *)
                { echo "${ERROR} ${CONTENT} HTTP code ${HTTP_CODE} from ${HTTP_WEB3SIGNER}"; exit 1; }
                ;;
        esac
    else
        { echo "${ERROR} web3signer not available"; exit 1; }
    fi
}

# Reads public keys from file by new line separated and converts to string array
function read_old_public_keys() {
    if [ -f ${PUBLIC_KEYS_FILE} ]; then
        echo "${INFO} reading public keys from file"
        PUBLIC_KEYS_OLD=($(cat ${PUBLIC_KEYS_FILE} | tr '\n' ' '))
    else
        echo "${WARN} file ${PUBLIC_KEYS_FILE} not found"
        PUBLIC_KEYS_OLD=()
    fi
}

# Writes public keys
# - by new line separated
# - creates file if it does not exist
function write_public_keys() {
    rm -rf ${PUBLIC_KEYS_FILE}
    touch ${PUBLIC_KEYS_FILE}
    echo "${INFO} writing public keys to file"
    for PUBLIC_KEY in ${PUBLIC_KEYS_API}; do
        if [ ! -z "${PUBLIC_KEY}" ]; then
            echo "${INFO} adding public key: $PUBLIC_KEY"    
            echo "${PUBLIC_KEY}" >> ${PUBLIC_KEYS_FILE}
        else
            echo "${WARN} empty public key"
        fi
    done
}

# Compares the public keys from the file with the public keys from the api
function compare_public_keys() { 
    # Convert PUBLIC_KEYS_API to array
    PUBLIC_KEYS_API=($(echo ${PUBLIC_KEYS_API}))
    case ${VALIDATOR_STATUS} in
        RUNNING)
            echo "${INFO} validator is running"
            if [ ${#PUBLIC_KEYS_OLD[@]} -ne ${#PUBLIC_KEYS_API[@]} ]; then
                echo "${INFO} public keys from file and api are different. Reloading validator service"
                write_public_keys
                supervisorctl -u dummy -p dummy restart validator || { echo "${ERROR} could not restart validator"; exit 1; }
                exit 0
            else
                if [ ${#PUBLIC_KEYS_API[@]} -eq 0 ]; then
                    echo "${INFO} public keys from web3signer are empty. Stopping validator service"
                    supervisorctl -u dummy -p dummy stop validator || { echo "${ERROR} could not stop validator"; exit 1; }
                    exit 0
                else
                    echo "${INFO} same number of public keys, comparing"
                    for i in "${PUBLIC_KEYS_OLD[@]}"; do
                        if [[ "${PUBLIC_KEYS_API[@]}" =~ "${i}" ]]; then
                            echo "${INFO} public key ${i} found in api"
                        else
                            echo "${WARN} public key ${i} from file not found in api. Reloading validator service"
                            write_public_keys
                            supervisorctl -u dummy -p dummy restart validator || { echo "${ERROR} could not restart validator"; exit 1; }
                            exit 0
                        fi
                    done
                fi
            fi
            ;;
        STOPPED)
            echo "${INFO} validator is stopped"
            # If there are public keys in the web3signer start validator
            if [ ${#PUBLIC_KEYS_API[@]} -gt 0 ]; then
                echo "${INFO} found public keys in the web3signer"
                write_public_keys
                echo "${INFO} starting validator"
                supervisorctl -u dummy -p dummy start validator || { echo "${ERROR} validator could not be started"; exit 1; }
                exit 0
            else
                echo "${INFO} no public keys found in the web3signer"
            fi
            ;;
        STARTING|STOPPING)
            echo "${INFO} supervisor request is been processed"
            exit 0
            ;;
        *) # BACKOFF EXITED UNKNOWN FATAL
            echo "${ERROR} unexpected status: ${VALIDATOR_STATUS}"
            supervisorctl -u dummy -p dummy reload
            exit 1
            ;;
    esac
}

########
# MAIN #
########

echo "${INFO} starting cronjob"
get_public_keys
read_old_public_keys
compare_public_keys
echo "${INFO} finished cronjob"
exit 0