#!/bin/bash

ERROR="[ ERROR ]"
WARN="[ WARN ]"
INFO="[ INFO ]"

# Var used to start the teku validator: pubkeys must be comma separated
PUBLIC_KEYS_COMMA_SEPARATED=""

# Checks the following vars exist or exits:
# - BEACON_RPC_PROVIDER
# - BEACON_RPC_GATEWAY_PROVIDER
# - HTTP_WEB3SIGNER
# - PUBLIC_KEYS_FILE
# - WALLET_DIR
function ensure_envs_exist() {
    [ -z "${BEACON_RPC_PROVIDER}" ] && { echo "${ERROR} BEACON_RPC_PROVIDER is not set"; exit 1; }
    [ -z "${BEACON_RPC_GATEWAY_PROVIDER}" ] && { echo "${ERROR} BEACON_RPC_GATEWAY_PROVIDER is not set"; exit 1; }
    [ -z "${HTTP_WEB3SIGNER}" ] && { echo "${ERROR} HTTP_WEB3SIGNER is not set"; exit 1; }
    [ -z "${PUBLIC_KEYS_FILE}" ] && { echo "${ERROR} PUBLIC_KEYS_FILE is not set"; exit 1; }
    [ -z "${WALLET_DIR}" ] && { echo "${ERROR} WALLET_DIR is not set"; exit 1; }
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
#
# IMPORTANT! Prysm validator-web3signer does not allow to start without public keys.
# - Service must exit with 1 to keep the service restarting until there are uploaded validators on the web3signer.
# - Prysm is about to change this behaviour: https://github.com/prysmaticlabs/prysm/issues/10293
function get_public_keys() {
    # Try for 3 minutes    
    while true; do
        if PUBLIC_KEYS_API=$(curl -s -X GET \
        -H "Content-Type: application/json" \
        --retry 60 \
        --retry-delay 3 \
        --retry-connrefused \
        "${HTTP_WEB3SIGNER}/eth/v1/keystores"); then
            if PUBLIC_KEYS_API=$(echo ${PUBLIC_KEYS_API} | jq -r '.data[].validating_pubkey'); then
                if [ ! -z "$PUBLIC_KEYS_API" ]; then
                    PUBLIC_KEYS_COMMA_SEPARATED=$(echo ${PUBLIC_KEYS_API} | tr ' ' ',')
                    { echo "${INFO} found public keys: $PUBLIC_KEYS_API"; break; }
                else
                    { echo "${WARN} no public keys found"; continue; }
                fi
            else
                { echo "${WARN} something wrong happened parsing the public keys"; continue; }
            fi
        else
            { echo "${WARN} web3signer not available"; continue; }
            
        fi
    done
}

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

# Check if the envs exist
ensure_envs_exist

# Migrate if required
validator accounts list \
    --wallet-dir="$WALLET_DIR" \
    --wallet-password-file="${WALLET_DIR}/walletpassword.txt" \
    --prater \
    --accept-terms-of-use \
    && { echo "${INFO} found validators, starging migration"; eth2-migrate.sh & wait $!; } \
    || { echo "${INFO} validators not found, no migration needed"; }

# Get public keys from API keymanager
get_public_keys

# Clean old public keys
clean_public_keys

if [ ! -z "${PUBLIC_KEYS_API}" ]; then
    # Write public keys to file
    echo "${INFO} writing public keys file"
    write_public_keys
else
    echo "${WARN} no public keys found"
fi

echo "${INFO} starting cronjob"
cron

# Must used escaped \"$VAR\" to accept spaces: --graffiti=\"$GRAFFITI\"
exec -c validator \
  --prater \
  --datadir="$WALLET_DIR" \
  --wallet-dir="$WALLET_DIR" \
  --rpc-host 0.0.0.0 \
  --monitoring-host 0.0.0.0 \
  --beacon-rpc-provider="$BEACON_RPC_PROVIDER" \
  --beacon-rpc-gateway-provider="$BEACON_RPC_GATEWAY_PROVIDER" \
  --validators-external-signer-url="$HTTP_WEB3SIGNER" \
  --validators-external-signer-public-keys="$PUBLIC_KEYS_COMMA_SEPARATED" \
  --graffiti=\"$GRAFFITI\" \
  --grpc-gateway-host=0.0.0.0 \
  --grpc-gateway-port=80 \
  --accept-terms-of-use \
  ${EXTRA_OPTS}