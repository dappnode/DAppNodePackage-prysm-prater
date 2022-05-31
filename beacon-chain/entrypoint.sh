#!/bin/bash

[[ -n $WEB3_BACKUP ]] && EXTRA_OPTS="--fallback-web3provider=${WEB3_BACKUP} ${EXTRA_OPTS}"
[[ -n $CHECKPOINT_SYNC_URL ]] && EXTRA_OPTS="--checkpoint-sync-url=${CHECKPOINT_SYNC_URL}/eth/v2/debug/beacon/states/finalized ${EXTRA_OPTS}"

exec -c beacon-chain \
  --prater \
  --datadir=/data \
  --rpc-host=0.0.0.0 \
  --grpc-gateway-host=0.0.0.0 \
  --monitoring-host=0.0.0.0 \
  --http-web3provider=\"$HTTP_WEB3PROVIDER\" \
  --grpc-gateway-port=3500 \
  --grpc-gateway-corsdomain=\"$CORSDOMAIN\" \
  --genesis-state=/genesis.ssz \
  --accept-terms-of-use \
  $EXTRA_OPTS
