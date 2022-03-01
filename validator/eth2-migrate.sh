#!/bin/bash

# TODO:
# - Implement curl response check
# - Implement int tests
# - Implement unit tests
# - Move slashing_protection data from old location (/root/.eth2validators/validator.db) to new location (/root/.eth2validators/prysm-wallet-v2/validator.db) ??

#############
# VARIABLES #
#############

ERROR="[ ERROR-migration ]"
WARN="[ WARN-migration ]"
INFO="[ INFO-migration ]"

HTTP_WEB3SIGNER="http://web3signer.web3signer-prater.dappnode:9000"
NETWORK="prater"
WALLET_DIR="/root/.eth2validators"
WALLETPASSWORD_FILE="${WALLET_DIR}/walletpassword.txt"
BACKUP_DIR="/root/.eth2validators/backup"
BACKUP_ZIP_FILE="${BACKUP_DIR}/backup.zip"
BACKUP_KEYSTORES_DIR="${BACKUP_DIR}/keystores" # Directory where the keystores are stored in format: keystore_0.json keystore_1.json ...
BACKUP_SLASHING_FILE="${BACKUP_DIR}/slashing_protection.json"
BACKUP_WALLETPASSWORD_FILE="${BACKUP_DIR}/walletpassword.txt"

#############
# FUNCTIONS #
#############

# Ensure requirements
function ensure_requirements() {
    # Check if web3signer is available: https://consensys.github.io/web3signer/web3signer-eth2.html#tag/Server-Statuss
    if ! curl -s -X GET \
    -H "Content-Type: application/json" \
    --max-time 10 \
    --retry 5 \
    --retry-delay 2 \
    --retry-max-time 40 \
    "${HTTP_WEB3SIGNER}/upcheck" > /dev/null; then
        { echo "${ERROR} web3signer not available, manual migration required"; empty_validator_volume; exit 1; }
    fi

    # Check if wallet directory exists
    if [ ! -d ${WALLET_DIR} ]; then
        { echo "${ERROR} wallet directory not found, manual migration required"; empty_validator_volume; exit 1; }
    fi

    # Check if wallet password file exists
    if [ ! -f ${WALLETPASSWORD_FILE} ]; then
        { echo "${ERROR} wallet password file not found, manual migration required"; empty_validator_volume; exit 1; }
    fi
}

# Get VALIDATORS_PUBKEYS as array of strings and as string comma separated
function get_public_keys() {
    # Output from validator accounts list
    # ```
    # Account 0 | conversely-game-leech
    # [validating public key] 0xb28d911308c25b9168878abb672c1338e2720ad68fee29bbc27a7c2be4c4efda2696666795e1f8c83ee891e39433b7e5

    # Account 1 | mutually-talented-piranha
    # [validating public key] 0xa17fb850bed4c509ade62a28025a1ba2cfb2ddfcc7f57f2314671b72452f7b46d7cc5385dde861aa9b109ab1bc2c62f7

    # Account 2 | publicly-renewing-tiger
    # [validating public key] 0xa7d24732e326207a732fa2f7e2dbc82a476accae977ab31698c31a5f47f5a3f1ab16a2f2a91ea1d5d6eaebe7f01a34a1
    # ```

    # Get validator pubkeys or exit
    if VALIDATORS_PUBKEYS=$(validator accounts list \
    --wallet-dir=${WALLET_DIR} \
    --wallet-password-file=${WALLETPASSWORD_FILE} \
    --${NETWORK} \
    --accept-terms-of-use); then
        # Grep pubkeys
        VALIDATORS_PUBKEYS_ARRAY=$(echo ${VALIDATORS_PUBKEYS} | grep -o -E '0x[a-zA-Z0-9]{96}')
        # Convert to string comma separated
        PUBLIC_KEYS_COMMA_SEPARATED=$(echo ${VALIDATORS_PUBKEYS_ARRAY} | tr ' ' ',')
        if [ ! -z "$VALIDATORS_PUBKEYS" ]; then
            echo "${INFO} Validator pubkeys found: ${VALIDATORS_PUBKEYS}"
        else
            { echo "${WARN} no validators found, no migration needed"; empty_validator_volume; exit 0; }
        fi  
    else
        { echo "${ERROR} validator accounts list failed, manual migration required"; empty_validator_volume; exit 1; }
    fi
}

# Export validators and slashing protection data
function export_keystores() {
    validator accounts backup \
        --wallet-dir=${WALLET_DIR} \
        --wallet-password-file=${WALLETPASSWORD_FILE} \
        --backup-dir=${BACKUP_DIR} \
        --backup-password-file=${WALLETPASSWORD_FILE} \
        --backup-public-keys=${PUBLIC_KEYS_COMMA_SEPARATED} \
        --${NETWORK} \
        --accept-terms-of-use || { echo "${ERROR} failed to export keystores, manual migration required"; empty_validator_volume; exit 1; }

    unzip -d ${BACKUP_KEYSTORES_DIR} ${BACKUP_ZIP_FILE} || { echo "${ERROR} failed to unzip keystores, manual migration required"; empty_validator_volume; exit 1; }
}

# Export slashing protection data 
function export_slashing_protection() {
    validator slashing-protection-history export \
        --datadir=${WALLET_DIR} \
        --slashing-protection-export-dir=${BACKUP_DIR} \
        --${NETWORK} \
        --accept-terms-of-use || { echo "${ERROR} failed to export slashing protection, manual migration required"; empty_validator_volume; exit 1; }
}

# Export walletpassword.txt
function export_walletpassword() {
    cp ${WALLETPASSWORD_FILE} ${BACKUP_WALLETPASSWORD_FILE} || { echo "${ERROR} failed to export walletpassword.txt, manual migration required"; empty_validator_volume; exit 1; }
}

# Create request body file
function create_request_body() {
    REQUEST_BODY="$( echo '{}' | jq -c '{ keystores: [], passwords: [], slashing_protection: "" }' )"
    KEYSTORE_FILES=$(ls ${BACKUP_KEYSTORES_DIR}/*.json)
    for KEYSTORE_FILE in ${KEYSTORE_FILES}; do
        KEYSTORE_DATA=$(jq @json <<< $(cat ${KEYSTORE_FILE}))
        # Append keystores to request body
        REQUEST_BODY=$(echo ${REQUEST_BODY} | jq -c ".keystores += ["$(echo ${KEYSTORE_DATA})"]")
        # Append passwords to request body
        REQUEST_BODY=$(echo ${REQUEST_BODY} | jq -c ".passwords += [\"$(cat ${WALLETPASSWORD_FILE})\"]")
    done
    # Append slashing protection to request body
    SLASHING_DATA=$(jq @json <<< $(cat ${BACKUP_SLASHING_FILE}))
    REQUEST_BODY=$(echo ${REQUEST_BODY} | jq -c ".slashing_protection += "$(echo ${SLASHING_DATA})"")
}

# Import validators with request body file
# - Docs: https://consensys.github.io/web3signer/web3signer-eth2.html#operation/KEYMANAGER_IMPORT
function import_validators() {
    curl -X POST \
        -d ${REQUEST_BODY} \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        ${HTTP_WEB3SIGNER}/eth/v1/keystores || { echo "${ERROR} failed to import validators, manual migration required"; empty_validator_volume; exit 1; }
    echo "${INFO} validators imported"
}

function empty_validator_volume() {
    rm -rf ${WALLET_DIR} || { echo "${ERROR} failed to remove wallet dir"; exit 1; }
}

########
# MAIN #
########

echo "${INFO} ensuring requirements"
ensure_requirements
echo "${INFO} getting validator pubkeys"
get_public_keys
echo "${INFO} exporting and unzipping keystores"
export_keystores
echo "${INFO} exporting slashing protection"
export_slashing_protection
echo "${INFO} exporting walletpassword.txt"
export_walletpassword
echo "${INFO} creating request body"
create_request_body
echo "${INFO} importing validators"
import_validators
echo "${INFO} removing wallet dir recursively"
empty_validator_volume

exit 0
