#!/bin/bash
# This script does the following:
# - Start/stop validator service deppending on:
#   - If the validator is already running
#   - web3signer status
#   - beacon node syncing status
# - Reload pubkeys in the validator on the fly deppending on the web3signer pubkeys

# Validator service status: http://supervisord.org/subprocess.html
VALIDATOR_STATUS=$(supervisorctl -u dummy -p dummy status validator | awk '{print $2}')

# Log level function: $1 = logType $2 = message
function log {
  case $1 in
  debug)
    [[ $LOG_LEVEL -le 0 ]] && echo "[ DEBUG-cron ] ${2}"
    ;;
  info)
    [[ $LOG_LEVEL -le 1 ]] && echo "[ INFO-cron ] ${2}"
    ;;
  warn)
    [[ $LOG_LEVEL -le 2 ]] && echo "[ WARN-cron ] ${2}"
    ;;
  error)
    [[ $LOG_LEVEL -le 3 ]] && echo "[ ERROR-cron ] ${2}"
    ;;
  esac
}

##################
# WEB3SIGNER API #
##################

# web3signer responses middleware: $1=http_code $2=content
function web3signer_response_middleware() {
  local http_code=$1 content=$2
  case ${http_code} in
  200)
    log debug "client authorized to access the web3signer api"
    ;;
  403)
    if [ "$content" == "*Host not authorized*" ]; then
      log debug "client not authorized to access the web3signer api"
      if [[ "$VALIDATOR_STATUS" == "RUNNING" ]]; then
        {
          log debug "stopping validator"
          supervisorctl -u dummy -p dummy stop validator
          exit 0
        } || {
          log error "could not stop validator"
          exit 1
        }
      fi
      exit 0
    else
      {
        log error "${content} HTTP code ${http_code} from ${WEB3SIGNER_API}"
        exit 1
      }
    fi
    ;;
  *)
    {
      log error "${content} HTTP code ${http_code} from ${WEB3SIGNER_API}"
      exit 1
    }
    ;;
  esac
}

# Get the web3signer status into the variable WEB3SIGNER_STATUS
# https://consensys.github.io/web3signer/web3signer-eth2.html#tag/Server-Status
# Response: plain text
function get_web3signer_status() {
  local response content http_code
  response=$(curl -s -w "%{http_code}" -X GET -H "Content-Type: application/json" -H "Host: validator.${CLIENT}-${NETWORK}.dappnode" "${WEB3SIGNER_API}/upcheck")
  http_code=${response: -3}
  content=$(echo "${response}" | head -c-4)
  web3signer_response_middleware "$http_code" "$content"
  WEB3SIGNER_STATUS=$content
}

# Get public keys from web3signer API into the variable WEB3SIGNER_PUBLIC_KEYS
# https://consensys.github.io/web3signer/web3signer-eth2.html#operation/KEYMANAGER_LIST
# Response:
# {
#   "data": [
#       {
#           "validating_pubkey": "0x93247f2209abcacf57b75a51dafae777f9dd38bc7053d1af526f220a7489a6d3a2753e5f3e8b1cfe39b56f43611df74a",
#           "derivation_path": "m/12381/3600/0/0/0",
#           "readonly": true
#       }
#   ]
# }
function get_web3signer_pubkeys() {
  local response content http_code
  response=$(curl -s -w "%{http_code}" -X GET -H "Content-Type: application/json" -H "Host: validator.${CLIENT}-${NETWORK}.dappnode" "${WEB3SIGNER_API}/eth/v1/keystores")
  http_code=${response: -3}
  content=$(echo "${response}" | head -c-4)
  web3signer_response_middleware "$http_code" "$content"
  WEB3SIGNER_PUBKEYS=($(echo "${content}" | jq -r 'try .data[].validating_pubkey'))
}

#################
# VALIDATOR API #
#################

# validator client responses middleware: $1=http_code $2=content
function client_response_middleware() {
  local http_code=$1 content=$2
  case ${http_code} in
  200)
    log debug "successfully requested vc"
    ;;
  *)
    {
      log error "${content} HTTP code ${http_code} from ${CLIENT_API}"
      #supervisorctl -u dummy -p dummy restart validator
      exit 1
    }
    ;;
  esac
}

# Get public keys from client keymanager API into the variable CLIENT_PUBKEYS
# https://ethereum.github.io/keymanager-APIs/#/Remote%20Key%20Manager/ListRemoteKeys
# Response:
# {
#   "data": [
#     {
#       "pubkey": "0x93247f2209abcacf57b75a51dafae777f9dd38bc7053d1af526f220a7489a6d3a2753e5f3e8b1cfe39b56f43611df74a",
#       "url": "https://remote.signer",
#       "readonly": true
#     }
#   ]
# }
function get_client_pubkeys() {
  local response content http_code
  response=$(curl -s -w "%{http_code}" -X GET -H "Content-Type: application/json" "${CLIENT_API}/eth/v1/keystores")
  http_code=${response: -3}
  content=$(echo "${response}" | head -c-4)
  client_response_middleware "$http_code" "$content"
  CLIENT_PUBKEYS=($(echo "${content}" | jq -r 'try .data[].validating_pubkey'))
}

# Import public keys in client keymanager API
# https://ethereum.github.io/keymanager-APIs/#/Remote%20Key%20Manager/ImportRemoteKeys
# Request format
# {
#   "remote_keys": [
#     {
#       "pubkey": "0x93247f2209abcacf57b75a51dafae777f9dd38bc7053d1af526f220a7489a6d3a2753e5f3e8b1cfe39b56f43611df74a",
#       "url": "https://remote.signer"
#     }
#   ]
# }
function post_client_pubkey() {
  local request response http_code content
  request='{"remote_keys": [{"pubkey": "'${1}'", "url": "'${WEB3SIGNER_API}'"}]}'
  response=$(curl -s -w "%{http_code}" -X POST -H "Content-Type: application/json" "${CLIENT_API}/eth/v1/keystores")
  http_code=${response: -3}
  content=$(echo "${response}" | head -c-4)
  client_response_middleware "$http_code" "$content"
  log debug "successfully imported pubkey $1 in clinent, validator client returned: ${content}"
}

# Delete public keys from client keymanager API
# https://ethereum.github.io/keymanager-APIs/#/Remote%20Key%20Manager/DeleteRemoteKeys
# Request format
# {
#   "pubkeys": [
#     "0x93247f2209abcacf57b75a51dafae777f9dd38bc7053d1af526f220a7489a6d3a2753e5f3e8b1cfe39b56f43611df74a"
#   ]
# }
function delete_client_pubkey() {
  local request response http_code content
  request='{"pubkeys": ["'${1}'"]}'
  response=$(curl -s -w "%{http_code}" -X DELETE -H "Content-Type: application/json" --data="${request}" "${CLIENT_API}/eth/v1/keystores")
  http_code=${response: -3}
  content=$(echo "${response}" | head -c-4)
  client_response_middleware "$http_code" "$content"
  log debug "successfully deleted pubkey $1 in client, validator client returned: ${content}"
}

# Get beacon node syncing status into the variable IS_BEACON_SYNCING
# https://ethereum.github.io/beacon-APIs/#/Node/getSyncingStatus
# Response format
# {
#   "data": {
#     "head_slot": "1",
#     "sync_distance": "1",
#     "is_syncing": true
#   }
# }
function get_beacon_status() {
  local response http_code content
  response=$(curl -s -w "%{http_code}" -H "Content-Type: application/json" "${BEACON_RPC_GATEWAY_PROVIDER}/eth/v1/node/syncing")
  http_code=${response: -3}
  content=$(echo "${response}" | head -c-4)
  client_response_middleware "$http_code" "$content"
  IS_BEACON_SYNCING=$(echo "${content}" | jq -r 'try .data.is_syncing')
}

# Compares the public keys from the web3signer with the public keys from the validator client
function compare_public_keys() {
  log debug "client public keys: ${#CLIENT_PUBKEYS[@]}"
  log debug "web3signer public keys: ${#WEB3SIGNER_PUBKEYS[@]}"
  local unique_pubkeys
  unique_pubkeys=($(echo "${WEBWEB3SIGNER_PUBKEYS[@]}" "${CLIENT_PUBKEYS[@]}" | tr ' ' '\n' | sort | uniq -u))
  for i in "${unique_pubkeys[@]}"; do
    if [[ "${WEBWEB3SIGNER_PUBKEYS[*]}" =~ ${i} ]]; then
      log debug "public key from validator client ${i} found in web3signer"
    else
      log debug "public key ${i} from validator client not found in web3signer. Deleting it from client"
      delete_client_pubkey "$i"
    fi
    if [[ "${CLIENT_PUBKEYS[*]}" =~ ${i} ]]; then
      log debug "public key from web3signer ${i} found in validator client"
    else
      log debug "public key ${i} from web3signer not found in validator client. Posting it to client"
      post_client_pubkey "$i"
    fi
  done
}

########
# MAIN #
########

log debug "starting cronjob"

get_beacon_status # IS_BEACON_SYNCING
log debug "beacon node syncing status: ${IS_BEACON_SYNCING}"

get_web3signer_status # WEB3SIGNER_STATUS
log debug "web3signer status: ${WEB3SIGNER_STATUS}"

get_web3signer_pubkeys # WEBWEB3SIGNER_PUBKEYS

case ${VALIDATOR_STATUS} in
RUNNING)
  {
    log debug "validator is running"
    if [[ "${IS_BEACON_SYNCING}" == "true" ]] || [[ "${#WEB3SIGNER_PUBKEYS[@]}" -eq 0 ]] || [[ "${WEB3SIGNER_STATUS}" != "ok" ]]; then
      {
        log debug "stopping validator"
        supervisorctl -u dummy -p dummy stop validator
        exit 0
      } || {
        log error "could not stop validator"
        exit 1
      }
    else
      get_client_pubkeys # CLIENT_PUBKEYS
      log debug "comparing public keys"
      compare_public_keys
    fi
  }
  ;;
STOPPED)
  log debug "validator is stopped"
  if [[ "${WEB3SIGNER_STATUS}" == "ok" ]] && [[ "${#WEB3SIGNER_PUBKEYS[@]}" -ne 0 ]] && [[ "${IS_BEACON_SYNCING}" == "false" ]]; then
    {
      log debug "starting validator"
      supervisorctl -u dummy -p dummy start validator
      exit 0
    } || {
      log error "could not start validator"
      exit 1
    }
  fi
  ;;
STARTING | STOPPING)
  {
    log info "supervisor request is been processed"
    exit 0
  }
  ;;
*) # BACKOFF EXITED UNKNOWN FATAL
  {
    log error "unexpected status: ${VALIDATOR_STATUS}"
    supervisorctl -u dummy -p dummy reload
    exit 1
  }
  ;;
esac

log debug "finished cronjob"
exit 0
