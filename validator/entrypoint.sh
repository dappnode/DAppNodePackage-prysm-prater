#!/bin/bash

ERROR="[ ERROR ]"
WARN="[ WARN ]"
INFO="[ INFO ]"

function ensure_envs_exist() {
    [ -z "${BEACON_RPC_PROVIDER}" ] && { echo "${ERROR} BEACON_RPC_PROVIDER is not set"; exit 1; }
    [ -z "${BEACON_RPC_GATEWAY_PROVIDER}" ] && { echo "${ERROR} BEACON_RPC_GATEWAY_PROVIDER is not set"; exit 1; }
    [ -z "${HTTP_WEB3SIGNER}" ] && { echo "${ERROR} HTTP_WEB3SIGNER is not set"; exit 1; }
    [ -z "${PUBLIC_KEYS_FILE}" ] && { echo "${ERROR} PUBLIC_KEYS_FILE is not set"; exit 1; }
    [ -z "${WALLET_DIR}" ] && { echo "${ERROR} WALLET_DIR is not set"; exit 1; }
    [ -z "${SUPERVISOR_CONF}" ] && { echo "${ERROR} SUPERVISOR_CONF is not set"; exit 1; }
}

# Get public keys from API keymanager: BASH ARRAY OF STRINGS
# - Endpoint: http://web3signer.web3signer-prater.dappnode:9000/eth/v1/keystores
# - Returns:
# { "data": [{
#     "validating_pubkey": "0x93247f2209abcacf57b75a51dafae777f9dd38bc7053d1af526f220a7489a6d3a2753e5f3e8b1cfe39b56f43611df74a",
#     "derivation_path": "m/12381/3600/0/0/0",
#     "readonly": true
#     }]
# }
function get_public_keys() {
    # Try for 3 minutes    
    while true; do
        if WEB3SIGNER_RESPONSE=$(curl -s -X GET \
        -H "Content-Type: application/json" \
        -H "Host: validator.prysm-prater.dappnode" \
        --retry 60 \
        --retry-delay 3 \
        --retry-connrefused \
        "${HTTP_WEB3SIGNER}/eth/v1/keystores"); then
            # Check host is not authorized
            if [ "$(echo ${WEB3SIGNER_RESPONSE} | jq -r '.message')" == *"Host not authorized"* ]; then
                echo "${WARN} the current client is not authorized to access the web3signer api"
                sed -i 's/autostart=true/autostart=false/g' $SUPERVISOR_CONF
                break
            fi

            if [ "$(echo ${WEB3SIGNER_RESPONSE} | jq -r '.data[].validating_pubkey')" == "null" ]; then
                echo "${WARN} error getting public keys from web3signer"
                sed -i 's/autostart=true/autostart=false/g' $SUPERVISOR_CONF
                break
            elif [ "$(echo ${WEB3SIGNER_RESPONSE} | jq -r '.data[].validating_pubkey')" != "null" ]; then
                PUBLIC_KEYS_API=$(echo ${WEB3SIGNER_RESPONSE} | jq -r '.data[].validating_pubkey')
                if [ -z "${PUBLIC_KEYS_API}" ]; then
                    sed -i 's/autostart=true/autostart=false/g' $SUPERVISOR_CONF
                    { echo "${WARN} no public keys found on web3signer"; break; }
                else 
                    sed -i 's/autostart=false/autostart=true/g' $SUPERVISOR_CONF
                    write_public_keys
                    { echo "${INFO} found public keys: $PUBLIC_KEYS_API"; break; }
                fi
            else
                { echo "${WARN} something wrong happened parsing the public keys"; break; }
            fi
        else
            { echo "${WARN} web3signer not available"; continue; }
        fi
    done
}

# Ensure file will exists
function clean_public_keys() {
    rm -rf ${PUBLIC_KEYS_FILE}
    touch ${PUBLIC_KEYS_FILE}
}

# Writes public keys
# - by new line separated
# - creates file if it does not exist
function write_public_keys() {
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

########
# MAIN #
########

ensure_envs_exist

# Migrate if required
validator accounts list \
    --wallet-dir="$WALLET_DIR" \
    --wallet-password-file="${WALLET_DIR}/walletpassword.txt" \
    --prater \
    --accept-terms-of-use \
    && { echo "${INFO} found validators, starging migration"; eth2-migrate.sh & wait $!; } \
    || { echo "${INFO} validators not found, no migration needed"; }

clean_public_keys

get_public_keys

# Execute supervisor with current environment!
exec supervisord -c $SUPERVISOR_CONF