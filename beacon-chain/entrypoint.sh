#!/bin/bash

if [[ -n $CHECKPOINT_SYNC_URL ]]; then
  EXTRA_OPTS="--checkpoint-sync-url=${CHECKPOINT_SYNC_URL} --genesis-beacon-api-url=${CHECKPOINT_SYNC_URL} ${EXTRA_OPTS}"
else
  EXTRA_OPTS="--genesis-state=/genesis.ssz ${EXTRA_OPTS}"
fi

case $_DAPPNODE_GLOBAL_EXECUTION_CLIENT_PRATER in
"goerli-geth.dnp.dappnode.eth")
  HTTP_ENGINE="http://goerli-geth.dappnode:8551"
  ;;
"goerli-nethermind.dnp.dappnode.eth")
  HTTP_ENGINE="http://goerli-nethermind.dappnode:8551"
  ;;
"goerli-besu.dnp.dappnode.eth")
  HTTP_ENGINE="http://goerli-besu.dappnode:8551"
  ;;
"goerli-erigon.dnp.dappnode.eth")
  HTTP_ENGINE="http://goerli-erigon.dappnode:8551"
  ;;
*)
  echo "Unknown value for _DAPPNODE_GLOBAL_EXECUTION_CLIENT_PRATER: $_DAPPNODE_GLOBAL_EXECUTION_CLIENT_PRATER"
  HTTP_ENGINE=$_DAPPNODE_GLOBAL_EXECUTION_CLIENT_PRATER
  ;;
esac

# MEVBOOST: https://hackmd.io/@prysmaticlabs/BJeinxFsq
if [ -n "$_DAPPNODE_GLOBAL_MEVBOOST_PRATER" ] && [ "$_DAPPNODE_GLOBAL_MEVBOOST_PRATER" == "true" ]; then
  echo "MEVBOOST is enabled"
  MEVBOOST_URL="http://mev-boost.mev-boost-goerli.dappnode:18550"
  if curl --retry 5 --retry-delay 5 --retry-all-errors "${MEVBOOST_URL}"; then
    EXTRA_OPTS="--http-mev-relay=${MEVBOOST_URL} ${EXTRA_OPTS}"
  else
    echo "MEVBOOST is enabled but ${MEVBOOST_URL} is not reachable"
    curl -X POST -G 'http://my.dappnode/notification-send' --data-urlencode 'type=danger' --data-urlencode title="${MEVBOOST_URL} is not available" --data-urlencode 'body=Make sure the mevboost is available and running'
  fi
fi

# Chek the env FEE_RECIPIENT_ADDRESS has a valid ethereum address if not set to the null address
if [ -n "$FEE_RECIPIENT_ADDRESS" ] && [[ "$FEE_RECIPIENT_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    echo "FEE_RECIPIENT is valid"
else
    echo "FEE_RECIPIENT is not a valid ethereum address, setting it to the null address"
    FEE_RECIPIENT_ADDRESS="0x0000000000000000000000000000000000000000"
fi

# If EXTRA_OPTS does not include flag --suggested-fee-recipient, append it
if [[ $EXTRA_OPTS != *"suggested-fee-recipient"* ]]; then
  echo "Adding --suggested-fee-recipient=${FEE_RECIPIENT_ADDRESS} to EXTRA_OPTS"
  EXTRA_OPTS="--suggested-fee-recipient=${FEE_RECIPIENT_ADDRESS} ${EXTRA_OPTS}"
fi

exec -c beacon-chain \
  --datadir=/data \
  --rpc-host=0.0.0.0 \
  --accept-terms-of-use \
  --prater \
  --grpc-gateway-host=0.0.0.0 \
  --monitoring-host=0.0.0.0 \
  --p2p-tcp-port=$P2P_TCP_PORT \
  --p2p-udp-port=$P2P_UDP_PORT \
  --execution-endpoint=$HTTP_ENGINE \
  --grpc-gateway-port=3500 \
  --grpc-gateway-corsdomain=$CORSDOMAIN \
  --jwt-secret=/jwtsecret \
  $EXTRA_OPTS
