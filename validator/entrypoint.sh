#!/bin/bash

SUPERVISOR_CONF="/etc/supervisor/conf.d/supervisord.conf"
export PUBLIC_KEYS_COMMA_SEPARATED=""
export CLIENT="prysm"
export NETWORK="prater"
export VALIDATOR_PORT=3500
export WEB3SIGNER_API="http://web3signer.web3signer-${NETWORK}.dappnode:9000"
export CLIENT_API="http://validator.${CLIENT}-${NETWORK}.dappnode:${VALIDATOR_PORT}"
export WALLET_DIR="/root/.eth2validators"
export EXTRA_OPTS="${EXTRA_OPTS} --graffiti='${GRAFFITI}'" # Concatenate EXTRA_OPTS with existing var, otherwise supervisor will throw error

if [[ $LOG_TYPE == "DEBUG" ]]; then
    export LOG_LEVEL=0
elif [[ $LOG_TYPE == "INFO" ]]; then
    export LOG_LEVEL=1
elif [[ $LOG_TYPE == "WARN" ]]; then
    export LOG_LEVEL=2
elif [[ $LOG_TYPE == "ERROR" ]]; then
    export LOG_LEVEL=3
else
    export LOG_LEVEL=1
fi

# Loads envs into /etc/environment to be used by the cronjob
envs=$(env)
echo "$envs" > /etc/environment

# $1 = logType
# $2 = message
function log {
    case $1 in 
        debug)
            [[ $LOG_LEVEL -le 0 ]] && echo -e "[ DEBUG-entrypoint ] ${2}" ;;
        info)
            [[ $LOG_LEVEL -le 1 ]] && echo -e "[ INFO-entrypoint ] ${2}" ;;
        warn)  
            [[ $LOG_LEVEL -le 2 ]] && echo -e "[ WARN-entrypoint ] ${2}" ;;
        error)
            [[ $LOG_LEVEL -le 3 ]] && echo -e "[ ERROR-entrypoint ] ${2}" ;;
    esac
}

function get_web3signer_pubkeys() {
    # Try for 3 minutes    
    while true; do
        if WEB3SIGNER_RESPONSE=$(curl -s -w "%{http_code}" -X GET -H "Content-Type: application/json" -H "Host: validator.${CLIENT}-${NETWORK}.dappnode" \
        --retry 60 --retry-delay 3 --retry-connrefused "${WEB3SIGNER_API}/eth/v1/keystores"); then

            HTTP_CODE=${WEB3SIGNER_RESPONSE: -3}
            CONTENT=$(echo ${WEB3SIGNER_RESPONSE} | head -c-4)

            case ${HTTP_CODE} in
                200)
                    PUBLIC_KEYS_COMMA_SEPARATED=$(echo ${CONTENT} | jq -r 'try .data[].validating_pubkey' | tr '\n' ',')
                    if [ -z "${PUBLIC_KEYS_COMMA_SEPARATED}" ]; then
                        sed -i 's/autostart=true/autostart=false/g' $SUPERVISOR_CONF
                        { log debug "no public keys found on web3signer"; break; }
                    else 
                        sed -i 's/autostart=false/autostart=true/g' $SUPERVISOR_CONF
                        { log debug "found public keys: $PUBLIC_KEYS_COMMA_SEPARATED"; break; }
                    fi
                    ;;
                403)
                    if [[ "${CONTENT}" == *"Host not authorized"* ]]; then
                        sed -i 's/autostart=true/autostart=false/g' $SUPERVISOR_CONF
                        { log info "client not authorized to access the web3signer api"; break; }
                    fi
                    break
                    ;;
                *)
                    { log error "${CONTENT} HTTP code ${HTTP_CODE} from ${WEB3SIGNER_API}"; break; }
                    ;;
            esac
            break
        else
            { log warn "web3signer not available" ; continue; }
        fi
    done
}

########
# MAIN #
########

# Migrate if required
validator accounts list \
    --wallet-dir="$WALLET_DIR" \
    --wallet-password-file="${WALLET_DIR}/walletpassword.txt" \
    --prater \
    --accept-terms-of-use \
    && { log info "found validators, starging migration"; eth2-migrate.sh & wait $!; } \
    || { log info "validators not found, no migration needed"; }

get_web3signer_pubkeys

# Execute supervisor with current environment!
exec supervisord -c $SUPERVISOR_CONF