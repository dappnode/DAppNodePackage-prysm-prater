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
function ensure_envs_exist() {
    [ -z "${BEACON_RPC_PROVIDER}" ] && echo "${ERROR} BEACON_RPC_PROVIDER is not set" && exit 1
    [ -z "${BEACON_RPC_GATEWAY_PROVIDER}" ] && echo "${ERROR} BEACON_RPC_GATEWAY_PROVIDER is not set" && exit 1
    [ -z "${HTTP_WEB3SIGNER}" ] && echo "${ERROR} HTTP_WEB3SIGNER is not set" && exit 1
    [ -z "${PUBLIC_KEYS_FILE}" ] && echo "${ERROR} PUBLIC_KEYS_FILE is not set" && exit 1
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
    if PUBLIC_KEYS=$(curl -s -X GET \
    -H "Content-Type: application/json" \
    --max-time 10 \
    --retry 2 \
    --retry-delay 2 \
    --retry-max-time 40 \
    "${HTTP_WEB3SIGNER}/eth/v1/keystores"); then
        if PUBLIC_KEYS_PARSED=$(echo ${PUBLIC_KEYS} | jq -r '.data[].validating_pubkey'); then
            if [ ! -z "$PUBLIC_KEYS_PARSED" ]; then
                echo "${INFO} found public keys: $PUBLIC_KEYS_PARSED"
            else
                echo "${WARN} no public keys found"
            fi
        else
            echo "${WARN} something wrong happened parsing the public keys"
        fi
    else
        echo "${WARN} web3signer not available"
    fi
}

# Clean old file and writes new public keys file
# - by new line separated
# - creates file if it does not exist
function write_public_keys() {
    # Clean file
    rm -rf ${PUBLIC_KEYS_FILE}
    touch ${PUBLIC_KEYS_FILE}

    echo "${INFO} writing public keys to file"
    for PUBLIC_KEY in ${PUBLIC_KEYS_PARSED}; do
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

# Get public keys from API keymanager
get_public_keys

if [ ! -z "${PUBLIC_KEYS_PARSED}" ]; then
    # Write public keys to file
    echo "${INFO} writing public keys file"
    write_public_keys

    # Create comma separated string of public keys
    echo "${INFO} creating comma separated string of public keys"
    PUBLIC_KEYS_COMMA_SEPARATED=$(echo ${PUBLIC_KEYS_COMMA_SEPARATED} | tr ' ' ',')
fi

echo "${INFO} starting cronjob"
cron

# Must used escaped \"$VAR\" to accept spaces: --graffiti=\"$GRAFFITI\"
exec -c validator \
  --prater \
  --datadir=/root/.eth2 \
  --rpc-host 0.0.0.0 \
  --monitoring-host 0.0.0.0 \
  --beacon-rpc-provider="$BEACON_RPC_PROVIDER" \
  --beacon-rpc-gateway-provider="$BEACON_RPC_GATEWAY_PROVIDER" \
  --wallet-dir=/root/.eth2validators \
  --wallet-password-file=/root/.eth2wallets/wallet-password.txt \
  --write-wallet-password-on-web-onboarding \
  --validators-external-signer-url=$HTTP_WEB3SIGNER \
  --validators-external-signer-public-keys=$PUBLIC_KEYS_COMMA_SEPARATED \
  --graffiti="$GRAFFITI" \
  --grpc-gateway-host=0.0.0.0 \
  --grpc-gateway-port=80 \
  --accept-terms-of-use \
  ${EXTRA_OPTS}