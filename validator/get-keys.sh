#!/bin/bash

# Validator service status: http://supervisord.org/subprocess.html
VALIDATOR_STATUS=$(supervisorctl -u dummy -p dummy status validator | awk '{print $2}')

# $1 = logType
# $2 = message
function log {
    case $1 in 
        debug)
            [[ $LOG_LEVEL -le 0 ]] && echo -e "[ DEBUG-cron ] ${2}" ;;
        info)
            [[ $LOG_LEVEL -le 1 ]] && echo -e "[ INFO-cron ] ${2}" ;;
        warn)  
            [[ $LOG_LEVEL -le 2 ]] && echo -e "[ WARN-cron ] ${2}" ;;
        error)
            [[ $LOG_LEVEL -le 3 ]] && echo -e "[ ERROR-cron ] ${2}" ;;
    esac
}

# web3signer responses middleware
# $1=HTTP_CODE  $2=CONTENT
function check_web3signer_response() {
    local HTTP_CODE=$1
    local CONTENT=$2
    case ${HTTP_CODE} in
        200)
            log debug "client authorized to access the web3signer api"
            if [ "$VALIDATOR_STATUS" != "RUNNING" ]; then
                log debug "starting validator"
                supervisorctl -u dummy -p dummy start validator || { log error "could not start validator"; exit 1; }
            fi
            ;;
        403)
            if [ "$CONTENT" == "*Host not authorized*" ]; then
                log debug "client not authorized to access the web3signer api"
                if [ "$VALIDATOR_STATUS" != "STOPPED" ]; then
                    log debug "stopping validator"
                    supervisorctl -u dummy -p dummy stop validator || { log error "could not stop validator"; exit 1; }
                fi
                exit 0
            else 
                { log error "${CONTENT} HTTP code ${HTTP_CODE} from ${WEB3SIGNER_API}"; exit 1; }
            fi
            ;;
        *)
            { log error "${CONTENT} HTTP code ${HTTP_CODE} from ${WEB3SIGNER_API}"; exit 1; } 
            ;;
    esac
}

# Ensure the validator service is stopped or running deppending on the web3signer response
function get_web3signer_status() {
    local response=$(curl -s -w "%{http_code}" -X GET -H "Content-Type: application/json" -H "Host: validator.${CLIENT}-${NETWORK}.dappnode" "${WEB3SIGNER_API}/upcheck")
    local http_code=${response: -3}
    local content=$(echo ${response} | head -c-4)

    check_web3signer_response $http_code $content

    WEB3SIGNER_STATUS=$content
}

# Get public keys from web3signer API
function get_web3signer_pubkeys() {
    local response=$(curl -s -w "%{http_code}" -X GET -H "Content-Type: application/json" -H "Host: validator.${CLIENT}-${NETWORK}.dappnode" "${WEB3SIGNER_API}/eth/v1/keystores")
    local http_code=${response: -3}
    local content=$(echo ${response} | head -c-4)

    check_web3signer_response $http_code $content

    PUBLIC_KEYS_WEB3SIGNER=$(echo ${content} | jq -r 'try .data[].validating_pubkey')
}

# Get public keys from client keymanager API
function get_client_pubkeys() {
    PUBLIC_KEYS_CLIENT=$(curl -s -X GET -H "Content-Type: application/json" "${CLIENT_API}/eth/v1/keystores" | jq -r 'try .data[].validating_pubkey')
}

# Import public keys in client keymanager API
function post_client_pubkeys() {
    PUBLIC_KEYS_CLIENT=$(curl -s -X POST -H "Content-Type: application/json" "${CLIENT_API}/eth/v1/keystores" | jq -r 'try .data[].validating_pubkey')
}

# Delete public keys from client keymanager API
function delete_client_pubkeys() {
    PUBLIC_KEYS_CLIENT=$(curl -s -X DELETE -H "Content-Type: application/json" "${CLIENT_API}/eth/v1/keystores" | jq -r 'try .data[].validating_pubkey')
}

# Compares the public keys from the file with the public keys from the api
function compare_public_keys() { 
    case ${VALIDATOR_STATUS} in
        RUNNING)
            log debug "validator is running"
            if [ ${#PUBLIC_KEYS_CLIENT[@]} -ne ${#PUBLIC_KEYS_WEB3SIGNER[@]} ]; then
                log debug "public keys from file and api are different. Reloading validator service"
                supervisorctl -u dummy -p dummy restart validator || { log error "could not restart validator"; exit 1; }
                exit 0
            else
                if [ ${#PUBLIC_KEYS_WEB3SIGNER[@]} -eq 0 ]; then
                    log debug "public keys from web3signer are empty. Stopping validator service"
                    supervisorctl -u dummy -p dummy stop validator || { log error "could not stop validator"; exit 1; }
                    exit 0
                else
                    log debug "same number of public keys, comparing"
                    for i in "${PUBLIC_KEYS_CLIENT[@]}"; do
                        if [[ "${PUBLIC_KEYS_WEB3SIGNER[@]}" =~ "${i}" ]]; then
                            log debug "public key ${i} found in api"
                        else
                            log warn "public key ${i} from file not found in api. Reloading validator service"
                            supervisorctl -u dummy -p dummy restart validator || { log error "could not restart validator"; exit 1; }
                            exit 0
                        fi
                    done
                fi
            fi
            ;;
        STOPPED)
            log debug "validator is stopped"
            # If there are public keys in the web3signer start validator
            if [ ${#PUBLIC_KEYS_WEB3SIGNER[@]} -gt 0 ]; then
                log debug "found public keys in the web3signer, starting validators"
                supervisorctl -u dummy -p dummy start validator || { log error "validator could not be started"; exit 1; }
                exit 0
            else
                log debug "no public keys found in the web3signer"
            fi
            ;;
        STARTING|STOPPING)
            { log info "supervisor request is been processed"; exit 0; }
            ;;
        *) # BACKOFF EXITED UNKNOWN FATAL
            log error "unexpected status: ${VALIDATOR_STATUS}"
            supervisorctl -u dummy -p dummy reload
            exit 1
            ;;
    esac
}

########
# MAIN #
########

log debug "starting cronjob"

get_web3signer_status
if [ "$WEB3SIGNER_STATUS" == "OK" ]; then
    log debug "client authorized to access the web3signer api"
    if [ "$VALIDATOR_STATUS" != "RUNNING" ]]; then
        log debug "starting validator"
        supervisorctl -u dummy -p dummy start validator || { log error "could not start validator"; exit 1; }
    fi
else 
    log error "unknown web3signer status: ${WEB3SIGNER_STATUS}"
    if [ "$VALIDATOR_STATUS" != "STOPPED" ]; then
        log debug "stopping validator"
        supervisorctl -u dummy -p dummy stop validator || { log error "could not stop validator"; exit 1; }
    fi
fi

get_web3signer_pubkeys
if [ -z "${PUBLIC_KEYS_WEB3SIGNER}" ]; then
    log debug "no public keys found in web3signer api"
    if [ $VALIDATOR_STATUS != "STOPPED" ]; then
        log debug "stopping validator"
        supervisorctl -u dummy -p dummy stop validator || { log error "could not stop validator"; exit 1; }
    fi
    exit 0
else
    log debug "found public keys: $PUBLIC_KEYS_WEB3SIGNER"
fi

get_client_pubkeys
if [ -z "${PUBLIC_KEYS_CLIENT}" ]; then
    log debug "no public keys found in client keymanager api"
else
    log debug "found public keys: $PUBLIC_KEYS_CLIENT"
fi

compare_public_keys

log debug "finished cronjob"
exit 0