#!/bin/bash

SUPERVISOR_CONF="/etc/supervisor/conf.d/supervisord.conf"
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
echo "$envs" >/etc/environment

# Migrate if required
if [[ $(validator accounts list \
  --wallet-dir="$WALLET_DIR" \
  --wallet-password-file="${WALLET_DIR}/walletpassword.txt" \
  --prater \
  --accept-terms-of-use) ]]; then
  {
    echo "found validators, starging migration"
    eth2-migrate.sh &
    wait $!
  }
else
  { echo "validators not found, no migration needed"; }
fi

# Set auto start true or false deppending on the response from the web3signer
WEB3SIGNER_RESPONSE=$(curl -s -w "%{http_code}" -X GET -H "Content-Type: application/json" -H "Host: validator.${CLIENT}-${NETWORK}.dappnode" "${WEB3SIGNER_API}/eth/v1/keystores")
HTTP_CODE=${WEB3SIGNER_RESPONSE: -3}
CONTENT=$(echo "${WEB3SIGNER_RESPONSE}" | head -c-4)
if [ "$HTTP_CODE" != "200" ]; then
  echo "vc autostart false"
  sed -i 's/autostart=true/autostart=false/g' $SUPERVISOR_CONF
else
  echo "vc autostart true"
  sed -i 's/autostart=false/autostart=true/g' $SUPERVISOR_CONF
  PUBLIC_KEYS_WEB3SIGNER=($(echo "${CONTENT}" | jq -r 'try .data[].validating_pubkey'))
  if [ ${#PUBLIC_KEYS_WEB3SIGNER[@]} -gt 0 ]; then
    PUBLIC_KEYS_COMMA_SEPARATED=$(echo "${PUBLIC_KEYS_WEB3SIGNER[*]}" | tr ' ' ',')
    echo "found validators in web3signer, starting vc with pubkeys: ${PUBLIC_KEYS_COMMA_SEPARATED}"
    export EXTRA_OPTS="${EXTRA_OPTS} --validators-external-signer-public-keys=${PUBLIC_KEYS_COMMA_SEPARATED}"
  fi
fi

# Execute supervisor with current environment!
exec supervisord -c $SUPERVISOR_CONF
