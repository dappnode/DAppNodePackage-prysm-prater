#!/bin/bash
#
# This script must fetch and compare the public keys returned from the web3signer api
# with the public keys in the public_keys.txt file used to start the validator
# if the public keys are different, the script will kill the process 1 to restart the process
# if the public keys are the same, the script will do nothing

ERROR="[ ERROR-cronjob ]"
WARN="[ WARN-cronjob ]"
INFO="[ INFO-cronjob ]"

# This var must be set here and must be equal to the var defined in the compose file
PUBLIC_KEYS_FILE="/public_keys.txt"
HTTP_WEB3SIGNER="http://web3signer.web3signer-prater.dappnode:9000"

# Get public keys in format: string[]
function get_public_keys() {
    # Try for 30 seconds
    if PUBLIC_KEYS_API=$(curl -s -X GET \
    -H "Content-Type: application/json" \
    --retry 10 \
    --retry-delay 3 \
    --retry-connrefused \
    "${HTTP_WEB3SIGNER}/eth/v1/keystores"); then
        if PUBLIC_KEYS_API=($(echo ${PUBLIC_KEYS_API} | jq -r '.data[].validating_pubkey')); then
            if [ ! -z "$PUBLIC_KEYS_API" ]; then
                echo "${INFO} found public keys: $PUBLIC_KEYS_API"
            else
                echo "${WARN} no public keys found"
                PUBLIC_KEYS_API=()
            fi
        else
            { echo "${ERROR} something wrong happened parsing the public keys"; exit 1; }
        fi
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

# Compares the public keys from the file with the public keys from the api
#   - kill main process if public keys from web3signer api does not contain the public keys from the file
#   - kill main process if public keys from file does not contain the public keys from the web3signer api
#   - kill main process if bash array length different
function compare_public_keys() { 
    echo "${INFO} comparing public keys"

    # compare array lentghs
    if [ ${#PUBLIC_KEYS_OLD[@]} -ne ${#PUBLIC_KEYS_API[@]} ]; then
        echo "${WARN} public keys from file and api are different. Killing process to restart"
        kill 1
        exit 0
    else
        if [ ${#PUBLIC_KEYS_API[@]} -eq 0 ]; then
            echo "${INFO} public keys from file and api are empty. Not comparision needed"
            exit 0
        else
            echo "${INFO} same number of public keys, comparing"
                # Compare public keys
            for i in "${PUBLIC_KEYS_OLD[@]}"; do
                if [[ "${PUBLIC_KEYS_API[@]}" =~ "${i}" ]]; then
                    echo "${INFO} public key ${i} found in api"
                else
                    echo "${WARN} public key ${i} from file not found in api. Killing process to restart"
                    kill 1
                    exit 0
                fi
            done
        fi
    fi
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